import SwiftUI

struct AIProfileGeneratorView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    let userId: UUID
    let onAvatarUpdated: (() -> Void)?

    @State private var prompt = ""
    @State private var generatedImage: UIImage?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var quotaRemaining: Int?
    @State private var showPaywall = false
    @State private var generationTask: Task<Void, Never>?

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
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Generating your profile picture...")
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
                        dismiss()
                    }
                }
            }
            .onDisappear {
                generationTask?.cancel()
                generationTask = nil
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(appState)
                    .environmentObject(container)
            }
        }
    }

    private func generateImage() {
        guard prompt.count >= 3, prompt.count <= 200 else { return }

        // Cancel any existing task
        generationTask?.cancel()

        isGenerating = true
        errorMessage = nil

        generationTask = Task {
            do {
                let response = try await container.supabaseDataService.generateProfilePicture(prompt: prompt)

                // Check for cancellation before UI update
                guard !Task.isCancelled else { return }

                // Decode base64 to UIImage
                guard let imageData = Data(base64Encoded: response.imageBase64),
                      let image = UIImage(data: imageData) else {
                    guard !Task.isCancelled else { return }
                    throw NSError(domain: "ImageError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode generated image"])
                }

                await MainActor.run {
                    generatedImage = image
                    quotaRemaining = response.quotaRemaining
                    isGenerating = false
                }
            } catch let error as SupabaseDataService.GenerateProfilePictureError {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    switch error {
                    case .quotaExceeded:
                        errorMessage = "Daily limit reached. Upgrade to Premium for unlimited generations!"
                        showPaywall = true
                    case .inappropriateContent:
                        errorMessage = "This prompt contains inappropriate content. Please try a different description."
                    case .networkError:
                        errorMessage = "Network error. Please check your connection and try again."
                    case .apiError(let message):
                        errorMessage = message
                    }
                    isGenerating = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    errorMessage = "Failed to generate image. Please try again."
                    isGenerating = false
                }
            }
        }
    }

    private func regenerateImage() {
        generatedImage = nil
        generateImage()
    }

    private func confirmGeneratedImage() {
        guard let generatedImage else { return }

        isGenerating = true
        errorMessage = nil

        Task {
            do {
                // Validate generated image before upload
                try generatedImage.validateForAvatar()
                
                // Use shared upload pipeline
                let publicUrl = try await container.supabaseDataService.uploadAndSetAvatar(generatedImage, userId: userId)

                // Update AppState with new UserProfile instance
                await MainActor.run {
                    if let user = appState.currentUser {
                        appState.currentUser = UserProfile(
                            id: user.id,
                            handle: user.handle,
                            displayName: user.displayName,
                            email: user.email,
                            avatarUrl: publicUrl,
                            timezone: user.timezone,
                            createdAt: user.createdAt,
                            onboardingCompletedAt: user.onboardingCompletedAt,
                            stats: user.stats,
                            settings: user.settings,
                            entitlements: user.entitlements,
                            badges: user.badges
                        )
                    }
                    onAvatarUpdated?()
                    dismiss()
                }
            } catch {
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
