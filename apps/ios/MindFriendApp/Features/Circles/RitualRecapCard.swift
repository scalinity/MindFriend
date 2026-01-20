import SwiftUI

/// Card for displaying a ritual recap post in the circle feed
struct RitualRecapCard: View {
    @EnvironmentObject var container: DependencyContainer

    let post: CirclePost
    let ritualId: UUID?

    @State private var reflections: [RitualReflectionInfo] = []
    @State private var isLoadingReflections = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundColor(.purple)
                    .frame(width: 44, height: 44)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(post.userDisplayName)
                            .fontWeight(.semibold)

                        Text("RITUAL")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(4)
                    }

                    Text(post.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Body text
            if let body = post.bodyText {
                Text(body)
                    .font(.body)
            }

            // Reflections section
            if !reflections.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Reflections")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    ForEach(reflections) { reflection in
                        ReflectionRow(reflection: reflection)
                    }
                }
            } else if isLoadingReflections {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(16)
        .task {
            if let ritualId = ritualId {
                await loadReflections(ritualId: ritualId)
            }
        }
    }

    private func loadReflections(ritualId: UUID) async {
        isLoadingReflections = true
        defer { isLoadingReflections = false }

        do {
            reflections = try await container.ritualService.fetchReflections(ritualId: ritualId)
        } catch {
            print("Failed to load reflections: \(error)")
        }
    }
}

/// Single reflection row
struct ReflectionRow: View {
    let reflection: RitualReflectionInfo

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Quote mark
            Text("\u{201D}")
                .font(.title2)
                .foregroundColor(.purple.opacity(0.5))

            VStack(alignment: .leading, spacing: 4) {
                Text(reflection.content)
                    .font(.subheadline)
                    .italic()

                Text("— \(reflection.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RitualRecapCard(
        post: CirclePost(
            id: UUID().uuidString,
            circleId: UUID().uuidString,
            userId: UUID().uuidString,
            kind: .ritualRecap,
            moodEmoji: nil,
            bodyText: "3 members completed the Gratitude ritual: \"Morning Practice\"",
            localDate: "2026-01-20",
            createdAt: Date(),
            userDisplayName: "Alice"
        ),
        ritualId: UUID()
    )
    .environmentObject(DependencyContainer())
    .padding()
}
