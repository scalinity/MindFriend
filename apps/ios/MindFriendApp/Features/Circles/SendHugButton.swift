import SwiftUI

/// A button that sends a "hug" to a circle member with animation feedback
struct SendHugButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let memberId: String
    let circleId: String

    @EnvironmentObject private var container: DependencyContainer
    @State private var isSending = false
    @State private var showSentAnimation = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Button {
            sendHug()
        } label: {
            Image(systemName: showSentAnimation ? "heart.fill" : "heart")
                .font(.title2)
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .foregroundColor(showSentAnimation ? .red : SupportTheme.accent)
                .scaleEffect(reduceMotion ? 1 : (showSentAnimation ? 1.3 : 1.0))
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.6), value: showSentAnimation)
        }
        .disabled(isSending)
        .opacity(isSending ? 0.5 : 1.0)
        .accessibilityLabel("Send a hug")
        .accessibilityHint("Sends encouragement to this circle member")
        .alert("Couldn't Send Hug", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func sendHug() {
        guard !isSending else { return }

        isSending = true

        Task {
            do {
                try await container.supabaseDataService.sendHug(to: memberId, in: circleId)

                await MainActor.run {
                    // Show success animation
                    withAnimation(reduceMotion ? nil : .default) {
                        showSentAnimation = true
                    }

                    // Reset after animation
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        await MainActor.run {
                            withAnimation(reduceMotion ? nil : .default) {
                                showSentAnimation = false
                            }
                            isSending = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

/// A compact hug button for use in member lists
struct CompactHugButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let memberId: String
    let circleId: String

    @EnvironmentObject private var container: DependencyContainer
    @State private var isSending = false
    @State private var showSent = false

    var body: some View {
        Button {
            sendHug()
        } label: {
            HStack(spacing: SupportTheme.Spacing.xxs) {
                Image(systemName: showSent ? "heart.fill" : "heart")
                    .foregroundColor(showSent ? .red : SupportTheme.textSecondary)
                if showSent {
                    Text("Sent!")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showSent)
        }
        .accessibilityLabel(showSent ? "Hug sent" : "Send a hug")
        .disabled(isSending || showSent)
        .buttonStyle(.plain)
    }

    private func sendHug() {
        guard !isSending else { return }

        isSending = true

        Task {
            do {
                try await container.supabaseDataService.sendHug(to: memberId, in: circleId)
                await MainActor.run {
                    showSent = true
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    // Silently fail for compact version
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: SupportTheme.Spacing.xl) {
        SendHugButton(memberId: "test-id", circleId: "circle-id")

        CompactHugButton(memberId: "test-id", circleId: "circle-id")
    }
    .environmentObject(DependencyContainer())
}
