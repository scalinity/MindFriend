import SwiftUI

struct ActionPlanProgressSheet: View {
    let plan: ActionPlan
    let items: [ActionPlanItem]

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var currentItems: [ActionPlanItem]
    @State private var showFeedbackSheet = false
    @State private var isSaving = false

    init(plan: ActionPlan, items: [ActionPlanItem]) {
        self.plan = plan
        self.items = items
        _currentItems = State(initialValue: items)
    }

    private var completedCount: Int {
        currentItems.filter { $0.status == .completed }.count
    }

    private var allDone: Bool {
        !currentItems.isEmpty && currentItems.allSatisfy { $0.status != .pending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Progress")
                    .font(.title2)
                    .fontWeight(.semibold)

                ForEach(currentItems) { item in
                    ActionPlanProgressRow(
                        item: item,
                        onComplete: { Task { await markItem(item, status: .completed) } },
                        onSkip: { Task { await markItem(item, status: .skipped) } }
                    )
                }

                if allDone {
                    Button {
                        showFeedbackSheet = true
                    } label: {
                        Text("Leave Feedback")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Action Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showFeedbackSheet) {
                ActionPlanFeedbackSheet(
                    plan: plan,
                    onPlanUpdated: handlePlanUpdate
                )
                .environmentObject(appState)
                .environmentObject(container)
            }
        }
    }

    private func markItem(_ item: ActionPlanItem, status: ActionPlanItemStatus) async {
        guard item.status == .pending else { return }
        isSaving = true
        do {
            let result: (ActionPlan, [ActionPlanItem])
            if status == .completed {
                result = try await container.actionPlanService.recordPlan(
                    planId: plan.id,
                    status: nil,
                    scheduledFor: nil,
                    itemsCompleted: [item.id],
                    itemsSkipped: [],
                    feedback: nil
                )
            } else {
                result = try await container.actionPlanService.recordPlan(
                    planId: plan.id,
                    status: nil,
                    scheduledFor: nil,
                    itemsCompleted: [],
                    itemsSkipped: [item.id],
                    feedback: nil
                )
            }
            await MainActor.run {
                handlePlanUpdate(result.0, result.1)
            }
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
        isSaving = false
    }

    private func handlePlanUpdate(_ plan: ActionPlan, _ items: [ActionPlanItem]) {
        currentItems = items
        appState.todayActionPlan = plan
        appState.todayActionPlanItems = items
    }
}

private struct ActionPlanProgressRow: View {
    let item: ActionPlanItem
    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text("\(item.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.status == .pending {
                Button("Complete") { onComplete() }
                    .buttonStyle(.borderedProminent)
                Button("Skip") { onSkip() }
                    .buttonStyle(.bordered)
            } else {
                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "minus.circle.fill")
                    .foregroundStyle(item.status == .completed ? .green : .orange)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}

