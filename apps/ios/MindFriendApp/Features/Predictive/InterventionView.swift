import SwiftUI

/// View for displaying and responding to proactive interventions
/// Designed to be supportive and non-clinical
struct InterventionView: View {
    let intervention: Intervention
    let onAccept: (String?) -> Void
    let onDismiss: () -> Void

    @State private var selectedAction: String?
    @State private var isAccepting = false

    var body: some View {
        VStack(spacing: 24) {
            // Header with icon
            headerSection

            // Message
            messageSection

            // Suggested actions
            actionsSection

            // Response buttons
            buttonSection
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        .padding(.horizontal, 20)
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Icon with background
            ZStack {
                Circle()
                    .fill(iconBackgroundColor.opacity(0.15))
                    .frame(width: 72, height: 72)

                Image(systemName: intervention.interventionType.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(iconBackgroundColor)
            }

            Text(intervention.interventionType.title)
                .font(.title3.weight(.semibold))
        }
    }

    private var iconBackgroundColor: Color {
        switch intervention.interventionType {
        case .gentleNudge:
            return .blue
        case .activeCheckin:
            return .purple
        case .crisisProtocol:
            return .pink
        case .familyAlert:
            return .orange
        }
    }

    private var messageSection: some View {
        Text(intervention.messageTemplate)
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            ForEach(Array(zip(intervention.suggestedActions.indices, intervention.suggestedActions)), id: \.0) { index, action in
                ActionButton(
                    action: action,
                    label: index < intervention.actionLabels.count ? intervention.actionLabels[index] : action,
                    isSelected: selectedAction == action
                ) {
                    selectedAction = action
                }
            }
        }
    }

    private var buttonSection: some View {
        VStack(spacing: 12) {
            // Accept button
            Button {
                isAccepting = true
                onAccept(selectedAction)
            } label: {
                HStack {
                    if isAccepting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(acceptButtonText)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .cornerRadius(14)
            }
            .disabled(isAccepting)

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Text("Not right now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .disabled(isAccepting)
        }
    }

    private var acceptButtonText: String {
        if let action = selectedAction {
            switch action {
            case "breathing_exercise":
                return "Start Breathing Exercise"
            case "chat":
                return "Let's Talk"
            case "crisis_line":
                return "Get Support Now"
            case "grounding_exercise":
                return "Start Grounding Exercise"
            case "sleep_meditation":
                return "Start Sleep Meditation"
            case "circle_checkin":
                return "Check In with Circle"
            default:
                return "Let's Do This"
            }
        }
        return "I'm Here"
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let action: String
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: iconForAction)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? .white : .accentColor)
                    .frame(width: 24)

                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : Color(.separator), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconForAction: String {
        switch action {
        case "breathing_exercise":
            return "wind"
        case "chat":
            return "bubble.left.and.bubble.right"
        case "crisis_line":
            return "phone.fill"
        case "grounding_exercise":
            return "leaf.fill"
        case "sleep_meditation":
            return "moon.stars.fill"
        case "circle_checkin":
            return "person.2.fill"
        default:
            return "sparkles"
        }
    }
}

// MARK: - Intervention Sheet

struct InterventionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let intervention: Intervention
    let onAccept: (String?) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // Don't dismiss on background tap for important interventions
                    if intervention.interventionType == .gentleNudge {
                        onDismiss()
                        dismiss()
                    }
                }

            InterventionView(
                intervention: intervention,
                onAccept: { action in
                    onAccept(action)
                    dismiss()
                },
                onDismiss: {
                    onDismiss()
                    dismiss()
                }
            )
        }
    }
}

// MARK: - Intervention Rating View

struct InterventionRatingView: View {
    let interventionId: UUID
    let onSubmit: (Int, String?) -> Void

    @State private var rating: Int = 0
    @State private var feedback: String = ""
    @State private var showFeedback = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Was this helpful?")
                .font(.headline)

