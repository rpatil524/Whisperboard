import Common
import ComposableArchitecture
import Inject
import SwiftUI

// MARK: - RecordingDetails

@Reducer
struct RecordingDetails {
  enum DisplayMode: Equatable {
    case text, timeline
  }

  struct TimelineItem: Equatable, Identifiable {
    var id: Duration { startTime }
    var text: String
    var startTime: Duration
    var endTime: Duration
  }

  @ObservableState
  struct State: Equatable {
    var recordingCard: RecordingCard.State
    var displayMode: DisplayMode = .text

    @Presents var alert: AlertState<Action.Alert>?

    var timeline: [TimelineItem] {
      recordingCard.recording.transcription?.segments.map {
        TimelineItem(text: $0.text, startTime: Duration.milliseconds($0.startTime), endTime: Duration.milliseconds($0.endTime))
      } ?? []
    }

    var shareAudioFileURL: URL { recordingCard.recording.fileURL }
  }

  enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case recordingCard(RecordingCard.Action)
    case delete
    case alert(PresentationAction<Alert>)
    case delegate(Delegate)

    enum Alert: Hashable {
      case deleteDialogConfirmed
    }

    enum Delegate: Hashable {
      case deleteDialogConfirmed
    }
  }

  var body: some Reducer<State, Action> {
    BindingReducer()

    Scope(state: \.recordingCard, action: /Action.recordingCard) {
      RecordingCard()
    }

    Reduce<State, Action> { state, action in
      switch action {
      case .binding:
        return .none

      case .recordingCard:
        return .none

      case .delete:
        state.alert = AlertState {
          TextState("Confirmation")
        } actions: {
          ButtonState(role: .destructive, action: .deleteDialogConfirmed) {
            TextState("Delete")
          }
        } message: {
          TextState("Are you sure you want to delete this recording?")
        }
        return .none

      case .alert(.presented(.deleteDialogConfirmed)):
        return .send(.delegate(.deleteDialogConfirmed))

      case .alert:
        return .none

      case .delegate:
        return .none
      }
    }
    .ifLet(\.$alert, action: /Action.alert)
  }
}

// MARK: - RecordingDetailsView

struct RecordingDetailsView: View {
  enum Field: Int, CaseIterable {
    case title, text
  }

  @FocusState private var focusedField: Field?
  @Perception.Bindable var store: StoreOf<RecordingDetails>

  var body: some View {
    WithPerceptionTracking {
      VStack(spacing: .grid(2)) {
        headerView
        transcriptionView
        waveformProgressView
        playButtonView
      }
      .padding(.vertical, .grid(4))
      .toolbar {
        ToolbarItem(placement: .keyboard) {
          doneButton
        }
      }
      .alert($store.scope(state: \.alert, action: \.alert))
      .background(Color.DS.Background.primary)
    }
  }

  private var headerView: some View {
    RecordingDetailsHeaderView(
      store: store,
      focusedField: _focusedField
    )
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .padding(.horizontal, .grid(4))
  }

  private var waveformProgressView: some View {
    WaveformProgressView(
      store: store.scope(
        state: \.recordingCard.playerControls.waveform,
        action: \.recordingCard.playerControls.view.waveform
      )
    )
    .padding(.horizontal, .grid(4))
  }

  private var playButtonView: some View {
    PlayButton(isPlaying: store.recordingCard.playerControls.isPlaying) {
      store.send(.recordingCard(.playerControls(.view(.playButtonTapped))), animation: .spring())
    }
    .padding(.horizontal, .grid(4))
  }

  private var doneButton: some View {
    Button("Done") {
      focusedField = nil
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
  }

  private var transcriptionView: some View {
    ScrollView {
      switch store.displayMode {
      case .text:
        textTranscriptionView

      case .timeline:
        timelineTranscriptionView
      }
    }
    .scrollAnchor(id: 1, valueToTrack: store.recordingCard.transcription, anchor: store.recordingCard.recording.isTranscribing ? .bottom : .zero)
    .applyVerticalEdgeSofteningMask()
    .offset(x: 0, y: -8)
  }

  private var textTranscriptionView: some View {
    Text(store.recordingCard.transcription)
      .foregroundColor(store.recordingCard.recording.isTranscribing ? .DS.Text.subdued : .DS.Text.base)
      .textStyle(.body)
      .lineLimit(nil)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.vertical, .grid(2))
      .padding(.horizontal, .grid(4))
      .id(1)
  }

