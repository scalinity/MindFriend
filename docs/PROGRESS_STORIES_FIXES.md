# Progress Stories - Concrete Fix Specifications

This document provides specific, copy-paste-ready code fixes for each issue identified in the reliability audit.

---

## Phase 1: Critical Fixes

### Fix #1: Edge Function - Add Error Handling to Query Chain

**File:** `supabase/functions/generate-weekly-story/index.ts`  
**Lines:** 335-398 (fetchWeeklyStats)  
**Issue:** 4 database queries with no error handling

**Current Code:**
```typescript
async function fetchWeeklyStats(
  supabase: SupabaseClient,
  userId: string,
  weekStart: string,
  weekEnd: string,
  currentStreakDays: number,
): Promise<WeeklyStats> {
  // Fetch mood check-ins
  const { data: moods, count: moodCount } = await supabase
    .from("moods")
    .select("mood_score", { count: "exact" })
    .eq("user_id", userId)
    .gte("local_date", weekStart)
    .lt("local_date", weekEnd);

  // ... rest of queries
}
```

**Fixed Code:**
```typescript
async function fetchWeeklyStats(
  supabase: SupabaseClient,
  userId: string,
  weekStart: string,
  weekEnd: string,
  currentStreakDays: number,
): Promise<WeeklyStats> {
  // Fetch mood check-ins
  const { data: moods, count: moodCount, error: moodError } = await supabase
    .from("moods")
    .select("mood_score", { count: "exact" })
    .eq("user_id", userId)
    .gte("local_date", weekStart)
    .lt("local_date", weekEnd);

  if (moodError) {
    console.error("Mood query error:", moodError);
    // Return empty stats rather than crashing
    return {
      checkinCount: 0,
      questCount: 0,
      exerciseCount: 0,
      avgMood: null,
      moodTrend: null,
      moodMin: null,
      moodMax: null,
      exerciseMinutes: 0,
      streakDays: currentStreakDays,
    };
  }

  // Fetch quest completions
  const { count: questCount, error: questError } = await supabase
    .from("quests")
    .select("id", { count: "exact" })
    .eq("user_id", userId)
    .eq("status", "completed")
    .gte("completed_at", weekStart + "T00:00:00Z")
    .lt("completed_at", weekEnd + "T00:00:00Z");

  if (questError) {
    console.error("Quest query error:", questError);
    return {
      checkinCount: moodCount ?? 0,
      questCount: 0,
      exerciseCount: 0,
      avgMood: null,
      moodTrend: null,
      moodMin: null,
      moodMax: null,
      exerciseMinutes: 0,
      streakDays: currentStreakDays,
    };
  }

  // Fetch exercise sessions
  const { data: exercises, count: exerciseCount, error: exerciseError } = await supabase
    .from("exercise_sessions")
    .select("duration_seconds", { count: "exact" })
    .eq("user_id", userId)
    .gte("completed_at", weekStart + "T00:00:00Z")
    .lt("completed_at", weekEnd + "T00:00:00Z");

  if (exerciseError) {
    console.error("Exercise query error:", exerciseError);
    return {
      checkinCount: moodCount ?? 0,
      questCount: questCount ?? 0,
      exerciseCount: 0,
      avgMood: null,
      moodTrend: null,
      moodMin: null,
      moodMax: null,
      exerciseMinutes: 0,
      streakDays: currentStreakDays,
    };
  }

  // Continue with existing logic for calculating stats...
  // (rest of function unchanged)
}
```

---

### Fix #2: iOS ViewModel - Add Retry Logic with Exponential Backoff

**File:** `apps/ios/MindFriendApp/Features/ProgressStories/ProgressStoryViewModel.swift`  
**Lines:** 54-71 (loadStory) & 77-96 (generateStory)  
**Issue:** No retry on transient network errors

