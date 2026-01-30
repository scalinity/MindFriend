import SwiftUI

struct LockScreenView: View {
    @StateObject private var lockManager = PrivacyLockManager.shared
    @State private var isAuthenticating = false
    @State private var showError = false
    @State private var errorMessage = ""

    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: lockManager.biometricType.iconName)
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, isActive: isAuthenticating)

                Text("MindFriend is locked")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text("Unlock with \(lockManager.biometricType.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                Button {
                    unlock()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: lockManager.biometricType.iconName)
                        Text("Unlock with \(lockManager.biometricType.displayName)")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                }
                .disabled(isAuthenticating)
                .padding(.top, 32)

                Spacer()

                Text("Your privacy is protected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 32)
            }
        }
        .alert("Unlock Failed", isPresented: $showError) {
            Button("Try Again", role: .cancel) { }
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
        .animation(.easeInOut(duration: 0.3), value: lockManager.isLocked)
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
