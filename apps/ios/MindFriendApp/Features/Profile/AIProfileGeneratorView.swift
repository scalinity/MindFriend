import SwiftUI

struct AIProfileGeneratorView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    let userId: UUID
    let onAvatarUpdated: (() -> Void)?

    typealias Generation = @MainActor (String, @escaping (Data, Int) -> Void) async throws -> SupabaseDataService.GenerateProfilePictureResponse
    typealias Save = @MainActor (UIImage, UUID) async throws -> String
    private let generation: Generation?
    private let save: Save?
    init(userId: UUID, onAvatarUpdated: (() -> Void)? = nil, initialPrompt: String = "", generation: Generation? = nil, save: Save? = nil) {
        self.userId = userId; self.onAvatarUpdated = onAvatarUpdated; self.generation = generation; self.save = save
        _prompt = State(initialValue: initialPrompt)
    }

    @State private var prompt = ""
    @State private var generatedImage: UIImage?
    @State private var partialImage: UIImage?  // For streaming progressive updates
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var quotaRemaining: Int?
    @State private var showPaywall = false
    @State private var generationTask: Task<Void, Never>?
    @State private var activeGeneration: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let generatedImage {
                        // Final generated image preview
                        VStack(spacing: 16) {
                            Image(uiImage: generatedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 300, height: 300)
                                .clipShape(Circle())
                                .accessibilityLabel("Generated profile picture preview")

                            HStack(spacing: 16) {
                                Button {
                                    confirmGeneratedImage()
                                } label: {
                                    Label("Use This", systemImage: "checkmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    regenerateImage()
                                } label: {
                                    Label("Regenerate", systemImage: "arrow.clockwise")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.horizontal)
                            .disabled(isGenerating)
                        }
                    } else {
                        // Prompt input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Describe your ideal profile picture")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)

                            TextField("e.g., A calm ocean sunset with palm trees", text: $prompt, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...5)
                                .disabled(isGenerating)
                                .accessibilityLabel("Profile picture description")
                                .accessibilityHint("Enter a description of the profile picture you want to generate, between 3 and 200 characters")
                                .accessibilityValue(prompt.isEmpty ? "Empty" : "\(prompt.count) characters entered")

                            HStack {
                                Spacer()
                                Text("\(prompt.count)/200")
                                    .font(.caption)
                                    .foregroundStyle(prompt.count > 200 ? .red : .secondary)
                                    .accessibilityLabel("Character count")
                                    .accessibilityValue("\(prompt.count) of 200 characters")
                            }

                            if let quotaRemaining {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.caption)
                                    Text("\(quotaRemaining) generations remaining today")
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Quota status")
                                .accessibilityValue("\(quotaRemaining) AI profile picture generations remaining today")
                            }
                        }
                        .padding(.horizontal)

                        if isGenerating {
                            VStack(spacing: 12) {
                                // Show partial image if available during streaming
                                if let partialImage {
                                    ZStack {
                                        Image(uiImage: partialImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 250, height: 250)
                                            .clipShape(Circle())
                                            .opacity(0.7)
                                            .blur(radius: 1)

                                        ProgressView()
                                            .scaleEffect(1.5)
                                            .tint(.white)
                                    }
                                    .accessibilityLabel("Generating profile picture")
                                    .accessibilityValue("Preview showing, refining details")
                                } else {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                }
                                Text(partialImage != nil ? "Refining your image..." : "Generating your profile picture...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Generating")
                            .accessibilityValue("Please wait while your profile picture is being generated")
                        } else {
                            Button {
                                generateImage()
                            } label: {
                                Label("Generate", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(prompt.count < 3 || prompt.count > 200)
                            .padding(.horizontal)
                            .accessibilityLabel("Generate profile picture")
                            .accessibilityHint(prompt.count < 3 ? "Enter at least 3 characters first" : 
                                             prompt.count > 200 ? "Reduce description to 200 characters or less" :
                                             "Double tap to generate a profile picture using AI")
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("AI Profile Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelGeneration()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                cancelGeneration()
            }
            .onChange(of: appState.currentUser?.id) { _, currentId in
                if currentId != userId { cancelGeneration(); dismiss() }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(appState)
                    .environmentObject(container)
            }
        }
    }

    private func generateImage() {
        guard !isGenerating, prompt.count >= 3, prompt.count <= 200 else { return }
        let requestId = UUID()
        let requestedPrompt = prompt
        activeGeneration = requestId

        isGenerating = true
        errorMessage = nil
        partialImage = nil

        generationTask = Task {
            do {
                // One explicit action creates one request; failed streams never fall back to another paid call.
                let operation = generation ?? { prompt, partial in
                    try await container.supabaseDataService.generateProfilePictureStreaming(prompt: prompt, onPartialImage: partial)
                }
                let response = try await operation(requestedPrompt) { imageData, _ in
                    Task { @MainActor in
                        guard activeGeneration == requestId, isGenerating else { return }
                        partialImage = UIImage(data: imageData)
                    }
                }

                // Check for cancellation before UI update
                guard !Task.isCancelled, activeGeneration == requestId else { return }

                // Decode base64 to UIImage
                guard let imageData = Data(base64Encoded: response.imageBase64),
                      let image = UIImage(data: imageData) else {
                    guard !Task.isCancelled, activeGeneration == requestId else { return }
                    throw NSError(domain: "ImageError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode generated image"])
                }

                await MainActor.run {
                    activeGeneration = nil
                    generatedImage = image
                    partialImage = nil
                    quotaRemaining = response.quotaRemaining
                    isGenerating = false
                }
            } catch let error as SupabaseDataService.GenerateProfilePictureError {
                guard !Task.isCancelled, activeGeneration == requestId else { return }
                await MainActor.run {
                    switch error {
                    case .quotaExceeded:
                        // Show paywall directly without error message
                        showPaywall = true
                    case .inappropriateContent:
                        errorMessage = "This prompt contains inappropriate content. Please try a different description."
                    case .networkError:
                        errorMessage = "Network error. Please check your connection and try again."
                    case .apiError(let message):
                        errorMessage = message
                    }
                    activeGeneration = nil
                    partialImage = nil
                    isGenerating = false
                }
            } catch {
                guard !Task.isCancelled, activeGeneration == requestId else { return }
                await MainActor.run {
                    errorMessage = "Failed to generate image. Please try again."
                    activeGeneration = nil
                    partialImage = nil
                    isGenerating = false
                }
            }
        }
    }

    private func cancelGeneration() {
        activeGeneration = nil
        generationTask?.cancel()
        generationTask = nil
        partialImage = nil
        isGenerating = false
    }

    private func regenerateImage() {
        generatedImage = nil
        partialImage = nil
        generateImage()
    }

    private func confirmGeneratedImage() {
        guard !isGenerating, let generatedImage else { return }

        isGenerating = true
        errorMessage = nil

        generationTask = Task {
            do {
                // Validate generated image before upload
                try generatedImage.validateForAvatar()
                
                // Use shared upload pipeline with AI source tag
                let operation = save ?? { image, owner in
                    try await container.supabaseDataService.uploadAndSetAvatar(image, userId: owner, source: "ai_generated")
                }
                let publicUrl = try await operation(generatedImage, userId)

                try Task.checkCancellation()
                // Only the account that confirmed the save may receive the local update.
                await MainActor.run {
                    guard let user = appState.currentUser, user.id == userId else { return }
                    var updatedUser = user
                    updatedUser.avatarUrl = publicUrl
                    appState.currentUser = updatedUser
                    onAvatarUpdated?()
                    dismiss()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}

#Preview {
    AIProfileGeneratorView(
        userId: UUID(),
        onAvatarUpdated: {}
    )
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