**Add New Helper:**
```swift
// MARK: - Retry Logic

private func retryWithBackoff<T>(
    maxAttempts: Int = 3,
    initialDelay: TimeInterval = 1.0,
    operation: @escaping () async throws -> T
) async throws -> T {
    var lastError: Error?
    var delay = initialDelay

    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch let error as URLError where error.code == .timedOut || 
                                            error.code == .networkConnectionLost {
            // Transient error - retry
            lastError = error
            if attempt < maxAttempts {
                logger.info("[ProgressStory] Transient error, retrying in \(delay)s (attempt \(attempt)/\(maxAttempts))")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay *= 2.0 // Exponential backoff
            }
        } catch {
            // Permanent error - give up immediately
            throw error
        }
    }

    throw lastError ?? DataError.operationFailed("Failed after \(maxAttempts) attempts")
}
```

**Replace loadStory:**
```swift
func loadStory() async {
    isLoading = true
    defer { isLoading = false }

    do {
        let story = try await retryWithBackoff {
            try await self.dataService.getWeeklyStory(weekStart: self.weekStart)
        }

        if let story = story {
            self.story = story
            Analytics.shared.track(.weeklyStoryViewed, properties: [
                "week_start": self.weekStart,
                "card_count": story.cards.count
            ])
        } else {
            // No story exists, generate one
            await generateStory()
        }
    } catch {
        logger.error("[ProgressStory] Failed to load story after retries: \(error)")
        self.error = .loadFailed(error.localizedDescription)
        showError = true
    }
}
```

**Replace generateStory:**
```swift
func generateStory() async {
    isLoading = true
    defer { isLoading = false }

    do {
        story = try await retryWithBackoff {
            try await self.dataService.generateWeeklyStory(weekStart: self.weekStart)
        }
        logger.info("[ProgressStory] Generated story with \(self.story?.cards.count ?? 0) cards")
    } catch {
        logger.error("[ProgressStory] Failed to generate story after retries: \(error)")
        self.error = .generationFailed(error.localizedDescription)
        showError = true
    }
}
```

---

### Fix #3: iOS ViewModel - Add Timeout Protection

**File:** `apps/ios/MindFriendApp/Features/ProgressStories/ProgressStoryViewModel.swift`  
**Issue:** Async operations can hang indefinitely

**Add New Helper:**
```swift
// MARK: - Timeout Protection

private func withTimeout<T>(
    timeoutSeconds: TimeInterval = 30,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Start the actual operation
        group.addTask {
            try await operation()
        }

        // Start a timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            throw DataError.operationFailed("Operation timed out after \(Int(timeoutSeconds))s")
        }

        // Return result from whichever completes first
        let result = try await group.next()
        group.cancelAll()
        return result!
    }
}
```

**Update loadStory to use timeout:**
```swift
func loadStory() async {
    isLoading = true
    defer { isLoading = false }

    do {
        let story = try await withTimeout(timeoutSeconds: 30) {
            try await self.retryWithBackoff {
                try await self.dataService.getWeeklyStory(weekStart: self.weekStart)
            }
        }

        if let story = story {
            self.story = story
            Analytics.shared.track(.weeklyStoryViewed, properties: [
                "week_start": self.weekStart,
                "card_count": story.cards.count
            ])
        } else {
            await generateStory()
        }
    } catch {
        logger.error("[ProgressStory] Failed to load story: \(error)")
        self.error = .loadFailed(error.localizedDescription)
        showError = true
    }
}
```

---

### Fix #4: CircleShareSheet - Show Error Instead of Silent Failure

**File:** `apps/ios/MindFriendApp/Features/ProgressStories/CircleShareSheet.swift`  
**Lines:** 235-245 (loadCircles)  
**Issue:** Silent failure to load circles

**Add Error State:**
```swift
@State private var circleLoadError: String?
```

**Replace loadCircles:**
```swift
private func loadCircles() async {
    isLoading = true
    defer { isLoading = false }

    do {
        circles = try await container.supabaseDataService.getCircles()
        circleLoadError = nil

        // Auto-select first circle if only one exists
        if circles.count == 1 {
            selectedCircle = circles.first
        }
    } catch {
        circleLoadError = "Unable to load circles: \(error.localizedDescription)"
        logger.error("[CircleShare] Failed to load circles: \(error)")
    }
}
```

