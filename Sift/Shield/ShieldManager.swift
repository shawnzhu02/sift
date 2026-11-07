#if SHIELD
import FamilyControls
import ManagedSettings
import SwiftUI

/// Phase 2: blocks the native Instagram and YouTube apps with Screen Time,
/// so the only way in is through Sift. Needs the Family Controls entitlement,
/// so it only compiles in the Shield configurations.
@MainActor
final class ShieldManager: ObservableObject {
    @Published var selection = FamilyActivitySelection()
    @Published private(set) var authorized = false

    private let settings = ManagedSettingsStore()
    private let key = "shieldSelection"

    init() {
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        }
    }

    var shieldedCount: Int { selection.applicationTokens.count }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            // Denied or cancelled. The status below says so.
        }
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    func apply() {
        let apps = selection.applicationTokens
        settings.shield.applications = apps.isEmpty ? nil : apps
        if let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct ShieldSection: View {
    @StateObject private var shield = ShieldManager()
    @State private var picking = false

    var body: some View {
        if shield.authorized {
            Button(shield.shieldedCount == 0 ? "Choose apps to block" : "Blocking \(shield.shieldedCount) app(s). Change") {
                picking = true
            }
            .familyActivityPicker(isPresented: $picking, selection: $shield.selection)
            .onChange(of: shield.selection) { shield.apply() }
            Text("Pick Instagram and YouTube. Opening them shows a Screen Time block.")
                .foregroundStyle(.secondary)
        } else {
            Button("Allow Screen Time access") {
                Task { await shield.requestAuthorization() }
            }
            Text("Needed to block the native Instagram and YouTube apps.")
                .foregroundStyle(.secondary)
        }
    }
}
#endif
