import Dependencies
import Foundation

// MARK: - LocalTranscriptionError

enum LocalTranscriptionError: Error {
  case notEnoughMemory(available: UInt64, required: UInt64)
}

// MARK: - LocalTranscriptionWorkExecutor

final class LocalTranscriptionWorkExecutor: TranscriptionWorkExecutor {
  var currentWhisperContext: (context: WhisperContextProtocol, modelType: VoiceModelType)? = nil

  private let updateTranscription: (_ transcription: Transcription) -> Void

  @Dependency(\.storage) var storage

  init(updateTranscription: @escaping (_ transcription: Transcription) -> Void) {
    self.updateTranscription = updateTranscription
  }

  func processTask(_ task: TranscriptionTask, updateTask: @escaping (TranscriptionTask) -> Void) async {
    let initialSegments = task.segments
    var task: TranscriptionTask = task {
      didSet { updateTask(task) }
    }
    var transcription = Transcription(
      id: task.id,
      fileName: task.fileName,
      segments: task.segments,
      parameters: task.parameters,
      model: task.modelType
    ) {
      didSet {
        task.segments = transcription.segments
        updateTranscription(transcription)
      }
    }

    let fileURL = storage.audioFileURLWithName(task.fileName)

    do {
      transcription.status = .loading

      let context: WhisperContextProtocol = try await resolveContextFor(task: task) { task = $0 }

      transcription.status = .progress(task.progress)

      for await action in try await context.fullTranscribe(audioFileURL: fileURL, params: task.parameters) {
        log.debug(action)
        var _transcription = transcription
        switch action {
        case let .newSegment(segment):
          _transcription.segments.append(segment)
          _transcription.status = .progress(task.progress)
        case let .progress(progress):
          log.debug("Progress: \(progress)")
        case let .error(error):
          _transcription.status = .error(message: error.localizedDescription)
        case .canceled:
          _transcription.status = .canceled
        case let .finished(segments):
          _transcription.segments = initialSegments + segments
          _transcription.status = .done(Date())
        }
        transcription = _transcription
      }
    } catch {
      transcription.status = .error(message: error.localizedDescription)
    }
  }

  func cancel(task _: TranscriptionTask) {
    Task {
      await currentWhisperContext?.context.cancel()
    }
  }

  private func resolveContextFor(task: TranscriptionTask, updateTask: (TranscriptionTask) -> Void) async throws -> WhisperContextProtocol {
    if let currentContext = currentWhisperContext, currentContext.modelType == task.modelType {
      return currentContext.context
    } else {
      let selectedModel = FileManager.default.fileExists(atPath: task.modelType.localURL.path) ? task.modelType : .default
      // Update model type in case it of fallback to default
      updateTask(task.with(\.modelType, setTo: selectedModel))

      let memory = freeMemoryAmount()
      log.info("Available memory: \(bytesToReadableString(bytes: availableMemory()))")
      log.info("Free memory: \(bytesToReadableString(bytes: memory))")

      guard memory > selectedModel.memoryRequired else {
        throw LocalTranscriptionError.notEnoughMemory(available: memory, required: selectedModel.memoryRequired)
      }

      let context = try await WhisperContext.createFrom(modelPath: selectedModel.localURL.path)
      currentWhisperContext = (context, selectedModel)
      return context
    }
  }
}
