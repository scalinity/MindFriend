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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { consent.isGranted(feature) },
                set: { newValue in handleToggle(newValue) }
            )) {
                Text(feature.displayName)
            }
            .accessibilityLabel(feature.displayName)
            Text(NSLocalizedString("ai.settings.providerLabel",
                value: "Provider: \(feature.providerName)",
                comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func handleToggle(_ newValue: Bool) {
        isMutating = true
        Task {
            if newValue {
                try? await consent.grant([feature])
            } else {
                try? await consent.revoke(feature)
            }
            isMutating = false
        }
    }
}
