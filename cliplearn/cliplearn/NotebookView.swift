import SwiftUI

/// The vocabulary notebook — words and lines saved while studying, synced with
/// the web app via `GET /api/notebook`. Swipe to delete.
struct NotebookView: View {
    let auth: AuthStore

    @State private var entries: [NotebookEntry] = []
    @State private var loadState: LoadState = .loading
    @State private var query = ""
    @State private var selectedCategory: String?

    enum LoadState: Equatable { case loading, loaded, needsAuth, failed(String) }

    /// Distinct categories (part-of-speech) present, for the filter chips.
    private var presentCategories: [String] {
        Array(Set(entries.compactMap { c in
            (c.category?.isEmpty == false) ? c.category : nil
        })).sorted()
    }

    private var filteredEntries: [NotebookEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { entry in
            let matchesCategory = selectedCategory == nil || entry.category == selectedCategory
            guard matchesCategory else { return false }
            guard !q.isEmpty else { return true }
            return entry.word.lowercased().contains(q)
                || (entry.definition?.lowercased().contains(q) ?? false)
                || (entry.example?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading where entries.isEmpty:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .needsAuth:
                    signInPrompt
                case .failed(let message) where entries.isEmpty:
                    ContentUnavailableView {
                        Label("Couldn't load notebook", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") { Task { await load() } }.buttonStyle(.bordered)
                    }
                default:
                    content
                }
            }
            .navigationTitle("Notebook")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search words")
        }
        .task { await load() }
        .onChange(of: auth.isAuthenticated) { _, signedIn in
            if signedIn { Task { await load() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            ContentUnavailableView("No saved words yet", systemImage: "book",
                description: Text("Tap a word in the transcript, or save a line — it'll show up here."))
        } else {
            VStack(spacing: 0) {
                if !presentCategories.isEmpty { categoryChips }
                if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            NotebookRow(entry: entry)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await delete(entry) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await load() }
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
            .padding(.vertical, 8)
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

    private var signInPrompt: some View {
        ContentUnavailableView {
            Label("Sign in to see your notebook", systemImage: "person.crop.circle")
        } description: {
            Text("Words you save sync with the Clip Learner web app.")
        } actions: {
            Button { auth.requireLogin() } label: {
                Text("Sign In").font(.headline).foregroundStyle(.black)
                    .padding(.horizontal, 32).padding(.vertical, 12)
                    .background(.white, in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }

    private func load() async {
        if entries.isEmpty { loadState = .loading }
        do {
            entries = try await auth.api.notebook()
            auth.setAuthenticated(true)
            loadState = .loaded
        } catch APIError.unauthorized {
            auth.setAuthenticated(false)
            entries = []
            loadState = .needsAuth
        } catch {
            loadState = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func delete(_ entry: NotebookEntry) async {
        let backup = entries
        withAnimation { entries.removeAll { $0.id == entry.id } }
        do { try await auth.api.deleteNotebookEntry(id: entry.id) }
        catch { withAnimation { entries = backup } }
    }
}

private struct NotebookRow: View {
    let entry: NotebookEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.word)
                    .font(.headline)
                    .lineLimit(3)
                if let phonetic = entry.phonetic, !phonetic.isEmpty {
                    Text(phonetic).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if let definition = entry.definition, !definition.isEmpty {
                Text(definition).font(.callout).foregroundStyle(.primary.opacity(0.9))
            }
            if let example = entry.example, !example.isEmpty {
                Text(example).font(.footnote).italic().foregroundStyle(.secondary)
            }
            if let title = entry.episode_title, !title.isEmpty {
                Label(title, systemImage: "play.rectangle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }
}
