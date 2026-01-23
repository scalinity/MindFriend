import SwiftUI
import PhotosUI

struct ProfilePictureEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showAIGenerator = false
    @State private var showRemoveConfirm = false
    @State private var showCropView = false
    @State private var selectedUIImage: UIImage?
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var loadPhotoTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Current avatar or placeholder
                if let avatarUrl = appState.currentUser?.avatarUrl, !avatarUrl.isEmpty {
                    AsyncImage(url: URL(string: avatarUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 150, height: 150)
                                .clipShape(Circle())
                        case .failure:
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 150))
                                .foregroundStyle(.gray)
                        case .empty:
                            ProgressView()
                                .frame(width: 150, height: 150)
                        @unknown default:
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 150))
                                .foregroundStyle(.gray)
                        }
                    }
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 150))
                        .foregroundStyle(.gray)
                }

                if isUploading {
                    ProgressView("Uploading...")
                        .padding()
                } else {
                    VStack(spacing: 12) {
                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label("Upload Photo", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Upload photo from library")
                        .accessibilityHint("Double tap to select a photo from your device")

                        Button {
                            showAIGenerator = true
                        } label: {
                            Label("Generate with AI", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Generate AI profile picture")
                        .accessibilityHint("Double tap to create an AI-generated profile picture")

                        if appState.currentUser?.avatarUrl != nil {
                            Button(role: .destructive) {
                                showRemoveConfirm = true
                            } label: {
                                Label("Remove Photo", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Profile Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, newItem in
                loadPhotoTask?.cancel()
                loadPhotoTask = Task {
                    await loadPhoto(newItem)
                }
            }
            .onDisappear {
                loadPhotoTask?.cancel()
                loadPhotoTask = nil
            }
            .sheet(isPresented: $showCropView) {
                if let image = selectedUIImage {
                    ImageCropView(
                        image: image,
                        onCrop: { croppedImage in
                            showCropView = false
                            uploadCroppedImage(croppedImage)
                        },
                        onCancel: {
                            showCropView = false
                            selectedUIImage = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showAIGenerator) {
                AIProfileGeneratorView(
                    userId: appState.currentUser?.id ?? UUID(),
                    onAvatarUpdated: {
                        // Avatar already updated in AppState by AIProfileGeneratorView
                        dismiss()
                    }
                )
                .environmentObject(appState)
                .environmentObject(container)
            }
            .alert("Remove profile picture?", isPresented: $showRemoveConfirm) {
                Button("Remove", role: .destructive) {
                    removePhoto()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove your profile picture and show the default placeholder.")
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard !Task.isCancelled else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    errorMessage = "Failed to load image"
                }
                return
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                selectedUIImage = uiImage
                showCropView = true
                errorMessage = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                errorMessage = "Failed to load image: \(error.localizedDescription)"
            }
        }
    }

    private func uploadCroppedImage(_ croppedImage: UIImage) {
        guard let userId = appState.currentUser?.id else {
            errorMessage = "User not found"
            return
        }

        isUploading = true
        errorMessage = nil

        Task {
            do {
                // Validate image before upload
                try croppedImage.validateForAvatar()
                
                // Use shared upload pipeline
                let publicUrl = try await container.supabaseDataService.uploadAndSetAvatar(croppedImage, userId: userId)

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
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isUploading = false
                }
            }
        }
    }

    private func removePhoto() {
        guard let userId = appState.currentUser?.id else {
            errorMessage = "User not found"
            return
        }

        isUploading = true
        errorMessage = nil

        Task {
            do {
                // Delete from Storage (if path exists)
                if let avatarUrl = appState.currentUser?.avatarUrl,
                   let url = URL(string: avatarUrl),
                   let path = extractStoragePath(from: url) {
                    try? await container.supabaseDataService.deleteProfilePicture(path: path)
                }

                // Update avatar_url to NULL in database
                try await container.supabaseDataService.updateAvatarUrl("", userId: userId)

                // Update AppState with new UserProfile instance
                await MainActor.run {
                    if let user = appState.currentUser {
                        appState.currentUser = UserProfile(
                            id: user.id,
                            handle: user.handle,
                            displayName: user.displayName,
                            email: user.email,
                            avatarUrl: nil,
                            timezone: user.timezone,
                            createdAt: user.createdAt,
                            onboardingCompletedAt: user.onboardingCompletedAt,
                            stats: user.stats,
                            settings: user.settings,
                            entitlements: user.entitlements,
                            badges: user.badges
                        )
                    }
                    isUploading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isUploading = false
                }
            }
        }
    }

    private func extractStoragePath(from url: URL) -> String? {
        // Extract path from Supabase Storage URL
        // Format: https://<project>.supabase.co/storage/v1/object/public/profile-pictures/<path>
        let components = url.pathComponents
        if let index = components.firstIndex(of: "profile-pictures"), index + 1 < components.count {
            return components[(index + 1)...].joined(separator: "/")
        }
        return nil
    }
}

#Preview {
    ProfilePictureEditorView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
