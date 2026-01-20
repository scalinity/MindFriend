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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Rituals", systemImage: "sparkles")
                    .font(.headline)

                Spacer()

                Button {
                    onCreateRitual()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .accessibilityLabel("Create ritual")
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if upcomingRituals.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("No upcoming rituals")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        onCreateRitual()
                    } label: {
                        Text("Start a Ritual")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(upcomingRituals) { ritual in
                    RitualRowView(
                        ritual: ritual,
                        onJoin: { onJoinRitual(ritual) }
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
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
        HStack(spacing: 12) {
            // Icon
            Image(systemName: ritual.ritualType.icon)
                .font(.title2)
                .foregroundColor(ritual.ritualType.swiftUIColor)
                .frame(width: 40, height: 40)
                .background(ritual.ritualType.swiftUIColor.opacity(0.15))
                .cornerRadius(10)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(ritual.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(ritual.ritualType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(timeRemaining)
                        .font(.caption)
                        .foregroundColor(ritual.hasStarted ? .green : .secondary)
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(ritual.hasStarted ? .green : .accentColor)
            } else {
                Text("Ended")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
