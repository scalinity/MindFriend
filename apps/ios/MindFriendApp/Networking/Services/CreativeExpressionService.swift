import Foundation
import Supabase

/// Service for managing creative expression features: AI art, voice journals, drawing
@MainActor
final class CreativeExpressionService: ObservableObject {

    // MARK: - Published Properties

    @Published var creativeWorks: [CreativeWork] = []
    @Published var exercises: [CreativeExercise] = []
    @Published var quota: CreativeQuota?
    @Published var isLoading = false
    @Published var error: Error?

    // MARK: - Init

    init() {
        // Uses global supabase client
    }

    // MARK: - Private Helpers

    /// Validate user is authenticated before making Edge Function calls
    private func ensureAuthenticated() throws {
        guard supabase.auth.currentUser != nil else {
            throw CreativeError.notAuthenticated
        }
    }

    // MARK: - Quota Management

    /// Fetch current creative quota for the user
    func fetchQuota() async throws -> CreativeQuota {
        let response: [CreativeQuotaRow] = try await supabase.rpc("get_creative_quota").execute().value

        guard let row = response.first else {
            throw CreativeError.quotaNotAvailable
        }

        let quota = CreativeQuota(
            aiArtCount: row.aiArtCount,
            aiArtLimit: row.aiArtLimit,
            voiceMinutesUsed: row.voiceMinutesUsed,
            voiceMinutesLimit: row.voiceMinutesLimit,
            isPremium: row.isPremium
        )

        self.quota = quota
        return quota
    }

    // MARK: - AI Art Generation

    /// Generate AI art from a prompt
    func generateArt(
        prompt: String,
        style: ArtStyle? = nil,
        moodScore: Int? = nil,
        moodTags: [String]? = nil
    ) async throws -> CreativeWork {
        try ensureAuthenticated()

        isLoading = true
        defer { isLoading = false }

        let request = GenerateArtRequest(
            prompt: prompt,
            style: style?.rawValue,
            moodScore: moodScore,
            moodTags: moodTags
        )

        let response: GenerateArtResponse
        do {
            response = try await supabase.functions.invoke(
                "generate-art",
                options: .init(body: request)
            )
        } catch {
            // Check if this is a 429 quota exceeded error
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("429") || errorString.contains("quota") || errorString.contains("limit") {
                print("[ArtGen] Detected quota exceeded from error: \(error)")
                throw CreativeError.quotaExceeded
            }
            throw error
        }

        if let error = response.error {
            if response.quotaExceeded == true {
                throw CreativeError.quotaExceeded
            }
            throw CreativeError.generationFailed(error)
        }

        guard response.success, let workId = response.creativeWorkId else {
            throw CreativeError.generationFailed("No creative work created")
        }

        // Fetch the created work
        let work = try await fetchCreativeWork(id: workId)

        // Add to local cache
        creativeWorks.insert(work, at: 0)

        return work
    }

