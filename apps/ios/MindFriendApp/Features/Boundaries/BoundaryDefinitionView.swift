//
//  BoundaryDefinitionView.swift
//  MindFriendApp
//
//  Form for defining a boundary statement with type, statement, and why it matters
//

import SwiftUI

struct BoundaryDefinitionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BoundaryDefinitionViewModel

    let assessmentId: UUID?

    init(service: BoundaryPlannerService, assessmentId: UUID? = nil) {
        self.assessmentId = assessmentId
        _viewModel = StateObject(wrappedValue: BoundaryDefinitionViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Form {
                // Boundary Type Section
                Section {
                    Picker("definition.type_label", selection: $viewModel.selectedType) {
                        ForEach(BoundaryType.allCases) { type in
                            Label {
                                Text(type.displayName)
                            } icon: {
                                Image(systemName: type.icon)
                                    .foregroundStyle(type.colorScheme)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("definition.type_header")
                } footer: {
                    Text(viewModel.selectedType.description)
                        .font(.caption)
                }

                // Statement Section
                Section {
                    TextEditor(text: $viewModel.statement)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if viewModel.statement.isEmpty {
                                Text("definition.statement_placeholder")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }

                    Text("\(viewModel.statement.count)/500")
                        .font(.caption)
                        .foregroundStyle(viewModel.statement.count > 500 ? .red : .secondary)
                } header: {
                    Text("definition.statement_header")
                } footer: {
                    Text("definition.statement_footer")
                        .font(.caption)
                }

                // Why It Matters Section
                Section {
                    TextEditor(text: $viewModel.whyMatters)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if viewModel.whyMatters.isEmpty {
                                Text("definition.why_matters_placeholder")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }

                    Text("\(viewModel.whyMatters.count)/500")
                        .font(.caption)
                        .foregroundStyle(viewModel.whyMatters.count > 500 ? .red : .secondary)
                } header: {
                    Text("definition.why_matters_header")
                } footer: {
                    Text("definition.why_matters_footer")
                        .font(.caption)
                }

                // Stakeholder (Optional)
                Section {
                    TextField("definition.stakeholder_placeholder", text: $viewModel.stakeholder)
                } header: {
                    Text("definition.stakeholder_header")
                } footer: {
                    Text("definition.stakeholder_footer")
                        .font(.caption)
                }

                // Templates Section
                if !viewModel.templates.isEmpty {
                    Section {
                        ForEach(viewModel.templates) { template in
                            Button {
                                viewModel.applyTemplate(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.toneGuidance)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text(template.templateText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    } header: {
                        Text("definition.templates_header")
                    }
                }
            }
            .navigationTitle("definition.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await viewModel.generateBoundary(assessmentId: assessmentId)
                            if viewModel.generatedBoundary != nil {
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isGenerating {
                            ProgressView()
                        } else {
                            Text("definition.generate")
                        }
                    }
                    .disabled(!viewModel.isValid || viewModel.isGenerating)
                }
            }
            .task {
                await viewModel.loadTemplates()
            }
            .alert("definition.error_title", isPresented: $viewModel.showError) {
                Button("Retry") {
                    Task {
                        await viewModel.loadTemplates()
                    }
                }
                Button("Cancel", role: .cancel) {
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
final class BoundaryDefinitionViewModel: ObservableObject {
    let service: BoundaryPlannerService

    @Published var selectedType: BoundaryType = .time
    @Published var statement = ""
    @Published var whyMatters = ""
    @Published var stakeholder = ""

    @Published var templates: [BoundaryScriptTemplate] = []
    @Published var isLoadingTemplates = false
    @Published var isGenerating = false
    @Published var error: Error?
    @Published var showError = false

    @Published var generatedBoundary: GenerateBoundaryResponse?

    var isValid: Bool {
        statement.count >= 10 && statement.count <= 500 &&
        whyMatters.count >= 10 && whyMatters.count <= 500
    }

    init(service: BoundaryPlannerService) {
        self.service = service
    }

    func loadTemplates() {
        isLoadingTemplates = true
        Task {
            do {
                let service = DependencyContainer.shared.boundaryPlannerService
                templates = try await service.getTemplates(
                    boundaryType: selectedType.rawValue,
                    relationshipType: stakeholder
                )
                isLoadingTemplates = false
            } catch {
                self.error = error as? BoundaryPlannerError ?? .unknown
                isLoadingTemplates = false
            }
        }
    }

    func applyTemplate(_ template: BoundaryScriptTemplate) {
        statement = template.templateText
        whyMatters = template.exampleContext ?? "This boundary helps me maintain healthy relationships and honor my needs."
    }

    func generateBoundary(assessmentId: UUID?) async {
        isGenerating = true
        error = nil

        do {
            generatedBoundary = try await service.generateBoundary(
                assessmentId: assessmentId,
                boundaryType: selectedType,
                statement: statement,
                whyMatters: whyMatters,
                stakeholder: stakeholder.isEmpty ? nil : stakeholder
            )
        } catch {
            self.error = error
            self.showError = true
        }

        isGenerating = false
    }
}

// MARK: - Boundary Type Extensions

extension BoundaryType {
    var description: LocalizedStringKey {
        switch self {
        case .time:
            return "definition.type_time_description"
        case .emotional:
            return "definition.type_emotional_description"
        case .digital:
            return "definition.type_digital_description"
        case .physical:
            return "definition.type_physical_description"
        case .financial:
            return "definition.type_financial_description"
        }
    }
}

// MARK: - Previews

#Preview {
    BoundaryDefinitionView(service: BoundaryPlannerService(supabase: .mock))
}
