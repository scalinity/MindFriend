import SwiftUI

/// Detail view for a therapist assignment with completion form
struct AssignmentDetailView: View {
    @StateObject private var viewModel: AssignmentDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(assignment: TherapistAssignment, therapyService: TherapyIntegrationService) {
        _viewModel = StateObject(wrappedValue: AssignmentDetailViewModel(
            assignment: assignment,
            therapyService: therapyService
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header section
                headerSection

                // Therapist info
                if let therapist = viewModel.assignment.connection?.therapist {
                    therapistSection(therapist)
                }

                // Assignment details
                detailsSection

                // Completion section
                if viewModel.assignment.status == .completed {
                    completedSection
                } else {
                    completionFormSection
                }
            }
            .padding()
        }
        .navigationTitle("Assignment Details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Success", isPresented: $viewModel.showingSuccess) {
            Button("Done") {
                dismiss()
            }
        } message: {
            Text("Assignment marked as complete")
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Failed to complete assignment")
        }
        .overlay {
            if viewModel.isSubmitting {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)

                        Text("Submitting...")
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.assignment.title)
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if viewModel.assignment.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
            }

            HStack(spacing: 12) {
                // Type badge
                Text(viewModel.assignment.assignmentType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(typeColor.opacity(0.2))
                    .foregroundColor(typeColor)
                    .cornerRadius(8)

                // Frequency badge
                if viewModel.assignment.frequency != .once {
                    Text(viewModel.assignment.frequency.displayName)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }

                // Status indicator
                if viewModel.assignment.isOverdue && viewModel.assignment.status != .completed {
                    Label("Overdue", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    private func therapistSection(_ therapist: TherapistInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assigned By")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(therapist.displayName ?? "Therapist")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let practiceName = therapist.practiceName {
                        Text(practiceName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if therapist.isVerified {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Description
            if let description = viewModel.assignment.description {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text(description)
                        .font(.body)
                }
            }

            // Due date
            if let dueDate = viewModel.assignment.dueDate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Due Date")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.secondary)

                        Text(dueDate.formatted(date: .long, time: .omitted))
                            .font(.body)

                        if viewModel.assignment.isOverdue && viewModel.assignment.status != .completed {
                            Spacer()
                            Text("Overdue")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .cornerRadius(6)
                        }
                    }
                }
            }

            // Assigned date
            VStack(alignment: .leading, spacing: 8) {
                Text("Assigned")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)

                    Text(viewModel.assignment.createdAt.formatted(date: .long, time: .shortened))
                        .font(.body)
                }
            }
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Completion Details")
                .font(.headline)

            if let completedAt = viewModel.assignment.completedAt {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)

                    Text("Completed \(completedAt.formatted(date: .long, time: .shortened))")
                        .font(.subheadline)
                }
            }

            if let notes = viewModel.assignment.clientNotes {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Notes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text(notes)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    private var completionFormSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Complete Assignment")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Notes (Optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                TextEditor(text: $viewModel.completionNotes)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                Text("Share any thoughts, reflections, or challenges you encountered")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button {
                Task {
                    await viewModel.completeAssignment()
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Mark as Complete")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .cornerRadius(12)
            }
            .disabled(viewModel.isSubmitting)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(12)
    }

    private var typeColor: Color {
        switch viewModel.assignment.assignmentType {
        case .exercise:
            return .purple
        case .journalPrompt:
            return .orange
        case .moodTracking:
            return .green
        case .custom:
            return .gray
        }
    }
}

// MARK: - View Model

@MainActor
class AssignmentDetailViewModel: ObservableObject {
    let therapyService: TherapyIntegrationService

    @Published var assignment: TherapistAssignment
    @Published var completionNotes: String = ""
    @Published var isSubmitting = false
    @Published var showingSuccess = false
    @Published var showingError = false
    @Published var errorMessage: String?

    init(assignment: TherapistAssignment, therapyService: TherapyIntegrationService) {
        self.assignment = assignment
        self.therapyService = therapyService

        // Pre-fill notes if already completed
        if let notes = assignment.clientNotes {
            self.completionNotes = notes
        }
    }

    func completeAssignment() async {
        guard assignment.status != .completed else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await therapyService.completeAssignment(
                id: assignment.id,
                notes: completionNotes.isEmpty ? nil : completionNotes
            )
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        AssignmentDetailView(
            assignment: .sample,
            therapyService: TherapyIntegrationService(
                supabase: .init(
                    supabaseURL: URL(string: "https://example.supabase.co")!,
                    supabaseKey: "test"
                )
            )
        )
    }
}