    /// Generate AI art from a prompt with streaming partial images
    /// - Parameters:
    ///   - prompt: The art description prompt
    ///   - style: Optional art style
    ///   - moodScore: Optional mood score (1-10)
    ///   - moodTags: Optional mood tags
    ///   - onPartialImage: Callback for partial image updates during generation
    /// - Returns: The final CreativeWork with the generated art
    func generateArtStreaming(
        prompt: String,
        style: ArtStyle? = nil,
        moodScore: Int? = nil,
        moodTags: [String]? = nil,
        onPartialImage: @escaping (Data, Int) -> Void
    ) async throws -> CreativeWork {
        print("[ArtGen] Starting streaming generation with prompt: \(prompt.prefix(50))...")
        try ensureAuthenticated()
        print("[ArtGen] Authentication verified")

        isLoading = true
        defer {
            isLoading = false
            print("[ArtGen] isLoading set to false")
        }

        // Build request body for SSE streaming
        var body: [String: Any] = ["prompt": prompt]
        if let style = style {
            body["style"] = style.rawValue
        }
        if let moodScore = moodScore {
            body["moodScore"] = moodScore
        }
        if let moodTags = moodTags {
            body["moodTags"] = moodTags
        }
        print("[ArtGen] Request body built: \(body)")

        var finalWorkId: String?
        var finalImageData: Data?

        // Stream the generation
        print("[ArtGen] Creating SSE stream...")
        let stream = SSEStreamingHelper.streamImageGeneration(
            functionName: "generate-art",
            body: body
        )

        print("[ArtGen] Starting to iterate stream events...")
        var eventCount = 0
        do {
            for try await event in stream {
                eventCount += 1
                print("[ArtGen] Event #\(eventCount) received")

                switch event {
                case .partial(let index, let imageData):
                    print("[ArtGen] Partial image \(index), size: \(imageData.count)")
                    onPartialImage(imageData, index)

                case .complete(let imageData, let metadata):
                    print("[ArtGen] Complete event received, image size: \(imageData.count)")
                    finalImageData = imageData
                    // Extract creativeWorkId from metadata
                    if let workId = metadata?["creativeWorkId"] as? String {
                        finalWorkId = workId
                        print("[ArtGen] Got creativeWorkId: \(workId)")
                    } else {
                        let keys = metadata?.keys.map { String(describing: $0) } ?? []
                        print("[ArtGen] WARNING: No creativeWorkId in metadata. Keys: \(keys)")
                    }

                case .error(let error):
                    print("[ArtGen] ERROR event: \(error)")
                    // Check if this is a quota exceeded error
                    let errorString = error.localizedDescription.lowercased()
                    if errorString.contains("429") || errorString.contains("quota") || errorString.contains("limit") {
                        throw CreativeError.quotaExceeded
                    }
                    throw CreativeError.generationFailed(error.localizedDescription)
                }
            }
        } catch let error as SSEStreamError {
            // Check for 429 status code indicating quota exceeded
            if case .httpError(let statusCode, _) = error, statusCode == 429 {
                print("[ArtGen] Detected 429 quota exceeded from SSE error")
                throw CreativeError.quotaExceeded
            }
            // Check error message for quota indicators
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("429") || errorString.contains("quota") || errorString.contains("limit") {
                print("[ArtGen] Detected quota exceeded from error message: \(error)")
                throw CreativeError.quotaExceeded
            }
            throw error
        } catch let error as CreativeError {
            throw error
        } catch {
            // Check if the generic error contains 429 indicators
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("429") || errorString.contains("quota") || errorString.contains("limit") {
                print("[ArtGen] Detected quota exceeded from generic error: \(error)")
                throw CreativeError.quotaExceeded
            }
            throw error
        }
        print("[ArtGen] Stream iteration complete. Total events: \(eventCount)")

        // Fetch the created work
        guard let workId = finalWorkId else {
            print("[ArtGen] ERROR: No finalWorkId after stream")
            throw CreativeError.generationFailed("No creative work created")
        }

        print("[ArtGen] Fetching creative work with id: \(workId)")
        let work = try await fetchCreativeWork(id: workId)
        print("[ArtGen] Creative work fetched successfully")

        // Add to local cache
        creativeWorks.insert(work, at: 0)

        return work
    }

    // MARK: - Voice Journal

    /// Create a voice journal entry and upload the audio
    func createVoiceJournal(
        audioData: Data,
        durationSeconds: Int,
        moodScore: Int? = nil,
        moodTags: [String]? = nil
    ) async throws -> CreativeWork {
        isLoading = true
        defer { isLoading = false }

        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            throw CreativeError.notAuthenticated
        }

        // Create creative work record first
        let workId = UUID()
        let storagePath = "\(userId)/voice-journals/\(workId.uuidString).m4a"

        // Upload audio to storage
        try await supabase.storage
            .from("creative-works")
            .upload(
                path: storagePath,
                file: audioData,
                options: FileOptions(contentType: "audio/m4a")
            )

