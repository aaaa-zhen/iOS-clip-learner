import SwiftUI

/// Loads `GET /api/episodes/[id]` for the tapped episode, then hands the
/// transcript to the existing `StudyView`. Keeps `StudyView` a pure, testable
/// view that just renders segments + player.
struct StudyLoaderView: View {
    let episode: Episode
    let api: APIClient
    let auth: AuthStore

    @State private var phase: Phase = .loading

    enum Phase {
        case loading
        case loaded([Segment])
        case failed(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Loading transcript…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let segments):
                StudyView(title: episode.title,
                          videoID: episode.video_id ?? "",
                          segments: segments,
                          api: api,
                          auth: auth)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load transcript", systemImage: "text.badge.xmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            }
        }
        .navigationTitle(episode.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        phase = .loading
        do {
            let detail = try await api.episodeDetail(id: episode.id)
            phase = .loaded(detail.segments)
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
