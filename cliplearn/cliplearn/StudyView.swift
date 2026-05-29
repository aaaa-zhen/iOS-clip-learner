import SwiftUI
import YouTubePlayerKit

/// The core study screen: a YouTube clip on top, a caption-style transcript that
/// follows playback below, and a custom transport bar (rewind / play-pause /
/// forward + scrubber) docked above the tab bar. Styled with Liquid Glass.
struct StudyView: View {
    let title: String
    let segments: [Segment]
    let api: APIClient
    let auth: AuthStore

    @State private var player: YouTubePlayer
    @State private var currentIndex: Int?
    @State private var isPlaying = false
    @State private var currentSeconds: Double = 0
    @State private var duration: Double = 0
    @State private var scrubbing = false
    @State private var lookup: WordLookup?
    @State private var captionsOn = true
    @State private var savedLines: Set<Int> = []

    private let skipInterval: Double = 10

    /// A tapped word + the line it came from, used to drive the lookup popover.
    /// `index` is the word's position in the current line so the popover anchors
    /// to the exact word that was tapped.
    struct WordLookup: Identifiable {
        let id = UUID()
        let word: String
        let line: String
        let index: Int
    }

    init(title: String, videoID: String, segments: [Segment], api: APIClient, auth: AuthStore) {
        self.title = title
        self.segments = segments
        self.api = api
        self.auth = auth
        // Strip the YouTube embed chrome we *can* remove: bottom control bar,
        // fullscreen button, captions, and related-video suggestions. (The title
        // bar, "Watch on YouTube", and the initial big play button are enforced
        // by YouTube's iFrame API and can't be removed.) Playback is driven by
        // our own transport bar + tapping transcript lines instead.
        _player = State(initialValue: YouTubePlayer(
            source: .video(id: videoID),
            parameters: .init(
                autoPlay: false,
                showControls: false,
                showFullscreenButton: false,
                keyboardControlsDisabled: true,
                showCaptions: false,
                restrictRelatedVideosToSameChannel: true
            ),
            // A desktop-Safari user agent helps avoid YouTube's embed
            // "confirm you're not a bot" gate (common on the Simulator / flagged IPs).
            configuration: .init(
                customUserAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
            )
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            YouTubePlayerView(player)
                .frame(height: 210)
                .clipShape(.rect(cornerRadius: 16))
                .padding(.horizontal, 10)
                .padding(.top, 8)
            if captionsOn {
                caption
            } else {
                Spacer(minLength: 0)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { transportBar }
        // Follow playback.
        .onReceive(player.currentTimePublisher) { time in
            let seconds = time.converted(to: .seconds).value
            if !scrubbing {
                // The YouTube embed's onStateChange doesn't always fire (e.g. when
                // started from its own poster button), so infer "playing" from the
                // clock advancing — keeps our play/pause icon in sync.
                if seconds > currentSeconds + 0.05 { isPlaying = true }
                currentSeconds = seconds
            }
            currentIndex = TranscriptSync.currentSegmentIndex(at: seconds, in: segments)
        }
        .onReceive(player.durationPublisher) { d in
            duration = d.converted(to: .seconds).value
        }
        .onReceive(player.playbackStatePublisher) { state in
            // Only react to definitive states. The embed also emits .buffering /
            // .unstarted intermittently — ignoring those keeps the icon from
            // flipping back to ▶ while the clock is clearly advancing.
            if state == .playing { isPlaying = true }
            else if state == .paused || state == .ended { isPlaying = false }
        }
    }

    // MARK: Caption (follows the video)

    /// Immersive caption: the current line is shown as tappable words. The word
    /// being spoken is full white; the rest are dimmed (alpha 0.7). Long lines
    /// scroll, and the view auto-scrolls to keep the active word centered.
    private var caption: some View {
        let active = currentIndex ?? 0
        let segment = segments[safe: active]
        let tokens = segment.map(\.text).map(tokenize) ?? []
        let activeWord = segment.flatMap { activeWordIndex(in: $0, tokenCount: tokens.count) }
        return GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    if let segment {
                        FlowLayout(spacing: 6, lineSpacing: 12) {
                            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                                Text(token.display)
                                    .font(.system(size: 25, weight: .semibold))
                                    .foregroundStyle(.white.opacity(index == activeWord ? 1 : 0.7))
                                    .animation(.easeInOut(duration: 0.15), value: activeWord)
                                    .padding(.vertical, 1)
                                    .contentShape(.rect)
                                    .id("w\(index)")
                                    .onTapGesture { lookUp(word: token.lookup, line: segment.text, index: index) }
                                    .popover(isPresented: popoverBinding(for: index), arrowEdge: .bottom) {
                                        WordLookupSheet(word: lookup?.word ?? token.lookup,
                                                        currentLine: segment.text,
                                                        episodeTitle: title, api: api)
                                            .presentationCompactAdaptation(.popover)
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
                        .padding(.horizontal, 24)
                    }
                }
                // Auto-scroll within a long line to keep the active word visible.
                .onChange(of: activeWord) { _, w in
                    guard let w else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo("w\(w)", anchor: .center) }
                }
            }
        }
        // Treat each line as a fresh view: the old line fades out, the next fades
        // in — no words sliding/morphing between lines.
        .id(active)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: active)
    }

