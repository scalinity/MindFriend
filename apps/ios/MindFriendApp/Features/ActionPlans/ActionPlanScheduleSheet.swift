import SwiftUI

struct ActionPlanScheduleSheet: View {
    let plan: ActionPlan
    let items: [ActionPlanItem]
    let onPlanUpdated: (ActionPlan, [ActionPlanItem]) -> Void

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTime: Date = Date()
    @State private var adjustedTime: Date = Date()
    @State private var showEditSheet = false
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    private let scheduler = ActionPlanScheduler()

    private var quietHoursStart: String? {
        appState.currentUser?.settings.quietHoursStartLocal
    }

    private var quietHoursEnd: String? {
        appState.currentUser?.settings.quietHoursEndLocal
    }

    private var adjustmentNotice: String? {
        guard selectedTime != adjustedTime else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Adjusted to \(formatter.string(from: adjustedTime)) to respect quiet hours."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    "Choose a time",
                    selection: $selectedTime,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .onChange(of: selectedTime) { _, newValue in
                    adjustedTime = scheduler.adjustForQuietHours(
                        date: newValue,
                        quietHoursStart: quietHoursStart,
                        quietHoursEnd: quietHoursEnd
                    )
                }

                if let notice = adjustmentNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    showEditSheet = true
                } label: {
                    Text("Edit Items")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                }
                .disabled(plan.status != .draft)

                Button {
                    Task { await schedulePlan() }
                } label: {
                    Text("Schedule")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(isSaving)

                Spacer()
            }
            .padding()
            .navigationTitle("Schedule Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                ActionPlanEditItemsSheet(
                    plan: plan,
                    items: items,
                    onPlanUpdated: handlePlanUpdate
                )
                .environmentObject(appState)
                .environmentObject(container)
            }
            .alert("Schedule", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            let initial = plan.scheduledFor ?? Date().addingTimeInterval(60 * 30)
            selectedTime = initial
            adjustedTime = scheduler.adjustForQuietHours(
                date: initial,
                quietHoursStart: quietHoursStart,
                quietHoursEnd: quietHoursEnd
            )
        }
    }

    private func schedulePlan() async {
        isSaving = true
        do {
            let scheduledTime = try await scheduler.schedulePlan(
                planId: plan.id,
                title: "Your Action Plan",
                scheduledFor: selectedTime,
                quietHoursStart: quietHoursStart,
                quietHoursEnd: quietHoursEnd,
                fallbackToNotifications: false
            )

            let result = try await container.actionPlanService.recordPlan(
                planId: plan.id,
                status: .scheduled,
                scheduledFor: scheduledTime,
                itemsCompleted: [],
                itemsSkipped: [],
                feedback: nil
            )

            await MainActor.run {
                handlePlanUpdate(result.0, result.1)
                appState.todayActionPlan = result.0
                appState.todayActionPlanItems = result.1
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        isSaving = false
    }

    private func handlePlanUpdate(_ plan: ActionPlan, _ items: [ActionPlanItem]) {
        onPlanUpdated(plan, items)
    }
}

