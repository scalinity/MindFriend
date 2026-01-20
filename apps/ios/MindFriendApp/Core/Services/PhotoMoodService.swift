import Foundation
import SwiftUI
import Supabase

/// Service for managing photo mood operations
///
/// Handles:
/// - Photo upload with EXIF stripping and compression
/// - Thumbnail generation
/// - Database CRUD operations
/// - Signed URL generation for secure image access
/// - Deletion with cascade cleanup
@MainActor
final class PhotoMoodService: ObservableObject {
    // MARK: - Properties

    private let supabase: SupabaseClient
    private let bucketName = "mood-photos"

    @Published var photoMoods: [PhotoMood] = []
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    @Published var isDeleting = false

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Create Photo Mood

    /// Creates new photo mood with compression, EXIF stripping, thumbnail generation
    ///
    /// - Parameters:
    ///   - image: Original UIImage from camera/library
    ///   - moodScore: Mood rating 1-5
    ///   - caption: Optional caption (max 500 chars)
    ///   - emotions: Selected emotion tags (max 5)
    ///   - locationName: Optional user-entered location
    /// - Returns: Created PhotoMood record
    /// - Throws: PhotoMoodError if validation or upload fails
    func createPhotoMood(
        image: UIImage,
        moodScore: Int,
        caption: String?,
        emotions: [MoodEmotion],
        locationName: String?
    ) async throws -> PhotoMood {
        // Validate inputs
        guard (1...5).contains(moodScore) else {
            throw PhotoMoodError.invalidMoodScore
        }

        if let caption = caption, caption.count > 500 {
            throw PhotoMoodError.captionTooLong
        }

        if let location = locationName, location.count > 100 {
            throw PhotoMoodError.locationNameTooLong
        }

        if emotions.count > 5 {
            throw PhotoMoodError.tooManyEmotions
        }

        // Validate image can be converted to CGImage
        guard image.cgImage != nil else {
            throw PhotoMoodError.invalidPhotoFormat
        }

        isUploading = true
        uploadProgress = 0.0
        defer {
            isUploading = false
            uploadProgress = 0.0
        }

        // Get current user ID
        let userId = try await supabase.auth.session.user.id

        // Step 1: Prepare full image (strip EXIF, compress) - background processing
        await MainActor.run { uploadProgress = 0.2 }

        // Process image on background queue to avoid blocking main thread
        let (imageData, thumbnailData) = try await Task.detached(priority: .userInitiated) {
            guard let compressed = image.compressToLimit() else {
                throw PhotoMoodError.photoTooLarge
            }
            let thumbnail = image.generateThumbnail()
            return (compressed, thumbnail)
        }.value

        // Step 2: Thumbnail generation completed
        await MainActor.run { uploadProgress = 0.3 }

        // Step 3: Generate file paths
        let timestamp = Int(Date().timeIntervalSince1970)
        let photoPath = "\(userId.uuidString)/\(timestamp).jpg"
        let thumbPath = "\(userId.uuidString)/thumb_\(timestamp).jpg"

        // Step 4: Upload full photo
        await MainActor.run { uploadProgress = 0.4 }
        do {
            let _: EmptyResponse = try await supabase.storage
                .from(bucketName)
                .upload(
                    path: photoPath,
                    file: imageData,
                    options: FileOptions(contentType: "image/jpeg")
                )
        } catch {
            throw PhotoMoodError.uploadFailed("Failed to upload photo: \(error.localizedDescription)")
        }

        // Step 5: Upload thumbnail (non-fatal if fails)
        await MainActor.run { uploadProgress = 0.6 }
        var finalThumbPath: String?
        if let thumbData = thumbnailData {
            do {
                let _: EmptyResponse = try await supabase.storage
                    .from(bucketName)
                    .upload(
                        path: thumbPath,
                        file: thumbData,
                        options: FileOptions(contentType: "image/jpeg")
                    )
                finalThumbPath = thumbPath
            } catch {
                // Non-fatal: continue without thumbnail
                print("⚠️ Thumbnail upload failed: \(error)")
            }
        }

        // Step 6: Create database record
        await MainActor.run { uploadProgress = 0.8 }
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCaption = trimmedCaption?.isEmpty == true ? nil : trimmedCaption

        let insertData: [String: any Sendable] = [
            "user_id": userId.uuidString,
            "mood_score": moodScore,
            "caption": finalCaption as Any,
            "emotion_tags": emotions.map { $0.rawValue },
            "location_name": locationName as Any,
            "photo_storage_path": photoPath,
            "photo_thumbnail_path": finalThumbPath as Any
        ]

        do {
            let photoMood: PhotoMood = try await supabase
                .from("photo_moods")
                .insert(insertData)
                .select()
                .single()
                .execute()
                .value

            await MainActor.run {
                uploadProgress = 1.0
                photoMoods.insert(photoMood, at: 0)
            }
            return photoMood
        } catch {
            // Cleanup: delete uploaded files if DB insert fails
            try? await supabase.storage.from(bucketName).remove(paths: [photoPath])
            if let thumbPath = finalThumbPath {
                try? await supabase.storage.from(bucketName).remove(paths: [thumbPath])
            }
            throw PhotoMoodError.uploadFailed("Failed to save mood: \(error.localizedDescription)")
        }
    }

    // MARK: - Fetch Photo Moods

