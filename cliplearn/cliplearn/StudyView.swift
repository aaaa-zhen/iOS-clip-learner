import SwiftUI
import YouTubePlayerKit

/// The v1 core screen: a YouTube clip on top, the transcript below. The current
/// line highlights and auto-scrolls as the video plays; tapping a line seeks the
/// video to that line. Styled with Apple's Liquid Glass design (iOS 26).
struct StudyView: View {
    let title: String
    let segments: [Segment]

    @State private var player: YouTubePlayer
    @State private var currentIndex: Int?

    init(title: String, videoID: String, segments: [Segment]) {
        self.title = title
        self.segments = segments
        _player = State(initialValue: YouTubePlayer(source: .video(id: videoID)))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                YouTubePlayerView(player)
                    .frame(height: 220)

                transcript
            }

            replayControl
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // Follow playback: map the current time to the line that should be lit.
        .onReceive(player.currentTimePublisher) { time in
            let seconds = time.converted(to: .seconds).value
            currentIndex = TranscriptSync.currentSegmentIndex(at: seconds, in: segments)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // A container lets the Liquid Glass highlight blend and morph as
                // the active line changes.
                GlassEffectContainer(spacing: 8) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            TranscriptLineView(text: segment.text, isCurrent: index == currentIndex)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { seek(to: segment) }
                        }
                    }
                }
                .padding()
                .padding(.bottom, 72) // clear the floating control
            }
            .onChange(of: currentIndex) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var replayControl: some View {
        if let index = currentIndex {
            Button {
                seek(to: segments[index])
            } label: {
                Label("Replay line", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.glass)
            .padding(.bottom, 12)
        }
    }

    private func seek(to segment: Segment) {
        Task {
            try? await player.seek(
                to: Measurement(value: segment.start_time, unit: UnitDuration.seconds),
                allowSeekAhead: true
            )
            try? await player.play()
        }
    }
}

private struct TranscriptLineView: View {
    let text: String
    let isCurrent: Bool

    var body: some View {
        let base = Text(text)
            .font(.body)
            .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

        if isCurrent {
            base.glassEffect(
                .regular.tint(.accentColor.opacity(0.55)).interactive(),
                in: .rect(cornerRadius: 12)
            )
        } else {
            base
        }
    }
}
