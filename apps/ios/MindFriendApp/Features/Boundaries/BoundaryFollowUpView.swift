//
//  BoundaryFollowUpView.swift
//  MindFriendApp
//
//  View for recording follow-up check-in outcomes
//

import SwiftUI

struct BoundaryFollowUpView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BoundaryFollowUpViewModel

    let followUpId: UUID

    init(service: BoundaryPlannerService, followUpId: UUID) {
        self.followUpId = followUpId
        _viewModel = StateObject(wrappedValue: BoundaryFollowUpViewModel(service: service, followUpId: followUpId))
    }

    var body: some View {
        NavigationStack {
            Form {
                // Outcome Section
                Section {
                    Picker("followup.outcome_label", selection: $viewModel.selectedOutcome) {
                        ForEach([
                            FollowUpOutcome.successful,
                            .partiallySuccessful,
                            .challenged,
                            .ignored
                        ], id: \.self) { outcome in
                            Label {
                                Text(outcome.displayName)
                            } icon: {
                                Image(systemName: outcome.icon)
                                    .foregroundStyle(outcome.color)
                            }
                            .tag(outcome)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("followup.outcome_header")
                } footer: {
                    Text(viewModel.selectedOutcome.description)
                        .font(.caption)
                }

                // Notes Section
                Section {
                    TextEditor(text: $viewModel.notes)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if viewModel.notes.isEmpty {
                                Text("followup.notes_placeholder")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("followup.notes_header")
                } footer: {
                    Text("followup.notes_footer")
                        .font(.caption)
                }

                // Reflection Section
                Section {
                    TextEditor(text: $viewModel.reflection)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if viewModel.reflection.isEmpty {
                                Text("followup.reflection_placeholder")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("followup.reflection_header")
                } footer: {
                    Text("followup.reflection_footer")
                        .font(.caption)
                }

                // Next Action Section
                Section {
                    TextEditor(text: $viewModel.nextAction)
                        .frame(minHeight: 80)
                        .overlay(alignment: .topLeading) {
                            if viewModel.nextAction.isEmpty {
                                Text("followup.next_action_placeholder")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("followup.next_action_header")
                } footer: {
                    Text("followup.next_action_footer")
                        .font(.caption)
                }

                // Submit Button
                Section {
                    Button {
                        Task {
                            await viewModel.recordOutcome()
                            if viewModel.recordedOutcome != nil {
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isRecording {
                            HStack {
                                ProgressView()
                                Text("followup.recording")
                            }
                        } else {
                            Text("followup.submit")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.isRecording)
                }
            }
            .navigationTitle("followup.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                }
            }
            .alert("followup.success_title", isPresented: $viewModel.showSuccess) {
                Button("common.ok") {
                    dismiss()
                }
            } message: {
                if let outcome = viewModel.recordedOutcome {
                    VStack(spacing: 12) {
                        if let encouragement = outcome.encouragement {
                            Text(encouragement)
                        }
                        
                        if !outcome.suggestions.isEmpty {
                            Text("followup.suggestions_header")
                                .fontWeight(.semibold)
                            
                            ForEach(outcome.suggestions, id: \.self) { suggestion in
                                Text("• \(suggestion)")
                            }
                        }
                    }
                }
            }
            .alert("followup.error_title", isPresented: $viewModel.showError) {
                Button("common.ok") {
                    viewModel.showError = false
                }
            } message: {
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class BoundaryFollowUpViewModel: ObservableObject {
    let service: BoundaryPlannerService
    let followUpId: UUID

    @Published var selectedOutcome: FollowUpOutcome = .successful
    @Published var notes = ""
    @Published var reflection = ""
    @Published var nextAction = ""

    @Published var isRecording = false
    @Published var recordedOutcome: RecordOutcomeResponse?
    @Published var showSuccess = false
    @Published var error: Error?
    @Published var showError = false

    init(service: BoundaryPlannerService, followUpId: UUID) {
        self.service = service
        self.followUpId = followUpId
    }

    func recordOutcome() async {
        isRecording = true
        error = nil

        do {
            recordedOutcome = try await service.recordOutcome(
                followUpId: followUpId,
                outcome: selectedOutcome,
                notes: notes.isEmpty ? nil : notes,
                reflection: reflection.isEmpty ? nil : reflection,
                nextAction: nextAction.isEmpty ? nil : nextAction
            )
            showSuccess = true
        } catch {
            self.error = error
            self.showError = true
        }

        isRecording = false
    }
}

// MARK: - Follow-Up Outcome Extensions

extension FollowUpOutcome {
    var displayName: LocalizedStringKey {
        switch self {
        case .successful:
            return "followup.outcome_successful"
        case .partiallySuccessful:
            return "followup.outcome_partially_successful"
        case .challenged:
            return "followup.outcome_challenged"
        case .ignored:
            return "followup.outcome_ignored"
        }
    }

    var description: LocalizedStringKey {
        switch self {
        case .successful:
            return "followup.outcome_successful_description"
        case .partiallySuccessful:
            return "followup.outcome_partially_successful_description"
        case .challenged:
            return "followup.outcome_challenged_description"
        case .ignored:
            return "followup.outcome_ignored_description"
        }
    }

    var icon: String {
        switch self {
        case .successful:
            return "checkmark.circle.fill"
        case .partiallySuccessful:
            return "checkmark.circle"
        case .challenged:
            return "exclamationmark.triangle.fill"
        case .ignored:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .successful:
            return .green
        case .partiallySuccessful:
            return .orange
        case .challenged:
            return .yellow
        case .ignored:
            return .red
        }
    }
}

// MARK: - Previews

#Preview {
    BoundaryFollowUpView(
        service: BoundaryPlannerService(supabase: .mock),
        followUpId: UUID()
    )
}
