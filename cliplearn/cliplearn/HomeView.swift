import SwiftUI

/// The home feed — the user's episodes from `GET /api/episodes`, as left-cover /
/// right-title rows. Tapping a row opens the study view for that episode.
struct HomeView: View {
    let auth: AuthStore

    @State private var episodes: [Episode] = []
    @State private var loadState: LoadState = .loading
    @State private var selectedCategory: String?   // nil = All
    @State private var showAdd = false
    @State private var pendingDelete: Episode?

    /// Episodes still being processed on the server (drives status polling).
    private var processingCount: Int {
        episodes.filter { !$0.isReady && $0.status != "error" }.count
    }

    enum LoadState: Equatable {
        case loading, loaded, needsAuth, failed(String)
    }

    /// Categories a user can assign to an episode.
    static let categories = ["Learning", "Talk", "Comedy", "News", "Music", "Other"]

    /// Categories actually in use (drives the filter chips).
    private var presentCategories: [String] {
        Array(Set(episodes.compactMap(\.category))).sorted()
    }

    private var filteredEpisodes: [Episode] {
        guard let selectedCategory else { return episodes }
        return episodes.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading where episodes.isEmpty:
                    ProgressView("Loading your clips…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .needsAuth:
                    signInPrompt
                case .failed(let message) where episodes.isEmpty:
                    errorState(message)
                default:
                    feed
                }
            }
            .navigationTitle("")
            .toolbar { topBar }
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: Episode.self) { episode in
                StudyLoaderView(episode: episode, api: auth.api, auth: auth)
            }
        }
        .task { await load() }
        .onChange(of: auth.isAuthenticated) { _, signedIn in
            if signedIn { Task { await load() } }
        }
        .sheet(isPresented: $showAdd) {
            AddEpisodeView(api: auth.api) { await load() }
        }
        // Poll while anything is still processing, then stop.
        .task(id: processingCount) {
            guard processingCount > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { break }
                await load()
                if processingCount == 0 { break }
            }
        }
    }

    private var signInPrompt: some View {
        ContentUnavailableView {
            Label("Sign in to see your clips", systemImage: "person.crop.circle")
        } description: {
            Text("Your episodes from the Clip Learner web app will appear here.")
        } actions: {
            Button { auth.requireLogin() } label: {
                Text("Sign In")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(.white, in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: States

    @ViewBuilder
    private var feed: some View {
        if episodes.isEmpty {
            ContentUnavailableView(
                "No clips yet",
                systemImage: "play.rectangle.on.rectangle",
                description: Text("Generate episodes on the Clip Learner web app — they'll show up here.")
            )
        } else {
            VStack(spacing: 0) {
                if !presentCategories.isEmpty { categoryChips }
                List {
                    ForEach(filteredEpisodes) { episode in
                        Group {
                            // Only ready episodes open the study view — tapping one
                            // that's still processing would land on an empty screen.
                            if episode.isReady {
                                NavigationLink(value: episode) { EpisodeCard(episode: episode) }
                            } else {
                                EpisodeCard(episode: episode)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { pendingDelete = episode } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Menu("Category") {
                                ForEach(HomeView.categories, id: \.self) { category in
                                    Button {
                                        setCategory(episode, category)
                                    } label: {
                                        if episode.category == category {
                                            Label(category, systemImage: "checkmark")
                                        } else {
                                            Text(category)
                                        }
                                    }
                                }
                                if episode.category != nil {
                                    Divider()
                                    Button("Remove from category") { setCategory(episode, nil) }
                                }
                            }
                            if episode.status == "error" {
                                Button {
                                    retry(episode)
                                } label: { Label("Retry", systemImage: "arrow.clockwise") }
                            }
                            Button(role: .destructive) { pendingDelete = episode } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await load() }
                .confirmationDialog(
                    "Delete this clip?",
                    isPresented: Binding(get: { pendingDelete != nil },
                                         set: { if !$0 { pendingDelete = nil } }),
                    presenting: pendingDelete
                ) { episode in
                    Button("Delete", role: .destructive) { Task { await delete(episode) } }
                    Button("Cancel", role: .cancel) {}
                } message: { episode in
                    Text(episode.title)
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: selectedCategory == nil) { selectedCategory = nil }
                ForEach(presentCategories, id: \.self) { category in
                    chip(category, selected: selectedCategory == category) {
                        selectedCategory = (selectedCategory == category) ? nil : category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func chip(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15), action) }) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.vertical, 7).padding(.horizontal, 14)
                .background(selected ? Color.primary : Color.primary.opacity(0.12), in: .capsule)
                .foregroundStyle(selected ? Color(.systemBackground) : .primary)
        }
        .buttonStyle(.plain)
    }

    private func delete(_ episode: Episode) async {
        let backup = episodes
        withAnimation { episodes.removeAll { $0.id == episode.id } }
        do {
            try await auth.api.deleteEpisode(id: episode.id)
        } catch {
            withAnimation { episodes = backup } // restore on failure
        }
    }

    /// Re-run the server pipeline for a failed episode.
    private func retry(_ episode: Episode) {
        Task {
            try? await auth.api.addEpisode(url: episode.url)
            await load()
        }
    }

    private func setCategory(_ episode: Episode, _ category: String?) {
        guard let i = episodes.firstIndex(where: { $0.id == episode.id }) else { return }
        let old = episodes[i].category
        withAnimation { episodes[i].category = category }
        // If the active filter no longer matches, fall back to All.
        if let selectedCategory, episodes[i].category != selectedCategory, !presentCategories.contains(selectedCategory) {
            self.selectedCategory = nil
        }
        Task {
            do { try await auth.api.setCategory(episodeID: episode.id, category: category) }
            catch { episodes[i].category = old }
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load clips", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { Task { await load() } }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var topBar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(.red)
                    .font(.title2)
                Text("Clip Learner")
                    .font(.title3.weight(.bold))
                    .tracking(-0.5)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if auth.isAuthenticated { showAdd = true } else { auth.requireLogin() }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: Data

    private func load() async {
        if episodes.isEmpty { loadState = .loading }
        do {
            episodes = try await auth.api.episodes()
            auth.setAuthenticated(true)
            loadState = .loaded
        } catch APIError.unauthorized {
            auth.setAuthenticated(false)
            episodes = []
            loadState = .needsAuth
        } catch {
            loadState = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

// MARK: - Feed card (left cover, right title)

private struct EpisodeCard: View {
    let episode: Episode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            cover
            info
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    private var cover: some View {
        AsyncImage(url: episode.thumbnailURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty:
                Rectangle().fill(.quaternary).overlay(ProgressView())
            default:
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "play.slash").foregroundStyle(.secondary))
            }
        }
        .frame(width: 150, height: 84)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(alignment: .bottomTrailing) {
            if let duration = episode.durationLabel {
                Text(duration)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.78), in: .rect(cornerRadius: 5))
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(episode.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(spacing: 5) {
                Image(systemName: episode.isReady ? "checkmark.circle.fill" : "clock")
                    .font(.caption2)
                    .foregroundStyle(episode.isReady ? .green : .orange)
                Text(episode.statusLabel)
                if !episode.createdAgoLabel.isEmpty {
                    Text("· \(episode.createdAgoLabel)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let category = episode.category {
                Text(category)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.tint.opacity(0.18), in: .capsule)
                    .foregroundStyle(.tint)
            }
        }
    }
}
