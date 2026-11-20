import SwiftUI

/// Sift's own bottom bar: one button per visible tab. Tapping the current
/// tab again takes its page back to the start.
struct TabBar: View {
    @EnvironmentObject private var store: WebStore
    @EnvironmentObject private var features: FeatureStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SiftTab.visible(features.features)) { tab in
                Button {
                    store.select(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7)
                    .padding(.bottom, 4)
                    .foregroundStyle(store.tab == tab ? Color.accentColor : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(store.tab == tab ? .isSelected : [])
            }
        }
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
        }
    }
}

/// The Clips tab: Reels or Shorts, with a switch between them when both are on.
struct ClipsPage: View {
    @EnvironmentObject private var store: WebStore
    @EnvironmentObject private var features: FeatureStore
    @EnvironmentObject private var clips: ClipAllowlist

    private var sites: [SiteID] {
        SiteID.allCases.filter { features.features.clips($0) != .off }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach([WebRole.reels, WebRole.shorts], id: \.self) { role in
                WebPage(controller: store.controller(role))
                    .opacity(store.clipRole == role ? 1 : 0)
                    .allowsHitTesting(store.clipRole == role)
            }

            VStack(spacing: 8) {
                if sites.count > 1 {
                    Picker("Clips", selection: $store.clipSite) {
                        Text("Reels").tag(SiteID.instagram)
                        Text("Shorts").tag(SiteID.youtube)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .padding(4)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                if features.features.clips(store.clipSite) == .following, clips.list(store.clipSite).ids.isEmpty {
                    Text(store.clipSite == .instagram
                         ? "No reels yet. Scroll this feed so Sift can find reels from people you follow, then tap Clips again."
                         : "No Shorts yet. Scroll your subscriptions here so Sift can find their Shorts, then tap Clips again.")
                        .font(.footnote.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 24)
                }
            }
            .padding(.top, 6)
        }
    }
}
