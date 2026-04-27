// AIConsentGateView.swift
// Full-screen AI consent gate for App Store guidelines 5.1.1(i) / 5.1.2(i).
// Used as the first onboarding step for new users and as a non-dismissible
// fullScreenCover for migrating v1.0 users on first launch of v1.0.1.

import SwiftUI

struct AIConsentGateView: View {
    @EnvironmentObject var consent: AIConsentService
    var onComplete: () -> Void

    @State private var enabled: Set<AIFeature>
    @State private var isSaving = false
    @State private var showError = false
    @State private var showPolicy = false

    /// Snapshotted at init from `AIConsent.defaultsToOptIn` so the initial toggle state
    /// and the primary-button enabled logic agree on a single locale read. Avoids any
    /// chance of the two diverging if `Locale.current` somehow re-evaluates differently
    /// between init and render.
    private let defaultsToOptIn: Bool

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        // Locale-aware default: EEA/UK/CH defaults to OFF, rest of world defaults to ON.
        let snapshot = AIConsent.defaultsToOptIn
        self.defaultsToOptIn = snapshot
        let initial: Set<AIFeature> = snapshot ? [] : Set(AIFeature.allCases)
        self._enabled = State(initialValue: initial)
    }

    /// Primary button is enabled when at least one feature is selected (in opt-in regions),
    /// or always enabled (in opt-out regions where defaults are on).
    private var primaryEnabled: Bool {
        defaultsToOptIn ? !enabled.isEmpty : true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                processingSection
                neverSection
                policyLink
            }
            .padding()
            .padding(.bottom, 200) // room for the sticky button bar
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { buttonBar }
        .sheet(isPresented: $showPolicy) {
            SafariView(url: AppURLs.privacyPolicy)
        }
        .alert(NSLocalizedString("ai.gate.saveError",
            value: "Could not save your choice. Please try again.",
            comment: ""),
            isPresented: $showError) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("ai.gate.badge", value: "Privacy", comment: ""))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(NSLocalizedString("ai.gate.title",
                value: "How MindFriend uses AI",
                comment: ""))
                .font(.largeTitle.weight(.bold))

            Text(NSLocalizedString("ai.gate.subtitle",
                value: "MindFriend uses AI to power some of its most helpful features. Before we begin, here's exactly what's sent, who receives it, and how you stay in control.",
                comment: ""))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("ai.gate.processing.title",
                value: "What's processed by AI providers",
                comment: ""))
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(AIFeature.allCases) { feature in
                    ConsentRow(
                        feature: feature,
                        isOn: Binding(
                            get: { enabled.contains(feature) },
                            set: { isOn in
                                if isOn { enabled.insert(feature) } else { enabled.remove(feature) }
                            }
                        )
                    )
                    if feature != AIFeature.allCases.last {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var neverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("ai.gate.never.title",
                value: "What we never share with AI providers",
                comment: ""))
                .font(.headline)
            BulletRow(NSLocalizedString("ai.gate.never.bullet1",
                value: "Your email or sign-in identifiers",
                comment: ""))
            BulletRow(NSLocalizedString("ai.gate.never.bullet2",
                value: "Other Circle members' content",
                comment: ""))
            BulletRow(NSLocalizedString("ai.gate.never.bullet3",
                value: "Your subscription or payment information",
                comment: ""))
        }
    }

    private var policyLink: some View {
        Button {
            showPolicy = true
        } label: {
            HStack(spacing: 4) {
                Text(NSLocalizedString("ai.gate.policyLink",
                    value: "Read full privacy policy",
                    comment: ""))
                Image(systemName: "chevron.right")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
    }

    private var buttonBar: some View {
        VStack(spacing: 12) {
            Button {
                Task { await save(grant: enabled, denyOthers: true) }
            } label: {
                Text(isSaving
                    ? NSLocalizedString("ai.gate.saving", value: "Saving…", comment: "")
                    : NSLocalizedString("ai.gate.continueWithSelected",
                        value: "Continue with selected features",
                        comment: ""))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(primaryEnabled ? Color.accentColor : Color.gray.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!primaryEnabled || isSaving)

            Button {
                Task { await save(grant: [], denyOthers: true) }
            } label: {
                Text(NSLocalizedString("ai.gate.continueWithoutAI",
                    value: "Continue without AI",
                    comment: ""))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.secondary)
            }
            .disabled(isSaving)

            Text(NSLocalizedString("ai.gate.changeLater",
                value: "You can change these any time in Settings → Privacy → AI & Data Sharing.",
                comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.regularMaterial)
    }

    private func save(grant: Set<AIFeature>, denyOthers: Bool) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await consent.setConsent(grant: grant, denyOthers: denyOthers)
            onComplete()
        } catch {
            showError = true
        }
    }
}

// MARK: - Sub-components

private struct ConsentRow: View {
    let feature: AIFeature
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(feature.displayName) (\(feature.providerName))")
                    .font(.subheadline.weight(.semibold))
                Text(feature.dataSentDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .accessibilityLabel(feature.displayName)
        }
        .padding(.vertical, 8)
    }
}

private struct BulletRow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
