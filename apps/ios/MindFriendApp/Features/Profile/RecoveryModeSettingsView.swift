import SwiftUI

/// Settings view for managing Recovery Mode
/// Allows users to manually toggle recovery mode and view current status
/// See: kimispecs/03-recovery-mode-ux-spec.md
struct RecoveryModeSettingsView: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject var appState: AppState
    @State private var recoveryState: RecoveryModeState = .inactive
    @State private var isLoading = false
    @State private var showExitConfirmation = false
    @State private var showEnableConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            // Status Section
            Section {
                HStack(spacing: SupportTheme.Spacing.m) {
                    ZStack {
                        Circle()
                            .fill(
                                recoveryState.isActive
                                    ? SupportTheme.accent.opacity(0.15) : SupportTheme.textSecondary.opacity(0.1)
                            )
                            .frame(width: 56, height: 56)

                        Image(systemName: recoveryState.isActive ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(recoveryState.isActive ? SupportTheme.accent : SupportTheme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(recoveryState.isActive ? "Recovery Mode Active" : "Recovery Mode Off")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        if recoveryState.isActive {
                            if let reason = recoveryState.reason {
                                Text(reason.displayText)
                                    .font(.subheadline)
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }
                        } else {
                            Text("Enable when you need a gentler experience")
                                .font(.subheadline)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }
                }
                .padding(.vertical, SupportTheme.Spacing.xs)
            }

            .listRowBackground(SupportTheme.surface)

            // Description
            Section {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text("What is Recovery Mode?")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Text(
                        "Recovery Mode simplifies your experience when you're going through a difficult time. It reduces notifications, shows only essential actions, and removes any pressure."
                    )
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        benefitRow(icon: "bell.slash", text: "Fewer notifications")
                        benefitRow(icon: "square.stack", text: "Simplified home screen")
                        benefitRow(icon: "hand.raised", text: "Move at your own pace")
                        benefitRow(icon: "heart.text.square", text: "Crisis resources always available")
                    }
                    .padding(.top, SupportTheme.Spacing.xxs)
                }
                .padding(.vertical, SupportTheme.Spacing.xs)
            }

            .listRowBackground(SupportTheme.surface)

            // Toggle Section
            Section {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if recoveryState.isActive {
                    // Exit button
                    Button(role: .destructive) {
                        if recoveryState.canManuallyExit {
                            showExitConfirmation = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.right.circle")
                            Text("Exit Recovery Mode")
                        }
                    }
                    .disabled(!recoveryState.canManuallyExit)

                    if !recoveryState.canManuallyExit, let timeRemaining = recoveryState.timeUntilExitFormatted {
                        Text("You can exit in \(timeRemaining). This helps ensure you have time to rest.")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                } else {
                    // Enable button
                    Button {
                        showEnableConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "heart.circle.fill")
                            Text("Enable Recovery Mode")
                        }
                        .foregroundStyle(SupportTheme.accent)
                    }
                }
            } footer: {
                if recoveryState.isActive {
                    Text(
                        "Recovery Mode will automatically turn off after 7 days, or when you've logged 3 days of improved mood."
                    )
                } else {
                    Text("Recovery Mode can also be enabled automatically when you've had several difficult days.")
                }
            }

            .listRowBackground(SupportTheme.surface)

            // Error display
            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .listRowBackground(SupportTheme.surface)
            }
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Recovery Mode")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadState()
        }
        .refreshable {
            await loadState()
        }
        .confirmationDialog(
            "Exit Recovery Mode?",
            isPresented: $showExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("Exit Recovery Mode") {
                Task { await toggleRecoveryMode(enable: false) }
            }
            Button("Stay in Recovery Mode", role: .cancel) {}
        } message: {
            Text("You'll return to the full app experience with all features and notifications.")
        }
        .confirmationDialog(
            "Enable Recovery Mode?",
            isPresented: $showEnableConfirmation,
            titleVisibility: .visible
        ) {
            Button("Enable Recovery Mode") {
                Task { await toggleRecoveryMode(enable: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will simplify your home screen and reduce notifications for at least 24 hours.")
        }
    }

    // MARK: - Helper Views

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.accent)
                .frame(minWidth: 20)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    // MARK: - Actions

    private func loadState() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let state = try await container.supabaseDataService.fetchRecoveryModeState()
            await MainActor.run {
                recoveryState = state
                errorMessage = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load recovery mode status"
            }
        }
    }

    private func toggleRecoveryMode(enable: Bool) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await container.supabaseDataService.toggleRecoveryMode(enable: enable)
            await MainActor.run {
                if result.success {
                    recoveryState = result.newState
                    errorMessage = nil

                    // Track analytics
                    Analytics.shared.track(
                        enable ? .recoveryModeEnabled : .recoveryModeExited,
                        properties: ["method": "manual_settings"]
                    )
                } else {
                    errorMessage = result.errorMessage ?? "Failed to toggle recovery mode"
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to \(enable ? "enable" : "disable") recovery mode"
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RecoveryModeSettingsView()
            .environmentObject(DependencyContainer())
            .environmentObject(AppState())
    }
}
