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
    @State private var uploadTask: Task<Void, Never>?
    @State private var removeTask: Task<Void, Never>?
    
    // History
    @State private var pictureHistory: [SupabaseDataService.ProfilePictureHistoryEntry] = []
    @State private var isLoadingHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
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

                // Picture History Section
                if !pictureHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Previous Pictures")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(pictureHistory) { entry in
                                HistoryPictureCell(
                                    entry: entry,
                                    isCurrentAvatar: appState.currentUser?.avatarUrl == entry.publicUrl,
                                    onSelect: { selectFromHistory(entry) }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 8)
                } else if isLoadingHistory {
                    ProgressView("Loading history...")
                        .padding()
                }
            }
            .padding()
            }
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
                uploadTask?.cancel()
                uploadTask = nil
                removeTask?.cancel()
                removeTask = nil
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
                        // Reload history to show new picture
                        Task {
                            await loadHistory()
                        }
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
            .task {
                await loadHistory()
            }
        }
    }
    
    private func loadHistory() async {
        isLoadingHistory = true
        do {
            var history = try await container.supabaseDataService.getProfilePictureHistory()
            
            // Backfill: If current avatar exists but isn't in history, add it
            if let avatarUrl = appState.currentUser?.avatarUrl,
               !avatarUrl.isEmpty,
               !history.contains(where: { $0.publicUrl == avatarUrl }),
               let url = URL(string: avatarUrl),
               let storagePath = extractStoragePath(from: url) {
                // Add current avatar to history
                do {
                    try await container.supabaseDataService.saveProfilePictureToHistory(
                        storagePath: storagePath,
                        publicUrl: avatarUrl,
                        source: "upload"  // Default to upload for backfilled pictures
                    )
                    // Reload to get the new entry with proper ID
                    history = try await container.supabaseDataService.getProfilePictureHistory()
                } catch {
                    print("[ProfilePicture] Failed to backfill current avatar: \(error.localizedDescription)")
                }
            }
            
            pictureHistory = history
        } catch {
            // Silently fail - history is a nice-to-have feature
            print("[ProfilePicture] Failed to load history: \(error.localizedDescription)")
        }
        isLoadingHistory = false
    }
    
    private func selectFromHistory(_ entry: SupabaseDataService.ProfilePictureHistoryEntry) {
        guard !isUploading else { return }
        
        isUploading = true
        errorMessage = nil
        
        Task {
            do {
                try await container.supabaseDataService.setAvatarFromHistory(historyEntry: entry)
                
                await MainActor.run {
                    if let user = appState.currentUser {
                        appState.currentUser = UserProfile(
                            id: user.id,
                            handle: user.handle,
                            displayName: user.displayName,
                            email: user.email,
                            avatarUrl: entry.publicUrl,
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

        // Cancel any existing upload
        uploadTask?.cancel()
        
        isUploading = true
        errorMessage = nil

        uploadTask = Task {
            do {
                // Check for cancellation
                guard !Task.isCancelled else { return }
                
                // Validate image before upload
                try croppedImage.validateForAvatar()
                
                guard !Task.isCancelled else { return }
                
                // Use shared upload pipeline
                let publicUrl = try await container.supabaseDataService.uploadAndSetAvatar(croppedImage, userId: userId)

                guard !Task.isCancelled else { return }
                
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
                    isUploading = false
                }
                
                // Reload history to show new picture
                await loadHistory()
            } catch {
                guard !Task.isCancelled else { return }
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

        // Cancel any existing remove operation
        removeTask?.cancel()
        
        isUploading = true
        errorMessage = nil

        removeTask = Task {
            do {
                guard !Task.isCancelled else { return }
                
                // Delete from Storage (if path exists)
                if let avatarUrl = appState.currentUser?.avatarUrl,
                   let url = URL(string: avatarUrl),
                   let path = extractStoragePath(from: url) {
                    try? await container.supabaseDataService.deleteProfilePicture(path: path)
                }

                guard !Task.isCancelled else { return }
                
                // Update avatar_url to NULL in database
                try await container.supabaseDataService.updateAvatarUrl("", userId: userId)

                guard !Task.isCancelled else { return }
                
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
                guard !Task.isCancelled else { return }
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

// MARK: - History Picture Cell

private struct HistoryPictureCell: View {
    let entry: SupabaseDataService.ProfilePictureHistoryEntry
    let isCurrentAvatar: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            ZStack {
                AsyncImage(url: URL(string: entry.publicUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.gray)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        Color.gray.opacity(0.2)
                    }
                }
                .frame(width: 90, height: 90)
                .clipShape(Circle())
                
                // Current avatar indicator
                if isCurrentAvatar {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: 94, height: 94)
                }
                
                // AI badge for generated pictures
                if entry.source == "ai_generated" {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Circle().fill(Color.purple))
                        }
                    }
                    .frame(width: 90, height: 90)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCurrentAvatar ? "Current profile picture" : "Previous profile picture")
        .accessibilityHint("Double tap to use this picture")
        .accessibilityAddTraits(isCurrentAvatar ? .isSelected : [])
    }
}

#Preview {
    ProfilePictureEditorView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
