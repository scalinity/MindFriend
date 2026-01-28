import SwiftUI

/// View for generating a new personalized exercise
struct GenerateExerciseView: View {
    @StateObject private var viewModel: GenerateExerciseViewModel
    @Environment(\.dismiss) private var dismiss
    
    let container: DependencyContainer

    init(container: DependencyContainer) {
        self.container = container
        _viewModel = StateObject(wrappedValue: GenerateExerciseViewModel(
            dataService: container.supabaseDataService,
            container: container
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)

                        Text("Generate Exercise")
                            .font(.title2.bold())

                        Text("Create a personalized exercise just for you")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // Exercise type selector
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Exercise Type")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach([GeneratedContentType.breathing, .meditation, .grounding, .journaling]) { type in
                                ExerciseTypeCard(
                                    type: type,
                                    isSelected: viewModel.selectedType == type,
                                    action: { viewModel.selectedType = type }
                                )
                            }
                        }
                    }

                    // Duration picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Duration")
                            .font(.headline)

                        Picker("Duration", selection: $viewModel.duration) {
                            ForEach(viewModel.durationOptions, id: \.self) { seconds in
                                Text(formatDuration(seconds)).tag(seconds)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Optional: Current mood input
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Include my current mood", isOn: $viewModel.includeMood)
                            .font(.headline)

                        if viewModel.includeMood {
                            VStack(spacing: 8) {
                                Text("How are you feeling?")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Picker("Mood", selection: $viewModel.mood) {
                                    ForEach(MoodOption.allCases) { mood in
                                        Text(mood.displayName).tag(mood)
                                    }
                                }
                                .pickerStyle(.menu)

                                HStack {
                                    Text("Energy Level: \(viewModel.energyLevel)")
                                        .font(.subheadline)
                                    Spacer()
                                    Stepper("", value: $viewModel.energyLevel, in: 1...10)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }

                    // Generate button
                    Button(action: { Task { await viewModel.generateExercise() } }) {
                        if viewModel.isGenerating {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                Text("Generating...")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.8))
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        } else {
                            Text("Generate Exercise for Me")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                    }
                    .disabled(viewModel.isGenerating || !viewModel.canGenerate)
                    .padding(.top, 8)

                    // Quota status
                    if let quota = viewModel.quotaStatus {
                        HStack {
                            Image(systemName: quota.isPremium ? "crown.fill" : "sparkles")
                                .foregroundColor(quota.isPremium ? .yellow : .blue)

                            Text(quota.isPremium
                                ? "Premium: Unlimited generations"
                                : "\(quota.remaining) of \(quota.limit) generations remaining today")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Create Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Generation Failed", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .fullScreenCover(item: $viewModel.generatedContent) { content in
                GeneratedExercisePlayerView(content: content, container: container)
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return "\(minutes) min"
    }
}

// MARK: - Exercise Type Card

struct ExerciseTypeCard: View {
    let type: GeneratedContentType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 32))
                    .foregroundColor(isSelected ? .white : .blue)

                Text(type.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(isSelected ? .white : .primary)

                Text(type.description)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
        }
    }
}

// MARK: - Mood Options

enum MoodOption: String, CaseIterable, Identifiable {
    case calm
    case anxious
    case sad
    case stressed
    case tired
    case energetic
    case angry
    case neutral

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - ViewModel

@MainActor
class GenerateExerciseViewModel: ObservableObject {
    @Published var selectedType: GeneratedContentType = .breathing
    @Published var duration: Int = 300
    @Published var includeMood = false
    @Published var mood: MoodOption = .neutral
    @Published var energyLevel: Int = 5

    @Published var isGenerating = false
    @Published var generatedContent: GeneratedContent?
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var quotaStatus: QuotaStatus?

    let dataService: SupabaseDataService
    let container: DependencyContainer

    var durationOptions: [Int] {
        switch selectedType {
        case .breathing: return [180, 300, 600] // 3, 5, 10 min
        case .meditation: return [300, 600, 900, 1200] // 5, 10, 15, 20 min
        case .grounding: return [180, 300, 420] // 3, 5, 7 min
        case .journaling: return [300, 600, 900] // 5, 10, 15 min
        default: return [300, 600, 900]
        }
    }

    var canGenerate: Bool {
        !isGenerating && (quotaStatus?.remaining ?? 0 > 0 || quotaStatus?.isPremium == true)
    }

    init(dataService: SupabaseDataService, container: DependencyContainer) {
        self.dataService = dataService
        self.container = container
        Task { await loadQuotaStatus() }
    }

    func generateExercise() async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            // Prepare request for Edge Function
            struct GenerateContentRequest: Encodable {
                let contentType: String
                let params: GenerateContentParams
            }
            
            struct GenerateContentParams: Encodable {
                let duration: Int
                let theme: String?
                let customPrompt: String?
            }
            
            // Response matches Edge Function generate-content response
            struct GenerateContentResponse: Decodable {
                let contentId: String
                let status: String
                let title: String
                let quotaUsed: Int
                let quotaLimit: Int
                let disclaimer: String
                // Optional fields
                let textContent: String?
                let audioUrl: String?
                let duration: Int?
                let qualityScore: Int?
                let triggerWarnings: [String]?
            }
            
            let request = GenerateContentRequest(
                contentType: selectedType.rawValue,
                params: GenerateContentParams(
                    duration: duration,
                    theme: includeMood ? mood.rawValue : nil,
                    customPrompt: nil
                )
            )

            let response: GenerateContentResponse = try await container.supabase.functions.invoke(
                "generate-content",
                options: .init(body: request)
            )

            // Fetch the generated content
            if let content = try await dataService.getGeneratedContent(id: response.contentId) {
                generatedContent = content
                // Update quota from response
                let remaining = max(0, response.quotaLimit - response.quotaUsed)
                quotaStatus?.remaining = remaining
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func loadQuotaStatus() async {
        do {
            struct QuotaResponse: Decodable {
                let used: Int
                let limit: Int
                let remaining: Int
                let isPremium: Bool
            }

            let response: QuotaResponse = try await container.supabase.functions.invoke(
                "get-exercise-quota",
                options: .init()
            )

            await MainActor.run {
                quotaStatus = QuotaStatus(
                    used: response.used,
                    limit: response.limit,
                    remaining: response.remaining,
                    isPremium: response.isPremium
                )
            }
        } catch {
            // Fall back to default quota on error
            await MainActor.run {
                quotaStatus = QuotaStatus(used: 0, limit: 3, remaining: 3, isPremium: false)
            }
        }
    }
}

struct QuotaStatus {
    var used: Int
    let limit: Int
    var remaining: Int
    let isPremium: Bool
}
