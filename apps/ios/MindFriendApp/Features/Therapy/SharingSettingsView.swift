import SwiftUI

/// View for managing granular data sharing permissions with a therapist
struct SharingSettingsView: View {
    @StateObject private var viewModel: SharingSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    init(connection: TherapyConnection, therapyService: TherapyIntegrationService) {
        _viewModel = StateObject(wrappedValue: SharingSettingsViewModel(
            connection: connection,
            therapyService: therapyService
        ))
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    PermissionToggle(
                        title: "Mood Check-ins",
                        description: "Your daily mood scores and emotions",
                        isOn: $viewModel.shareMood,
                        icon: "face.smiling"
                    )

                    PermissionToggle(
                        title: "Assessment Results",
                        description: "PHQ-9, GAD-7 scores and severity",
                        isOn: $viewModel.shareAssessments,
                        icon: "chart.line.uptrend.xyaxis"
                    )

                    PermissionToggle(
                        title: "Journal Entries",
                        description: "Your written reflections and notes",
                        isOn: $viewModel.shareJournal,
                        icon: "book.pages"
                    )

                    PermissionToggle(
                        title: "Exercise Activity",
                        description: "Completed exercises and ratings",
                        isOn: $viewModel.shareExercises,
                        icon: "figure.mind.and.body"
                    )
                }
            } header: {
                Text("What can your therapist see?")
            } footer: {
                Text("Changes take effect immediately. You can update these settings anytime.")
            }

            Section {
                PermissionToggle(
                    title: "Crisis Alerts",
                    description: "Alert therapist if you access crisis resources",
                    isOn: $viewModel.crisisAlertsEnabled,
                    icon: "exclamationmark.triangle.fill",
                    tintColor: .red
                )
            } header: {
                Text("Safety Features")
            } footer: {
                Text("Your therapist will be notified immediately if you access crisis support. This helps them provide timely assistance.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Your therapist can NEVER see:", systemImage: "lock.shield.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 4) {
                        BulletPoint(text: "Your password or login")
                        BulletPoint(text: "Private circle posts")
                        BulletPoint(text: "Individual chat messages")
                    }
                }
            } header: {
                Text("Privacy Protection")
            }
        }
        .navigationTitle("Sharing Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await viewModel.saveSettings()
                    }
                }
                .disabled(!viewModel.hasChanges || viewModel.isSaving)
            }
        }
        .overlay {
            if viewModel.isSaving {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
            }
        }
        .alert("Settings Saved", isPresented: $viewModel.showingSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your sharing preferences have been updated.")
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Failed to save settings")
        }
    }
}

// MARK: - Helper Views

struct PermissionToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    let icon: String
    var tintColor: Color = .accentColor

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(tintColor)
                .font(.title3)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
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

fileprivate struct BulletPoint: View {
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
class SharingSettingsViewModel: ObservableObject {
    let connection: TherapyConnection
    let therapyService: TherapyIntegrationService

    @Published var shareMood: Bool
    @Published var shareJournal: Bool
    @Published var shareAssessments: Bool
    @Published var shareExercises: Bool
    @Published var crisisAlertsEnabled: Bool

    @Published var isSaving = false
    @Published var showingSuccess = false
    @Published var showingError = false
    @Published var errorMessage: String?

    private let originalSettings: (Bool, Bool, Bool, Bool, Bool)

    init(connection: TherapyConnection, therapyService: TherapyIntegrationService) {
        self.connection = connection
        self.therapyService = therapyService

        // Initialize with current values
        self.shareMood = connection.shareMood
        self.shareJournal = connection.shareJournal
        self.shareAssessments = connection.shareAssessments
        self.shareExercises = connection.shareExercises
        self.crisisAlertsEnabled = connection.crisisAlertsEnabled

        // Store original values for comparison
        self.originalSettings = (
            connection.shareMood,
            connection.shareJournal,
            connection.shareAssessments,
            connection.shareExercises,
            connection.crisisAlertsEnabled
        )
    }

    var hasChanges: Bool {
        shareMood != originalSettings.0 ||
        shareJournal != originalSettings.1 ||
        shareAssessments != originalSettings.2 ||
        shareExercises != originalSettings.3 ||
        crisisAlertsEnabled != originalSettings.4
    }

    func saveSettings() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await therapyService.updateSharingSettings(
                connectionId: connection.id,
                shareMood: shareMood,
                shareJournal: shareJournal,
                shareAssessments: shareAssessments,
                shareExercises: shareExercises,
                crisisAlerts: crisisAlertsEnabled
            )
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
