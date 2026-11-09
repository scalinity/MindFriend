import SwiftUI

/// Goal creation interface for setting outcome targets based on baseline assessment
@MainActor
struct GoalSettingView: View {
    let response: AssessmentResponse
    let template: AssessmentTemplate
    @ObservedObject var outcomeService: OutcomeTrackingService
    @Binding var isPresented: Bool

    @State private var suggestedTargetScore: Int = 0
    @State private var customTargetScore: String = ""
    @State private var targetDate = Date().addingTimeInterval(86400 * 84) // 12 weeks
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var showingConfirmation = false

    var assessmentType: AssessmentType? { AssessmentType(rawValue: template.code) }
    var baselineScore: Int { response.totalScore }
    var maxScore: Int { AssessmentType(rawValue: template.code)?.maxScore ?? 27 }
    var recommendedTargetScore: Int {
        assessmentType?.suggestedTargetScore(from: baselineScore) ?? baselineScore
    }

    var selectedTargetScore: Int {
        if let custom = Int(customTargetScore) {
            return custom
        }
        return recommendedTargetScore
    }

    var scoreImprovement: Int {
        assessmentType?.improvement(from: baselineScore, to: selectedTargetScore) ?? 0
    }

    var isValidTarget: Bool {
        guard response.availableScore != nil, let assessmentType,
              customTargetScore.isEmpty || Int(customTargetScore) != nil else { return false }
        return (0...maxScore).contains(selectedTargetScore)
            && assessmentType.improvement(from: baselineScore, to: selectedTargetScore) >= 0
    }

