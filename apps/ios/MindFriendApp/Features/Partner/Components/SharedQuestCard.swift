import SwiftUI

/// Card displaying partner's today quest status
struct SharedQuestCard: View {
    let quest: Quest?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star")
                    .foregroundStyle(.tint)
                Text("Today's Quest")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            if let quest = quest {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(quest.template.title)
                            .font(.subheadline)
                            .lineLimit(2)

                        Text(quest.template.type.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Status badge
                    HStack(spacing: 4) {
                        Image(systemName: quest.status == .completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(quest.status == .completed ? .green : .secondary)

                        Text(quest.status == .completed ? "Done" : "In Progress")
                            .font(.caption)
                            .foregroundStyle(quest.status == .completed ? .green : .secondary)
                    }
                }
            } else {
                Text("No quest assigned yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 16) {
        SharedQuestCard(quest: Quest(
            id: "1",
            localDate: "2026-01-20",
            status: .completed,
            assignedAt: Date(),
            completedAt: Date(),
            template: QuestTemplate(
                id: "t1",
                type: .walk,
                title: "Take a 10-minute mindful walk",
                description: "Notice the sights and sounds around you",
                estimatedMinutes: 10,
                difficulty: "easy",
                tags: ["mindfulness", "outdoor"],
                instructions: []
            )
        ))

        SharedQuestCard(quest: Quest(
            id: "2",
            localDate: "2026-01-20",
            status: .assigned,
            assignedAt: Date(),
            completedAt: nil,
            template: QuestTemplate(
                id: "t2",
                type: .breathing,
                title: "Practice deep breathing",
                description: "Take 5 deep breaths",
                estimatedMinutes: 5,
                difficulty: "easy",
                tags: ["breathing"],
                instructions: []
            )
        ))

        SharedQuestCard(quest: nil)
    }
    .padding()
}
