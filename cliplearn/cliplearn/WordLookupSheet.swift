import SwiftUI

/// Word/phrase explanation shown as a popover anchored to the tapped word.
/// Calls `POST /api/explain` and renders the result like the web word popup.
struct WordLookupSheet: View {
    let word: String
    let currentLine: String
    let episodeTitle: String
    let api: APIClient

    @State private var phase: Phase = .loading

    enum Phase {
        case loading
        case loaded(WordExplanation)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch phase {
            case .loading:
                header(word)
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            case .loaded(let entry):
                header(entry.phrase?.isEmpty == false ? entry.phrase! : word,
                       phonetic: entry.phonetic, pos: entry.partOfSpeech)
                if let definition = entry.definition, !definition.isEmpty {
                    Text(definition).font(.callout)
                }
                if let example = entry.example, !example.isEmpty {
                    Label {
                        Text(example).italic()
                    } icon: {
                        Image(systemName: "text.quote")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            case .failed(let message):
                header(word)
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("Retry") { Task { await load() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(18)
        .frame(width: 290, alignment: .leading)
        .task { await load() }
    }

    private func header(_ title: String, phonetic: String? = nil, pos: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
            HStack(spacing: 8) {
                if let phonetic, !phonetic.isEmpty {
                    Text(phonetic).foregroundStyle(.secondary)
                }
                if let pos, !pos.isEmpty {
                    Text(pos)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.tint.opacity(0.18), in: .capsule)
                        .foregroundStyle(.tint)
                }
            }
            .font(.subheadline)
        }
    }

    private func load() async {
        phase = .loading
        do {
            let entry = try await api.explain(word: word, currentLine: currentLine, episodeTitle: episodeTitle)
            phase = .loaded(entry)
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
