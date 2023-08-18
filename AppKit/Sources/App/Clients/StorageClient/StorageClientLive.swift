import AppDevUtils
import AVFoundation
import Combine
import ComposableArchitecture
import Dependencies
import Foundation
import SwiftUI
import UIKit

// MARK: - StorageClient + DependencyKey

extension StorageClient: DependencyKey {
  static let liveValue: Self = {
    let storage = Storage()
    let documentsURL = Storage.documentsURL

    return StorageClient(
      read: {
        storage.currentRecordings.identifiedArray
      },

      recordingsInfoStream: storage.currentRecordingsStream.asAsyncStream(),

      write: { recordings in
        storage.write(recordings.elements)
      },

      addRecordingInfo: { recording in
        let newRecordings = storage.currentRecordings + [recording]
        storage.write(newRecordings)
      },

      createNewWhisperURL: {
        let filename = UUID().uuidString + ".wav"
        let url = documentsURL.appending(path: filename)
        storage.setAsCurrentlyRecording(url)
        return url
      },

      audioFileURLWithName: { name in
        documentsURL.appending(path: name)
      },

      waveFileURLWithName: { name in
        documentsURL.appending(path: name)
      },

      delete: { recordingId in
        let recordings = storage.currentRecordings.identifiedArray
        guard let recording = recordings[id: recordingId] else {
          customAssertionFailure()
          return
        }

        let url = documentsURL.appending(path: recording.fileName)
        try FileManager.default.removeItem(at: url)
        let newRecordings = recordings.filter { $0.id != recordingId }
        storage.write(newRecordings.elements)
      },

      update: { id, updater in
        var recordings = storage.currentRecordings.identifiedArray
        guard var recording = recordings[id: id] else {
          customAssertionFailure()
          return
        }

        updater(&recording)

        recordings[id: id] = recording
        storage.write(recordings.elements)
      },

      freeSpace: { freeDiskSpaceInBytes() },
      totalSpace: { totalDiskSpaceInBytes() },
      takenSpace: { takenSpace() },
      deleteStorage: { try await deleteStorage(storage) }
    )
  }()

  private static func totalDiskSpaceInBytes() -> UInt64 {
    do {
      let fileURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey])
      let capacity = values.volumeAvailableCapacityForImportantUsage
      return UInt64(capacity ?? 0)
    } catch {
      log.error("Error while getting total disk space: \(error)")
      return 0
    }
  }

  private static func freeDiskSpaceInBytes() -> UInt64 {
    do {
      let fileURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      let capacity = values.volumeAvailableCapacityForImportantUsage
      return UInt64(capacity ?? 0)
    } catch {
      log.error("Error while getting free disk space: \(error)")
      return 0
    }
  }

  private static func takenSpace() -> UInt64 {
    do {
      let fileURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let capacity = try fileURL.directoryTotalAllocatedSize(includingSubfolders: true)
      return UInt64(capacity ?? 0)
    } catch {
      log.error("Error while getting taken disk space: \(error)")
      return 0
    }
  }

  private static func deleteStorage(_ storage: Storage) async throws {
    let documentDir = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let contents = try FileManager.default.contentsOfDirectory(at: documentDir, includingPropertiesForKeys: nil, options: [])
    for item in contents where item.lastPathComponent != "settings.json" {
      try FileManager.default.removeItem(at: item)
    }
    try storage.read()
  }
}

// MARK: - Storage

private final class Storage {
  @Published private var recordings: [RecordingInfo] = []

  static var documentsURL: URL {
    do {
      return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    } catch {
      customAssertionFailure("Could not get documents directory")
      return URL(fileURLWithPath: "~/Documents")
    }
  }

  static var dbURL: URL {
    documentsURL.appendingPathComponent("recordings.json")
  }

