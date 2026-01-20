import SwiftUI

/// Form for inviting a therapist by email
struct InviteTherapistView: View {
    @StateObject private var viewModel: InviteTherapistViewModel
    @Environment(\.dismiss) private var dismiss

    init(therapyService: TherapyIntegrationService) {
        _viewModel = StateObject(wrappedValue: InviteTherapistViewModel(therapyService: therapyService))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Therapist Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Therapist Information")
                } footer: {
                    Text("Enter your therapist's email address. They'll receive an invitation to connect with you.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        PermissionToggleRow(
                            title: "Mood Check-ins",
                            description: "Daily mood scores and emotions",
                            isOn: .constant(true)
                        )
                        .disabled(true) // Default enabled

                        PermissionToggleRow(
                            title: "Assessment Results",
                            description: "PHQ-9, GAD-7 scores",
                            isOn: .constant(true)
                        )
                        .disabled(true) // Default enabled

                        Text("You can adjust sharing settings after connecting")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Default Sharing Permissions")
                } footer: {
                    Text("Mood and assessment data will be shared by default. You can change these settings anytime.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Your therapist can NEVER see:", systemImage: "lock.shield.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            PrivacyBullet(text: "Your password or login credentials")
                            PrivacyBullet(text: "Private circle posts")
                            PrivacyBullet(text: "Individual chat messages")
                            PrivacyBullet(text: "Any data you don't explicitly share")
                        }
                    }
                } header: {
                    Text("Privacy Protection")
                }
            }
            .navigationTitle("Invite Therapist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Invite") {
                        Task {
                            await viewModel.sendInvite()
                        }
                    }
                    .disabled(!viewModel.isValidEmail || viewModel.isSending)
                }
            }
            .alert("Success", isPresented: $viewModel.showingSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Invitation sent to \(viewModel.email)")
            }
            .alert("Error", isPresented: $viewModel.showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Failed to send invitation")
            }
            .overlay {
                if viewModel.isSending {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)

                            Text("Sending invitation...")
                                .foregroundColor(.white)
                                .font(.subheadline)
                        }
                        .padding(24)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
            }
        }
    }
}

// MARK: - Helper Views

struct PermissionToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

struct PrivacyBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - View Model

@MainActor
class InviteTherapistViewModel: ObservableObject {
    let therapyService: TherapyIntegrationService

    @Published var email = ""
    @Published var isSending = false
    @Published var showingSuccess = false
    @Published var showingError = false
    @Published var errorMessage: String?

    init(therapyService: TherapyIntegrationService) {
        self.therapyService = therapyService
    }

    var isValidEmail: Bool {
        let emailRegex = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func sendInvite() async {
        guard isValidEmail else { return }

        isSending = true
        defer { isSending = false }

        do {
            _ = try await therapyService.inviteTherapist(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Previews

#Preview {
    InviteTherapistView(
        therapyService: TherapyIntegrationService(
            supabase: .init(
                supabaseURL: URL(string: "https://example.supabase.co")!,
                supabaseKey: "test"
            )
        )
    )
}
