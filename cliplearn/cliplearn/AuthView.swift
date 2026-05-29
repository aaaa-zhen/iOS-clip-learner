import SwiftUI

/// Login / sign-up, presented as a lightweight sheet (raised on demand, not a
/// launch wall). Grouped rounded fields + one prominent white primary button.
struct AuthView: View {
    let auth: AuthStore

    enum Mode { case login, signup }

    @State private var mode: Mode = .login
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    private enum Field { case username, password }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty && !auth.isSubmitting
    }

    private var primaryTitle: String { mode == .login ? "Sign In" : "Create Account" }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                Text(mode == .login ? "Sign in to Clip Learner" : "Create your account")
                    .font(.title2.weight(.bold))
                Text("Save words and sync with the web app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)

            VStack(spacing: 0) {
                field(.username)
                Divider().padding(.leading, 16)
                field(.password)
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))

            if let message = auth.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            Button(action: { Task { await submit() } }) {
                ZStack {
                    if auth.isSubmitting { ProgressView().tint(.black) }
                    Text(primaryTitle)
                        .font(.headline)
                        .opacity(auth.isSubmitting ? 0 : 1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .background(canSubmit ? Color.white : Color.white.opacity(0.25),
                        in: .rect(cornerRadius: 14))
            .foregroundStyle(.black)
            .disabled(!canSubmit)

            HStack(spacing: 6) {
                Text(mode == .login ? "New to Clip Learner?" : "Already have an account?")
                    .foregroundStyle(.secondary)
                Button(mode == .login ? "Sign Up" : "Sign In") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = (mode == .login) ? .signup : .login
                        auth.errorMessage = nil
                    }
                }
                .fontWeight(.semibold)
                .tint(.accentColor)
            }
            .font(.subheadline)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.2), value: auth.errorMessage)
    }

    @ViewBuilder
    private func field(_ which: Field) -> some View {
        Group {
            if which == .username {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
            } else {
                SecureField("Password", text: $password)
                    .textContentType(mode == .login ? .password : .newPassword)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
            }
        }
        .focused($focused, equals: which)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }

    private func submit() async {
        let name = username.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .login: await auth.login(username: name, password: password)
        case .signup: await auth.signup(username: name, password: password)
        }
    }
}
