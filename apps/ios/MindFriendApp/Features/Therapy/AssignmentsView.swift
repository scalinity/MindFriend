import SwiftUI

/// View displaying therapist-assigned homework and exercises
struct AssignmentsView: View {
    @StateObject private var viewModel: AssignmentsViewModel
    @Environment(\.dismiss) private var dismiss

    init(therapyService: TherapyIntegrationService, connectionId: UUID? = nil) {
        _viewModel = StateObject(wrappedValue: AssignmentsViewModel(
            therapyService: therapyService,
            connectionId: connectionId
        ))
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView("Loading assignments...")
            } else if viewModel.assignments.isEmpty {
                emptyStateView
            } else {
                assignmentsList
            }
        }
        .navigationTitle("Assignments")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !viewModel.connections.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            viewModel.selectedConnectionId = nil
                        } label: {
                            HStack {
                                Text("All Therapists")
                                if viewModel.selectedConnectionId == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        ForEach(viewModel.connections) { connection in
                            Button {
                                viewModel.selectedConnectionId = connection.id
                            } label: {
                                HStack {
                                    Text(connection.therapist?.displayName ?? "Therapist")
                                    if viewModel.selectedConnectionId == connection.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .task {
            await viewModel.loadData()
        }
        .refreshable {
            await viewModel.loadData()
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Assignments")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your therapist hasn't assigned any homework yet.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var assignmentsList: some View {
        List {
            // Overdue section
            if !viewModel.overdueAssignments.isEmpty {
                Section {
                    ForEach(viewModel.overdueAssignments) { assignment in
                        NavigationLink {
                            AssignmentDetailView(
                                assignment: assignment,
                                therapyService: viewModel.therapyService
                            )
                        } label: {
                            AssignmentRow(assignment: assignment)
                        }
                    }
                } header: {
                    Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
            }

            // Pending section
            if !viewModel.pendingAssignments.isEmpty {
                Section("Active Assignments") {
                    ForEach(viewModel.pendingAssignments) { assignment in
                        NavigationLink {
                            AssignmentDetailView(
                                assignment: assignment,
                                therapyService: viewModel.therapyService
                            )
                        } label: {
                            AssignmentRow(assignment: assignment)
                        }
                    }
                }
            }

            // Completed section
            if !viewModel.completedAssignments.isEmpty {
                Section("Completed") {
                    ForEach(viewModel.completedAssignments) { assignment in
                        NavigationLink {
                            AssignmentDetailView(
                                assignment: assignment,
                                therapyService: viewModel.therapyService
                            )
                        } label: {
                            AssignmentRow(assignment: assignment)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Assignment Row

struct AssignmentRow: View {
    let assignment: TherapistAssignment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(assignment.title)
                        .font(.headline)
                        .foregroundColor(assignment.status == .completed ? .secondary : .primary)

                    if let therapist = assignment.connection?.therapist {
                        Text("Assigned by \(therapist.displayName ?? "")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let description = assignment.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if assignment.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }

            // Assignment details
            HStack(spacing: 12) {
                // Type badge
                Text(assignment.assignmentType.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(typeColor.opacity(0.2))
                    .foregroundColor(typeColor)
                    .cornerRadius(6)

                // Frequency badge
                if assignment.frequency != .once {
                    Text(assignment.frequency.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                }

                Spacer()

                // Due date
                if let dueDate = assignment.dueDate {
                    if assignment.isOverdue && assignment.status != .completed {
                        Label(
                            dueDate.formatted(date: .abbreviated, time: .omitted),
                            systemImage: "clock.badge.exclamationmark"
                        )
                        .font(.caption)
                        .foregroundColor(.red)
                    } else {
                        Label(
                            dueDate.formatted(date: .abbreviated, time: .omitted),
                            systemImage: "calendar"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var typeColor: Color {
        switch assignment.assignmentType {
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
class AssignmentsViewModel: ObservableObject {
    let therapyService: TherapyIntegrationService

    @Published var assignments: [TherapistAssignment] = []
    @Published var connections: [TherapyConnection] = []
    @Published var selectedConnectionId: UUID?
    @Published var isLoading = false
    @Published var showingError = false
    @Published var errorMessage: String?

    init(therapyService: TherapyIntegrationService, connectionId: UUID?) {
        self.therapyService = therapyService
        self.selectedConnectionId = connectionId
    }

    var filteredAssignments: [TherapistAssignment] {
        guard let connectionId = selectedConnectionId else {
            return assignments
        }
        return assignments.filter { $0.connectionId == connectionId }
    }

    var overdueAssignments: [TherapistAssignment] {
        filteredAssignments.filter { $0.isOverdue && $0.status != .completed }
    }

    var pendingAssignments: [TherapistAssignment] {
        filteredAssignments.filter { $0.status == .assigned && !$0.isOverdue }
    }

    var completedAssignments: [TherapistAssignment] {
        filteredAssignments.filter { $0.status == .completed }
    }

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load connections for filter menu
            connections = try await therapyService.getConnections()
                .filter { $0.status == .active }

            // Load assignments
            assignments = try await therapyService.getAssignments(
                connectionId: selectedConnectionId
            )
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        AssignmentsView(
            therapyService: TherapyIntegrationService(
                supabase: .init(
                    supabaseURL: URL(string: "https://example.supabase.co")!,
                    supabaseKey: "test"
                )
            )
        )
    }
}