            // Star rating
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                        if star >= 4 {
                            onSubmit(star, nil)
                        } else {
                            showFeedback = true
                        }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(star <= rating ? .yellow : .gray)
                    }
                }
            }

            if showFeedback {
                VStack(spacing: 12) {
                    Text("How can we do better?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Optional feedback", text: $feedback, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)

                    Button("Submit") {
                        onSubmit(rating, feedback.isEmpty ? nil : feedback)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .animation(.spring(response: 0.3), value: showFeedback)
    }
}

// MARK: - Preview

#Preview("Gentle Nudge") {
    InterventionView(
        intervention: Intervention(
            id: UUID(),
            userId: UUID(),
            riskAssessmentId: nil as UUID?,
            interventionType: InterventionType.gentleNudge,
            channel: InterventionChannel.inApp,
            messageTemplate: "Hi! Just checking in. I noticed you've been less active lately. Remember, I'm always here if you want to talk or do a quick breathing exercise.",
            personalization: nil as [String: AnyCodableValue]?,
            suggestedActions: ["breathing_exercise", "chat"],
            suggestedExerciseId: nil as UUID?,
            scheduledAt: Date(),
            deliveredAt: Date(),
            expiresAt: Date().addingTimeInterval(86400),
            response: InterventionResponse.pending,
            respondedAt: nil as Date?,
            actionTaken: nil as String?,
            moodBefore: nil as Int?,
            mood24hAfter: nil as Int?,
            helpfulRating: nil as Int?,
            userFeedback: nil as String?
        ),
        onAccept: { action in print("Accepted: \(action ?? "none")") },
        onDismiss: { print("Dismissed") }
    )
}

#Preview("Active Check-in") {
    InterventionView(
        intervention: Intervention(
            id: UUID(),
            userId: UUID(),
            riskAssessmentId: nil as UUID?,
            interventionType: InterventionType.activeCheckin,
            channel: InterventionChannel.inApp,
            messageTemplate: "Hey, I noticed things have been tough lately. I'm here for you – want to check in together?",
            personalization: nil as [String: AnyCodableValue]?,
            suggestedActions: ["grounding_exercise", "chat", "circle_checkin"],
            suggestedExerciseId: nil as UUID?,
            scheduledAt: Date(),
            deliveredAt: Date(),
            expiresAt: Date().addingTimeInterval(86400),
            response: InterventionResponse.pending,
            respondedAt: nil as Date?,
            actionTaken: nil as String?,
            moodBefore: nil as Int?,
            mood24hAfter: nil as Int?,
            helpfulRating: nil as Int?,
            userFeedback: nil as String?
        ),
        onAccept: { action in print("Accepted: \(action ?? "none")") },
        onDismiss: { print("Dismissed") }
    )
}

#Preview("Crisis Protocol") {
    InterventionView(
        intervention: Intervention(
            id: UUID(),
            userId: UUID(),
            riskAssessmentId: nil as UUID?,
            interventionType: InterventionType.crisisProtocol,
            channel: InterventionChannel.push,
            messageTemplate: "I'm concerned about you and want to make sure you're safe. Would you like to talk or connect with support resources?",
            personalization: nil as [String: AnyCodableValue]?,
            suggestedActions: ["crisis_line", "chat", "breathing_exercise"],
            suggestedExerciseId: nil as UUID?,
            scheduledAt: Date(),
            deliveredAt: Date(),
            expiresAt: Date().addingTimeInterval(86400),
            response: InterventionResponse.pending,
            respondedAt: nil as Date?,
            actionTaken: nil as String?,
            moodBefore: nil as Int?,
            mood24hAfter: nil as Int?,
            helpfulRating: nil as Int?,
            userFeedback: nil as String?
        ),
        onAccept: { action in print("Accepted: \(action ?? "none")") },
        onDismiss: { print("Dismissed") }
    )
}

#Preview("Rating") {
    InterventionRatingView(interventionId: UUID()) { rating, feedback in
        print("Rating: \(rating), Feedback: \(feedback ?? "none")")
    }
}
