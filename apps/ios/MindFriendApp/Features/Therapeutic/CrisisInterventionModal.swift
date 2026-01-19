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
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Message
                    messageSection

                    // Crisis Resources
                    crisisResourcesSection

                    // Acknowledgment
                    acknowledgmentSection

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .navigationTitle("We're Here For You")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!hasAcknowledged)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Your Safety Matters")
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding(.top, 20)
    }

    // MARK: - Message Section

    private var messageSection: some View {
        VStack(spacing: 16) {
            Text("Based on your responses, we want to make sure you're getting the support you need.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("You don't have to face this alone. There are people who care and want to help.")
                .font(.body)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    // MARK: - Crisis Resources Section

    private var crisisResourcesSection: some View {
        VStack(spacing: 16) {
            Text("Immediate Support Available 24/7")
                .font(.headline)
                .padding(.top, 8)

            // National Suicide Prevention Lifeline
            Button(action: onCallHotline) {
                HStack {
                    Image(systemName: "phone.fill")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("988 Suicide & Crisis Lifeline")
                            .font(.headline)
                        Text("Call or text 988")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            // Crisis Text Line
            Button(action: onTextCrisisLine) {
                HStack {
                    Image(systemName: "message.fill")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Crisis Text Line")
                            .font(.headline)
                        Text("Text HOME to 741741")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            // International Association for Suicide Prevention
            Link(destination: URL(string: "https://www.iasp.info/resources/Crisis_Centres/")!) {
                HStack {
                    Image(systemName: "globe")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("International Resources")
                            .font(.headline)
                        Text("Find help in your country")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .foregroundStyle(.purple)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Acknowledgment Section

    private var acknowledgmentSection: some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.vertical, 8)

            Text("Please acknowledge that you've seen this information before continuing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                hasAcknowledged = true
                onAcknowledge()
                dismiss()
            }) {
                Text("I Understand")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text("This doesn't replace professional help. If you're in immediate danger, please call emergency services (911).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
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
