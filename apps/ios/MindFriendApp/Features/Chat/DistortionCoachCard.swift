import SwiftUI

struct DistortionCoachCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let coachData: CoachData
    let isAcknowledged: Bool  // Passed from parent instead of local @State
    let onAction: (CoachInteraction.Action) -> Void

    @State private var showFullEducation = false

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(SupportTheme.accent)
                    .accessibilityHidden(true)
                Text("Noticed something")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            // Short description with distortion name
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Text("\"" + coachData.distortionName + "\"")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(SupportTheme.textPrimary)

                Text(coachData.shortDescription)
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }

            // Reframe suggestion
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(SupportTheme.Celebration.gold)
                        .accessibilityHidden(true)
                    Text("Reframe:")
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                Text(coachData.reframeText)
                    .font(.subheadline)
                    .foregroundColor(SupportTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, SupportTheme.Spacing.xxs)

            // Socratic questions (optional expansion)
            if showFullEducation && !coachData.socraticQuestions.isEmpty {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Questions to consider:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(Array(coachData.socraticQuestions.prefix(3).enumerated()), id: \.offset) { index, question in
                        HStack(alignment: .top, spacing: SupportTheme.Spacing.xs) {
                            Text("•")
                                .foregroundColor(SupportTheme.textSecondary)
                            Text(question)
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)
                        }
                    }
                }
                .padding(.top, SupportTheme.Spacing.xxs)
            }

            // Action buttons
            if !isAcknowledged {
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: SupportTheme.Spacing.s))
                    : AnyLayout(HStackLayout(spacing: SupportTheme.Spacing.s))) {
                    Button {
                        onAction(.helpful)
                    } label: {
                        Text("This helps")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.supportPrimary)
                    .accessibilityLabel("This helps")
                    .accessibilityHint("Marks this cognitive reframe as helpful and records your feedback")

                    Button {
                        onAction(.dismissed)
                    } label: {
                        Text("Not right now")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.supportSecondary)
                    .accessibilityLabel("Not right now")
                    .accessibilityHint("Dismisses this suggestion and suppresses coaching for 30 minutes")

                    Button {
                        showFullEducation.toggle()
                    } label: {
                        Text("Learn more")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.supportSecondary)
                    .accessibilityLabel("Learn more")
                    .accessibilityHint("Shows additional reflection questions about this thinking pattern")
                }
            } else {
                // Acknowledged state
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(SupportTheme.accent)
                        .accessibilityHidden(true)
                    Text("Thank you for engaging")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }
                .accessibilityLabel("Coach feedback acknowledged")
                .transition(reduceMotion ? .opacity.animation(.easeInOut(duration: 0.2)) : .opacity)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                .fill(SupportTheme.canvas)
                .shadow(color: SupportTheme.canvas.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                .stroke(SupportTheme.accent.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.vertical, SupportTheme.Spacing.xs)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        DistortionCoachCard(
            coachData: CoachData(
                encounterId: UUID(),
                distortionCode: "AON",
                distortionName: "All-or-Nothing Thinking",
                shortDescription: "Seeing things in black and white categories",
                reframeText: "Perfection isn't possible. What went well?",
                educationalContent: "All-or-nothing thinking means viewing situations in only two categories instead of on a continuum.",
                socraticQuestions: [
                    "What evidence do I have that supports both sides?",
                    "Am I viewing this in extremes?",
                    "What's the middle ground here?"
                ],
                confidence: 0.85
            ),
            isAcknowledged: false,
            onAction: { action in
                print("Action: \(action)")
            }
        )

        Spacer()
    }
    .background(SupportTheme.surface)
}