        // Insert creative work record
        let workRow = DBCreativeWorkInsert(
            id: workId,
            userId: UUID(uuidString: userId)!,
            workType: "voice_journal",
            storagePath: storagePath,
            durationSeconds: durationSeconds,
            transcriptionStatus: "pending",
            moodScore: moodScore,
            moodTags: moodTags
        )

        let insertedWork: DBCreativeWork = try await supabase
            .from(Tables.creativeWorks)
            .insert(workRow)
            .select()
            .single()
            .execute()
            .value

        let work = insertedWork.toModel()
        creativeWorks.insert(work, at: 0)

        return work
    }

    /// Analyze a voice journal entry
    func analyzeVoiceJournal(workId: String, durationSeconds: Int) async throws -> VoiceJournalAnalysis {
        try ensureAuthenticated()

        isLoading = true
        defer { isLoading = false }

        let request = AnalyzeVoiceRequest(
            creativeWorkId: workId,
            audioUrl: nil,
            durationSeconds: durationSeconds
        )

        let response: AnalyzeVoiceResponse = try await supabase.functions.invoke(
            "analyze-voice-journal",
            options: .init(body: request)
        )

        if let error = response.error {
            if response.quotaExceeded == true {
                throw CreativeError.quotaExceeded
            }
            throw CreativeError.analysisFailed(error)
        }

        guard response.success, let analysis = response.analysis else {
            throw CreativeError.analysisFailed("No analysis returned")
        }

        // Fetch the full analysis from DB
        let fullAnalysis = try await fetchVoiceAnalysis(workId: workId)
        return fullAnalysis
    }

    /// Fetch voice journal analysis for a creative work
    func fetchVoiceAnalysis(workId: String) async throws -> VoiceJournalAnalysis {
        let dbAnalysis: DBVoiceJournalAnalysis = try await supabase
            .from(Tables.voiceJournalAnalysis)
            .select()
            .eq("creative_work_id", value: workId)
            .single()
            .execute()
            .value

        return dbAnalysis.toModel()
    }

    // MARK: - Drawing

    /// Save a drawing to the gallery
    func saveDrawing(
        strokes: [DrawingStroke],
        canvasSize: CGSize,
        imageData: Data,
        title: String? = nil,
        moodScore: Int? = nil,
        moodTags: [String]? = nil
    ) async throws -> CreativeWork {
        isLoading = true
        defer { isLoading = false }

        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            throw CreativeError.notAuthenticated
        }

        let workId = UUID()
        let storagePath = "\(userId)/drawings/\(workId.uuidString).png"

        // Upload drawing image
        try await supabase.storage
            .from("creative-works")
            .upload(
                path: storagePath,
                file: imageData,
                options: FileOptions(contentType: "image/png")
            )

        // Save drawing session for replay capability
        let strokesData = try JSONEncoder().encode(strokes)

        let sessionRow = DBDrawingSessionInsert(
            userId: UUID(uuidString: userId)!,
            creativeWorkId: workId,
            canvasWidth: Int(canvasSize.width),
            canvasHeight: Int(canvasSize.height),
            strokes: strokesData,
            strokeCount: strokes.count
        )

        try await supabase
            .from(Tables.drawingSessions)
            .insert(sessionRow)
            .execute()

        // Create creative work record
        let workRow = DBCreativeWorkInsert(
            id: workId,
            userId: UUID(uuidString: userId)!,
            workType: "drawing",
            title: title,
            storagePath: storagePath,
            moodScore: moodScore,
            moodTags: moodTags
        )

        let insertedWork: DBCreativeWork = try await supabase
            .from(Tables.creativeWorks)
            .insert(workRow)
            .select()
            .single()
            .execute()
            .value

        let work = insertedWork.toModel()
        creativeWorks.insert(work, at: 0)

        return work
    }

    // MARK: - Gallery

    /// Fetch user's creative works gallery
    func fetchGallery(workType: CreativeWorkType? = nil, limit: Int = 20, offset: Int = 0) async throws -> [CreativeWork] {
        isLoading = true
        defer { isLoading = false }

        let dbWorks: [DBCreativeWork]

        if let type = workType {
            dbWorks = try await supabase
                .from(Tables.creativeWorks)
                .select()
                .eq("work_type", value: type.rawValue)
                .order("created_at", ascending: false)
                .limit(limit)
                .range(from: offset, to: offset + limit - 1)
                .execute()
                .value
        } else {
            dbWorks = try await supabase
                .from(Tables.creativeWorks)
                .select()
                .order("created_at", ascending: false)
                .limit(limit)
                .range(from: offset, to: offset + limit - 1)
                .execute()
                .value
        }

        let works = dbWorks.map { $0.toModel() }

        if offset == 0 {
            creativeWorks = works
        } else {
            creativeWorks.append(contentsOf: works)
        }

        return works
    }

    /// Fetch a single creative work by ID
    func fetchCreativeWork(id: String) async throws -> CreativeWork {
        let dbWork: DBCreativeWork = try await supabase
            .from(Tables.creativeWorks)
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value

        return dbWork.toModel()
    }

    /// Toggle favorite status
    func toggleFavorite(workId: String) async throws -> Bool {
        let result: [ToggleFavoriteResult] = try await supabase
            .rpc("toggle_creative_work_favorite", params: ["p_work_id": workId])
            .execute()
            .value

        let newStatus = result.first?.toggleCreativeWorkFavorite ?? false

        // Update local cache
        if let index = creativeWorks.firstIndex(where: { $0.id == workId }) {
            creativeWorks[index].isFavorite = newStatus
        }

        return newStatus
    }

    /// Delete a creative work
    func deleteWork(id: String) async throws {
        // Get storage path first
        if let work = creativeWorks.first(where: { $0.id == id }),
           let path = work.storagePath {
            // Delete from storage
            try? await supabase.storage
                .from("creative-works")
                .remove(paths: [path])
        }

        // Delete from database (cascades to related tables)
        try await supabase
            .from(Tables.creativeWorks)
            .delete()
            .eq("id", value: id)
            .execute()

        // Remove from local cache
        creativeWorks.removeAll { $0.id == id }
    }

    // MARK: - Exercises

    /// Fetch creative exercises
    func fetchExercises(category: CreativeExerciseCategory? = nil, isPremium: Bool? = nil) async throws -> [CreativeExercise] {
        var baseQuery = supabase
            .from(Tables.creativeExercises)
            .select()
            .eq("is_active", value: true)

        if let category = category {
            baseQuery = baseQuery.eq("category", value: category.rawValue)
        }

        if let isPremium = isPremium {
            baseQuery = baseQuery.eq("is_premium", value: isPremium)
        }

        let dbExercises: [DBCreativeExercise] = try await baseQuery
            .order("category")
            .order("difficulty")
            .execute()
            .value

        let exercises = dbExercises.map { $0.toModel() }
        self.exercises = exercises

        return exercises
    }

    /// Start a creative exercise
    func startExercise(exerciseId: String) async throws -> String {
        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            throw CreativeError.notAuthenticated
        }

        let completionId = UUID()
        let row = DBExerciseCompletionInsert(
            id: completionId,
            userId: UUID(uuidString: userId)!,
            exerciseId: UUID(uuidString: exerciseId)!,
            startedAt: Date()
        )

        try await supabase
            .from(Tables.creativeExerciseCompletions)
            .insert(row)
            .execute()

        return completionId.uuidString
    }

    /// Complete a creative exercise
    func completeExercise(
        completionId: String,
        creativeWorkId: String?,
        reflection: String?,
        moodBefore: Int?,
        moodAfter: Int?
    ) async throws {
        let updates = DBExerciseCompletionUpdate(
            completedAt: Date(),
            creativeWorkId: creativeWorkId != nil ? UUID(uuidString: creativeWorkId!) : nil,
            userReflection: reflection,
            moodBefore: moodBefore,
            moodAfter: moodAfter
        )

        try await supabase
            .from(Tables.creativeExerciseCompletions)
            .update(updates)
            .eq("id", value: completionId)
            .execute()
    }
}