  static var containerGroupURL: URL? {
    let appGroupName = "group.whisperboard"
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)?.appending(component: "share")
  }

  var currentRecordings: [RecordingInfo] {
    recordings
  }

  var currentRecordingsStream: AnyPublisher<[RecordingInfo], Never> {
    $recordings.eraseToAnyPublisher()
  }

  private var currentlyRecordingURL: URL?

  init() {
    recordings = (try? [RecordingInfo].fromFile(path: Self.dbURL.path)) ?? []

    subscribeToDidBecomeActiveNotifications()
    catchingRead()
  }

  func read() throws {
    var storedRecordings = currentRecordings

    // Update the duration of the recordings that don't have it
    storedRecordings = storedRecordings.map { recording in
      var recording = recording
      if recording.duration == 0 {
        do {
          recording.duration = try getFileDuration(url: Self.documentsURL.appending(path: recording.fileName))
        } catch {
          log.error(error)
        }
      }
      return recording
    }

    // If there are files in shared container, move them to the documents directory
    let sharedRecordings = moveSharedFiles(to: Self.documentsURL)
    if !sharedRecordings.isEmpty {
      storedRecordings.append(contentsOf: sharedRecordings)
    }

    // Get the files in the documents directory with the .wav extension
    let recordingFiles = try FileManager.default
      .contentsOfDirectory(atPath: Self.documentsURL.path)
      .filter { $0.hasSuffix(".wav") }
      // Remove the currently recording file from the list until it is finished
      .filter { $0 != currentlyRecordingURL?.lastPathComponent }

    let recordings: [RecordingInfo] = try recordingFiles.map { file in
      // If the recording is already stored in the database, return it
      if let recording = storedRecordings.first(where: { $0.fileName == file }) {
        return recording
      }

      log.warning("Recording \(file) not found in database, creating new info for it")
      return try createInfo(fileName: file)
    }

    write(recordings)
  }

  func write(_ newRecordings: [RecordingInfo]) {
    log.verbose("Writing \(newRecordings.count) recordings to database file")

    // If the currently recording file is in the new recordings, set it to nil as it is not in progress anymore
    if newRecordings.contains(where: { $0.fileName == currentlyRecordingURL?.lastPathComponent }) {
      currentlyRecordingURL = nil
    }

    recordings = newRecordings.sorted { $0.date > $1.date }

    do {
      try recordings.saveToFile(path: Self.dbURL.path)
    } catch {
      log.error(error)
    }
  }

  func setAsCurrentlyRecording(_ url: URL) {
    currentlyRecordingURL = url
  }

  private func moveSharedFiles(to docURL: URL) -> [RecordingInfo] {
    var recordings: [RecordingInfo] = []
    if let containerGroupURL = Self.containerGroupURL, FileManager.default.fileExists(atPath: containerGroupURL.path) {
      do {
        for file in try FileManager.default.contentsOfDirectory(atPath: containerGroupURL.path) {
          let sourceURL = containerGroupURL.appendingPathComponent(file)
          let newFileName = UUID().uuidString + ".wav"
          let destinationURL = docURL.appending(path: newFileName)
          try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
          let duration = try getFileDuration(url: destinationURL)
          let recording = RecordingInfo(
            fileName: newFileName,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            date: Date(),
            duration: duration
          )
          recordings.append(recording)
          log.info("successfully moved file \(file) to \(destinationURL.path)")
          log.info(recording)
        }
      } catch {
        log.error(error)
      }
    }
    return recordings
  }

  private func createInfo(fileName: String) throws -> RecordingInfo {
    let docURL = Storage.documentsURL
    let fileURL = docURL.appending(component: fileName)
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let date = attributes[.creationDate] as? Date ?? Date()
    let duration = try getFileDuration(url: fileURL)
    let recording = RecordingInfo(fileName: fileName, date: date, duration: duration)
    return recording
  }

  private func subscribeToDidBecomeActiveNotifications() {
    NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
      self?.catchingRead()
    }
  }

  private func catchingRead() {
    do {
      try read()
    } catch {
      log.error("Error reading recordings: \(error)")
    }
  }
}

// MARK: - CodableValueSubject + Then

extension CodableValueSubject: Then {}

extension URL {
  func isDirectoryAndReachable() throws -> Bool {
    guard try resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
      return false
    }
    return try checkResourceIsReachable()
  }

  func directoryTotalAllocatedSize(includingSubfolders: Bool = false) throws -> Int? {
    guard try isDirectoryAndReachable() else { return nil }
    if includingSubfolders {
      guard let urls = FileManager.default.enumerator(at: self, includingPropertiesForKeys: nil)?.allObjects as? [URL] else { return nil }
      return try urls.lazy.reduce(0) {
        try ($1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) + $0
      }
    }
    return try FileManager.default.contentsOfDirectory(at: self, includingPropertiesForKeys: nil).lazy.reduce(0) {
      try ($1.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        .totalFileAllocatedSize ?? 0) + $0
    }
  }
}

#if DEBUG
  extension StorageClient {
    /// In memory simple storage that is initialised with RecordingEnvelop.fixtures
    static var testValue: StorageClient {
      let recordings = CurrentValueSubject<[RecordingInfo], Never>(RecordingInfo.fixtures)

      return Self(
        read: {
          recordings.value.identifiedArray
        },

        recordingsInfoStream: recordings.asAsyncStream(),

        write: { newRecordings in
          recordings.value = newRecordings.elements
        },

        addRecordingInfo: { recording in
          recordings.value.append(recording)
        },

        createNewWhisperURL: {
          let filename = UUID().uuidString + ".wav"
          let url = URL(fileURLWithPath: filename)
          return url
        },

        audioFileURLWithName: { name in
          URL(fileURLWithPath: name)
        },

        waveFileURLWithName: { name in
          URL(fileURLWithPath: name)
        },

        delete: { recordingId in
          recordings.value = recordings.value.filter { $0.id != recordingId }
        },

        update: { id, updater in
          var identifiedRecordings = recordings.value.identifiedArray
          guard var recording = identifiedRecordings[id: id] else {
            customAssertionFailure()
            return
          }

          updater(&recording)

          identifiedRecordings[id: id] = recording

          recordings.value = identifiedRecordings.elements
        },

        freeSpace: { 0 },
        totalSpace: { 0 },
        takenSpace: { 0 },
        deleteStorage: {}
      )
    }
  }
#endif
