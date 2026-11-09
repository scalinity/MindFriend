import SwiftUI

struct LockScreenView: View {
    @StateObject private var lockManager = PrivacyLockManager.shared
    @State private var isAuthenticating = false
    @State private var showError = false
    @State private var errorMessage = ""

    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            SupportTheme.canvas
                .ignoresSafeArea()

            VStack(spacing: SupportTheme.Spacing.xl) {
                Spacer()

                Image(systemName: lockManager.biometricType.iconName)
                    .font(.system(size: 80))
                    .foregroundStyle(SupportTheme.textSecondary)
                    .symbolEffect(.pulse, isActive: isAuthenticating)

                Text("MindFriend is locked")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.medium)
                    .foregroundStyle(SupportTheme.textSecondary)

                Text("Unlock with \(lockManager.biometricType.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)

                Button {
                    unlock()
                } label: {
                    HStack(spacing: SupportTheme.Spacing.s) {
                        Image(systemName: lockManager.biometricType.iconName)
                        Text("Unlock with \(lockManager.biometricType.displayName)")
                    }
                    .font(.headline)
                    .foregroundStyle(SupportTheme.onAccent)
                    .padding(.horizontal, SupportTheme.Spacing.xl)
                    .padding(.vertical, SupportTheme.Spacing.m)
                    .background(SupportTheme.accent)
                    .clipShape(Capsule())
                }
                .disabled(isAuthenticating)
                .padding(.top, SupportTheme.Spacing.xl)

                Spacer()

                Text("Your privacy is protected")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .padding(.bottom, SupportTheme.Spacing.xl)
            }
        }
        .alert("Unlock Failed", isPresented: $showError) {
            Button("Try Again", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func unlock() {
        isAuthenticating = true

        Task {
            let success = await lockManager.unlockApp()
            await MainActor.run {
                isAuthenticating = false
                if success {
                    onUnlock()
                } else {
                    errorMessage = "Authentication failed. Please try again."
                    showError = true
                }
            }
        }
    }
}

struct PrivacyLockOverlay: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var lockManager = PrivacyLockManager.shared
    let onUnlock: () -> Void

    func body(content: Content) -> some View {
        ZStack {
            content

            if lockManager.isLocked {
                LockScreenView(onUnlock: onUnlock)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : (.easeInOut(duration: 0.3)), value: lockManager.isLocked)
        .task {
            // Load privacy lock settings on app launch
            await lockManager.loadSettings()
        }
    }
}

extension View {
    func privacyLockOverlay(onUnlock: @escaping () -> Void) -> some View {
        modifier(PrivacyLockOverlay(onUnlock: onUnlock))
    }
}

#Preview("Lock Screen") {
    LockScreenView(onUnlock: {})
}

#Preview("Overlay") {
    Text("Main Content")
        .privacyLockOverlay(onUnlock: {})
}
