import SwiftUI

/// Settings section for Private Vault feature.
/// Provides navigation to the vault with a descriptive entry point.
struct VaultSettingsSection: View {
    @EnvironmentObject private var viewModel: VaultViewModel

    var body: some View {
        Section {
            NavigationLink {
                VaultListView()
                    .environmentObject(viewModel)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text("Private Vault")

                        Text("Encrypted, device-only journal")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(SupportTheme.accent)
                }
            }
            .accessibilityHint("Access your encrypted private journal entries")
        } header: {
            Text("Privacy")
        } footer: {
            Text(
                "Your vault entries are encrypted with AES-256 and stored only on this device. They are never synced to the cloud or used by AI."
            )
        }
        .listRowBackground(SupportTheme.surface)
    }
}

#Preview {
    NavigationStack {
        Form {
            VaultSettingsSection()
        }
    }
}
