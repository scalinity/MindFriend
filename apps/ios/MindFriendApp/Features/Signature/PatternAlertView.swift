import SwiftUI

/// Detail view for a pattern alert with intervention options and feedback collection
struct PatternAlertView: View {
    let alert: PatternAlert
    @ObservedObject var engine: StressSignatureEngine

    @Environment(\.dismiss) private var dismiss

    @State private var selectedFeedback: AlertFeedback?
    @State private var feedbackNotes: String = ""
    @State private var isSubmitting = false
    @State private var showingFeedbackSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                alertHeader

                // Message
                messageCard

                // Active components
                activeComponentsCard

                // Suggested interventions
                if let pending = engine.interventionService.pendingIntervention,
                   pending.alertId == alert.id {
                    interventionsCard(pending: pending)
                }

                // Feedback section
                if alert.userFeedback == nil {
                    feedbackCard
                } else {
                    feedbackGivenCard
                }

                // Dismiss button
                if alert.isActive {
                    dismissButton
                }
            }
            .padding()
        }
        .navigationTitle("Pattern Alert")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Thank You", isPresented: $showingFeedbackSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your feedback helps us improve pattern detection. Your signature has been updated.")
        }
    }

    // MARK: - Alert Header

    private var alertHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(severityGradient)
                    .frame(width: 80, height: 80)

                Image(systemName: severityIcon)
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }

            Text(alert.severity.displayName)
                .font(.title2)
                .fontWeight(.bold)

            Text("Detected \(alert.detectedAt, style: .relative)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let hours = alert.predictedHours {
                HStack {
                    Image(systemName: "clock.fill")
                    Text("Estimated \(hours)h until crisis")
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.2))
                .foregroundStyle(.orange)
                .cornerRadius(16)
            }
        }
    }

    private var severityGradient: LinearGradient {
        switch alert.severity {
        case .mild:
            return LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .moderate:
            return LinearGradient(colors: [.orange, .red.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .severe:
            return LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var severityIcon: String {
        switch alert.severity {
        case .mild: return "exclamationmark"
        case .moderate: return "exclamationmark.2"
        case .severe: return "exclamationmark.3"
        }
    }

    // MARK: - Message Card

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(generateMessage())
                .font(.body)
                .lineSpacing(4)

            Divider()

            Text("This pattern has been detected based on your personal warning signs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func generateMessage() -> String {
        let signals = alert.activeComponents.map { $0.signal }

        if signals.contains("isolation") && signals.contains("insomnia_wired") {
            return "I've noticed you've been quieter lately and sleep has been tough. This is a pattern we've seen before. How are you really doing?"
        }

        if signals.contains("catastrophizing") || signals.contains("rumination") {
            return "It seems like worries have been building up. Your mind has been busy with difficult thoughts. Let's take a moment to get grounded."
        }

        if signals.contains("numbness") || signals.contains("oversleeping") {
            return "I'm noticing some familiar patterns - feeling disconnected or wanting to retreat. These are signs your system is overwhelmed."
        }

        switch alert.severity {
        case .severe:
            return "Several warning signs are appearing together. This is a good time to reach out for support and be extra gentle with yourself."
        case .moderate:
            return "Some patterns are emerging that we've tracked before. Take a moment to check in with yourself."
        case .mild:
            return "I'm noticing a few familiar signs. It might be worth paying attention to how you're feeling today."
        }
    }

    // MARK: - Active Components Card

    private var activeComponentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Warning Signs")
                .font(.headline)

            ForEach(alert.activeComponents, id: \.componentId) { active in
                if let component = SignatureComponent.component(for: active.signal) {
                    HStack {
                        Image(systemName: component.category.icon)
                            .foregroundStyle(.purple)
                            .frame(width: 24)

                        VStack(alignment: .leading) {
                            Text(component.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            HStack {
                                ProgressView(value: active.detectedValue)
                                    .tint(signalColor(active.detectedValue))
                                    .frame(width: 60)

                                Text("\(Int(active.detectedValue * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                if active.daysActive > 1 {
                                    Text("• \(active.daysActive) days")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func signalColor(_ value: Double) -> Color {
        switch value {
        case 0.8...: return .red
        case 0.6...: return .orange
        default: return .yellow
        }
    }

    // MARK: - Interventions Card

    private func interventionsCard(pending: PendingIntervention) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested Support")
                .font(.headline)

            ForEach(pending.suggestedInterventions.prefix(3)) { intervention in
                Button {
                    handleInterventionTap(intervention)
                } label: {
                    HStack {
                        interventionIcon(intervention.type)
                            .frame(width: 32, height: 32)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)

                        VStack(alignment: .leading) {
                            Text(intervention.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(intervention.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func interventionIcon(_ type: SuggestedIntervention.InterventionType) -> some View {
        switch type {
        case .exercise:
            Image(systemName: "figure.mind.and.body")
                .foregroundStyle(.purple)
        case .chat:
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(.blue)
        case .socialConnection:
            Image(systemName: "person.2.fill")
                .foregroundStyle(.green)
        case .crisisResources:
            Image(systemName: "phone.fill")
                .foregroundStyle(.red)
        case .journal:
            Image(systemName: "book.fill")
                .foregroundStyle(.orange)
        }
    }

    private func handleInterventionTap(_ intervention: SuggestedIntervention) {
        // Navigate to appropriate screen based on intervention type
        // This would be wired up to actual navigation
    }

    // MARK: - Feedback Card

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Was this helpful?")
                .font(.headline)

            Text("Your feedback helps us improve pattern detection")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach([AlertFeedback.accuratePrediction, .helpedPrevent, .falseAlarm], id: \.self) { feedback in
                    feedbackButton(feedback)
                }
            }

            if selectedFeedback != nil {
                TextField("Add notes (optional)", text: $feedbackNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                Button {
                    submitFeedback()
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Submit Feedback")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(isSubmitting)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func feedbackButton(_ feedback: AlertFeedback) -> some View {
        Button {
            withAnimation {
                selectedFeedback = feedback
            }
        } label: {
            HStack {
                Image(systemName: feedbackIcon(feedback))
                    .foregroundStyle(feedbackColor(feedback))

                Text(feedback.displayName)
                    .font(.subheadline)

                Spacer()

                if selectedFeedback == feedback {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.purple)
                }
            }
            .padding()
            .background(selectedFeedback == feedback ? Color.purple.opacity(0.1) : Color(.systemGray5))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func feedbackIcon(_ feedback: AlertFeedback) -> String {
        switch feedback {
        case .accuratePrediction: return "checkmark.circle"
        case .helpedPrevent: return "hand.raised.fill"
        case .falseAlarm: return "xmark.circle"
        case .missedPattern: return "eye.slash"
        }
    }

    private func feedbackColor(_ feedback: AlertFeedback) -> Color {
        switch feedback {
        case .accuratePrediction, .helpedPrevent: return .green
        case .falseAlarm: return .orange
        case .missedPattern: return .red
        }
    }

    private var feedbackGivenCard: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            VStack(alignment: .leading) {
                Text("Feedback Received")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let feedback = alert.userFeedback {
                    Text(feedback.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button {
            dismissAlert()
        } label: {
            Text("Dismiss Alert")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray5))
                .foregroundStyle(.primary)
                .cornerRadius(12)
        }
    }

    // MARK: - Actions

    private func submitFeedback() {
        guard let feedback = selectedFeedback else { return }

        isSubmitting = true

        Task {
            do {
                try await engine.submitFeedback(
                    for: alert,
                    feedback: feedback,
                    notes: feedbackNotes.isEmpty ? nil : feedbackNotes
                )
                showingFeedbackSuccess = true
            } catch {
                print("Feedback error: \(error)")
            }

            isSubmitting = false
        }
    }

    private func dismissAlert() {
        Task {
            try? await engine.dismissAlert(alert)
            dismiss()
        }
    }
}

struct PatternAlertView_Previews: PreviewProvider {
    static var previews: some View {
        let authService = SupabaseAuthService()
        let dataService = SupabaseDataService(authService: authService)
        let mockAlert = PatternAlert(
            id: UUID(),
            userId: UUID(),
            signatureId: UUID(),
            detectedAt: Date(),
            activeComponents: [
                ActiveSignal(componentId: UUID(), signal: "isolation", detectedValue: 0.75, threshold: 0.6, daysActive: 2),
                ActiveSignal(componentId: UUID(), signal: "insomnia_wired", detectedValue: 0.82, threshold: 0.6, daysActive: 3)
            ],
            emergenceScore: 0.68,
            severity: .moderate,
            predictedTimeToEvent: 48 * 3600,
            interventionTier: .moderate,
            interventionDelivered: true,
            interventionDeliveredAt: Date(),
            userFeedback: nil,
            feedbackNotes: nil,
            feedbackAt: nil,
            dismissedAt: nil,
            createdAt: Date()
        )
        return NavigationStack {
            PatternAlertView(
                alert: mockAlert,
                engine: StressSignatureEngine(
                    supabaseDataService: dataService,
                    patternLearner: PatternLearner(supabaseDataService: dataService),
                    signalMonitor: SignalMonitor(supabaseDataService: dataService),
                    patternDetector: PatternDetector(supabaseDataService: dataService),
                    interventionService: EarlyInterventionService(supabaseDataService: dataService)
                )
            )
        }
    }
}
