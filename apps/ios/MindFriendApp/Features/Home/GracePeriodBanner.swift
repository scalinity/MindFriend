import SwiftUI
import Combine

/// Banner displayed when user has an active grace period (48-hour window to complete missed quest)
struct GracePeriodBanner: View {
    let expiresAt: Date
    let onCompleteRetroactive: () -> Void

    @State private var timeRemaining: TimeInterval = 0
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(urgencyColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Grace Period Active")
                        .font(.headline)
                    Text("Complete yesterday's quest before time runs out")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Label(formatTimeRemaining(), systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(urgencyColor)

                Spacer()

                Button("Complete Now") {
                    onCompleteRetroactive()
                }
                .buttonStyle(.borderedProminent)
                .tint(urgencyColor)
            }
        }
        .padding()
        .background(urgencyColor.opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(urgencyColor.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            updateTimeRemaining()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    // MARK: - Computed Properties

    private var iconName: String {
        timeRemaining < 3600 ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark"
    }

    private var urgencyColor: Color {
        if timeRemaining < 3600 {
            return .red
        } else if timeRemaining < 7200 {
            return .orange
        } else {
            return .yellow
        }
    }

    // MARK: - Time Formatting

    private func formatTimeRemaining() -> String {
        guard timeRemaining > 0 else { return "Expired" }

        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h left"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m left"
        } else {
            return "\(minutes)m left"
        }
    }

    // MARK: - Timer Management

    private func updateTimeRemaining() {
        timeRemaining = expiresAt.timeIntervalSince(Date())
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                updateTimeRemaining()
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        GracePeriodBanner(
            expiresAt: Date().addingTimeInterval(12 * 3600),
            onCompleteRetroactive: {
                print("Complete retroactive quest tapped")
            }
        )

        GracePeriodBanner(
            expiresAt: Date().addingTimeInterval(1.5 * 3600),
            onCompleteRetroactive: {
                print("Complete retroactive quest tapped")
            }
        )

        GracePeriodBanner(
            expiresAt: Date().addingTimeInterval(30 * 60),
            onCompleteRetroactive: {
                print("Complete retroactive quest tapped")
            }
        )
    }
    .padding()
}
