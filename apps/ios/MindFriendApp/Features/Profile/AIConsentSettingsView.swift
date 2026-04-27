// AIConsentSettingsView.swift
// Settings → Privacy → AI & Data Sharing.
// Lets the user enable/disable AI features individually, revoke all at once,
// or delete their AI conversation history.

import SwiftUI

struct AIConsentSettingsView: View {
    @EnvironmentObject var consent: AIConsentService

    @State private var showDeleteConfirmation = false
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    /// Master switch is ON if at least one feature is granted; OFF only when none are.
    private var masterIsOn: Bool {
        AIFeature.allCases.contains(where: { consent.isGranted($0) })
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { masterIsOn },
                    set: { newValue in handleMasterToggle(newValue) }
                )) {
                    Text(NSLocalizedString("ai.settings.master",
                        value: "Use AI features",
                        comment: ""))
                }
            } footer: {
                Text(NSLocalizedString("ai.settings.master.footer",
                    value: "When this is off, all six AI capabilities are disabled and your content is not sent to any AI provider. You can still log moods, do exercises, and use Circles.",
                    comment: ""))
            }

            Section {
                ForEach(AIFeature.allCases) { feature in
                    PerFeatureRow(feature: feature)
                        .environmentObject(consent)
                        .disabled(!masterIsOn || isMutating)
                }
            } header: {
                Text(NSLocalizedString("ai.settings.perFeature.header",
                    value: "Per-feature controls",
                    comment: ""))
            }

            Section {
                Link(destination: AppURLs.privacyPolicy) {
                    Label(
                        NSLocalizedString("ai.settings.readPolicy",
                            value: "Read our privacy policy",
                            comment: ""),
                        systemImage: "doc.text"
                    )
                }
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(
                        NSLocalizedString("ai.settings.deleteHistory",
                            value: "Delete AI conversation history",
                            comment: ""),
                        systemImage: "trash"
                    )
                }
                .disabled(isMutating)
            }
        }
        .navigationTitle(Text(NSLocalizedString("ai.settings.title",
            value: "AI & Data Sharing",
            comment: "")))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            NSLocalizedString("ai.settings.deleteHistory.confirm.title",
                value: "Delete AI conversation history?",
                comment: ""),
            isPresented: $showDeleteConfirmation
        ) {
            Button(NSLocalizedString("common.cancel", value: "Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("common.delete", value: "Delete", comment: ""), role: .destructive) {
                handleDeleteHistory()
            }
        } message: {
            Text(NSLocalizedString("ai.settings.deleteHistory.confirm.message",
                value: "This permanently deletes your chat history with the AI companion. Mood logs, journals, and other data are not affected.",
                comment: ""))
        }
        .alert(
            NSLocalizedString("ai.settings.error",
                value: "Could not update your AI settings.",
                comment: ""),
            isPresented: $showErrorAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Actions

    private func handleMasterToggle(_ newValue: Bool) {
        isMutating = true
        Task {
            do {
                if newValue {
                    try await consent.setConsent(grant: Set(AIFeature.allCases), denyOthers: true)
                } else {
                    try await consent.revokeAll(deleteAIHistory: false)
                }
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
            isMutating = false
        }
    }

    private func handleDeleteHistory() {
        isMutating = true
        Task {
            do {
                try await consent.revokeAll(deleteAIHistory: true)
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
            isMutating = false
        }
    }
}

// MARK: - Sub-components

private struct PerFeatureRow: View {
    let feature: AIFeature
    @EnvironmentObject var consent: AIConsentService
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { consent.isGranted(feature) },
                set: { newValue in handleToggle(newValue) }
            )) {
                Text(feature.displayName)
            }
            .accessibilityLabel(feature.displayName)
            // Use a single key with %@ format specifier so translators get one
            // string and the provider name is interpolated at render time. Without
            // this, all 6 rows would share the same translated string and show the
            // wrong provider once the .strings file is populated.
            Text(String(
                format: NSLocalizedString("ai.settings.providerLabel",
                    value: "Provider: %@",
                    comment: "Provider label under each AI feature toggle. %@ is the vendor name."),
                feature.providerName
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .alert(
            NSLocalizedString("ai.settings.toggleError",
                value: "Could not update this feature.",
                comment: ""),
            isPresented: $showErrorAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func handleToggle(_ newValue: Bool) {
        isMutating = true
        Task {
            do {
                if newValue {
                    try await consent.grant([feature])
                } else {
                    try await consent.revoke(feature)
                }
            } catch {
                // Surface the failure so the user knows the toggle didn't take.
                // The view re-renders from `consent.isGranted(...)` which still
                // reflects the un-mutated server state, so the toggle visually
                // reverts on its own.
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
            isMutating = false
        }
    }
}