    /// Fetches user's photo moods with pagination
    ///
    /// - Parameters:
    ///   - limit: Number of moods to fetch (default 50)
    ///   - offset: Pagination offset (default 0)
    ///   - moodFilter: Optional mood score filter (1-5)
    /// - Throws: PhotoMoodError.fetchFailed if query fails
    func fetchPhotoMoods(limit: Int = 50, offset: Int = 0, moodFilter: Int? = nil) async throws {
        let userId = try await supabase.auth.session.user.id

        var query = supabase
            .from("photo_moods")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("logged_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)

        if let filter = moodFilter {
            query = query.eq("mood_score", value: filter)
        }

        do {
            let moods: [PhotoMood] = try await query.execute().value

            await MainActor.run {
                if offset == 0 {
                    photoMoods = moods
                } else {
                    photoMoods.append(contentsOf: moods)
                }
            }
        } catch {
            throw PhotoMoodError.fetchFailed("Failed to fetch photo moods: \(error.localizedDescription)")
        }
    }

    // MARK: - Get Signed URLs

    /// Generates 1-hour signed URL for full photo
    ///
    /// - Parameter photoMood: Photo mood record
    /// - Returns: Signed URL valid for 1 hour
    /// - Throws: PhotoMoodError.uploadFailed if URL generation fails
    func getPhotoUrl(for photoMood: PhotoMood) async throws -> URL {
        do {
            return try await supabase.storage
                .from(bucketName)
                .createSignedURL(path: photoMood.photoStoragePath, expiresIn: 3600)
        } catch {
            throw PhotoMoodError.urlGenerationFailed("Failed to generate photo URL: \(error.localizedDescription)")
        }
    }

    /// Generates 1-hour signed URL for thumbnail
    ///
    /// - Parameter photoMood: Photo mood record
    /// - Returns: Signed URL valid for 1 hour, or nil if no thumbnail
    /// - Throws: PhotoMoodError.uploadFailed if URL generation fails
    func getThumbnailUrl(for photoMood: PhotoMood) async throws -> URL? {
        guard let thumbPath = photoMood.photoThumbnailPath else { return nil }

        do {
            return try await supabase.storage
                .from(bucketName)
                .createSignedURL(path: thumbPath, expiresIn: 3600)
        } catch {
            throw PhotoMoodError.urlGenerationFailed("Failed to generate thumbnail URL: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete Operations

    /// Deletes individual photo mood and storage files
    ///
    /// - Parameter photoMood: Photo mood to delete
    /// - Throws: PhotoMoodError.deleteFailed if deletion fails
    func deletePhotoMood(_ photoMood: PhotoMood) async throws {
        isDeleting = true
        defer { isDeleting = false }

        // Step 1: Delete from storage (storage-first for idempotency)
        var pathsToDelete = [photoMood.photoStoragePath]
        if let thumbPath = photoMood.photoThumbnailPath {
            pathsToDelete.append(thumbPath)
        }

        do {
            let _: EmptyResponse = try await supabase.storage
                .from(bucketName)
                .remove(paths: pathsToDelete)
        } catch {
            throw PhotoMoodError.deleteFailed("Failed to delete photo files: \(error.localizedDescription)")
        }

        // Step 2: Delete database record
        do {
            try await supabase
                .from("photo_moods")
                .delete()
                .eq("id", value: photoMood.id.uuidString)
                .execute()

            await MainActor.run {
                photoMoods.removeAll { $0.id == photoMood.id }
            }
        } catch {
            throw PhotoMoodError.deleteFailed("Failed to delete mood record: \(error.localizedDescription)")
        }
    }

    /// Deletes ALL user photo moods (privacy feature)
    ///
    /// Processes in batches of 100 for large deletions
    ///
    /// - Throws: PhotoMoodError.deleteFailed if deletion fails
    func deleteAllPhotoMoods() async throws {
        isDeleting = true
        defer { isDeleting = false }

        let userId = try await supabase.auth.session.user.id

        // Step 1: Fetch all photo paths (select all columns for proper decoding)
        let moods: [PhotoMood] = try await supabase
            .from("photo_moods")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        guard !moods.isEmpty else { return } // Nothing to delete

        // Step 2: Collect all paths efficiently with functional approach
        let paths = moods.flatMap { mood -> [String] in
            var result = [mood.photoStoragePath]
            if let thumbPath = mood.photoThumbnailPath {
                result.append(thumbPath)
            }
            return result
        }

        // Step 3: Delete in batches (100 per batch) with memory-efficient processing
        let batchSize = 100
        let totalBatches = (paths.count + batchSize - 1) / batchSize

        for (index, batch) in stride(from: 0, to: paths.count, by: batchSize).enumerated() {
            let endIndex = min(batch + batchSize, paths.count)
            let batchPaths = Array(paths[batch..<endIndex])

            // Process batch with proper error handling
            do {
                let _: EmptyResponse = try await supabase.storage
                    .from(bucketName)
                    .remove(paths: batchPaths)

                // Update progress for large operations
                if totalBatches > 1 {
                    let progress = Double(index + 1) / Double(totalBatches)
                    print("🗑️ Batch deletion progress: \(Int(progress * 100))%")
                }
            } catch {
                // Log but continue - orphaned files will be cleaned by cron
                print("⚠️ Batch \(index + 1)/\(totalBatches) delete failed: \(error)")
            }

            // Yield to allow other tasks to run and prevent blocking
            await Task.yield()
        }

        // Step 4: Delete all database records
        try await supabase
            .from("photo_moods")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .execute()

        await MainActor.run {
            photoMoods = []
        }
    }
}