// MARK: - Supporting Types

struct CreativeQuotaRow: Codable {
    let aiArtCount: Int
    let aiArtLimit: Int
    let voiceMinutesUsed: Int
    let voiceMinutesLimit: Int
    let isPremium: Bool

    enum CodingKeys: String, CodingKey {
        case aiArtCount = "ai_art_count"
        case aiArtLimit = "ai_art_limit"
        case voiceMinutesUsed = "voice_minutes_used"
        case voiceMinutesLimit = "voice_minutes_limit"
        case isPremium = "is_premium"
    }
}

struct ToggleFavoriteResult: Codable {
    let toggleCreativeWorkFavorite: Bool

    enum CodingKeys: String, CodingKey {
        case toggleCreativeWorkFavorite = "toggle_creative_work_favorite"
    }
}

struct DBCreativeWorkInsert: Codable {
    let id: UUID
    let userId: UUID
    let workType: String
    var title: String?
    var description: String?
    var storagePath: String?
    var generationPrompt: String?
    var artStyle: String?
    var durationSeconds: Int?
    var transcriptionStatus: String?
    var moodScore: Int?
    var moodTags: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case workType = "work_type"
        case title, description
        case storagePath = "storage_path"
        case generationPrompt = "generation_prompt"
        case artStyle = "art_style"
        case durationSeconds = "duration_seconds"
        case transcriptionStatus = "transcription_status"
        case moodScore = "mood_score"
        case moodTags = "mood_tags"
    }
}

