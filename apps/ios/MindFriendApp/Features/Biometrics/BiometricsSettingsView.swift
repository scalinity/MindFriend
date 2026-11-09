import SwiftUI

// MARK: - Update Payloads

private struct SettingsUpdatePayload: Encodable {
    let enableInsights: Bool
    let enableAlerts: Bool
    let syncFrequencyHours: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case enableInsights = "enable_insights"
        case enableAlerts = "enable_alerts"
        case syncFrequencyHours = "sync_frequency_hours"
        case updatedAt = "updated_at"
    }
}

struct BiometricsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var healthKit: HealthKitService
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var loadedOwner: OfflineOwnerProof?
    @State private var settingsError: String?

    @State private var connection: HealthKitConnection?
    @State private var enableInsights = true
    @State private var enableAlerts = true
    @State private var syncFrequency = 6
    @State private var isLoading = true
    @State private var showDisconnectAlert = false
    @State private var showHealthChoices = false

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            Form {
                Section {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Health")
                            Text("via HealthKit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if healthKit.hasCompletedPermissionRequest {
                            Text(healthKit.syncPaused ? "Sync paused" : "Setup complete")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(healthKit.isHealthKitAvailable ? "Choose data" : "Unavailable")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if healthKit.isHealthKitAvailable {
                        Button(healthKit.syncPaused ? "Reconnect Apple Health" : "Choose Health data") { showHealthChoices = true }
                    }
                    if let failure = healthKit.connectionError {
                        Text("Sync is paused on this device, but your account could not be updated: \(failure.localizedDescription)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let lastSync = healthKit.lastSyncDate {
                        LabeledContent("Last Synced") {
                            Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                } header: {
                    Text("HealthKit Connection")
                } footer: {
                    Text("MindFriend requests read-only access. Apple keeps your choices private; setup completion does not mean any data was shared. Disconnecting only pauses syncing in MindFriend; it does not change Apple Health permissions.")
                }

                Section {
                    LabeledContent("Source", value: HealthQueryOutcome.sourceName)
                    if let outcome = healthKit.lastQueryOutcome {
                        LabeledContent("Period") {
                            Text("\(outcome.interval.start.formatted(date: .abbreviated, time: .omitted)) – \(outcome.interval.end.formatted(date: .abbreviated, time: .omitted))")
                        }
                        LabeledContent("Status", value: outcome.statusText)
                        LabeledContent("Checked") {
                            Text(outcome.checkedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let failure = outcome.failureDescription {
                            Text(failure).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent("Status", value: "Not checked yet")
                    }
                } header: {
                    Text("Latest Health check")
                } footer: {
                    Text("“No recent data available” means Apple Health returned nothing for that period. It does not tell us whether access was changed, and nothing blank is uploaded.")
                }

                Section {
                    ForEach(HealthKitDataType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundStyle(.pink)
                                .frame(width: 24)
                            Text(type.displayName)
                            Spacer()
                            Text(healthKit.hasCompletedPermissionRequest ? "Requested" : "Optional")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Requested data types")
                } footer: {
                    Text("You can manage HealthKit permissions in Settings > Privacy & Security > Health.")
                }

                Section {
                    Picker("Sync Frequency", selection: $syncFrequency) {
                        Text("Every hour").tag(1)
                        Text("Every 6 hours").tag(6)
                        Text("Every 12 hours").tag(12)
                        Text("Daily").tag(24)
                    }
                } header: {
                    Text("Sync Settings")
                }

                Section {
                    Toggle("Biometric Insights", isOn: $enableInsights)
                    Toggle("Health Alerts", isOn: $enableAlerts)
                } header: {
                    Text("Features")
                } footer: {
                    Text("Insights analyze patterns between your health data and mood. Alerts notify you when metrics deviate from your baseline.")
                }

                Section {
                    Button("Sync Now") {
                        Task {
                            try? await healthKit.syncBiometrics(days: 7)
                        }
                    }
                    .disabled(healthKit.isSyncing || !healthKit.isSyncEnabled)

                    Button("Trigger Analysis") {
                        Task {
                            try? await healthKit.triggerAnalysis()
                        }
                    }
                }

                if let settingsError { Section { Text(settingsError).foregroundStyle(.secondary) } }

                if healthKit.isSyncEnabled {
                    Section {
                        Button("Disconnect Apple Health", role: .destructive) {
                            showDisconnectAlert = true
                        }
                    }
                }
            }
            .navigationTitle("Apple Health & HealthKit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                }
            }
            .task {
                await loadSettings()
            }
            .sheet(isPresented: $showHealthChoices) { HealthKitConnectionSheet(healthKit: healthKit) }
            .alert("Disconnect Apple Health?", isPresented: $showDisconnectAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    disconnect()
                }
            } message: {
                Text("This stops syncing your Health data to MindFriend on this account. It does not change Apple Health permissions or delete data already synced. You can reconnect at any time.")
            }
        }
    }

    private func loadSettings() async {
        isLoading = true
        defer { isLoading = false }

        guard let owner = currentOwner else { return }
        do {
            let response: [HealthKitConnection] = try await supabase
                .from("healthkit_connections")
                .select()
                .eq("user_id", value: owner.userId)
                .limit(1)
                .execute()
                .value

            guard currentOwner == owner else { return }
            loadedOwner = owner
            if let conn = response.first {
                connection = conn
                enableInsights = conn.enableInsights
                enableAlerts = conn.enableAlerts
                syncFrequency = conn.syncFrequencyHours
            }
        } catch {
            if currentOwner == owner { settingsError = "Couldn’t load your Health settings. Try reopening this screen." }
        }
    }

    private var currentOwner: OfflineOwnerProof? {
        guard let id = appState.currentUser?.id, container.supabaseAuthService.userId == id,
              container.supabaseClient.auth.currentSession?.user.id == id else { return nil }
        return OfflineOwnerProof(userId: id, epoch: appState.accountEpoch)
    }

    private func saveAndDismiss() {
        guard let owner = loadedOwner, currentOwner == owner else { return }
        Task {
            do {
                let payload = SettingsUpdatePayload(
                    enableInsights: enableInsights,
                    enableAlerts: enableAlerts,
                    syncFrequencyHours: syncFrequency,
                    updatedAt: Date().ISO8601Format()
                )
                try await supabase
                    .from("healthkit_connections")
                    .update(payload)
                    .eq("user_id", value: owner.userId)
                    .execute()
                guard currentOwner == owner else { return }
                dismiss()
            } catch {
                if currentOwner == owner { settingsError = "Couldn’t save your Health settings. Try again." }
            }
        }
    }

    private func disconnect() {
        guard let owner = currentOwner else { return }
        Task {
            await healthKit.disconnect()
            // Keep the screen open if the account could not be told, so the failure is visible.
            if currentOwner == owner, healthKit.connectionError == nil { dismiss() }
        }
    }
}

#Preview {
    BiometricsSettingsView(healthKit: HealthKitService.shared)
}
