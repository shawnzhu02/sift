import SwiftUI

@main
struct SiftApp: App {
    @StateObject private var store = WebStore()
    @StateObject private var accounts = AccountStatus()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(accounts)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: WebStore
    @EnvironmentObject private var accounts: AccountStatus
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("connectDismissed") private var connectDismissed = false
    @State private var showConnect = false
    @State private var showIndicator = false
    @State private var hideIndicator: Task<Void, Never>?

    var body: some View {
        PagerView()
            .overlay(alignment: .bottom) {
                PageIndicator(page: store.page)
                    .opacity(showIndicator ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: showIndicator)
                    .allowsHitTesting(false)
                    .padding(.bottom, 28)
            }
            .overlay(alignment: .top) {
                if let site = accounts.justConnected {
                    Toast(text: "\(site == .instagram ? "Instagram" : "YouTube") connected")
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: accounts.justConnected)
            .onChange(of: store.page) { flashIndicator() }
            .onChange(of: accounts.justConnected) {
                guard accounts.justConnected != nil else { return }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    accounts.justConnected = nil
                }
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active { accounts.refresh() }
            }
            .task {
                // Give the cookie store a moment to report before deciding.
                try? await Task.sleep(for: .milliseconds(600))
                if !accounts.allConnected && !connectDismissed { showConnect = true }
            }
            .fullScreenCover(isPresented: $showConnect) {
                ConnectView {
                    connectDismissed = true
                    showConnect = false
                }
                .environmentObject(store)
                .environmentObject(accounts)
            }
    }

    private func flashIndicator() {
        showIndicator = true
        hideIndicator?.cancel()
        hideIndicator = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            showIndicator = false
        }
    }
}

/// The three pages side by side, sliding to the current one.
/// Web pages run edge to edge; there is no tab bar.
struct PagerView: View {
    @EnvironmentObject private var store: WebStore

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Page.allCases) { page in
                    pageView(page)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .offset(x: -CGFloat(store.page.rawValue) * geo.size.width)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: store.page)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        if let site = page.site {
            // Edge to edge: WebKit keeps the page's content clear of the status bar
            // and home indicator, and paints those strips in the page's own color.
            WebTab(controller: store.controller(site))
                .ignoresSafeArea()
        } else {
            SettingsView()
                .contentShape(Rectangle())
                .simultaneousGesture(swipe)
        }
    }

    /// Same thresholds as swipe.js: a clear sideways flick.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) >= 70, abs(dx) >= 2.2 * abs(dy) else { return }
                store.step(dx < 0 ? 1 : -1)
            }
    }
}

/// Dots plus the page name, shown briefly after a switch.
struct PageIndicator: View {
    let page: Page

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Page.allCases) { p in
                    Circle()
                        .fill(p == page ? Color.primary : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
            }
            Text(page.title)
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}

struct Toast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.green.gradient, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}
