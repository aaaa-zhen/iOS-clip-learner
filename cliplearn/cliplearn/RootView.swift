import SwiftUI

/// App root. Uses the native iOS 26 `TabView`, which renders the Liquid Glass
/// floating tab bar (and the morphing search field) for free. Each tab owns its
/// own navigation, so HomeView keeps its internal `NavigationStack`.
struct RootView: View {
    let auth: AuthStore

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView(auth: auth)
            }

            Tab("Notebook", systemImage: "book") {
                NotebookView(auth: auth)
            }

            Tab("Profile", systemImage: "person") {
                ProfileView(auth: auth)
            }
        }
    }
}

/// Minimal account tab — currently just the log-out action.
private struct ProfileView: View {
    let auth: AuthStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if auth.isAuthenticated {
                        Button(role: .destructive) {
                            auth.signOut()
                        } label: {
                            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        Button {
                            auth.requireLogin()
                        } label: {
                            Label("Sign In", systemImage: "person.crop.circle")
                        }
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    RootView(auth: AuthStore())
}
