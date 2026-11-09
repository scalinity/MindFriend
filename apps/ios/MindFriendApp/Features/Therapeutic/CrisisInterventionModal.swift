import SwiftUI
import UIKit

/// Safety-critical modal shown when PHQ-9 Question 9 >= 1 (suicidal ideation detected)
/// This modal MUST be shown before allowing the user to continue with the app
struct CrisisInterventionModal: View {
    @Environment(\.dismiss) private var dismiss

    let onAcknowledge: () -> Void
    let onCallHotline: () -> Void
    let onTextCrisisLine: () -> Void

    @State private var hasAcknowledged = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Header
                    headerSection

                    // Message
                    messageSection

                    // Crisis Resources
                    crisisResourcesSection

                    // Acknowledgment
                    acknowledgmentSection

                    Spacer(minLength: SupportTheme.Spacing.xl)
                }
                .padding(SupportTheme.Spacing.m)
            }
            .background(SupportTheme.canvas)
            .supportScreen()
            .navigationTitle("We're Here For You")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!hasAcknowledged)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "heart.fill")
                .font(.system(.largeTitle))
                .foregroundStyle(.red)

            Text("Your Safety Matters")
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding(.top, SupportTheme.Spacing.m)
    }

    // MARK: - Message Section

    private var messageSection: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Text("Based on your responses, we want to make sure you're getting the support you need.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(SupportTheme.textSecondary)

            Text("You don't have to face this alone. There are people who care and want to help.")
                .font(.body)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, SupportTheme.Spacing.m)
    }

    // MARK: - Crisis Resources Section

    private var crisisResourcesSection: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Text("Immediate Support Available 24/7")
                .font(.headline)
                .padding(.top, SupportTheme.Spacing.xs)

            // National Suicide Prevention Lifeline
            Button(action: onCallHotline) {
                HStack {
                    Image(systemName: "phone.fill")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text("988 Suicide & Crisis Lifeline")
                            .font(.headline)
                        Text("Call or text 988")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.surface)
                .foregroundStyle(SupportTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }
            .buttonStyle(.plain)

            // Crisis Text Line
            Button(action: onTextCrisisLine) {
                HStack {
                    Image(systemName: "message.fill")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text("Crisis Text Line")
                            .font(.headline)
                        Text("Text HOME to 741741")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.surface)
                .foregroundStyle(SupportTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }
            .buttonStyle(.plain)

            // International Association for Suicide Prevention
            Link(destination: URL(string: "https://www.iasp.info/resources/Crisis_Centres/")!) {
                HStack {
                    Image(systemName: "globe")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text("International Resources")
                            .font(.headline)
                        Text("Find help in your country")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.surface)
                .foregroundStyle(SupportTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Acknowledgment Section

    private var acknowledgmentSection: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Divider()
                .padding(.vertical, SupportTheme.Spacing.xs)

            Text("Please acknowledge that you've seen this information before continuing.")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: {
                hasAcknowledged = true
                onAcknowledge()
                dismiss()
            }) {
                Text("I Understand")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(SupportTheme.Spacing.m)
                    .background(SupportTheme.accent)
                    .foregroundStyle(SupportTheme.onAccent)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }

            Text("This doesn't replace professional help. If you're in immediate danger, please call emergency services (911).")
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, SupportTheme.Spacing.xs)
    }
}

// MARK: - Crisis Intervention Coordinator

/// Coordinates crisis intervention actions and logging
@MainActor
final class CrisisInterventionCoordinator: ObservableObject {
    @Published var showCrisisModal = false
    @Published var crisisEventId: String?

    private var onDismiss: (() -> Void)?

    func triggerCrisisIntervention(crisisEventId: String?, onDismiss: @escaping () -> Void) {
        self.crisisEventId = crisisEventId
        self.onDismiss = onDismiss
        self.showCrisisModal = true
    }

    func callHotline() {
        // Open phone dialer with 988
        if let url = URL(string: "tel://988") {
            UIApplication.shared.open(url)
        }
    }

    func textCrisisLine() {
        // Open SMS to 741741 (Crisis Text Line)
        if let url = URL(string: "sms:741741?body=HOME") {
            UIApplication.shared.open(url)
        }
    }

    func handleAcknowledgment() {
        showCrisisModal = false
        onDismiss?()
    }
}

// MARK: - View Modifier for Crisis Intervention

struct CrisisInterventionModifier: ViewModifier {
    @ObservedObject var coordinator: CrisisInterventionCoordinator

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $coordinator.showCrisisModal) {
                CrisisInterventionModal(
                    onAcknowledge: coordinator.handleAcknowledgment,
                    onCallHotline: coordinator.callHotline,
                    onTextCrisisLine: coordinator.textCrisisLine
                )
            }
    }
}

extension View {
    func crisisIntervention(coordinator: CrisisInterventionCoordinator) -> some View {
        modifier(CrisisInterventionModifier(coordinator: coordinator))
    }
}

#Preview {
    CrisisInterventionModal(
        onAcknowledge: {},
        onCallHotline: {},
        onTextCrisisLine: {}
    )
}
