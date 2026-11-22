import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: WebStore
    @EnvironmentObject private var accounts: AccountStatus
    @EnvironmentObject private var featureStore: FeatureStore
    @State private var confirmSignOut = false
    @State private var confirmReset = false

    private var f: Binding<Features> { $featureStore.features }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text("Sift").font(.title2.bold())
                    Text("Pick exactly what each app is allowed to show you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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

            instagramSection
            youtubeSection

            Section {
                DisclosureGroup {
                    summaryRow("Instagram", featureStore.features.blockedSummary(for: .instagram))
                    summaryRow("YouTube", featureStore.features.blockedSummary(for: .youtube))
                } label: {
                    Label("What Sift blocks right now", systemImage: "hand.raised")
                }
                Button {
                    confirmReset = true
                } label: {
                    Label("Back to strict", systemImage: "arrow.counterclockwise")
                }
                .disabled(featureStore.features == .strict)
            } footer: {
                Text("Strict is DMs and Subscriptions only: no feeds, no Reels or Shorts.")
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
                // Redrawn when new filters arrive (store.filtersUpdated is published).
                VStack(spacing: 2) {
                    Text(versionText)
                    Text(FilterUpdates.statusText)
                }
                    .multilineTextAlignment(.center)
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
        .confirmationDialog(
            "Turn every switch back to strict?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Back to strict", role: .destructive) { featureStore.reset() }
        }
    }

    // MARK: - Instagram

    private var instagramSection: some View {
        Section {
            ClipModeRow(
                title: "Reels",
                symbol: "play.square.stack",
                mode: f.igReels,
                detail: clipDetail(featureStore.features.igReels, who: "people you follow")
            )
            SwitchRow("Feed", "square.grid.2x2", "Home, showing only people you follow. Adds a Feed tab.", f.igFeed)
            SwitchRow("Posting", "plus.app", "Make posts. The Feed tab keeps Instagram's own Create button.", f.igPosting)
            SwitchRow("Profiles", "person.crop.circle", "Open people's profile pages.", f.igProfiles)
            SwitchRow("Stories", "circle.dashed", "One person's stories at a time, never on to someone else's.", f.igStories)
            SwitchRow("Search", "magnifyingglass", "Search for people.", f.igSearch)
            SwitchRow("Notifications", "heart", "Likes, follows and comments on your posts.", f.igNotifications)
            SwitchRow("Explore", "safari", "The recommended Explore grid.", f.igExplore)
            shortcut("Instagram settings", "gearshape", "https://www.instagram.com/accounts/edit/", .instagram)
        } header: {
            Text("Instagram")
        } footer: {
            Text("Your DMs are always on.")
        }
    }

    // MARK: - YouTube

    private var youtubeSection: some View {
        Section {
            ClipModeRow(
                title: "Shorts",
                symbol: "play.square.stack",
                mode: f.ytShorts,
                detail: clipDetail(featureStore.features.ytShorts, who: "channels you subscribe to")
            )
            SwitchRow("Search", "magnifyingglass", "Search for videos and channels.", f.ytSearch)
            SwitchRow("Comments", "text.bubble", "Comments under videos.", f.ytComments)
            SwitchRow("Library", "books.vertical", "Your history, playlists and Watch later.", f.ytLibrary)
            SwitchRow("Up next", "list.bullet.below.rectangle", "Related videos under a video and the end screen.", f.ytUpNext)
            SwitchRow("Autoplay", "play.circle", "Start the next video when one ends.", f.ytAutoplay)
            SwitchRow("Home", "house", "YouTube's recommended Home feed and trending.", f.ytHome)
            if featureStore.features.ytLibrary {
                shortcut("Library", "books.vertical", "https://m.youtube.com/feed/library", .youtube)
                shortcut("History", "clock.arrow.circlepath", "https://m.youtube.com/feed/history", .youtube)
            }
            shortcut("Google account", "person.crop.circle", "https://myaccount.google.com/", .youtube)
        } header: {
            Text("YouTube")
        } footer: {
            Text("Your Subscriptions are always on.")
        }
    }

    private func clipDetail(_ mode: ClipMode, who: String) -> String {
        switch mode {
        case .off: return "Only ones sent to you in a DM or a link, one at a time."
        case .following: return "Only from \(who). Swiping stops after the last one. Adds a Clips tab."
        case .all: return "Everything, including recommendations. Adds a Clips tab."
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

    private func summaryRow(_ title: String, _ text: String) -> some View {
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

/// One on/off switch with a plain one-line description under its name.
struct SwitchRow: View {
    let title: String
    let symbol: String
    let detail: String
    @Binding var isOn: Bool

    init(_ title: String, _ symbol: String, _ detail: String, _ isOn: Binding<Bool>) {
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
            }
        }
    }
}

/// Off / Following / All for Reels or Shorts.
struct ClipModeRow: View {
    let title: String
    let symbol: String
    @Binding var mode: ClipMode
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
            Picker(title, selection: $mode) {
                ForEach(ClipMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
