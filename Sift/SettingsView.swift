import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: WebStore
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section("Instagram") {
                    Text("Only DMs, profiles, posts, search and settings.")
                    Text("Home, Explore and the Reels feed go to your inbox. A reel or story opens only from a DM, one at a time.")
                        .foregroundStyle(.secondary)
                    Button("Instagram settings") {
                        store.open(URL(string: "https://www.instagram.com/accounts/edit/")!, in: .instagram)
                    }
                }

                Section("YouTube") {
                    Text("Only Subscriptions, search, channels and videos.")
                    Text("Home and Shorts go to Subscriptions. Recommendations, up next and autoplay are hidden. A shared Short plays as one normal video.")
                        .foregroundStyle(.secondary)
                    Button("YouTube account") {
                        store.open(URL(string: "https://m.youtube.com/account")!, in: .youtube)
                    }
                }

                Section("Native apps") {
                    #if SHIELD
                    ShieldSection()
                    #else
                    Text("Blocking the Instagram and YouTube apps needs Apple's Screen Time approval, which is pending.")
                    Text("Until then, delete those apps, or set a 1 minute Screen Time limit on them with a passcode someone else knows.")
                        .foregroundStyle(.secondary)
                    #endif
                }

                Section {
                    Button("Sign out of everything", role: .destructive) { confirmSignOut = true }
                } footer: {
                    Text(versionText)
                }
            }
            .navigationTitle("Sift")
            .confirmationDialog(
                "Sign out of Instagram and YouTube?",
                isPresented: $confirmSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) { store.signOutEverywhere() }
            }
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Sift \(version) (\(build))"
    }
}
