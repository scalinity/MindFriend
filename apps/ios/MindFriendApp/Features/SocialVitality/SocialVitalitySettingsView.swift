//
//  SocialVitalitySettingsView.swift
//  MindFriend
//
//  Created: 2026-01-27
//  Feature: N004 - Social Vitality Index Settings
//

import SwiftUI

struct SocialVitalitySettingsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Binding var isPresented: Bool
    @ObservedObject var engine: SocialVitalityEngine

    @State private var alertsEnabled = true
    @State private var alertFrequency: AlertFrequency = .daily
    @State private var scoreThreshold = 50
    @State private var selectedSupporters: Set<String> = []
    @State private var availableSupporters: [SocialVitalityDashboard.SupporterInfo] = []
    @State private var isSaving = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView()
                } else {
                    // Peer Support Alerts Section
                    Section {
                        Toggle("Enable alerts", isOn: $alertsEnabled)

                        if alertsEnabled {
                            Picker("Frequency", selection: $alertFrequency) {
                                Text("Daily").tag(AlertFrequency.daily)
                                Text("Weekly").tag(AlertFrequency.weekly)
                                Text("When score drops").tag(AlertFrequency.threshold)
                            }

                            if alertFrequency == .threshold {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Alert when score drops below: \(scoreThreshold)")
                                        .font(.subheadline)

                                    Slider(value: Binding(
                                        get: { Double(scoreThreshold) },
                                        set: { scoreThreshold = Int($0) }
                                    ), in: 20...80, step: 5)
                                    .tint(.blue)
                                }
                            }
                        }
                    } header: {
                        Text("Peer Support Alerts")
                    } footer: {
                        Text("Get notified when your social vitality needs attention, or when supporters want to reach out.")
                    }

                    // Trusted Supporters Section
                    Section {
                        if !availableSupporters.isEmpty {
                            ForEach(availableSupporters) { supporter in
                                HStack {
                                    Image(systemName: selectedSupporters.contains(supporter.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedSupporters.contains(supporter.id) ? .green : .gray)

                                    Text(supporter.name)
                                        .font(.subheadline)

                                    Spacer()

                                    Text(supporter.correlationPercentage)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedSupporters.contains(supporter.id) {
                                        selectedSupporters.remove(supporter.id)
                                    } else {
                                        selectedSupporters.insert(supporter.id)
                                    }
                                }
                            }
                        } else {
                            Text("No supporters found yet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Trusted Supporters")
                    } footer: {
                        Text("Select people who can receive alerts about your social wellbeing.")
                    }

                    // Privacy Section
                    Section {
                        NavigationLink {
                            Text("Privacy settings coming soon")
                        } label: {
                            HStack {
                                Image(systemName: "lock.shield")
                                    .foregroundColor(.blue)
                                Text("Privacy & Sharing")
                            }
                        }
                    } header: {
                        Text("Privacy")
                    }
                }
            }
            .navigationTitle("Social Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveSettings() }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                await loadSettings()
            }
        }
    }

    // MARK: - Methods

    private func loadSettings() async {
        isLoading = true
        defer { isLoading = false }

        // Capture dashboard snapshot to avoid race conditions
        guard let dashboard = engine.dashboard else { return }

        // Load current settings from dashboard alert status
        alertsEnabled = dashboard.alertStatus.enabled

        // Capture supporters list from snapshot
        availableSupporters = dashboard.topSupporters

        // Pre-select current supporters (empty by default, user must opt-in)
        // Don't auto-select all - only select those explicitly designated
        selectedSupporters = []
    }

    private func saveSettings() async {
        isSaving = true
        defer { isSaving = false }

        do {
            guard let userId = container.supabaseAuthService.currentUser?.id else {
                errorMessage = "You must be signed in to save settings"
                return
            }

            struct SocialVitalitySettingsUpdate: Encodable {
                let social_alerts_enabled: Bool
                let social_alert_frequency: String
                let social_score_threshold: Int
                let social_trusted_supporters: [String]
            }

            try await container.supabase
                .from("user_settings")
                .update(SocialVitalitySettingsUpdate(
                    social_alerts_enabled: alertsEnabled,
                    social_alert_frequency: alertFrequency.rawValue,
                    social_score_threshold: scoreThreshold,
                    social_trusted_supporters: Array(selectedSupporters)
                ))
                .eq("user_id", value: userId.uuidString)
                .execute()

            isPresented = false
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}

// MARK: - Alert Frequency

enum AlertFrequency: String, CaseIterable {
    case daily
    case weekly
    case threshold
}

#Preview {
    SocialVitalitySettingsViewPreview()
}

private struct SocialVitalitySettingsViewPreview: View {
    @State private var isPresented = true

    var body: some View {
        SocialVitalitySettingsView(
            isPresented: $isPresented,
            engine: createMockEngine()
        )
        .environmentObject(DependencyContainer.preview)
    }

    private func createMockEngine() -> SocialVitalityEngine {
        // Create a mock engine for preview
        SocialVitalityEngine(supabase: DependencyContainer.preview.supabase)
    }
}
