import SwiftUI

/// View for requesting new AI-generated content
struct ContentRequestView: View {
    @StateObject private var viewModel: ContentRequestViewModel
    @Environment(\.dismiss) private var dismiss

    init(service: GeneratedContentService, contentType: GeneratedContentType? = nil) {
        _viewModel = StateObject(wrappedValue: ContentRequestViewModel(
            service: service,
            initialContentType: contentType
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Quota indicator
                    quotaSection

                    // Content type selector
                    contentTypeSection

                    // Parameters section
                    parametersSection

                    // Custom prompt
                    customPromptSection

                    // Generate button
                    generateButton

                    // Disclaimer
                    disclaimerSection
                }
                .padding()
            }
            .navigationTitle("Create Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Generation Failed", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
                if viewModel.error?.recoverySuggestion != nil {
                    Button("Upgrade") {
                        viewModel.showPaywall = true
                    }
                }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "Unknown error")
            }
            .sheet(isPresented: $viewModel.showResult) {
                if let response = viewModel.generationResponse {
                    ContentGeneratedSheet(response: response) {
                        dismiss()
                    }
                }
            }
            .overlay {
                if viewModel.isGenerating {
                    generatingOverlay
                }
            }
        }
    }

    // MARK: - Quota Section

    private var quotaSection: some View {
        VStack(spacing: 8) {
            if let quota = viewModel.quotaStatus {
                HStack {
                    Text("Daily Generations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if quota.isPremium {
                        Label("Premium", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    } else {
                        Text("\(quota.remaining)/\(quota.limit) remaining")
                            .font(.subheadline)
                            .foregroundStyle(quota.isExhausted ? .red : .secondary)
                    }
                }

                if !quota.isPremium {
                    ProgressView(value: quota.percentUsed)
                        .tint(quota.isExhausted ? .red : .blue)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Content Type Section

    private var contentTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Content Type")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(GeneratedContentType.allCases) { type in
                    ContentTypeCard(
                        type: type,
                        isSelected: viewModel.selectedType == type
                    ) {
                        viewModel.selectedType = type
                    }
                }
            }
        }
    }

    // MARK: - Parameters Section

    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Options")
                .font(.headline)

            // Duration picker (for audio content)
            if viewModel.selectedType.supportsAudio {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Duration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Duration", selection: $viewModel.duration) {
                        Text("3 min").tag(3)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("20 min").tag(20)
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                // Voice picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Voice")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(DefaultVoice.all) { voice in
                                VoiceOptionCard(
                                    voice: voice,
                                    isSelected: viewModel.selectedVoiceId == voice.id
                                ) {
                                    viewModel.selectedVoiceId = voice.id
                                }
                            }
                        }
                    }
                }

                Divider()

                // Background sound
                VStack(alignment: .leading, spacing: 8) {
                    Text("Background Sound")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(BackgroundSoundType.availableSounds, id: \.rawValue) { sound in
                                BackgroundSoundCard(
                                    sound: sound,
                                    isSelected: viewModel.backgroundSound == sound
                                ) {
                                    viewModel.backgroundSound = sound
                                }
                            }
                        }
                    }
                }
            }

            // Theme/Focus for all types
            VStack(alignment: .leading, spacing: 8) {
                Text("Theme (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("e.g., peaceful forest, ocean sunset", text: $viewModel.theme)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Custom Prompt Section

    private var customPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Personal Touch (optional)")
                    .font(.headline)

                Spacer()

                Text("\(viewModel.customPrompt.count)/200")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $viewModel.customPrompt)
                .frame(height: 80)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: viewModel.customPrompt) { _, newValue in
                    if newValue.count > 200 {
                        viewModel.customPrompt = String(newValue.prefix(200))
                    }
                }

            Text("Add specific details to personalize your content")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button {
            Task {
                await viewModel.generateContent()
            }
        } label: {
            HStack {
                Image(systemName: "sparkles")
                Text("Generate \(viewModel.selectedType.displayName)")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(viewModel.canGenerate ? Color.accentColor : Color.gray)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!viewModel.canGenerate)
    }

    // MARK: - Disclaimer

    private var disclaimerSection: some View {
        Text(ContentDisclaimer.standard)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    // MARK: - Generating Overlay

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Creating your \(viewModel.selectedType.displayName.lowercased())...")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("This may take up to 30 seconds")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - Content Type Card

private struct ContentTypeCard: View {
    let type: GeneratedContentType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(type.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Voice Option Card

private struct VoiceOptionCard: View {
    let voice: VoiceOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: voice.gender == .female ? "person.fill" : "person.fill")
                    .font(.title3)

                Text(voice.name)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(voice.style)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 70)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Background Sound Card

private struct BackgroundSoundCard: View {
    let sound: BackgroundSoundType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: sound.icon)
                    .font(.title3)

                Text(sound.displayName)
                    .font(.caption2)
            }
            .frame(width: 70)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Content Generated Sheet

private struct ContentGeneratedSheet: View {
    let response: GenerateContentResponse
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)

                Text("Content Created!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(response.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let duration = response.duration {
                    Text("\(duration / 60) min \(duration % 60) sec")
                        .foregroundStyle(.secondary)
                }

                // Trigger warnings if any
                if let warnings = response.triggerWarnings, !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Content Notes:")
                            .font(.caption)
                            .fontWeight(.medium)

                        ForEach(warnings, id: \.self) { warning in
                            Text("• \(warning.replacingOccurrences(of: "_", with: " ").capitalized)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Text("View in Library")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class ContentRequestViewModel: ObservableObject {
    private let service: GeneratedContentService

    @Published var selectedType: GeneratedContentType
    @Published var duration: Int = 10
    @Published var selectedVoiceId: String = DefaultVoice.sarah.id
    @Published var backgroundSound: BackgroundSoundType = .silence
    @Published var theme: String = ""
    @Published var customPrompt: String = ""

    @Published var isGenerating = false
    @Published var quotaStatus: ContentQuotaStatus?
    @Published var generationResponse: GenerateContentResponse?
    @Published var error: GeneratedContentError?
    @Published var showError = false
    @Published var showResult = false
    @Published var showPaywall = false

    var canGenerate: Bool {
        !isGenerating && (quotaStatus?.isExhausted != true || quotaStatus?.isPremium == true)
    }

    init(service: GeneratedContentService, initialContentType: GeneratedContentType?) {
        self.service = service
        self.selectedType = initialContentType ?? .meditation

        Task {
            await loadQuotaStatus()
        }
    }

    func loadQuotaStatus() async {
        do {
            quotaStatus = try await service.fetchQuotaStatus()
        } catch {
            // Silently fail - will show default quota
        }
    }

    func generateContent() async {
        isGenerating = true
        error = nil

        let params = GenerateContentParams(
            duration: selectedType.supportsAudio ? duration : nil,
            voiceId: selectedType.supportsAudio ? selectedVoiceId : nil,
            backgroundSound: selectedType.supportsAudio && backgroundSound != .silence ? backgroundSound : nil,
            theme: theme.isEmpty ? nil : theme,
            customPrompt: customPrompt.isEmpty ? nil : customPrompt
        )

        do {
            let response = try await service.generateContent(type: selectedType, params: params)
            generationResponse = response
            showResult = true
        } catch let contentError as GeneratedContentError {
            error = contentError
            showError = true
        } catch {
            self.error = .serverError(error.localizedDescription)
            showError = true
        }

        isGenerating = false
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ContentRequestView(service: .preview)
}
#endif
