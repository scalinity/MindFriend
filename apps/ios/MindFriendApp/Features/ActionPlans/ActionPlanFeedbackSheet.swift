import SwiftUI

struct ActionPlanFeedbackSheet: View {
    private enum FeedbackError: LocalizedError {
        case missingRating

        var errorDescription: String? {
            "Choose a rating before submitting feedback."
        }
    }

    let plan: ActionPlan
    let onPlanUpdated: (ActionPlan, [ActionPlanItem]) -> Void

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var rating: Int? = nil
    @State private var notes: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("How was this plan?")
                    .font(.headline)

                HStack(spacing: 16) {
                    feedbackButton(label: "Not helpful", value: 0)
                    feedbackButton(label: "Helpful", value: 1)
                }
                .accessibilityLabel("Plan feedback")

                TextField("Optional notes", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                Button {
                    Task { await saveFeedback() }
                } label: {
                    Text("Submit")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(isSaving || rating == nil)

                Spacer()
            }
            .padding()
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func feedbackButton(label: String, value: Int) -> some View {
        Button {
            rating = value
        } label: {
            Text(label)
                .font(.subheadline)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(rating == value ? Color.accentColor.opacity(0.2) : Color(uiColor: .secondarySystemBackground))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func saveFeedback() async {
        guard let rating else {
            appState.showError(.apiError(FeedbackError.missingRating.localizedDescription))
            return
        }

        isSaving = true
        let feedback = ActionPlanFeedback(
            planId: plan.id,
            rating: rating,
            notes: notes.isEmpty ? nil : notes
        )

        do {
            let result = try await container.actionPlanService.recordPlan(
                planId: plan.id,
                status: nil,
                scheduledFor: nil,
                itemsCompleted: [],
                itemsSkipped: [],
                feedback: feedback
            )
            await MainActor.run {
                onPlanUpdated(result.0, result.1)
                appState.showCelebration(
                    title: "Plan Complete",
                    subtitle: "Nice work showing up today.",
                    icon: "sparkles"
                )
                dismiss()
            }
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
        isSaving = false
    }
}

