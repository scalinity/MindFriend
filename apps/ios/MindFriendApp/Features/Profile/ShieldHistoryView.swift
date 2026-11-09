import SwiftUI

/// Displays transaction log of shields earned, used, expired, and reset
struct ShieldHistoryView: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject var appState: AppState

    @State private var events: [ShieldEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading shield history...")
            } else if let errorMessage {
                SupportUnavailableState(
                    title: "History unavailable", message: errorMessage,
                    actionTitle: "Try again", action: { Task { await loadHistory() } })
            } else if events.isEmpty {
                emptyState
            } else {
                eventsList
            }
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Shield History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHistory()
        }

    }

    // MARK: - Views

    private var emptyState: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.accent.opacity(0.6))

            Text("No Shield Events Yet")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: SupportTheme.Spacing.xs) {
                Text("Your past shield activity appears here.")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textPrimary)

                Text("Events appear here when:")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Label("Past protection events are kept in this history", systemImage: "checkmark.shield.fill")
                    Label("Milestone events appear when recorded", systemImage: "gift.fill")
                    Label("Shields are reset weekly", systemImage: "arrow.clockwise")
                }
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, SupportTheme.Spacing.l)
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
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let userId = appState.currentUser?.id else {
                errorMessage = "User not authenticated"
                return
            }

            let service = StreakShieldService(supabase: container.supabaseClient)
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
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: event.iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

            }

            Spacer()

            if let remaining = event.shieldsRemaining {
                VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                    Text("\(remaining)")
                        .font(.title3)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.bold)
                        .foregroundStyle(iconColor)

                    Text("shields")
                        .font(.caption2)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
    }

    private var iconColor: Color {
        switch event.eventType {
        case .earned:
            return SupportTheme.accent
        case .used:
            return SupportTheme.accent
        case .reset:
            return SupportTheme.accent
        case .expired:
            return .red
        case .purchased:
            return SupportTheme.accent
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