**Update circlePicker to show error:**
```swift
@ViewBuilder
private var circlePicker: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Select Circle")
            .font(.headline)

        if isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(height: 60)
        } else if let error = circleLoadError {
            VStack(spacing: 8) {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                
                Button("Try Again") {
                    Task { await loadCircles() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
        } else if circles.isEmpty {
            Text("You're not in any circles yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(circles, id: \.id) { circle in
                        circleButton(circle)
                    }
                }
            }
        }
    }
}
```

---

### Fix #5: ProgressStoryViewModel - Fix Array Access

**File:** `apps/ios/MindFriendApp/Features/ProgressStories/ProgressStoryViewModel.swift`  
**Lines:** 104-108 (exportCard)  
**Issue:** Unsafe subscript usage

**Replace exportCard:**
```swift
@MainActor
func exportCard(at index: Int) async -> UIImage? {
    guard let cards = story?.cards,
          index >= 0,
          index < cards.count else {
        logger.warning("[ProgressStory] Invalid card index: \(index)")
        return nil
    }

    let card = cards[index]

    isExporting = true
    exportingCardIndex = index
    defer {
        isExporting = false
        exportingCardIndex = nil
    }

    let renderer = ImageRenderer(
        content: StoryCardView(card: card, privacyMode: false, isExport: true)
            .frame(width: 1080, height: 1920)
    )
    renderer.scale = 1.0

    Analytics.shared.track(.weeklyStoryCardExported, properties: [
        "week_start": weekStart,
        "card_index": index,
        "card_type": card.cardType.rawValue
    ])

    return renderer.uiImage
}
```

---

## Phase 2: High Priority Fixes

### Fix #6: Edge Function - Profile Query Validation

**File:** `supabase/functions/generate-weekly-story/index.ts`  
**Lines:** 231-246 (generateStoryCards - profile fetch)  
**Issue:** `.single()` throws without error handling

**Current Code:**
```typescript
const { data: profileData } = await supabase
    .from("profiles")
    .select("id, display_name, wellness_focus, current_streak_days")
    .eq("id", userId)
    .single();
```

**Fixed Code:**
```typescript
const { data: profileData, error: profileError } = await supabase
    .from("profiles")
    .select("id, display_name, wellness_focus, current_streak_days")
    .eq("id", userId)
    .single();

if (profileError) {
    console.error("Profile query error:", profileError);
    // Use defaults if profile not found
    const profile: UserProfile = {
        id: userId,
        displayName: null,
        wellnessFocus: null,
        currentStreakDays: 0,
    };
}
```

---

### Fix #7: iOS SupabaseDataService - Map Errors to Classifications

**File:** `apps/ios/MindFriendApp/Networking/Services/SupabaseDataService.swift`  
**Lines:** 3817-3858 (generateWeeklyStory)  
**Issue:** No distinction between transient and permanent errors

**Add Helper:**
```swift
private func classifySupabaseError(_ error: Error) -> APIError {
    let description = error.localizedDescription.lowercased()

    // Transient errors
    if description.contains("timeout") || 
       description.contains("connection") ||
       description.contains("network") {
        return .networkError(error.localizedDescription)
    }

    // Server errors (potentially transient)
    if description.contains("500") || 
       description.contains("502") ||
       description.contains("503") ||
       description.contains("gateway") {
        return .serverError(error.localizedDescription)
    }

    // Permanent errors
    return .badRequest(error.localizedDescription)
}
```

