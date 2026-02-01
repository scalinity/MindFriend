//
//  ScriptGeneratorView.swift
//  MindFriendApp
//
//  View for generating and displaying boundary scripts
//

import SwiftUI

struct ScriptGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ScriptGeneratorViewModel

    let boundaryId: UUID

    init(service: BoundaryPlannerService, boundaryId: UUID) {
        self.boundaryId = boundaryId
        _viewModel = StateObject(wrappedValue: ScriptGeneratorViewModel(service: service, boundaryId: boundaryId))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if let scripts = viewModel.scripts {
                    scriptsContent(scripts)
                } else {
                    generatorForm
                }
            }
            .navigationTitle("scripts.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                }

                if viewModel.scripts != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("scripts.practice") {
                            viewModel.navigateToPractice()
                        }
                    }
                }
            }
            .alert("scripts.error_title", isPresented: $viewModel.showError) {
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

    // MARK: - Generator Form

    private var generatorForm: some View {
        Form {
            Section {
                Picker("scripts.relationship_type_label", selection: $viewModel.selectedRelationshipType) {
                    ForEach(viewModel.relationshipTypes, id: \.self) { type in
                        Text(type)
                    }
                }
            } header: {
                Text("scripts.relationship_type_header")
            } footer: {
                Text("scripts.relationship_type_footer")
                    .font(.caption)
            }

            Section {
                ForEach(ScriptVariation.allCases, id: \.self) { variation in
                    Toggle(isOn: Binding(
                        get: { viewModel.selectedVariations.contains(variation) },
                        set: { isOn in
                            if isOn {
                                viewModel.selectedVariations.insert(variation)
                            } else {
                                viewModel.selectedVariations.remove(variation)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(variation.displayName)
                                .font(.body)

                            Text(variation.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("scripts.variations_header")
            } footer: {
                Text("scripts.variations_footer")
                    .font(.caption)
            }

            Section {
                Button {
                    Task {
                        await viewModel.generateScripts()
                    }
                } label: {
                    if viewModel.isGenerating {
                        HStack {
                            ProgressView()
                            Text("scripts.generating")
                        }
                    } else {
                        Text("scripts.generate")
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(viewModel.selectedVariations.isEmpty || viewModel.isGenerating)
            }
        }
    }

    // MARK: - Scripts Content

    @ViewBuilder
    private func scriptsContent(_ scripts: GenerateScriptsResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Script Count
                Text("scripts.generated_count \(scripts.scripts.count)")
                    .font(.headline)
                    .padding(.horizontal)

                // Scripts List
                ForEach(scripts.scripts) { script in
                    ScriptCard(script: script)
                        .padding(.horizontal)
                }

                // Practice Prompt
                if !scripts.practicePrompts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("scripts.practice_prompts_header")
                            .font(.headline)

                        ForEach(scripts.practicePrompts, id: \.self) { prompt in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.title3)

                                Text(prompt)
                                    .font(.body)
                            }
                        }
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Script Card

struct ScriptCard: View {
    let script: ScriptResponse
    @State var isCopied = false
    
    var variation: ScriptVariation {
        script.variation
    }
    
    var variationColor: Color {
        switch variation {
        case .direct: return .red
        case .gentle: return .green
        case .assertive: return .orange
        case .collaborative: return .blue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(variation.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(variationColor)
                    .cornerRadius(6)
                
                Spacer()
                
                Button(action: { copyScript() }) {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundColor(variationColor)
                }
            }
            
            Text(script.script)
                .font(.body)
                .lineLimit(nil)
            
            if !script.tips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    ForEach(script.tips, id: \.self) { tip in
                        Label(tip, systemImage: "lightbulb.fill")
                            .font(.caption)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private func copyScript() {
        UIPasteboard.general.string = script.script
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
}

// MARK: - View Model

@MainActor
final class ScriptGeneratorViewModel: ObservableObject {
    let service: BoundaryPlannerService
    let boundaryId: UUID

    @Published var selectedRelationshipType = "partner"
    @Published var selectedVariations: Set<ScriptVariation> = [.direct, .gentle]

    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var scripts: GenerateScriptsResponse?
    @Published var error: Error?
    @Published var showError = false

    let relationshipTypes = ["partner", "family", "friend", "coworker", "other"]

    init(service: BoundaryPlannerService, boundaryId: UUID) {
        self.service = service
        self.boundaryId = boundaryId
    }

    func generateScripts() async {
        isGenerating = true
        error = nil

        do {
            scripts = try await service.generateScripts(
                boundaryId: boundaryId,
                relationshipType: selectedRelationshipType,
                variations: Array(selectedVariations)
            )
        } catch {
            self.error = error
            self.showError = true
        }

        isGenerating = false
    }

    func navigateToPractice() {
        // TODO: Implement navigation to practice view
        // showPracticeView = true
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    ScriptGeneratorView(
        service: BoundaryPlannerService(supabase: .mock),
        boundaryId: UUID()
    )
}
#endif