    var body: some View {
        ZStack {
            // Background
            SupportTheme.canvas
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text("Set Your Goal")
                            .font(.system(.title3, design: .default).weight(.bold))
                            .foregroundColor(SupportTheme.accent)

                        Text("Based on your baseline score")
                            .font(.system(.caption, design: .default).weight(.regular))
                            .foregroundColor(SupportTheme.textSecondary)
                    }

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.title2))
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                }
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.surface)
                .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 4, x: 0, y: 2)

                // Scrollable content
                ScrollView {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        // Baseline score card
                        VStack(spacing: SupportTheme.Spacing.s) {
                            HStack {
                                Text("Your Baseline")
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.accent)

                                Spacer()

                                HStack(spacing: SupportTheme.Spacing.xxs) {
                                    Text("\(baselineScore)")
                                        .font(.system(.title3, design: .default).weight(.bold))
                                        .foregroundColor(SupportTheme.accent)

                                    Text("/ \(maxScore)")
                                        .font(.system(.caption, design: .default).weight(.regular))
                                        .foregroundColor(SupportTheme.textSecondary)
                                }
                            }

                            Divider()

                            Text(response.severityLevel)
                                .font(.system(.caption, design: .default).weight(.semibold))
                                .foregroundColor(SupportTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(SupportTheme.Spacing.s)
                        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                        .padding(.horizontal, SupportTheme.Spacing.m)

                        // Target score section
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("Target Score")
                                .font(.system(.subheadline, design: .default).weight(.semibold))
                                .foregroundColor(SupportTheme.accent)

                            // Recommended target
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                                HStack(spacing: SupportTheme.Spacing.xs) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.system(.caption))
                                        .foregroundColor(SupportTheme.accent)

                                    Text("Recommended")
                                        .font(.system(.caption, design: .default).weight(.semibold))
                                        .foregroundColor(SupportTheme.accent)
                                }

                                HStack(spacing: SupportTheme.Spacing.s) {
                                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                        HStack(spacing: SupportTheme.Spacing.xxs) {
                                            Text("\(recommendedTargetScore)")
                                                .font(.system(.title3, design: .default).weight(.bold))
                                                .foregroundColor(SupportTheme.accent)

                                            Text("/ \(maxScore)")
                                                .font(.system(.subheadline, design: .default).weight(.regular))
                                                .foregroundColor(SupportTheme.textSecondary)
                                        }

                                        Text("\(scoreImprovement) point \(assessmentType?.higherScoresAreBetter == true ? "increase" : "reduction")")
                                            .font(.system(.caption, design: .default).weight(.regular))
                                            .foregroundColor(SupportTheme.textSecondary)
                                    }

                                    Spacer()

                                    if customTargetScore.isEmpty {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(.title3))
                                            .foregroundColor(SupportTheme.accent)
                                    }
                                }
                            }
                            .padding(SupportTheme.Spacing.s)
                            .background(
                                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                    .fill(SupportTheme.accent.opacity(0.05))
                                    .stroke(
                                        customTargetScore.isEmpty ?
                                        SupportTheme.accent :
                                        SupportTheme.textSecondary.opacity(0.2),
                                        lineWidth: 1
                                    )
                            )

                            // Custom target
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                                HStack(spacing: SupportTheme.Spacing.xs) {
                                    Text("Or set custom target")
                                        .font(.system(.caption, design: .default).weight(.regular))
                                        .foregroundColor(SupportTheme.textSecondary)

                                    Spacer()
                                }

                                HStack(spacing: SupportTheme.Spacing.s) {
                                    TextField(
                                        "Enter score 0-\(maxScore)",
                                        text: $customTargetScore
                                    )
                                    .keyboardType(.numberPad)
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .textFieldStyle(RoundedBorderTextFieldStyle())

                                    if !customTargetScore.isEmpty,
                                       let score = Int(customTargetScore),
                                       score >= 0, score <= maxScore {
                                        Text("–\(baselineScore - score) pts")
                                            .font(.system(.caption, design: .default).weight(.semibold))
                                            .foregroundColor(SupportTheme.textSecondary)
                                    }
                                }
                            }
                            .padding(SupportTheme.Spacing.s)
                            .background(
                                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                    .fill(SupportTheme.surface)
                                    .stroke(SupportTheme.textSecondary.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal, SupportTheme.Spacing.m)

                        // Target date section
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("Target Date")
                                .font(.system(.subheadline, design: .default).weight(.semibold))
                                .foregroundColor(SupportTheme.accent)

                            HStack(spacing: SupportTheme.Spacing.s) {
                                Image(systemName: "calendar")
                                    .font(.system(.subheadline))
                                    .foregroundColor(SupportTheme.accent)

                                DatePicker(
                                    "Target Date",
                                    selection: $targetDate,
                                    in: Date()...Date().addingTimeInterval(86400 * 365),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()

                                Spacer()

                                Text(targetDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(.caption, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.textSecondary)
                            }
                            .padding(SupportTheme.Spacing.s)
                            .background(
                                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                    .fill(SupportTheme.surface)
                                    .stroke(SupportTheme.textSecondary.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal, SupportTheme.Spacing.m)

                        // Goal summary card
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            HStack {
                                Image(systemName: "target")
                                    .font(.system(.subheadline).weight(.semibold))
                                    .foregroundColor(SupportTheme.accent)

                                Text("Goal Summary")
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.accent)

                                Spacer()
                            }

                            VStack(spacing: SupportTheme.Spacing.xs) {
                                GoalSummaryRow(label: "Current", value: "\(baselineScore)", color: SupportTheme.textSecondary)
                                GoalSummaryRow(label: "Target", value: "\(selectedTargetScore)", color: SupportTheme.accent)
                                GoalSummaryRow(label: "Timeline", value: "\(daysUntilTarget) days", color: SupportTheme.accent)
                            }
                        }
                        .padding(SupportTheme.Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                .fill(SupportTheme.surface)
                                .stroke(SupportTheme.textSecondary.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal, SupportTheme.Spacing.m)

                        Spacer()
                            .frame(height: 20)
                    }
                    .padding(.vertical, SupportTheme.Spacing.m)
                }

                // Action buttons
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Button(action: {
                        showingConfirmation = true
                    }) {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(SupportTheme.Spacing.s)
                        } else {
                            Text("Save Goal")
                                .font(.system(.subheadline, design: .default).weight(.semibold))
                                .foregroundColor(SupportTheme.onAccent)
                                .frame(maxWidth: .infinity)
                                .padding(SupportTheme.Spacing.s)
                                .background(
                                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                        .fill(SupportTheme.accent)
                                )
                        }
                    }
                    .disabled(isSaving || !isValidTarget)

                    Button(action: {
                        isPresented = false
                    }) {
                        Text("Skip for Now")
                            .font(.system(.subheadline, design: .default).weight(.semibold))
                            .foregroundColor(SupportTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(SupportTheme.Spacing.s)
                            .background(
                                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                    .fill(SupportTheme.surface)
                                    .stroke(SupportTheme.textSecondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.surface)
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Save Goal", isPresented: $showingConfirmation) {
            Button("Save", action: saveGoal)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a goal to reach \(selectedTargetScore) by \(targetDate.formatted(date: .abbreviated, time: .omitted))?")
        }
    }

    private var daysUntilTarget: Int {
        Int(targetDate.timeIntervalSince(Date()) / 86400)
    }

    private func saveGoal() {
        guard isValidTarget, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }

            do {
                // Call OutcomeTrackingService to save the custom goal
                _ = try await outcomeService.createCustomOutcomeGoal(
                    assessmentTemplateId: template.id,
                    baselineScore: baselineScore,
                    targetScore: selectedTargetScore,
                    targetDate: targetDate,
                    notes: notes.isEmpty ? nil : notes,
                    baselineResponseId: response.id
                )

                // Close the sheet on success
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                // Handle error - could show alert to user
                print("Failed to save goal: \(error.localizedDescription)")
                await MainActor.run {
                    isPresented = false
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct GoalSummaryRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .default).weight(.regular))
                .foregroundColor(SupportTheme.textSecondary)

            Spacer()

            HStack(spacing: SupportTheme.Spacing.xxs) {
                Text(value)
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundColor(color)
            }
        }
    }
}

#if DEBUG
#Preview {
    GoalSettingView(
        response: AssessmentResponse(
            id: UUID(),
            userId: UUID(),
            assessmentTemplateId: UUID(),
            answers: ["1": 1, "2": 2],
            totalScore: 20,
            severityLevel: "severe",
            isBaseline: true,
            notes: nil,
            completedAt: Date(),
            createdAt: Date()
        ),
        template: AssessmentTemplate(
            id: UUID(),
            code: "PHQ9",
            name: "PHQ-9",
            description: "Depression screening",
            questions: [],
            scoringRanges: [],
            recommendedFrequencyDays: 14,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        ),
        outcomeService: OutcomeTrackingService(supabase: .mock, authService: SupabaseAuthService()),
        isPresented: .constant(true)
    )
}
#endif