**Update generateWeeklyStory:**
```swift
func generateWeeklyStory(weekStart: String) async throws -> WeeklyStory {
    let session = try await supabase.auth.session

    let response: GenerateWeeklyStoryResponse
    do {
        response = try await supabase.functions.invoke(
            "generate-weekly-story",
            options: .init(
                method: .post,
                headers: ["Authorization": "Bearer \(session.accessToken)"],
                body: ["weekStart": weekStart]
            )
        )
    } catch {
        throw classifySupabaseError(error)
    }

    if !response.success {
        throw StoryGenerationError.internalError
    }

    // Fetch the persisted story from database
    guard let story = try await getWeeklyStory(weekStart: weekStart) else {
        return WeeklyStory(
            id: UUID(),
            userId: response.userId,
            weekStart: response.weekStart,
            cards: response.cards,
            createdAt: response.generatedAt,
            updatedAt: response.generatedAt
        )
    }

    Analytics.shared.track(.weeklyStoryGenerated, properties: [
        "week_start": weekStart,
        "card_count": response.cards.count
    ])

    return story
}
```

---

### Fix #8: CircleShareSheet - Callback for Success Feedback

**File:** `apps/ios/MindFriendApp/Features/ProgressStories/CircleShareSheet.swift`  
**Issue:** No success feedback to parent view

**Update postToCircle:**
```swift
private func postToCircle() async {
    guard let circle = selectedCircle,
          let circleUUID = UUID(uuidString: circle.id) else { return }

    isPosting = true
    defer { isPosting = false }

    await viewModel.shareToCircle(
        index: cardIndex,
        circleId: circleUUID,
        caption: caption.isEmpty ? nil : caption
    )

    // Check if share succeeded by looking at error state
    if viewModel.error == nil {
        // Success - close sheet
        dismiss()
    }
}
```

---

### Fix #9: Edge Function - Validate Upsert Succeeded

**File:** `supabase/functions/generate-weekly-story/index.ts`  
**Lines:** 215-227 (main function - upsert)  
**Issue:** Silent upsert failure

**Current Code:**
```typescript
if (upsertError) {
    console.error("Upsert error:", upsertError);
    // Don't fail the request - still return cards
}
```

**Fixed Code:**
```typescript
if (upsertError) {
    console.error("Upsert error:", upsertError);
    // For transient errors, warn but return cards anyway
    // For permanent errors, throw
    if (upsertError.message?.includes("permission denied") ||
        upsertError.message?.includes("violates foreign key")) {
        // Permanent error
        return new Response(
            JSON.stringify({
                error: "Unable to persist story",
                code: "PERSIST_FAILED",
            }),
            { status: 500, headers },
        );
    }
    // Transient error - log but continue
    console.warn("Upsert failed (transient), but returning cards");
}
```

---

### Fix #10: ProgressStoryViewer - Add Timeout Indicator

**File:** `apps/ios/MindFriendApp/Features/ProgressStories/ProgressStoryViewer.swift`  
**Lines:** 54-70 (loadingView)  
**Issue:** No indication if loading is taking too long

**Add State:**
```swift
@State private var showLoadingTimeout = false
```

**Update loadingView:**
```swift
@ViewBuilder
private var loadingView: some View {
    VStack(spacing: 16) {
        ProgressView()
            .scaleEffect(1.5)
            .tint(.white)

        Text("Loading your story...")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.8))

        if showLoadingTimeout {
            Text("This is taking longer than usual. Check your connection and try refreshing.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Button("Retry") {
                Task { await viewModel?.loadStory() }
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }
    .task {
        // Show timeout message after 10 seconds
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        if viewModel?.isLoading ?? false {
            withAnimation {
                showLoadingTimeout = true
            }
        }
    }
}
```

---

### Fix #11: SupabaseDataService - Validate Image Upload

**File:** `apps/ios/MindFriendApp/Networking/Services/SupabaseDataService.swift`  
**Lines:** 3888-3902 (uploadStoryCardImage)  
**Issue:** No validation of upload or size

