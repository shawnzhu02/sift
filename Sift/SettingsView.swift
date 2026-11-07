import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: WebStore
    @EnvironmentObject private var accounts: AccountStatus
    @State private var confirmSignOut = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text("Sift").font(.title2.bold())
                    Text("Swipe left or right to switch pages")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Accounts") {
                ForEach(SiteID.allCases) { site in
                    HStack(spacing: 12) {
                        SiteBadge(site: site, size: 30)
                        Text(site == .instagram ? "Instagram" : "YouTube")
                        Spacer()
                        if accounts.isConnected(site) {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        } else {
                            Button("Connect") { store.connect(site) }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule)
                        }
                    }
                }
            }

            Section("Instagram") {
                shortcut("Instagram settings", "gearshape", "https://www.instagram.com/accounts/edit/", .instagram)
            }

            Section("YouTube") {
                shortcut("Library", "books.vertical", "https://m.youtube.com/feed/library", .youtube)
                shortcut("History", "clock.arrow.circlepath", "https://m.youtube.com/feed/history", .youtube)
                shortcut("Google account", "person.crop.circle", "https://myaccount.google.com/", .youtube)
            }

            Section {
                DisclosureGroup {
                    blockedRow("Instagram", "Home, Explore and the Reels feed go to your inbox. A reel or story opens only from a DM, one at a time.")
                    blockedRow("YouTube", "Home and Shorts go to Subscriptions. Recommendations, up next, autoplay and ads are hidden. A shared Short plays once as a normal video.")
                } label: {
                    Label("What Sift blocks", systemImage: "hand.raised")
                }
            }

            Section("Native apps") {
                #if SHIELD
                ShieldSection()
                #else
                Label {
                    Text("Delete the Instagram and YouTube apps, or give them a 1 minute Screen Time limit with a passcode someone else knows. Sift will block them itself once Apple approves Screen Time access.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "hourglass")
                }
                #endif
            }

            Section {
                Button(role: .destructive) { confirmSignOut = true } label: {
                    Label("Sign out of everything", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text(versionText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog(
            "Sign out of Instagram and YouTube?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) { store.signOutEverywhere() }
        }
    }

    private func shortcut(_ title: String, _ symbol: String, _ url: String, _ site: SiteID) -> some View {
        Button {
            store.open(URL(string: url)!, in: site)
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    private func blockedRow(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Sift \(version) (\(build))"
    }
}