    /// Approximate the word being spoken inside `segment` by distributing the
    /// line's [start, end] window across the words, weighted by length. (The
    /// backend only stores per-line timestamps, not per-word.)
    private func activeWordIndex(in segment: Segment, tokenCount: Int) -> Int? {
        let duration = segment.end_time - segment.start_time
        guard duration > 0, tokenCount > 0, isPlaying || currentSeconds > segment.start_time else { return nil }
        let fraction = min(max((currentSeconds - segment.start_time) / duration, 0), 1)
        let weights = tokenize(segment.text).map { Double(max($0.display.count, 1)) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        var cumulative = 0.0
        for (i, w) in weights.enumerated() {
            cumulative += w
            if fraction <= cumulative / total { return i }
        }
        return tokenCount - 1
    }

    private func tokenize(_ text: String) -> [(display: String, lookup: String)] {
        text.split(separator: " ", omittingEmptySubsequences: true).map { piece in
            let display = String(piece)
            let lookup = display.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            return (display, lookup)
        }
    }

    private func lookUp(word: String, line: String, index: Int) {
        guard !word.isEmpty else { return }
        Task { try? await player.pause() } // pause while the popover is open, like the web
        lookup = WordLookup(word: word, line: line, index: index)
    }

    /// Per-word popover presentation: true only for the word currently looked up.
    private func popoverBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { lookup?.index == index },
            set: { presented in if !presented { lookup = nil } }
        )
    }

    // MARK: Transport bar

    private var transportBar: some View {
        VStack(spacing: 22) {
            ZStack {
                // Playback controls, centered. (Skip buttons swapped per request:
                // forward on the left, rewind on the right.)
                HStack(spacing: 38) {
                    circleButton(size: 44, icon: 16) {
                        seek(toSeconds: currentSeconds + skipInterval)
                    } label: { Image(systemName: "goforward.10") }

                    circleButton(size: 58, icon: 22) {
                        togglePlayPause()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .offset(x: isPlaying ? 0 : 2) // optically center the triangle
                    }

                    circleButton(size: 44, icon: 16) {
                        seek(toSeconds: currentSeconds - skipInterval)
                    } label: { Image(systemName: "gobackward.10") }
                }

                // Secondary controls flanking the playback row: captions toggle
                // (left) and save-this-line (right).
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { captionsOn.toggle() }
                    } label: {
                        Image(systemName: captionsOn ? "captions.bubble.fill" : "captions.bubble")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(captionsOn ? Color.accentColor : Color.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: saveCurrentLine) {
                        Image(systemName: isCurrentLineSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(isCurrentLineSaved ? Color.accentColor : Color.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrubBar(value: $currentSeconds, duration: duration) { editing in
                scrubbing = editing
                if !editing { seek(toSeconds: currentSeconds) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    /// Apple-style circular glass transport button.
    private func circleButton<L: View>(
        size: CGFloat, icon: CGFloat,
        action: @escaping () -> Void, @ViewBuilder label: () -> L
    ) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: icon, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
    }

    // MARK: Save line

    private var isCurrentLineSaved: Bool { savedLines.contains(currentIndex ?? 0) }

    /// Save the current line to the notebook. Requires an account — if signed
    /// out, raise the login sheet first (use-first, log-in-on-demand).
    private func saveCurrentLine() {
        guard auth.isAuthenticated else { auth.requireLogin(); return }
        let i = currentIndex ?? 0
        guard let segment = segments[safe: i], !isCurrentLineSaved else { return }
        Task {
            do {
                try await api.saveLine(segment.text, episodeID: segment.episode_id,
                                       sourceTime: segment.start_time)
                savedLines.insert(i)
            } catch APIError.server(let status, _) where status == 409 {
                savedLines.insert(i) // already saved — treat as success
            } catch APIError.unauthorized {
                auth.requireLogin()
            } catch {
                // Non-fatal; leave the bookmark unfilled so the user can retry.
            }
        }
    }

    // MARK: Playback control

    private func togglePlayPause() {
        let willPlay = !isPlaying
        isPlaying = willPlay // optimistic — the embed's state events are unreliable
        Task { willPlay ? try? await player.play() : try? await player.pause() }
    }

    private func seek(to segment: Segment) {
        seek(toSeconds: segment.start_time, play: true)
    }

    private func seek(toSeconds seconds: Double, play: Bool = false) {
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentSeconds = clamped
        Task {
            try? await player.seek(
                to: Measurement(value: clamped, unit: UnitDuration.seconds),
                allowSeekAhead: true
            )
            if play { try? await player.play() }
        }
    }

}

/// "12:34" / "1:02:03" time label.
fileprivate func clipTimeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let t = Int(seconds.rounded())
    let h = t / 3600, m = (t % 3600) / 60, s = t % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                 : String(format: "%d:%02d", m, s)
}

// MARK: - Scrub bar (capsule: current time · rounded track · duration)

private struct ScrubBar: View {
    @Binding var value: Double
    let duration: Double
    let onEditing: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(clipTimeLabel(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))

            GeometryReader { geo in
                let w = geo.size.width
                let frac = duration > 0 ? min(max(value / duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white).frame(width: max(6, w * frac))
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            onEditing(true)
                            guard duration > 0, w > 0 else { return }
                            value = min(max(g.location.x / w, 0), 1) * duration
                        }
                        .onEnded { _ in onEditing(false) }
                )
            }
            .frame(height: 22)

            Text(clipTimeLabel(duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Flow layout (wrapping, left-aligned rows of tappable words)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxW = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 {
                widest = max(widest, x - spacing)
                x = 0; y += rowH + lineSpacing; rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        widest = max(widest, x - spacing)
        let width = maxW.isFinite ? maxW : max(widest, 0)
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowH + lineSpacing; rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

private extension Array {
    /// Bounds-checked subscript — returns nil instead of trapping.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
