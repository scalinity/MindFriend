import Foundation
import Supabase
import AVFoundation

// Decode owned originals locally; only bounded canonical PCM leaves the device for
// analysis. Compressed Storage objects are never replaced or supplemented with WAV.
enum VoiceJournalPCM {
    nonisolated static func convert(_ original: Data, fileExtension: String) throws -> Data {
        try Task.checkCancellation()
        guard !original.isEmpty, original.count <= 25 * 1024 * 1024 else {
            throw CreativeError.analysisFailed("The saved recording is too large to analyze (25 MB maximum).")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("voice-analysis-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("original").appendingPathExtension(fileExtension)
        try original.write(to: source, options: .atomic)
        let input = try AVAudioFile(forReading: source)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: input.processingFormat, to: format),
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 4096),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
            throw CreativeError.analysisFailed("This saved recording could not be converted for analysis.")
        }
        converter.downmix = true
        var pcm = Data(count: 44)
        var finished = false
        while !finished {
            try Task.checkCancellation()
            var readError: Error?
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { requested, state in
                do {
                    try Task.checkCancellation()
                    let available = max(0, input.length - input.framePosition)
                    guard available > 0 else { state.pointee = .endOfStream; return nil }
                    try input.read(into: sourceBuffer, frameCount: min(requested, sourceBuffer.frameCapacity, AVAudioFrameCount(min(available, 4096))))
                    state.pointee = sourceBuffer.frameLength > 0 ? .haveData : .endOfStream
                    return sourceBuffer.frameLength > 0 ? sourceBuffer : nil
                } catch {
                    readError = error
                    state.pointee = .endOfStream
                    return nil
                }
            }
            if let readError { throw readError }
            if let conversionError { throw conversionError }
            let size = Int(output.frameLength) * 2
            guard pcm.count - 44 + size <= 600 * 32000 else {
                throw CreativeError.analysisFailed("Recordings must be at most 10 minutes to analyze. The original is still saved.")
            }
            if size > 0, let samples = output.int16ChannelData {
                pcm.append(UnsafeBufferPointer(start: UnsafeRawPointer(samples[0]).assumingMemoryBound(to: UInt8.self), count: size))
            }
            switch status {
            case .endOfStream: finished = true
            case .haveData: break
            default: throw CreativeError.analysisFailed("This saved recording could not be converted for analysis.")
            }
        }
        try Task.checkCancellation()
        guard pcm.count > 44 else { throw CreativeError.analysisFailed("This recording contains no audio to analyze.") }
        func write(_ number: UInt32, at offset: Int, bytes: Int = 4) {
            for index in 0..<bytes { pcm[offset + index] = UInt8(truncatingIfNeeded: number >> (8 * index)) }
        }
        for (offset, text) in [(0, "RIFF"), (8, "WAVEfmt "), (36, "data")] {
            pcm.replaceSubrange(offset..<(offset + text.utf8.count), with: text.utf8)
        }
        write(UInt32(pcm.count - 8), at: 4)
        write(16, at: 16)
        write(1, at: 20, bytes: 2)
        write(1, at: 22, bytes: 2)
        write(16000, at: 24)
        write(32000, at: 28)
        write(2, at: 32, bytes: 2)
        write(16, at: 34, bytes: 2)
        write(UInt32(pcm.count - 44), at: 40)
        return pcm
    }
}

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

    private let deletionClient: SupabaseClient

    init(deletionClient: SupabaseClient? = nil) {
        self.deletionClient = deletionClient ?? supabase
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

        var finalWorkId: String?

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
                    _ = imageData
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
            if case .httpError(let statusCode, _, _) = error, statusCode == 429 {
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

        guard let userUUID = supabase.auth.currentUser?.id else {
            throw CreativeError.notAuthenticated
        }
        let userId = userUUID.uuidString

        // Create creative work record first
        let workId = UUID()
        let storagePath = "\(userId)/voice-journals/\(workId.uuidString).m4a"

        guard !audioData.isEmpty, audioData.count <= 25 * 1024 * 1024,
              durationSeconds > 0, durationSeconds <= 600 else {
            throw CreativeError.generationFailed("Record up to 10 minutes of audio (25 MB maximum).")
        }
        // Upload audio to storage
        try await supabase.storage
            .from("creative-works")
            .upload(
                storagePath,
                data: audioData,
                options: FileOptions(contentType: "audio/m4a")
            )

        // Insert creative work record
        let workRow = DBCreativeWorkInsert(
            id: workId,
            userId: userUUID,
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

        // The insert is the save boundary. A display-signing outage must not
        // offer a second save of an already persisted journal.
        let savedWork = insertedWork.toModel()
        let work = (try? await resolveMedia([savedWork]))?.first ?? savedWork
        creativeWorks.insert(work, at: 0)

        return work
    }

    /// Analyze a voice journal entry
    func analyzeVoiceJournal(workId: String, durationSeconds: Int, originalAudio: Data? = nil) async throws -> VoiceJournalAnalysis {
        try ensureAuthenticated()

        isLoading = true
        defer { isLoading = false }

        guard let owner = supabase.auth.currentUser?.id else { throw CreativeError.notAuthenticated }
        let row: DBCreativeWork = try await supabase.from(Tables.creativeWorks).select()
            .eq("id", value: workId).eq("user_id", value: owner).single().execute().value
        try Task.checkCancellation()
        guard supabase.auth.currentUser?.id == owner, row.userId == owner else { throw CreativeError.notAuthenticated }
        guard row.workType == "voice_journal", let path = row.storagePath else { throw CreativeError.workNotFound }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0].lowercased() == owner.uuidString.lowercased(), parts[1] == "voice-journals",
              UUID(uuidString: (parts[2] as NSString).deletingPathExtension) != nil,
              ["m4a", "aac", "wav", "mp3"].contains((parts[2] as NSString).pathExtension.lowercased()) else {
            throw CreativeError.workNotFound
        }
        let options: FunctionInvokeOptions
        if row.transcriptionStatus == "completed" || row.transcriptionStatus == "processing" {
            // Saved results and uncertain in-flight work never trigger another conversion or paid call.
            options = .init(body: AnalyzeVoiceRequest(creativeWorkId: workId, audioUrl: nil, durationSeconds: max(1, min(600, durationSeconds))))
        } else {
            let original: Data
            if let originalAudio { original = originalAudio }
            else { original = try await supabase.storage.from("creative-works").download(path: path) }
            try Task.checkCancellation()
            guard supabase.auth.currentUser?.id == owner else { throw CreativeError.notAuthenticated }
            let conversion = Task.detached(priority: .userInitiated) {
                try VoiceJournalPCM.convert(original, fileExtension: (path as NSString).pathExtension)
            }
            let pcm = try await withTaskCancellationHandler {
                try await conversion.value
            } onCancel: { conversion.cancel() }
            try Task.checkCancellation()
            guard supabase.auth.currentUser?.id == owner else { throw CreativeError.notAuthenticated }
            options = .init(query: [URLQueryItem(name: "creativeWorkId", value: workId)],
                            headers: ["Content-Type": "audio/wav"], body: pcm, timeoutInterval: 120)
        }
        struct Reply: Decodable { let success: Bool?; let error: String?; let quotaExceeded: Bool? }
        let response: Reply
        do {
            response = try await supabase.functions.invoke("analyze-voice-journal", options: options)
        } catch FunctionsError.httpError(_, let data) {
            try Task.checkCancellation()
            let failure = try? JSONDecoder().decode(Reply.self, from: data)
            if failure?.quotaExceeded == true { throw CreativeError.quotaExceeded }
            throw CreativeError.analysisFailed(failure?.error ?? "Analysis could not be completed. Your recording is saved.")
        }
        try Task.checkCancellation()
        guard supabase.auth.currentUser?.id == owner else { throw CreativeError.notAuthenticated }

        if let error = response.error {
            if response.quotaExceeded == true {
                throw CreativeError.quotaExceeded
            }
            throw CreativeError.analysisFailed(error)
        }

        guard response.success == true else {
            throw CreativeError.analysisFailed("No analysis returned")
        }

        // Fetch the full analysis from DB
        let fullAnalysis = try await fetchVoiceAnalysis(workId: workId)
        return fullAnalysis
    }

    /// Fetch voice journal analysis for a creative work
    func fetchVoiceAnalysis(workId: String) async throws -> VoiceJournalAnalysis {
        guard let owner = supabase.auth.currentUser?.id else { throw CreativeError.notAuthenticated }
        let dbAnalysis: DBVoiceJournalAnalysis = try await supabase
            .from(Tables.voiceJournalAnalysis)
            .select()
            .eq("creative_work_id", value: workId)
            .single()
            .execute()
            .value
        try Task.checkCancellation()
        guard supabase.auth.currentUser?.id == owner else { throw CreativeError.notAuthenticated }
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

        guard let userUUID = supabase.auth.currentUser?.id else {
            throw CreativeError.notAuthenticated
        }
        let userId = userUUID.uuidString

        let workId = UUID()
        let storagePath = "\(userId)/drawings/\(workId.uuidString).png"

        // Upload drawing image
        try await supabase.storage
            .from("creative-works")
            .upload(
                storagePath,
                data: imageData,
                options: FileOptions(contentType: "image/png")
            )

        // Save drawing session for replay capability
        let strokesData = try JSONEncoder().encode(strokes)

        let sessionRow = DBDrawingSessionInsert(
            userId: userUUID,
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
            userId: userUUID,
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

        let work = try await resolveMedia([insertedWork.toModel()])[0]
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

        let works = try await resolveMedia(dbWorks.map { $0.toModel() })

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

        return try await resolveMedia([dbWork.toModel()])[0]
    }

    /// Refresh display access together when a gallery becomes visible or returns to the foreground.
    func refreshMedia(_ works: [CreativeWork]) async throws -> [CreativeWork] {
        let stale = works.filter { $0.storagePath != nil && SupabaseStorageMedia.signedURLNeedsRefresh($0.mediaUrl) }
        guard !stale.isEmpty else { return works }
        let refreshed = try await resolveMedia(stale)
        try Task.checkCancellation()
        let byID = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.id, $0.mediaUrl) })
        return works.map { work in
            var result = work
            if let url = byID[work.id] { result.mediaUrl = url }
            return result
        }
    }

    /// A shared link gets its full one-hour lifetime at the explicit Share action.
    func freshShareURL(for work: CreativeWork) async throws -> URL {
        guard let owner = supabase.auth.currentUser?.id else { throw CreativeError.notAuthenticated }
        guard let path = work.storagePath else { throw CreativeError.workNotFound }
        let url = try await supabase.storage.from("creative-works").createSignedURL(path: path, expiresIn: 3600)
        try Task.checkCancellation()
        guard supabase.auth.currentUser?.id == owner else { throw CreativeError.notAuthenticated }
        return url
    }

    private func resolveMedia(_ works: [CreativeWork]) async throws -> [CreativeWork] {
        guard let owner = supabase.auth.currentUser?.id else { throw CreativeError.notAuthenticated }
        let paths = Array(Set(works.compactMap(\.storagePath)))
        guard !paths.isEmpty else { return works }
        let results: [SignedURLResult] = try await supabase.storage.from("creative-works")
            .createSignedURLs(paths: paths, expiresIn: 3600)
        try Task.checkCancellation()
        guard supabase.auth.currentUser?.id == owner else { throw CreativeError.notAuthenticated }
        var urls: [String: URL] = [:]
        for result in results {
            if case .success(let path, let url) = result { urls[path] = url }
        }
        return works.map { item in
            var resolved = item
            if let path = item.storagePath { resolved.mediaUrl = urls[path] }
            return resolved
        }
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
        guard let owner = deletionClient.auth.currentUser?.id else { throw CreativeError.notAuthenticated }
        guard let workID = UUID(uuidString: id) else { throw CreativeError.workNotFound }
        struct StoredWork: Decodable {
            let storagePath: String?
            enum CodingKeys: String, CodingKey { case storagePath = "storage_path" }
        }
        // A detail view need not be in the gallery cache. Retain this authoritative
        // row until storage confirms removal so a failed delete remains retryable.
        let work: StoredWork = try await deletionClient
            .from(Tables.creativeWorks)
            .select("storage_path")
            .eq("id", value: workID)
            .eq("user_id", value: owner)
            .single()
            .execute()
            .value
        try Task.checkCancellation()
        guard deletionClient.auth.currentUser?.id == owner else { throw CreativeError.notAuthenticated }
        if let path = work.storagePath {
            guard path.split(separator: "/").first.map(String.init)?.lowercased() == owner.uuidString.lowercased() else {
                throw CreativeError.deletionFailed
            }
            _ = try await deletionClient.storage
                .from("creative-works")
                .remove(paths: [path])
            guard try await !deletionClient.storage.from("creative-works").exists(path: path) else {
                throw CreativeError.deletionFailed
            }
        }

        try Task.checkCancellation()
        guard deletionClient.auth.currentUser?.id == owner else { throw CreativeError.notAuthenticated }
        // Delete from database only after media cleanup (cascades to related tables).
        try await deletionClient
            .from(Tables.creativeWorks)
            .delete()
            .eq("id", value: workID)
            .eq("user_id", value: owner)
            .execute()

        try Task.checkCancellation()
        guard deletionClient.auth.currentUser?.id == owner else { throw CreativeError.notAuthenticated }
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
        guard let userUUID = supabase.auth.currentUser?.id else {
            throw CreativeError.notAuthenticated
        }
        guard let exerciseUUID = UUID(uuidString: exerciseId) else {
            throw CreativeError.workNotFound
        }

        let completionId = UUID()
        let row = DBExerciseCompletionInsert(
            id: completionId,
            userId: userUUID,
            exerciseId: exerciseUUID,
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
        // Safely convert optional creativeWorkId to UUID
        let creativeWorkUUID: UUID? = creativeWorkId.flatMap { UUID(uuidString: $0) }
        
        let updates = DBExerciseCompletionUpdate(
            completedAt: Date(),
            creativeWorkId: creativeWorkUUID,
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
    case deletionFailed

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
        case .deletionFailed:
            return "The saved media could not be deleted. Please try again."
        }
    }
}
