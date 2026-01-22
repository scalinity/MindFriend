import SwiftUI

@MainActor
final class CoachSettingsViewModel: ObservableObject {
    @Published var settings: CoachSettings
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingDistortionList = false

    private let coachService: CoachServiceProtocol

    init(coachService: CoachServiceProtocol) {
        self.coachService = coachService
        self.settings = CoachSettings()
    }

    func loadSettings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedSettings = try await coachService.getSettings()
            await MainActor.run {
                self.settings = loadedSettings
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Unable to load coach settings. Check your connection."
            }
        }
    }

    func saveSettings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await coachService.updateSettings(settings)
            await MainActor.run {
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Unable to save coach settings. Please try again."
            }
        }
    }
}

struct CoachSettingsView: View {
    @StateObject private var viewModel: CoachSettingsViewModel
    @Environment(\.dismiss) var dismiss

    init(coachService: CoachServiceProtocol) {
        _viewModel = StateObject(wrappedValue: CoachSettingsViewModel(coachService: coachService))
    }

    var body: some View {
        NavigationStack {
            Form {
                // Enable/Disable section
                Section(header: Text("Coaching Status")) {
                    Toggle("Enable Thinking Coach", isOn: $viewModel.settings.isEnabled)
                        .accessibilityHint("Tap to turn coaching on or off")

                    if viewModel.settings.isEnabled {
                        Text("The coaching feature helps you recognize and reframe thinking patterns in real-time.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Sensitivity Level section
                if viewModel.settings.isEnabled {
                    Section(header: Text("How often to intervene?")) {
                        Picker("Sensitivity Level", selection: $viewModel.settings.sensitivityLevel) {
                            Text("Minimal (rare suggestions)").tag(CoachSettings.SensitivityLevel.minimal)
                            Text("Balanced (default)").tag(CoachSettings.SensitivityLevel.balanced)
                            Text("Frequent (more suggestions)").tag(CoachSettings.SensitivityLevel.frequent)
                        }
                        .pickerStyle(.segmented)

                        Group {
                            switch viewModel.settings.sensitivityLevel {
                            case .minimal:
                                Text("You'll see suggestions only for very clear thinking patterns.")
                            case .balanced:
                                Text("You'll see suggestions for common thinking patterns.")
                            case .frequent:
                                Text("You'll see suggestions for subtle thinking patterns too.")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    // Silent Hours section
                    Section(header: Text("Silent Hours")) {
                        HStack {
                            Text("From:")
                            Spacer()
                            DatePicker("Start time", selection: $viewModel.settings.silentHoursStart, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }

                        HStack {
                            Text("To:")
                            Spacer()
                            DatePicker("End time", selection: $viewModel.settings.silentHoursEnd, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }

                        Text("No coaching suggestions will appear during these hours.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Disabled Distortions section
                    Section(header: Text("Distortions to Ignore")) {
                        NavigationLink(destination: DisabledDistortionsView(settings: $viewModel.settings)) {
                            HStack {
                                Text("Manage excluded patterns")
                                Spacer()
                                if let count = viewModel.settings.disabledDistortions?.count, count > 0 {
                                    Text("\(count) excluded")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    // Show Patterns section
                    Section(header: Text("Learning & Insights")) {
                        Toggle("Show me my thinking patterns", isOn: $viewModel.settings.showPatterns)
                            .accessibilityHint("Enable to see your weekly pattern summary")

                        Text("Track which thinking patterns you encounter most frequently and see trends over time.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Thinking Coach Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await viewModel.saveSettings()
                            dismiss()
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            }, message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            })
            .onAppear {
                Task {
                    await viewModel.loadSettings()
                }
            }
        }
    }
}

// MARK: - Disabled Distortions View

struct DisabledDistortionsView: View {
    @Binding var settings: CoachSettings
    @State private var allDistortions: [CognitiveDistortion] = []
    @State private var isLoading = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            ForEach(allDistortions, id: \.code) { distortion in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(distortion.name)
                            .font(.headline)
                        Text(distortion.shortDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if settings.disabledDistortions?.contains(distortion.code) ?? false {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleDistortion(distortion.code)
                }
            }
        }
        .navigationTitle("Manage Patterns")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadDistortions()
        }
    }

    private func loadDistortions() {
        // In a full implementation, this would fetch from CoachService
        // For now, we'll use mock data
        isLoading = true
        defer { isLoading = false }

        allDistortions = [
            CognitiveDistortion(
                code: "AON",
                name: "All-or-Nothing Thinking",
                shortDescription: "Seeing things in black and white",
                fullDescription: "Viewing situations as completely good or bad with no middle ground.",
                examples: ["If I'm not perfect, I'm a failure"],
                questionsToChallenge: ["What evidence contradicts this?"],
                reframeTemplates: ["Perfection isn't possible. What went well?"],
                severityWeight: 1,
                displayOrder: 1
            ),
            CognitiveDistortion(
                code: "CAT",
                name: "Catastrophizing",
                shortDescription: "Expecting the worst outcome",
                fullDescription: "Assuming the worst will happen with minimal evidence.",
                examples: ["One mistake means everything will fall apart"],
                questionsToChallenge: ["How likely is this really?"],
                reframeTemplates: ["One mistake doesn't determine the outcome"],
                severityWeight: 1,
                displayOrder: 2
            ),
            CognitiveDistortion(
                code: "MIND",
                name: "Mind Reading",
                shortDescription: "Assuming you know what others think",
                fullDescription: "Believing you know what others are thinking without evidence.",
                examples: ["They must think I'm stupid"],
                questionsToChallenge: ["Have they actually said this?"],
                reframeTemplates: ["I don't actually know what they're thinking"],
                severityWeight: 1,
                displayOrder: 3
            ),
        ]
    }

    private func toggleDistortion(_ code: String) {
        if settings.disabledDistortions == nil {
            settings.disabledDistortions = []
        }

        if settings.disabledDistortions!.contains(code) {
            settings.disabledDistortions!.removeAll { $0 == code }
        } else {
            settings.disabledDistortions!.append(code)
        }
    }
}

#Preview {
    CoachSettingsView(coachService: MockCoachService())
}

// MARK: - Mock Service for Preview

class MockCoachService: CoachServiceProtocol {
    func getSettings() async throws -> CoachSettings {
        return CoachSettings(
            isEnabled: true,
            sensitivityLevel: .balanced,
            silentHoursStart: Date(timeIntervalSince1970: 82800), // 11 PM
            silentHoursEnd: Date(timeIntervalSince1970: 21600),   // 6 AM
            disabledDistortions: nil,
            showPatterns: true
        )
    }

    func updateSettings(_ settings: CoachSettings) async throws {
        // Mock implementation
    }

    func recordInteraction(encounterId: UUID?, distortionCode: String, action: CoachInteraction.Action, confidence: Double?) async throws {
        // Mock implementation
    }

    func getMyPatterns() async throws -> PatternAnalytics {
        return PatternAnalytics(totalEncounters: 0, last7Days: 0, last30Days: 0, mostCommon: [], byDistortionType: [])
    }

    func getWeeklySummary() async throws -> WeeklyPatternSummary? {
        return nil
    }

    func getDistortionLibrary() async throws -> [CognitiveDistortionDefinition] {
        return []
    }

    func getDistortion(code: String) async throws -> CognitiveDistortionDefinition? {
        return nil
    }

    func getEncounters(limit: Int) async throws -> [DistortionEncounter] {
        return []
    }
}
