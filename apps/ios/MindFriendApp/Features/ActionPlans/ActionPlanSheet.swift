import SwiftUI

private enum ActionPlanRegenerationError: LocalizedError {
    case locked

    var errorDescription: String? {
        "You can't regenerate a plan once it has started."
    }
}

struct ActionPlanSheet: View {
    let plan: ActionPlan
    let items: [ActionPlanItem]
    let planSize: ActionPlanSize
    let onPlanUpdated: (ActionPlan, [ActionPlanItem]) -> Void
    let onDismiss: () -> Void

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var currentPlan: ActionPlan
    @State private var currentItems: [ActionPlanItem]
    @State private var currentPlanSize: ActionPlanSize
    @State private var isSaving = false
    @State private var showScheduleSheet = false
    @State private var showError = false
    @State private var errorMessage = ""

    init(
        plan: ActionPlan,
        items: [ActionPlanItem],
        planSize: ActionPlanSize,
        onPlanUpdated: @escaping (ActionPlan, [ActionPlanItem]) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.plan = plan
        self.items = items
        self.planSize = planSize
        self.onPlanUpdated = onPlanUpdated
        self.onDismiss = onDismiss
        _currentPlan = State(initialValue: plan)
        _currentItems = State(initialValue: items)
        _currentPlanSize = State(initialValue: planSize)
    }

    private var totalMinutes: Int {
        currentItems.reduce(0) { $0 + $1.durationMinutes }
    }

    private var itemCountLabel: String {
        "\(currentItems.count) items"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Your Action Plan")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("\(currentPlanSize.displayName) • \(currentPlanSize.timeRangeLabel) • \(itemCountLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("Plan Size", selection: $currentPlanSize) {
                    Text(ActionPlanSize.quick.displayName).tag(ActionPlanSize.quick)
                    Text(ActionPlanSize.standard.displayName).tag(ActionPlanSize.standard)
                }
                .pickerStyle(.segmented)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(currentItems) { item in
                            ActionPlanItemRow(item: item)
                        }

                        if currentItems.isEmpty {
                            Text("No items left in this plan.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    Task { await regeneratePlan() }
                } label: {
                    Text("Regenerate Plan")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                }
                .disabled(isSaving)

                VStack(spacing: 12) {
                    Button {
                        showScheduleSheet = true
                    } label: {
                        Text("Schedule Plan")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .disabled(currentItems.isEmpty || isSaving)

                    Button {
                        Task { await startNow() }
                    } label: {
                        Text("Start Now")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(12)
                    }
                    .disabled(currentItems.isEmpty || isSaving)
                }
            }
            .padding()
            .navigationTitle("Action Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismissSheet()
                    }
                }
            }
            .sheet(isPresented: $showScheduleSheet) {
                ActionPlanScheduleSheet(
                    plan: currentPlan,
                    items: currentItems,
                    onPlanUpdated: handlePlanUpdate
                )
                .environmentObject(appState)
                .environmentObject(container)
            }
            .alert("Action Plan", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func startNow() async {
        isSaving = true
        do {
            let result = try await container.actionPlanService.recordPlan(
                planId: currentPlan.id,
                status: .inProgress,
                scheduledFor: nil,
                itemsCompleted: [],
                itemsSkipped: [],
                feedback: nil
            )
            await MainActor.run {
                handlePlanUpdate(result.0, result.1)
                appState.todayActionPlan = result.0
                appState.todayActionPlanItems = result.1
                dismissSheet()
            }
        } catch {
            await MainActor.run {
                showError(message: error.localizedDescription)
            }
        }
        isSaving = false
    }

    private func regeneratePlan() async {
        guard currentPlan.status == .draft || currentPlan.status == .scheduled else {
            await MainActor.run {
                showError(message: ActionPlanRegenerationError.locked.localizedDescription)
            }
            return
        }

        isSaving = true
        do {
            let timezone = appState.currentUser?.timezone ?? TimeZone.current.identifier
            let (plan, items, _) = try await container.actionPlanService.generatePlan(
                sourceType: currentPlan.sourceType,
                planSize: currentPlanSize,
                timezone: timezone,
                regenerate: true
            )
            await MainActor.run {
                currentPlan = plan
                currentItems = items
                onPlanUpdated(plan, items)
            }
        } catch let error as APIError {
            await MainActor.run {
                if case .quotaExceeded = error {
                    appState.showPaywall = true
                } else {
                    showError(message: error.localizedDescription)
                }
            }
        } catch {
            await MainActor.run {
                showError(message: error.localizedDescription)
            }
        }
        isSaving = false
    }

    private func handlePlanUpdate(_ plan: ActionPlan, _ items: [ActionPlanItem]) {
        currentPlan = plan
        currentItems = items
        onPlanUpdated(plan, items)
    }

    private func dismissSheet() {
        dismiss()
        onDismiss()
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

private struct ActionPlanItemRow: View {
    let item: ActionPlanItem

    private var iconName: String {
        switch item.itemType {
        case .quest: return "star.fill"
        case .exercise: return "figure.mind.and.body"
        case .chat: return "bubble.left.and.bubble.right.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text("\(item.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if item.status == .skipped {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(14)
    }
}