**Replaced uploadStoryCardImage:**
```swift
func uploadStoryCardImage(imageData: Data, weekStart: String, cardIndex: Int) async throws -> String {
    // Validate image size (max 5MB)
    let maxSizeBytes = 5 * 1024 * 1024
    guard imageData.count <= maxSizeBytes else {
        throw DataError.operationFailed("Image too large (\(imageData.count) bytes, max \(maxSizeBytes))")
    }

    let uid = try userId
    let filename = "story_\(weekStart)_card\(cardIndex).png"
    let path = "\(uid.uuidString)/stories/\(filename)"

    // Perform upload with error handling
    let uploadResponse = try await supabase.storage
        .from("user-content")
        .upload(path, data: imageData, options: .init(contentType: "image/png", upsert: true))

    // Verify upload result is not nil
    guard uploadResponse != nil else {
        throw DataError.operationFailed("Upload returned empty response")
    }

    // Get and validate public URL
    let publicUrl = supabase.storage
        .from("user-content")
        .getPublicURL(path: path)

    guard publicUrl.absoluteString.count > 0 else {
        throw DataError.operationFailed("Generated URL is empty")
    }

    // Optionally verify the URL is accessible
    let urlSession = URLSession.shared
    var request = URLRequest(url: publicUrl)
    request.httpMethod = "HEAD"
    request.timeoutInterval = 5

    let (_, response) = try await urlSession.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw DataError.operationFailed("Uploaded file not accessible")
    }

    return publicUrl.absoluteString
}
```

---

## Phase 3: Polish Fixes

### Fix #12: ProgressStoryViewModel - Add Offline Caching

**File:** `apps/ios/MindFriendApp/Features/ProgressStories/ProgressStoryViewModel.swift`  
**Issue:** No cached fallback

**Add caching methods:**
```swift
// MARK: - Offline Caching

private let cacheKey = "progress_story_cache"

private func cacheStory(_ story: WeeklyStory) {
    do {
        let data = try JSONEncoder().encode(story)
        UserDefaults.standard.set(data, forKey: cacheKey)
    } catch {
        logger.error("[ProgressStory] Failed to cache story: \(error)")
    }
}

private func getCachedStory() -> WeeklyStory? {
    guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
    return try? JSONDecoder().decode(WeeklyStory.self, from: data)
}

private func clearCache() {
    UserDefaults.standard.removeObject(forKey: cacheKey)
}
```

**Update loadStory to use cache as fallback:**
```swift
func loadStory() async {
    isLoading = true
    defer { isLoading = false }

    do {
        let story = try await withTimeout(timeoutSeconds: 30) {
            try await self.retryWithBackoff {
                try await self.dataService.getWeeklyStory(weekStart: self.weekStart)
            }
        }

        if let story = story {
            self.story = story
            cacheStory(story)
        } else {
            // Try to use cached story if available
            if let cached = getCachedStory() {
                self.story = cached
                logger.info("[ProgressStory] Using cached story")
            } else {
                // No cached story, generate new one
                await generateStory()
            }
        }
    } catch {
        // Network error - try cache
        if let cached = getCachedStory() {
            self.story = cached
            logger.info("[ProgressStory] Network error, using cached story")
        } else {
            logger.error("[ProgressStory] Failed to load story and no cache available: \(error)")
            self.error = .loadFailed(error.localizedDescription)
            showError = true
        }
    }
}
```

---

## Verification Steps

After applying these fixes, verify:

```swift
// Test 1: Transient network error retry
// Simulate network timeout, verify it retries 3x then fails

// Test 2: Long-running operation timeout
// Simulate slow Edge Function (>30s), verify timeout error shown

// Test 3: Circle load error
// Remove circle permissions temporarily, verify error shown with retry button

// Test 4: Loading timeout indicator
// Simulate slow network, wait 10+ seconds, verify "taking longer" message

// Test 5: Image upload validation
// Try uploading 10MB image, verify rejected with size error

// Test 6: Offline cache
// Load story, go offline, reload, verify cached story shown

// Test 7: Upsert validation
// Monitor Supabase logs, verify upsert errors are properly logged
```

---

## Summary

- **Critical Fixes:** 5 items (crashes, silent failures, infinite waits)
- **High Priority Fixes:** 6 items (data integrity, error feedback)
- **Polish Fixes:** 3 items (offline support, better validation)
- **Total Estimated Effort:** 4-6 hours
- **Complexity:** Medium (mostly defensive coding patterns)

All fixes maintain backward compatibility and don't require database schema changes.

