import SwiftUI
import Combine

/// Banner displayed when a recovery quest is available to restore a broken streak
struct RecoveryQuestBanner: View {
    let streakToRecover: Int
    let expiresAt: Date
    let onStart: () -> Void

    @State private var timeRemaining: TimeInterval = 0
    @State private var timerSubscription: AnyCancellable?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recover Your Streak!")
                        .font(.headline)
                    Text("Complete a recovery quest to restore your \(streakToRecover)-day streak")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                // Countdown timer
                Label(formatTimeRemaining(), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(timeRemaining < 3600 ? .red : .orange)

                Spacer()

                Button(action: onStart) {
                    Text("Start Recovery")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            // Initialize time remaining
            timeRemaining = expiresAt.timeIntervalSince(Date())

            // Create timer with proper lifecycle management
            timerSubscription = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    timeRemaining = expiresAt.timeIntervalSince(Date())
                }
        }
        .onDisappear {
            // Clean up timer to prevent resource leak
            timerSubscription?.cancel()
            timerSubscription = nil
        }
    }

    private func formatTimeRemaining() -> String {
        guard timeRemaining > 0 else { return "Expired" }

        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        }
        return "\(minutes)m left"
    }
}

#Preview {
    VStack(spacing: 20) {
        RecoveryQuestBanner(
            streakToRecover: 14,
            expiresAt: Date().addingTimeInterval(23 * 60 * 60 + 45 * 60),
            onStart: {}
        )

        RecoveryQuestBanner(
            streakToRecover: 7,
            expiresAt: Date().addingTimeInterval(45 * 60),
            onStart: {}
        )
    }
    .padding()
}
