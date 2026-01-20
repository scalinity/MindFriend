import SwiftUI

struct ActionPlanEditItemsSheet: View {
    let plan: ActionPlan
    let items: [ActionPlanItem]
    let onPlanUpdated: (ActionPlan, [ActionPlanItem]) -> Void

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var currentItems: [ActionPlanItem]
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    init(plan: ActionPlan, items: [ActionPlanItem], onPlanUpdated: @escaping (ActionPlan, [ActionPlanItem]) -> Void) {
        self.plan = plan
        self.items = items
        self.onPlanUpdated = onPlanUpdated
        _currentItems = State(initialValue: items)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(currentItems) { item in
                    ActionPlanEditRow(
                        item: item,
                        onSwap: { Task { await swapItem(item) } },
                        onRemove: { Task { await removeItem(item) } }
                    )
                }
            }
            .navigationTitle("Edit Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Update Plan", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func removeItem(_ item: ActionPlanItem) async {
        guard plan.status == .draft else { return }
        isSaving = true
        do {
            let result = try await container.actionPlanService.recordPlan(
                planId: plan.id,
                status: nil,
                scheduledFor: nil,
                itemsCompleted: [],
                itemsSkipped: [],
                feedback: nil,
                removeItemIds: [item.id]
            )
            await MainActor.run {
                currentItems = result.1
                onPlanUpdated(result.0, result.1)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        isSaving = false
    }

    private func swapItem(_ item: ActionPlanItem) async {
        guard plan.status == .draft else { return }
        isSaving = true
        do {
            let replacement = try await buildReplacement(for: item)
            let update = ActionPlanService.ActionPlanItemUpdate(
                id: item.id,
                itemType: replacement.itemType,
                referenceId: replacement.referenceId,
                title: replacement.title,
                durationMinutes: replacement.durationMinutes,
                sortOrder: item.sortOrder
            )
            let result = try await container.actionPlanService.recordPlan(
                planId: plan.id,
                status: nil,
                scheduledFor: nil,
                itemsCompleted: [],
                itemsSkipped: [],
                feedback: nil,
                items: [update]
            )
            await MainActor.run {
                currentItems = result.1
                onPlanUpdated(result.0, result.1)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        isSaving = false
    }

    private func buildReplacement(for item: ActionPlanItem) async throws -> ActionPlanItem {
        switch item.itemType {
        case .quest:
            if let quest = appState.todayQuest {
                return ActionPlanItem(
                    id: item.id,
                    planId: plan.id,
                    itemType: .quest,
                    referenceId: quest.id,
                    title: quest.template.title,
                    durationMinutes: quest.template.estimatedMinutes,
                    sortOrder: item.sortOrder,
                    status: item.status,
                    completedAt: item.completedAt,
                    skippedAt: item.skippedAt
                )
            }
        case .exercise:
            let exercises = try await container.supabaseDataService.getExercises()
            let currentIds = Set(currentItems.compactMap { $0.referenceId })
            if let candidate = exercises.first(where: { !currentIds.contains($0.id) }) {
                return ActionPlanItem(
                    id: item.id,
                    planId: plan.id,
                    itemType: .exercise,
                    referenceId: candidate.id,
                    title: candidate.title,
                    durationMinutes: Int(ceil(Double(candidate.durationSeconds) / 60.0)),
                    sortOrder: item.sortOrder,
                    status: item.status,
                    completedAt: item.completedAt,
                    skippedAt: item.skippedAt
                )
            }
        case .chat:
            return ActionPlanItem(
                id: item.id,
                planId: plan.id,
                itemType: .chat,
                referenceId: nil,
                title: "Check in with MindFriend",
                durationMinutes: 2,
                sortOrder: item.sortOrder,
                status: item.status,
                completedAt: item.completedAt,
                skippedAt: item.skippedAt
            )
        }

        return item
    }
}

private struct ActionPlanEditRow: View {
    let item: ActionPlanItem
    let onSwap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .font(.headline)
                Spacer()
                Text("\(item.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Swap") { onSwap() }
                    .buttonStyle(.bordered)
                Button("Remove") { onRemove() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

