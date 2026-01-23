import SwiftUI

/// Displays transaction log of shields earned, used, expired, and reset
struct ShieldHistoryView: View {
    @EnvironmentObject var container: DependencyContainer

    @State private var events: [ShieldEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading shield history...")
            } else if events.isEmpty {
                emptyState
            } else {
                eventsList
            }
        }
        .navigationTitle("Shield History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHistory()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Views

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Shield Events Yet")
                .font(.headline)

            Text("Shields are earned every 7 days of consistent questing")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var eventsList: some View {
        List(events) { event in
            ShieldEventRow(event: event)
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let userId = container.appState.currentUser?.id else {
                errorMessage = "User not authenticated"
                return
            }

            let service = StreakShieldService(supabase: container.supabase)
            events = try await service.getShieldHistory(userId: userId)
        } catch {
            errorMessage = "Failed to load shield history: \(error.localizedDescription)"
        }
    }
}

// MARK: - Event Row

struct ShieldEventRow: View {
    let event: ShieldEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let streakDay = event.streakProtected {
                    Text("Streak Day: \(streakDay)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let remaining = event.shieldsRemaining {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(remaining)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(iconColor)

                    Text("shields")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var iconColor: Color {
        switch event.eventType {
        case .earned:
            return .green
        case .used:
            return .orange
        case .reset:
            return .blue
        case .expired:
            return .red
        case .purchased:
            return .purple
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ShieldHistoryView()
            .environmentObject(DependencyContainer.shared)
    }
}
