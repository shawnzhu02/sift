import SwiftUI

@main
struct SiftApp: App {
    @StateObject private var store = WebStore()
    @StateObject private var accounts = AccountStatus()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(store.features)
                .environmentObject(store.clips)
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

    var body: some View {
        VStack(spacing: 0) {
            PagerView()
            TabBar()
        }
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                if let site = accounts.justConnected {
                    Toast(text: "\(site == .instagram ? "Instagram" : "YouTube") connected", symbol: "checkmark.circle.fill", tint: .green)
                }
                if let note = store.note {
                    Toast(text: note, symbol: "hand.raised.fill", tint: .indigo)
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(.top, 6)
            .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: accounts.justConnected)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.note)
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
            #if DEBUG
            if TestPage.isActive { return }
            #endif
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
}

/// The visible tabs side by side, sliding to the current one. Every web
/// view stays alive, so switching tabs never reloads a page.
struct PagerView: View {
    @EnvironmentObject private var store: WebStore
    @EnvironmentObject private var features: FeatureStore

    var body: some View {
        let tabs = SiftTab.visible(features.features)
        let index = CGFloat(tabs.firstIndex(of: store.tab) ?? 0)
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    page(tab)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .offset(x: -index * geo.size.width)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: store.tab)
        }
        .clipped()
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private func page(_ tab: SiftTab) -> some View {
        switch tab {
        case .messages:
            WebPage(controller: store.controller(.messages))
        case .feed:
            WebPage(controller: store.controller(.feed))
        case .clips:
            ClipsPage()
        case .subscriptions:
            WebPage(controller: store.controller(.subscriptions))
        case .settings:
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

/// A web page inside the safe area, with the status bar strip painted in the
/// page's own color so it still looks edge to edge. The tab bar sits below it.
struct WebPage: View {
    @ObservedObject var controller: WebController

    var body: some View {
        WebTab(controller: controller)
            .background(controller.pageColor.ignoresSafeArea(edges: .top))
    }
}

struct Toast: View {
    let text: String
    var symbol = "checkmark.circle.fill"
    var tint: Color = .green

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tint.gradient, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}
