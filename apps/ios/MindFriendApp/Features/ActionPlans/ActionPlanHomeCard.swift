import SwiftUI

struct ActionPlanHomeCard: View {
    let plan: ActionPlan
    let items: [ActionPlanItem]

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var showPlanSheet = false

    private var completedCount: Int {
        items.filter { $0.status == .completed }.count
    }

    private var progressLabel: String {
        "\(completedCount)/\(items.count)"
    }

    private var statusLabel: String {
        switch plan.status {
        case .draft: return "Draft"
        case .scheduled: return "Scheduled"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    private var scheduleLabel: String {
        guard let scheduledFor = plan.scheduledFor else { return "Not scheduled" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Scheduled \(formatter.string(from: scheduledFor))"
    }

    var body: some View {
        Button {
            showPlanSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Today's Plan", systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.purple)
                    Spacer()
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(items.count) items • \(progressLabel) complete")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(scheduleLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(items.prefix(3)) { item in
                        Text(item.title)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .tertiarySystemBackground))
                            .cornerRadius(8)
                    }
                    Spacer()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPlanSheet) {
            ActionPlanProgressSheet(plan: plan, items: items)
                .environmentObject(appState)
                .environmentObject(container)
        }
    }
}

#Preview {
    ActionPlanHomeCard(
        plan: ActionPlan(
            id: "plan",
            userId: "user",
            sourceType: .manual,
            planSize: .quick,
            localDate: "2026-01-19",
            timezone: "UTC",
            status: .draft,
            scheduledFor: nil,
            createdAt: Date(),
            updatedAt: Date()
        ),
        items: [
            ActionPlanItem(
                id: "item",
                planId: "plan",
                itemType: .exercise,
                referenceId: nil,
                title: "Breathing Reset",
                durationMinutes: 5,
                sortOrder: 0,
                status: .pending,
                completedAt: nil,
                skippedAt: nil
            )
        ]
    )
    .environmentObject(AppState())
    .environmentObject(DependencyContainer.preview)
}
