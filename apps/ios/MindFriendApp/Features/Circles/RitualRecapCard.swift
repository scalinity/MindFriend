import SwiftUI

/// Card for displaying a ritual recap post in the circle feed
struct RitualRecapCard: View {
    @EnvironmentObject var container: DependencyContainer

    let post: CirclePost
    let ritualId: UUID?

    @State private var reflections: [RitualReflectionInfo] = []
    @State private var isLoadingReflections = false

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Header
            HStack(spacing: SupportTheme.Spacing.s) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundColor(SupportTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(SupportTheme.surface)
                    .cornerRadius(SupportTheme.controlRadius)

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    HStack {
                        Text(post.userDisplayName)
                            .fontWeight(.semibold)

                        Text("RITUAL")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(SupportTheme.accent)
                            .padding(.horizontal, SupportTheme.Spacing.xs)
                            .padding(.vertical, SupportTheme.Spacing.xxs)
                            .background(SupportTheme.surface)
                            .cornerRadius(SupportTheme.controlRadius)
                    }

                    Text(post.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
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

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Reflections")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(SupportTheme.textSecondary)

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
                .padding(.vertical, SupportTheme.Spacing.xs)
            }
        }
        .supportCard()
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
        HStack(alignment: .top, spacing: SupportTheme.Spacing.xs) {
            // Quote mark
            Text("\u{201D}")
                .font(.title2)
                .foregroundColor(SupportTheme.accent.opacity(0.5))

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(reflection.content)
                    .font(.subheadline)
                    .italic()

                Text("— \(reflection.displayName)")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
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
