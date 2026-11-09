import SwiftUI

/// Presentation preference only. Sensors, mood entries and server recovery flags never enable it.
enum SupportSimplerViewPreference {
    static func key(ownerID: UUID) -> String { "mf.support.simpler.\(ownerID.uuidString.lowercased())" }
    static func isEnabled(ownerID: UUID) -> Bool { UserDefaults.standard.bool(forKey: key(ownerID: ownerID)) }
    static func setEnabled(_ value: Bool, ownerID: UUID) {
        UserDefaults.standard.set(value, forKey: key(ownerID: ownerID))
    }
}

struct SupportSimplerViewSettings: View {
    @EnvironmentObject private var coordinator: SupportSessionCoordinator
    var body: some View { AccountSimplerViewSettings(ownerID: coordinator.identity.ownerID) }
}

private struct AccountSimplerViewSettings: View {
    @AppStorage private var enabled: Bool
    init(ownerID: UUID) {
        _enabled = AppStorage(wrappedValue: false, SupportSimplerViewPreference.key(ownerID: ownerID))
    }
    var body: some View {
        List {
            Section {
                Toggle("Use simpler view", isOn: $enabled)
            } footer: {
                Text(
                    "Hide optional check-in and pin rows on Today. You can turn this off immediately, whenever you choose."
                )
            }
            .listRowBackground(SupportTheme.surface)
            Section {
                Text(
                    "Your session, all four tabs, practices and Help stay available. This choice applies on this device."
                )
            }
            .listRowBackground(SupportTheme.surface)
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Simpler view")
        .supportCanvas()
    }
}
