import Common
import ComposableArchitecture
import DSWaveformImage
import DSWaveformImageViews
import Inject
import SwiftUI

// MARK: - WaveformProgressError

enum WaveformProgressError: Error {
  case audioFileNotFound
}

private let generationConfiguration = Waveform.Configuration(
  size: CGSize(width: 375, height: 50),
  backgroundColor: .clear,
  style: .striped(.init(color: UIColor(Color.DS.Text.base), width: 2, spacing: 4, lineCap: .round)),
  damping: .init(percentage: 0.125, sides: .both),
  scale: DSScreen.scale,
  verticalScalingFactor: 0.95,
  shouldAntialias: true
)

// MARK: - WaveformProgress

@Reducer
struct WaveformProgress {
  @ObservableState
  struct State: Equatable, Then {
    var audioFileURL: URL
    var waveformImageURL: URL
    var progress = 0.0
    var isPlaying = false
    var isSeeking = false
    var isImageCreated = false
    @Shared var waveformImage: UIImage?

    init(audioFileURL: URL, waveformImageURL: URL) {
      self.audioFileURL = audioFileURL
      self.waveformImageURL = waveformImageURL
      _waveformImage = Shared(nil)
    }
  }

  enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case onTask
    case waveformImageCreated
  }

  var body: some Reducer<State, Action> {
    BindingReducer()

    Reduce<State, Action> { state, action in
      switch action {
      case .binding:
        return .none

      case .onTask:
        guard !state.isImageCreated else { return .none }
        return .run(priority: .background) { [state] send in
//          guard !FileManager.default.fileExists(atPath: state.waveformImageURL.path)
//            || UIImage(contentsOfFile: state.waveformImageURL.path) == nil else {
//            await send(.waveformImageCreated)
//            return
//          }
//
//          guard FileManager.default.fileExists(atPath: state.audioFileURL.path) else {
//            logs.error("Can't find audio file at \(state.audioFileURL.path)")
//            await send(.waveformImageCreated)
//            return
//          }

          let waveImageDrawer = WaveformImageDrawer()
          let image = try await waveImageDrawer.waveformImage(fromAudioAt: state.audioFileURL, with: generationConfiguration)
          let data = try image.pngData().require()
          try data.write(to: state.waveformImageURL, options: .atomic)

          await send(.waveformImageCreated)
        } catch: { error, send in
          logs.error("Failed to create waveform image: \(error)")
          await send(.waveformImageCreated)
        }

      case .waveformImageCreated:
        state.isImageCreated = true
        return .run { [waveformImage = state.$waveformImage, path = state.waveformImageURL.path()] _ in
          waveformImage.withLock { value in
            value = UIImage(contentsOfFile: path)
          }
        }
      }
    }
  }
}

// MARK: - WaveformProgressView

@MainActor
struct WaveformProgressView: View {
  @Perception.Bindable var store: StoreOf<WaveformProgress>

  @State var imageSize = CGSize.zero
  @State private var lastSentProgress: Double? = nil

  var body: some View {
    WithPerceptionTracking {
      ZStack {
        waveImageView()
          .frame(height: 50)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, .grid(1))
          .animation(.linear(duration: 0.1), value: store.progress)
          .readSize { imageSize = $0 }
          .gesture(
            DragGesture(minimumDistance: 2)
              .onChanged { value in
                let progress = Double(value.location.x / imageSize.width)
                let clampedProgress = min(max(0, progress), 1.0)
                if shouldSendProgressUpdate(newProgress: clampedProgress) {
                  $store.progress.wrappedValue = clampedProgress
                  $store.isSeeking.wrappedValue = true
                  lastSentProgress = clampedProgress
                }
              }
              .onEnded { _ in
                $store.isSeeking.wrappedValue = false
              }
          )
      }
      .animation(.interpolatingSpring(mass: 1.0, stiffness: 200, damping: 20), value: store.isImageCreated)
      .task { await store.send(.onTask).finish() }
    }
  }

  private func shouldSendProgressUpdate(newProgress: Double) -> Bool {
    guard let lastProgress = lastSentProgress else {
      return true
    }
    return abs(newProgress - lastProgress) > 0.01 // Only send updates if the change is greater than 1%
  }

  @ViewBuilder
  private func waveImageView() -> some View {
    GeometryReader { geometry in
      WithPerceptionTracking {
        if let image = store.waveformImage {
          Color.DS.Text.subdued
            .overlay {
              Color.DS.Text.base
                .frame(width: geometry.size.width * (store.isPlaying ? store.progress : 1))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .mask(alignment: .leading) {
              Image(uiImage: image)
                .resizable()
                .scaledToFill()
            }
        }
      }
    }
  }
}

#if DEBUG
  struct WaveformProgressView_Previews: PreviewProvider {
    static var previews: some View {
      NavigationView {
        WaveformProgressView(
          store: Store(initialState: WaveformProgress.State(audioFileURL: .documentsDirectory, waveformImageURL: .documentsDirectory)) {
            WaveformProgress()
          }
        )
      }
    }
  }
#endif
