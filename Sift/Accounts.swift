import SwiftUI
import WebKit

/// Tracks whether Instagram and YouTube are signed in, by watching the
/// shared cookie store both web views use.
@MainActor
final class AccountStatus: NSObject, ObservableObject {
    @Published private(set) var instagram = false
    @Published private(set) var youtube = false
    /// Set when a site becomes connected, for a short toast.
    @Published var justConnected: SiteID?

    private let cookies = WKWebsiteDataStore.default().httpCookieStore
    private var loaded = false

    override init() {
        super.init()
        cookies.add(self)
        refresh()
    }

    func isConnected(_ site: SiteID) -> Bool {
        site == .instagram ? instagram : youtube
    }

    var allConnected: Bool { instagram && youtube }

    func refresh() {
        cookies.getAllCookies { [weak self] all in
            Task { @MainActor in self?.update(all) }
        }
    }

    private func update(_ all: [HTTPCookie]) {
        let now = Date()
        func has(_ domain: String, _ names: Set<String>) -> Bool {
            all.contains { c in
                let d = c.domain.lowercased()
                let live = c.expiresDate.map { $0 > now } ?? true
                return live && names.contains(c.name) && (d == domain || d.hasSuffix("." + domain))
            }
        }
        let ig = has("instagram.com", ["sessionid"])
        let yt = has("youtube.com", ["LOGIN_INFO", "SID", "__Secure-3PSID"])

        // Only celebrate changes after the first read (not on app launch).
        if loaded {
            if ig && !instagram { justConnected = .instagram }
            if yt && !youtube { justConnected = .youtube }
        }
        loaded = true
        instagram = ig
        youtube = yt
    }
}

extension AccountStatus: WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in self.refresh() }
    }
}

/// First-run screen: connect both accounts and learn the swipe.
struct ConnectView: View {
    @EnvironmentObject private var store: WebStore
    @EnvironmentObject private var accounts: AccountStatus
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Welcome to Sift")
                    .font(.largeTitle.bold())
                Text("Just your DMs and your subscriptions.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                ConnectCard(site: .instagram) { connect(.instagram) }
                ConnectCard(site: .youtube) { connect(.youtube) }
            }

            VStack(alignment: .leading, spacing: 14) {
                Tip(symbol: "key.fill",
                    text: "Tap the password box, then **Passwords** above the keyboard. Face ID fills in your saved password.")
                Tip(symbol: "hand.draw.fill",
                    text: "Swipe left or right anywhere to switch between **Messages**, **Subscriptions** and **Settings**.")
                Tip(symbol: "checkmark.shield.fill",
                    text: "You log in once. Sift remembers you.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()

            Button(action: dismiss) {
                Text(accounts.allConnected ? "Done" : "Skip for now")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func connect(_ site: SiteID) {
        store.connect(site)
        dismiss()
    }
}

/// One account row with its status and a Connect button.
struct ConnectCard: View {
    @EnvironmentObject private var accounts: AccountStatus
    let site: SiteID
    var action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            SiteBadge(site: site)
            VStack(alignment: .leading, spacing: 2) {
                Text(site == .instagram ? "Instagram" : "YouTube").font(.headline)
                Text(accounts.isConnected(site) ? "Connected" : "Not connected")
                    .font(.subheadline)
                    .foregroundStyle(accounts.isConnected(site) ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
            }
            Spacer()
            if accounts.isConnected(site) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            } else {
                Button("Connect", action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Small colored square with the site's symbol.
struct SiteBadge: View {
    let site: SiteID
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size / 4, style: .continuous)
            .fill(site == .instagram
                  ? AnyShapeStyle(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                  : AnyShapeStyle(Color.red))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: site == .instagram ? "bubble.left.and.bubble.right.fill" : "play.fill")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

private struct Tip: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
