import SwiftUI

@main
struct SiftApp: App {
    @StateObject private var store = WebStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: WebStore

    var body: some View {
        TabView(selection: $store.selected) {
            ForEach(SiteID.allCases) { site in
                WebTab(controller: store.controller(site))
                    .tabItem { Label(Site.title(site), systemImage: Site.symbol(site)) }
                    .tag(AppTab.site(site))
            }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}
