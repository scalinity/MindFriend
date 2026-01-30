import SwiftUI

struct PrivacyLockSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @StateObject private var lockManager = PrivacyLockManager.shared

    @State private var appLockEnabled: Bool = false
    @State private var selectedTimeout: AutoLockTimeout = .fiveMinutes
    @State private var quickLockMethod: PrivacyLockSettings.QuickLockMethod = .menu
    @State private var tripleTapEnabled: Bool = false

    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showBiometricPrompt = false
    @State private var isUpdatingToggle = false  // Prevent onChange loop

    var body: some View {
        Form {
            if !lockManager.canEnableBiometrics {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading) {
                            Text("Biometrics Unavailable")
                                .font(.headline)
                            Text("Enable Face ID, Touch ID, or a passcode in your device settings to use App Lock.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Toggle(isOn: $appLockEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable App Lock")
                            .font(.body)
                        Text("Requires \(lockManager.biometricType.displayName) to unlock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isSaving)
                .onChange(of: appLockEnabled) { _, newValue in
                    // Prevent onChange loop when we programmatically update the toggle
                    guard !isUpdatingToggle else { return }
                    if newValue {
                        enableLock()
                    } else {
                        disableLock()
                    }
                }
            } footer: {
                Text("When enabled, MindFriend will require authentication to access your data.")
            }

            if appLockEnabled {
                Section {
                    Picker("Lock after", selection: $selectedTimeout) {
                        ForEach(AutoLockTimeout.allCases) { timeout in
                            Text(timeout.displayName).tag(timeout)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedTimeout) { _, _ in
                        Task {
                            await saveSettings()
                        }
                    }
                } header: {
                    Text("Auto-Lock")
                } footer: {
                    Text("The app will automatically lock after the selected period of inactivity.")
                }

                Section {
                    Picker("Method", selection: $quickLockMethod) {
                        ForEach(PrivacyLockSettings.QuickLockMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: quickLockMethod) { _, _ in
                        Task {
                            await saveSettings()
                        }
                    }

                    if quickLockMethod == .tripleTap {
                        Toggle("Enable Triple-Tap", isOn: $tripleTapEnabled)
                            .onChange(of: tripleTapEnabled) { _, _ in
                                Task {
                                    await saveSettings()
                                }
                            }
                    }
                } header: {
                    Text("Quick Lock")
                } footer: {
                    Text(quickLockMethod.description)
                }
            }

            Section {
                Button {
                    Task {
                        await lockManager.quickLock()
                    }
                } label: {
                    Label("Lock Now", systemImage: "lock.fill")
                }
                .disabled(!appLockEnabled || isSaving)
            }
        }
        .navigationTitle("App Lock")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .overlay {
            if isSaving {
                ProgressView()
            }
        }
        .task {
            await loadSettings()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func loadSettings() async {
        await lockManager.loadSettings()
        await MainActor.run {
            // Set flag to prevent onChange from triggering during initial load
            isUpdatingToggle = true
            appLockEnabled = lockManager.settings.appLockEnabled
            isUpdatingToggle = false
            selectedTimeout = AutoLockTimeout(seconds: lockManager.settings.autoLockSeconds) ?? .fiveMinutes
            quickLockMethod = lockManager.settings.quickLockMethod
            tripleTapEnabled = lockManager.settings.tripleTapEnabled
        }
    }

    private func enableLock() {
        Task {
            isSaving = true
            defer { isSaving = false }

            let authenticated = await lockManager.unlockApp()
            if authenticated {
                Analytics.shared.track(.privacyLockEnabled)
                await saveSettings()
            } else {
                // Revert toggle without triggering onChange
                isUpdatingToggle = true
                appLockEnabled = false
                isUpdatingToggle = false
                showError = true
                errorMessage = "Authentication failed. Please try again."
            }
        }
    }

    private func disableLock() {
        Task {
            isSaving = true
            defer { isSaving = false }

            let authenticated = await lockManager.unlockApp()
            if authenticated {
                Analytics.shared.track(.privacyLockDisabled)
                await saveSettings()
            } else {
                // Revert toggle without triggering onChange
                isUpdatingToggle = true
                appLockEnabled = true
                isUpdatingToggle = false
                showError = true
                errorMessage = "Authentication failed. Please try again."
            }
        }
    }

    private func saveSettings() async {
        isSaving = true
        defer { isSaving = false }

        let newSettings = PrivacyLockSettings(
            appLockEnabled: appLockEnabled,
            autoLockSeconds: selectedTimeout.seconds == Int.max ? 0 : selectedTimeout.seconds,
            quickLockMethod: quickLockMethod,
            tripleTapEnabled: tripleTapEnabled,
            userId: nil,
            createdAt: nil,
            updatedAt: nil
        )

        do {
            try await lockManager.updateSettings(newSettings)
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyLockSettingsView()
            .environmentObject(AppState())
            .environmentObject(DependencyContainer())
    }
}