struct DBDrawingSessionInsert: Encodable {
    let userId: UUID
    let creativeWorkId: UUID
    let canvasWidth: Int
    let canvasHeight: Int
    let strokes: Data  // JSON-encoded stroke data
    let strokeCount: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case creativeWorkId = "creative_work_id"
        case canvasWidth = "canvas_width"
        case canvasHeight = "canvas_height"
        case strokes
        case strokeCount = "stroke_count"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(creativeWorkId, forKey: .creativeWorkId)
        try container.encode(canvasWidth, forKey: .canvasWidth)
        try container.encode(canvasHeight, forKey: .canvasHeight)
        try container.encode(strokeCount, forKey: .strokeCount)
        // Encode strokes as a JSON string for JSONB column
        let strokesString = String(data: strokes, encoding: .utf8) ?? "[]"
        try container.encode(strokesString, forKey: .strokes)
    }
}

struct DBExerciseCompletionInsert: Codable {
    let id: UUID
    let userId: UUID
    let exerciseId: UUID
    let startedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseId = "exercise_id"
        case startedAt = "started_at"
    }
}

struct DBExerciseCompletionUpdate: Codable {
    let completedAt: Date
    var creativeWorkId: UUID?
    var userReflection: String?
    var moodBefore: Int?
    var moodAfter: Int?

    enum CodingKeys: String, CodingKey {
        case completedAt = "completed_at"
        case creativeWorkId = "creative_work_id"
        case userReflection = "user_reflection"
        case moodBefore = "mood_before"
        case moodAfter = "mood_after"
    }
}

// MARK: - Errors

enum CreativeError: LocalizedError {
    case notAuthenticated
    case quotaExceeded
    case quotaNotAvailable
    case generationFailed(String)
    case analysisFailed(String)
    case uploadFailed(String)
    case workNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to use creative features."
        case .quotaExceeded:
            return "You've used your free daily AI art generation. Upgrade to MindFriend Premium for 20 generations per day!"
        case .quotaNotAvailable:
            return "Unable to check quota. Please try again."
        case .generationFailed(let message):
            return "Art generation failed: \(message)"
        case .analysisFailed(let message):
            return "Voice analysis failed: \(message)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .workNotFound:
            return "Creative work not found."
        }
    }
}
