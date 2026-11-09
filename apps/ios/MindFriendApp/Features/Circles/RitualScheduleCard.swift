import SwiftUI
import Combine

/// Card showing upcoming or active rituals in a circle
struct RitualScheduleCard: View {
    @EnvironmentObject var container: DependencyContainer

    let circleId: UUID
    let isOwner: Bool
    let onJoinRitual: (CircleRitual) -> Void
    let onCreateRitual: () -> Void

    @State private var upcomingRituals: [CircleRitual] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Label("Rituals", systemImage: "sparkles")
                    .font(.headline)

                Spacer()

                Button {
                    onCreateRitual()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(SupportTheme.accent)
                }
                .accessibilityLabel("Create ritual")
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, SupportTheme.Spacing.xs)
            } else if upcomingRituals.isEmpty {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Text("No upcoming rituals")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Button {
                        onCreateRitual()
                    } label: {
                        Text("Start a Ritual")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.supportSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SupportTheme.Spacing.xs)
            } else {
                ForEach(upcomingRituals) { ritual in
                    RitualRowView(
                        ritual: ritual,
                        onJoin: { onJoinRitual(ritual) }
                    )
                }
            }
        }
        .supportCard()
        .task {
            await loadRituals()
        }
        .refreshable {
            await loadRituals()
        }
    }

    private func loadRituals() async {
        isLoading = true
        defer { isLoading = false }

        do {
            upcomingRituals = try await container.ritualService.fetchUpcomingRituals(circleId: circleId)
        } catch {
            print("Failed to load rituals: \(error)")
        }
    }
}

/// Single ritual row
struct RitualRowView: View {
    let ritual: CircleRitual
    let onJoin: () -> Void

    @State private var timeRemaining: String = ""
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            // Icon
            Image(systemName: ritual.ritualType.icon)
                .font(.title2)
                .foregroundColor(SupportTheme.accent)
                .frame(width: 40, height: 40)
                .background(SupportTheme.accent)
                .cornerRadius(SupportTheme.controlRadius)

            // Info
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(ritual.title)
                    .font(.subheadline.bold())
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: SupportTheme.Spacing.xxs) {
                    Text(ritual.ritualType.displayName)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Text(timeRemaining)
                        .font(.caption)
                        .foregroundColor(ritual.hasStarted ? SupportTheme.accent : SupportTheme.textSecondary)
                }
            }

            Spacer()

            // Join button
            if ritual.isJoinable {
                Button {
                    onJoin()
                } label: {
                    Text(ritual.hasStarted ? "Join" : "Join")
                        .font(.subheadline.bold())
                        .padding(.horizontal, SupportTheme.Spacing.m)
                        .padding(.vertical, SupportTheme.Spacing.xs)
                }
                .buttonStyle(.supportPrimary)
                .tint(ritual.hasStarted ? SupportTheme.accent : SupportTheme.accent)
            } else {
                Text("Ended")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ritual.title), \(ritual.ritualType.displayName), \(timeRemaining)")
        .accessibilityAddTraits(ritual.isJoinable ? .isButton : [])
        .onAppear {
            updateTimeRemaining()
            // Start timer only when view appears
            timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    updateTimeRemaining()
                }
        }
        .onDisappear {
            // Cancel timer when view disappears
            timerCancellable?.cancel()
            timerCancellable = nil
        }
    }

    private func updateTimeRemaining() {
        if ritual.hasElapsed {
            timeRemaining = "Ended"
        } else if ritual.hasStarted {
            timeRemaining = "Live now"
        } else {
            timeRemaining = ritual.formattedTimeUntilStart
        }
    }
}

#Preview {
    RitualScheduleCard(
        circleId: UUID(),
        isOwner: true,
        onJoinRitual: { _ in },
        onCreateRitual: {}
    )
    .environmentObject(DependencyContainer())
    .padding()
}
