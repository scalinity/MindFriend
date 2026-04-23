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

private struct DisconnectPayload: Encodable {
    let isConnected: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case isConnected = "is_connected"
        case updatedAt = "updated_at"
    }
}

struct BiometricsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var healthKit: HealthKitService

    @State private var connection: HealthKitConnection?
    @State private var enableInsights = true
    @State private var enableAlerts = true
    @State private var syncFrequency = 6
    @State private var isLoading = true
    @State private var showDisconnectAlert = false

    var body: some View {
        NavigationStack {
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
                        if healthKit.isAuthorized {
                            Text("Connected")
                                .foregroundStyle(.green)
                        } else {
                            Text("Not Connected")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let lastSync = healthKit.lastSyncDate {
                        LabeledContent("Last Synced") {
                            Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                } header: {
                    Text("HealthKit Connection")
                } footer: {
                    Text("MindFriend uses Apple's HealthKit framework to read and write data to the Apple Health app.")
                }

                Section {
                    ForEach(HealthKitDataType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundStyle(.pink)
                                .frame(width: 24)
                            Text(type.displayName)
                            Spacer()
                            if healthKit.authorizedTypes.contains(type) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Data Types")
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
                    .disabled(healthKit.isSyncing)

                    Button("Trigger Analysis") {
                        Task {
                            try? await healthKit.triggerAnalysis()
                        }
                    }
                }

                if healthKit.isAuthorized {
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
            .alert("Disconnect Apple Health?", isPresented: $showDisconnectAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    disconnect()
                }
            } message: {
                Text("This will stop syncing your health data to MindFriend. You can reconnect at any time.")
            }
        }
    }

    private func loadSettings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response: [HealthKitConnection] = try await supabase
                .from("healthkit_connections")
                .select()
                .limit(1)
                .execute()
                .value

            if let conn = response.first {
                connection = conn
                enableInsights = conn.enableInsights
                enableAlerts = conn.enableAlerts
                syncFrequency = conn.syncFrequencyHours
            }
        } catch {
            Log.biometrics.error("Failed to load settings", error: error)
        }
    }

    private func saveAndDismiss() {
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
                    .execute()
            } catch {
                Log.biometrics.error("Failed to save settings", error: error)
            }
        }
        dismiss()
    }

    private func disconnect() {
        Task {
            do {
                let payload = DisconnectPayload(
                    isConnected: false,
                    updatedAt: Date().ISO8601Format()
                )
                try await supabase
                    .from("healthkit_connections")
                    .update(payload)
                    .execute()

                await healthKit.checkAuthorizationStatus()
            } catch {
                Log.biometrics.error("Failed to disconnect", error: error)
            }
        }
        dismiss()
    }
}

#Preview {
    BiometricsSettingsView(healthKit: HealthKitService.shared)
}