  private var timelineTranscriptionView: some View {
    LazyVStack {
      ForEach(store.timeline) { item in
        VStack(alignment: .leading, spacing: .grid(1)) {
          Text(
            "[\(item.startTime.formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 2, fractionalSecondsLength: 2)))) - \(item.endTime.formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 2, fractionalSecondsLength: 2))))]"
          )
          .foregroundColor(.DS.Text.subdued)
          .textStyle(.caption)

          Text(item.text)
            .foregroundColor(.DS.Text.base)
            .textStyle(.body)
            .lineLimit(nil)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, .grid(2))
      }
    }
    .padding(.horizontal, .grid(4))
    .id(1)
  }
}

// MARK: - RecordingDetailsHeaderView

struct RecordingDetailsHeaderView: View {
  @Perception.Bindable var store: StoreOf<RecordingDetails>
  @FocusState var focusedField: RecordingDetailsView.Field?

  var body: some View {
    WithPerceptionTracking {
      VStack(spacing: .grid(2)) {
        TextField(
          "Untitled",
          text: $store.recordingCard.recording.title,
          axis: .vertical
        )
        .focused($focusedField, equals: .title)
        .textStyle(.headline)
        .foregroundColor(.DS.Text.base)

        Text("Created: \(store.recordingCard.recording.date.formatted(date: .abbreviated, time: .shortened))")
          .textStyle(.caption)
          .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: .grid(2)) {
          CopyButton(store.recordingCard.transcription) {
            Image(systemName: "doc.on.clipboard")
          }

          ShareLink(item: store.recordingCard.transcription) {
            Image(systemName: "paperplane")
          }

          Button { store.send(.recordingCard(.transcribeButtonTapped)) } label: {
            Image(systemName: "arrow.clockwise")
          }.disabled(store.recordingCard.recording.isTranscribing)

          ShareLink(item: store.shareAudioFileURL) {
            Image(systemName: "square.and.arrow.up")
          }

          Button { store.send(.delete) } label: {
            Image(systemName: "trash")
          }

          Spacer()

          Picker(
            "",
            selection: $store.displayMode
          ) {
            Image(systemName: "text.alignleft")
              .tag(RecordingDetails.DisplayMode.text)
            Image(systemName: "list.bullet")
              .tag(RecordingDetails.DisplayMode.timeline)
          }
          .pickerStyle(.segmented)
          .colorMultiply(.DS.Text.accent)
        }.iconButtonStyle()

        if let tokensPerSecond = store.recordingCard.recording.transcription?.timings.tokensPerSecond {
          LabeledContent {
            Text(String(format: "%.2f", tokensPerSecond))
          } label: {
            Label("Tokens/Second", systemImage: "speedometer")
          }
          .textStyle(.footnote)
        }

        if store.recordingCard.recording.isTranscribing || store.recordingCard.queueInfo != nil || !store.recordingCard.recording.isTranscribed {
          TranscriptionControlsView(store: store.scope(state: \.recordingCard, action: \.recordingCard))
        } else if let error = store.recordingCard.recording.transcription?.status.errorMessage {
          Text("Last transcription failed")
            .textStyle(.error)
            .foregroundColor(.DS.Text.error)
          Text(error)
            .textStyle(.error)
            .foregroundColor(.DS.Text.error)
        }
      }
    }
  }
}

private extension View {
  func applyVerticalEdgeSofteningMask() -> some View {
    mask {
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0),
          .init(color: .black, location: 0.02),
          .init(color: .black, location: 0.98),
          .init(color: .clear, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }
}
