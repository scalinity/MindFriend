import SwiftUI

/// A button that sends a "hug" to a circle member with animation feedback
struct SendHugButton: View {
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
                .foregroundColor(showSentAnimation ? .red : .accentColor)
                .scaleEffect(showSentAnimation ? 1.3 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showSentAnimation)
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
                    withAnimation {
                        showSentAnimation = true
                    }

                    // Reset after animation
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        await MainActor.run {
                            withAnimation {
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
    let memberId: String
    let circleId: String

    @EnvironmentObject private var container: DependencyContainer
    @State private var isSending = false
    @State private var showSent = false

    var body: some View {
        Button {
            sendHug()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showSent ? "heart.fill" : "heart")
                    .foregroundColor(showSent ? .red : .secondary)
                if showSent {
                    Text("Sent!")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showSent)
        }
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
    VStack(spacing: 40) {
        SendHugButton(memberId: "test-id", circleId: "circle-id")

        CompactHugButton(memberId: "test-id", circleId: "circle-id")
    }
    .environmentObject(DependencyContainer())
}
