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
    private enum Phase {
        case preparing, generating, refining, saving
        var title: String {
            switch self {
            case .preparing: return "Preparing your request"
            case .generating: return "Creating your picture"
            case .refining: return "Refining your picture"
            case .saving: return "Saving your picture"
            }
        }
        var detail: String {
            switch self {
            case .preparing: return "Getting your description ready."
            case .generating: return "Creating an image from your description."
            case .refining: return "This is a preview. Waiting for the finished image."
            case .saving: return "Updating your profile with your choice."
            }
        }
    }
    @State private var phase: Phase?
    private var isGenerating: Bool { phase != nil }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var statusHeight: CGFloat = 96
    @State private var errorMessage: String?
    @State private var quotaRemaining: Int?
    @State private var showPaywall = false
    @State private var generationTask: Task<Void, Never>?
    @State private var activeGeneration: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle().fill(Color.secondary.opacity(0.1))
                            if let image = generatedImage ?? partialImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 80, weight: .ultraLight))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 280)
                        .clipShape(Circle())
                        .accessibilityLabel(generatedImage != nil ? "Generated profile picture preview" : partialImage != nil ? "Unfinished profile picture preview" : "Profile picture placeholder")

                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                if isGenerating { ProgressView().accessibilityHidden(true) }
                                Text(phase?.title ?? (generatedImage != nil ? "Your picture is ready" : "Create your profile picture"))
                                    .font(.headline)
                            }
                            Text(phase?.detail ?? (generatedImage != nil ? "Choose Use This to save it to your profile." : "Describe a picture that feels like you."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: statusHeight)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("avatar-status")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Describe your ideal profile picture")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        TextField("e.g., A calm ocean sunset with palm trees", text: $prompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...5)
                            .disabled(isGenerating)
                            .accessibilityLabel("Profile picture description")
                            .accessibilityHint("Enter between 3 and 200 characters")
                        Text("\(prompt.count)/200")
                            .font(.caption)
                            .foregroundStyle(prompt.count > 200 ? .red : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityLabel("\(prompt.count) of 200 characters")
                        if let quotaRemaining {
                            Label("\(quotaRemaining) generations remaining today", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if generatedImage != nil {
                        ViewThatFits(in: .horizontal) {
                            if !dynamicTypeSize.isAccessibilitySize {
                                HStack(spacing: 16) { imageActions }
                            }
                            VStack(spacing: 12) { imageActions }
                        }
                        .disabled(isGenerating)
                    } else {
                        Button(action: generateImage) {
                            Label(errorMessage == nil ? "Generate" : "Try Again", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGenerating || prompt.count < 3 || prompt.count > 200)
                        .accessibilityLabel(errorMessage == nil ? "Generate profile picture" : "Try generating again")
                    }
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

    @ViewBuilder private var imageActions: some View {
        Button(action: confirmGeneratedImage) {
            Label("Use This", systemImage: "checkmark").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        Button(action: regenerateImage) {
            Label("Regenerate", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(prompt.count < 3 || prompt.count > 200)
    }

    private func generateImage() {
        guard !isGenerating, prompt.count >= 3, prompt.count <= 200 else { return }
        let requestId = UUID()
        let requestedPrompt = prompt
        activeGeneration = requestId

        phase = .preparing
        errorMessage = nil
        partialImage = nil

        generationTask = Task {
            do {
                try Task.checkCancellation()
                phase = .generating
                // One explicit action creates one request; failed streams never fall back to another paid call.
                let operation = generation ?? { prompt, partial in
                    try await container.supabaseDataService.generateProfilePictureStreaming(prompt: prompt, onPartialImage: partial)
                }
                let response = try await operation(requestedPrompt) { imageData, _ in
                    Task { @MainActor in
                        guard activeGeneration == requestId, isGenerating else { return }
                        if let image = UIImage(data: imageData) {
                            partialImage = image
                            phase = .refining
                        }
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
                    phase = nil
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
                    phase = nil
                }
            } catch {
                guard !Task.isCancelled, activeGeneration == requestId else { return }
                await MainActor.run {
                    errorMessage = "Failed to generate image. Please try again."
                    activeGeneration = nil
                    partialImage = nil
                    phase = nil
                }
            }
        }
    }

    private func cancelGeneration() {
        activeGeneration = nil
        generationTask?.cancel()
        generationTask = nil
        partialImage = nil
        phase = nil
    }

    private func regenerateImage() {
        guard !isGenerating, prompt.count >= 3, prompt.count <= 200 else { return }
        generatedImage = nil
        partialImage = nil
        generateImage()
    }

    private func confirmGeneratedImage() {
        guard !isGenerating, let generatedImage else { return }

        phase = .saving
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
                    phase = nil
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
