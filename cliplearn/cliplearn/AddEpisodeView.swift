import SwiftUI

/// Paste a YouTube (or X) URL to generate a new episode. The server downloads,
/// transcribes, and analyzes it; the new clip appears in the feed as "Fetching…"
/// and updates to "Ready" as the home feed polls.
struct AddEpisodeView: View {
    let api: APIClient
    let onAdded: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var submitting = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var canSubmit: Bool {
        url.trimmingCharacters(in: .whitespaces).hasPrefix("http") && !submitting
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 38))
                        .foregroundStyle(.red)
                    Text("Add a clip")
                        .font(.title2.weight(.bold))
                    Text("Paste a YouTube link. We'll transcribe and analyze it for you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                TextField("https://youtube.com/watch?v=…", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
                    .padding(.horizontal, 16).padding(.vertical, 15)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: { Task { await submit() } }) {
                    ZStack {
                        if submitting { ProgressView().tint(.black) }
                        Text("Add").font(.headline).opacity(submitting ? 0 : 1)
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                }
                .background(canSubmit ? Color.white : Color.white.opacity(0.25), in: .rect(cornerRadius: 14))
                .foregroundStyle(.black)
                .disabled(!canSubmit)

                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationTitle("New Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        submitting = true
        error = nil
        defer { submitting = false }
        do {
            try await api.addEpisode(url: url.trimmingCharacters(in: .whitespaces))
            await onAdded()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
