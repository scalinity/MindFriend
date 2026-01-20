import SwiftUI

struct DistortionCoachCard: View {
    let coachData: CoachData
    let isAcknowledged: Bool  // Passed from parent instead of local @State
    let onAction: (CoachInteraction.Action) -> Void

    @State private var showFullEducation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)
                Text("Noticed something")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            // Short description with distortion name
            VStack(alignment: .leading, spacing: 6) {
                Text("\"" + coachData.distortionName + "\"")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(coachData.shortDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Reframe suggestion
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .accessibilityHidden(true)
                    Text("Reframe:")
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                Text(coachData.reframeText)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            // Socratic questions (optional expansion)
            if showFullEducation && !coachData.socraticQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Questions to consider:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(Array(coachData.socraticQuestions.prefix(3).enumerated()), id: \.offset) { index, question in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(question)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }

            // Action buttons
            if !isAcknowledged {
                HStack(spacing: 12) {
                    Button {
                        onAction(.helpful)
                    } label: {
                        Text("This helps")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .accessibilityLabel("This helps")
                    .accessibilityHint("Marks this cognitive reframe as helpful and records your feedback")

                    Button {
                        onAction(.dismissed)
                    } label: {
                        Text("Not right now")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                    .accessibilityLabel("Not right now")
                    .accessibilityHint("Dismisses this suggestion and suppresses coaching for 30 minutes")

                    Button {
                        showFullEducation.toggle()
                    } label: {
                        Text("Learn more")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                    .accessibilityLabel("Learn more")
                    .accessibilityHint("Shows additional reflection questions about this thinking pattern")
                }
            } else {
                // Acknowledged state
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .accessibilityHidden(true)
                    Text("Thank you for engaging")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Coach feedback acknowledged")
                .transition(.opacity)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
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
    .background(Color.gray.opacity(0.1))
}
