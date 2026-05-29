import SwiftUI

/// Word/phrase explanation shown as a popover anchored to the tapped word.
/// Calls `POST /api/explain` and renders the result like the web word popup,
/// with a "Save to Notebook" action.
struct WordLookupSheet: View {
    let word: String
    let currentLine: String
    let episodeTitle: String
    let episodeID: String
    let sourceTime: Double
    let api: APIClient

    @State private var phase: Phase = .loading
    @State private var saveState: SaveState = .idle

    enum Phase {
        case loading
        case loaded(WordExplanation)
        case failed(String)
    }

    enum SaveState { case idle, saving, saved, failed }

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
                saveButton(entry)
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

    @ViewBuilder
    private func saveButton(_ entry: WordExplanation) -> some View {
        Button {
            Task { await save(entry) }
        } label: {
            HStack(spacing: 6) {
                switch saveState {
                case .idle:
                    Image(systemName: "bookmark"); Text("Save to Notebook")
                case .saving:
                    ProgressView().controlSize(.small)
                case .saved:
                    Image(systemName: "checkmark"); Text("Saved")
                case .failed:
                    Image(systemName: "exclamationmark.triangle"); Text("Try again")
                }
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(saveState == .saved ? Color.green.opacity(0.2) : Color.primary.opacity(0.1),
                        in: .capsule)
            .foregroundStyle(saveState == .saved ? .green : .primary)
        }
        .buttonStyle(.plain)
        .disabled(saveState == .saving || saveState == .saved)
        .padding(.top, 4)
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

    private func save(_ entry: WordExplanation) async {
        saveState = .saving
        let term = entry.phrase?.isEmpty == false ? entry.phrase! : word
        do {
            try await api.saveWord(
                word: term, definition: entry.definition, example: entry.example,
                phonetic: entry.phonetic, sourceText: currentLine,
                episodeID: episodeID, sourceTime: sourceTime, category: entry.partOfSpeech
            )
            saveState = .saved
        } catch APIError.server(let status, _) where status == 409 {
            saveState = .saved // already in the notebook — treat as success
        } catch {
            saveState = .failed
        }
    }
}
