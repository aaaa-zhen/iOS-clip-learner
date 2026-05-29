import SwiftUI
import Observation

/// Login state + an on-demand login prompt. The app is usable without a full
/// login wall: `showLogin` drives a login *sheet* that we raise only when an
/// action needs an account (e.g. saving a word) or the user opts in.
@MainActor
@Observable
final class AuthStore {
    private(set) var isAuthenticated = false
    var showLogin = false
    var errorMessage: String?
    var isSubmitting = false

    let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    /// Silent session probe at launch — sets `isAuthenticated` without gating UI.
    func bootstrap() async {
        do {
            _ = try await api.episodes()
            isAuthenticated = true
        } catch {
            isAuthenticated = false
        }
    }

    func setAuthenticated(_ value: Bool) { isAuthenticated = value }

    /// Raise the login sheet (call before an action that needs an account).
    func requireLogin() {
        errorMessage = nil
        showLogin = true
    }

    func login(username: String, password: String) async {
        await submit { try await self.api.login(username: username, password: password) }
    }

    func signup(username: String, password: String) async {
        await submit { try await self.api.signup(username: username, password: password) }
    }

    func signOut() {
        api.clearStoredCookies()
        isAuthenticated = false
    }

    private func submit(_ work: () async throws -> Void) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await work()
            isAuthenticated = true
            showLogin = false
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
