# Progress Stories Feature - Reliability Audit

**Date:** 2026-01-20  
**Scope:** Edge Function (`generate-weekly-story`) + iOS Views & ViewModel  
**Focus:** Error handling, graceful degradation, network resilience, loading states, crash prevention  
**Overall Score:** 5/10

---

## Executive Summary

The Progress Stories feature has moderate reliability but suffers from **critical gaps in error handling, network resilience, and crash prevention**. Key concerns:

1. **Edge Function lacks error boundaries** - Missing error handling in query chains leaves functions unprotected
2. **iOS ViewModel missing retry logic** - Single-attempt failures result in user-facing errors
3. **No timeout handling** - Long-running operations can hang indefinitely
4. **Silent failure in circle loading** - CircleShareSheet silently fails to load circles without user feedback
5. **Unsafe array access** - Uses `[safe: index]` pattern inconsistently
6. **No fallback data** - App crashes if Weekly Stories table has RLS issues or is empty
7. **Missing offline strategy** - No cached data when network unavailable
8. **Incomplete validation** - Date/timezone edge cases not handled

---

## Issues by Severity

### CRITICAL (Must Fix to 10/10)

#### 1. Edge Function: Uncaught Query Failures in Stat Aggregation
**Location:** `supabase/functions/generate-weekly-story/index.ts:341-398` (fetchWeeklyStats)
**Status:** ❌ CRITICAL

The `fetchWeeklyStats` function performs 4 database queries without error handling:
```typescript
// Line 341-346: No error handling for moods query
const { data: moods, count: moodCount } = await supabase
    .from("moods")
    .select("mood_score", { count: "exact" })
    .eq("user_id", userId)
    .gte("local_date", weekStart)
    .lt("local_date", weekEnd);

// Lines 367-375: Quest query - no error handling
const { count: questCount } = await supabase
    .from("quests")
    .select("id", { count: "exact" })
    .eq("user_id", userId)
    .eq("status", "completed")
    .gte("completed_at", weekStart + "T00:00:00Z")
    .lt("completed_at", weekEnd + "T00:00:00Z");
```

**Issue:** If any query fails (RLS denial, network error, malformed date), the function crashes without user-facing error.

**Impact:** 
- 500 error returned to iOS client
- User sees "Internal server error"
- No retry logic in iOS (see Critical Issue #2)
- Story generation fails silently

**Fix:** Add try-catch around each query or a wrapper function.

---

#### 2. iOS ViewModel: No Retry Logic on Failure
**Location:** `apps/ios/MindFriendApp/Features/ProgressStories/ProgressStoryViewModel.swift:54-71` (loadStory)
**Status:** ❌ CRITICAL

```swift
func loadStory() async {
    isLoading = true
    defer { isLoading = false }

    do {
        if let existingStory = try await dataService.getWeeklyStory(weekStart: weekStart) {
            story = existingStory
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

**Issue:** 
- No retry mechanism (transient network errors aren't recovered)
- Error is shown immediately without user action
- `generateStory()` is called even if fetch fails (cascading failure)

**Impact:** Temporary network blip = permanent error state. User must manually retry.

**Fix:** Implement exponential backoff retry (max 3 attempts) for transient errors.

---

#### 3. iOS ViewModel: Missing Timeout Protection
**Location:** `apps/ios/MindFriendApp/Features/ProgressStories/ProgressStoryViewModel.swift:81-96` (generateStory)
**Status:** ❌ CRITICAL

The Edge Function call has no timeout:
```swift
func generateStory() async {
    isLoading = true
    defer { isLoading = false }

    do {
        story = try await dataService.generateWeeklyStory(weekStart: weekStart)
        // ...
    } catch {
        // ...
    }
}
```

**Issue:** 
- If Edge Function hangs (e.g., database deadlock), `await` waits indefinitely
- User sees spinner forever
- No timeout in `SupabaseDataService.generateWeeklyStory()`

**Impact:** User trapped in loading state, must force-kill app.

**Fix:** Add `Task.sleep()` timeout wrapper (30 seconds max).

---

#### 4. CircleShareSheet: Silent Failure on Circle Load
**Location:** `apps/ios/MindFriendApp/Features/ProgressStories/CircleShareSheet.swift:235-245` (loadCircles)
**Status:** ❌ CRITICAL

```swift
private func loadCircles() async {
    isLoading = true
    defer { isLoading = false }

    do {
        circles = try await container.supabaseDataService.getCircles()
        if circles.count == 1 {
            selectedCircle = circles.first
        }
    } catch {
        // Silently fail - user can retry by dismissing and reopening
    }
}
```

**Issue:** 
- Error is completely silently ignored
- User sees empty circle list with no explanation
- No way to retry without closing/reopening sheet

**Impact:** User confused (no circles shown but they have circles) or unable to share.

**Fix:** Show error state or allow manual retry.

---

#### 5. ProgressStoryViewer: Unsafe Array Access
**Location:** `apps/ios/MindFriendApp/Features/ProgressStories/ProgressStoryViewModel.swift:104-108` (exportCard)
**Status:** ❌ CRITICAL

```swift
@MainActor
func exportCard(at index: Int) async -> UIImage? {
    guard let card = story?.cards[safe: index] else { return nil }
    // ...
}
```

**Issue:** Uses `[safe: index]` subscript which is defined in `AssessmentFlowView.swift` (line 377), but:
1. Subscript may not be globally available (not in extension on Array)
2. If `story.cards` is empty, `[safe: index]` returns nil but code continues silently
3. No bounds validation before export

**Impact:** Potential crash if safe subscript isn't available, or silent failure.

**Fix:** Use standard bounds check: `guard index >= 0, index < cards.count else { return nil }`

---

#### 6. Edge Function: Missing Timeout on Profile/Data Queries
**Location:** `supabase/functions/generate-weekly-story/index.ts:231-246` (generateStoryCards)
**Status:** ❌ HIGH

The profile query has no timeout or error handling:
```typescript
const { data: profileData } = await supabase
    .from("profiles")
    .select("id, display_name, wellness_focus, current_streak_days")
    .eq("id", userId)
    .single();
```

**Issue:** 
- `.single()` throws if 0 or 2+ rows (bad data state)
- No error handling for this throw
- No timeout if query hangs

**Impact:** Story generation fails if profile row is missing or duplicated.

**Fix:** Add error handling: `const { data: profileData, error } = ...` and check error.

---

### HIGH PRIORITY (Should Fix for 10/10)

#### 7. SupabaseDataService: Missing Network Error Translation
**Location:** `apps/ios/MindFriendApp/Networking/Services/SupabaseDataService.swift:3817-3858` (generateWeeklyStory)
**Status:** ❌ HIGH

```swift
func generateWeeklyStory(weekStart: String) async throws -> WeeklyStory {
    let session = try await supabase.auth.session

    let response: GenerateWeeklyStoryResponse = try await supabase.functions.invoke(
        "generate-weekly-story",
        options: .init(
            method: .post,
            headers: ["Authorization": "Bearer \(session.accessToken)"],
            body: ["weekStart": weekStart]
        )
    )
    // ...
}
```

**Issue:** 
- No handling for specific HTTP errors (500, 503, timeout)
- Generic throw of `response.success` check
- No network error classification (transient vs. permanent)

**Impact:** Caller can't distinguish "try again" errors from "give up" errors.

**Fix:** Map Supabase errors to `APIError` cases: `.networkError()`, `.serverError()`.

---

#### 8. ProgressStoryViewer: Share Sheet Error Not Propagated
**Location:** `apps/ios/MindFriendApp/Features/ProgressStories/CircleShareSheet.swift:260-267` (postToCircle)
**Status:** ❌ HIGH

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
}
```

**Issue:** 
- Errors from `shareToCircle` are handled in ViewModel but UI doesn't know if post succeeded
- No callback or state to confirm success
- User has no feedback (success toast hardcoded in ViewModel)

**Impact:** User unsure if circle post was successful or failed.

**Fix:** Use `@Published` state in CircleShareSheet or accept completion callback.

---

#### 9. Edge Function: Upsert Failure Not Reported
**Location:** `supabase/functions/generate-weekly-story/index.ts:217-227`
**Status:** ❌ HIGH

```typescript
const { error: upsertError } = await supabaseAuth
    .from("weekly_stories")
    .upsert(
        {
            user_id: user.id,
            week_start: body.weekStart,
            cards: cards,
            updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id,week_start" },
    );

if (upsertError) {
    console.error("Upsert error:", upsertError);
    // Don't fail the request - still return cards
}
```

**Issue:** 
- Upsert failure is silently logged but request succeeds (200 OK)
- iOS client thinks story was persisted but it wasn't
- Next week, if load fails, user loses story

**Impact:** Data persistence assumption violated; user story lost.

**Fix:** Either throw error or ensure transient errors are retried.

---

#### 10. ProgressStoryViewer: No Loading Timeout Indicator
**Location:** `apps/ios/MindFriendApp/Features/ProgressStories/ProgressStoryViewer.swift:30-51`
**Status:** ❌ HIGH

```swift
if vm.isLoading && vm.story == nil {
    loadingView
} else if let story = vm.story, !story.cards.isEmpty {
    storyContentView(story: story, vm: vm)
// ...
```

Loading view shows spinner indefinitely:
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
    }
}
```

**Issue:** No timeout message if spinner shows for >10 seconds.

**Impact:** User thinks app is frozen.

**Fix:** Show "Loading is taking longer than expected" after 10 seconds.

---

#### 11. SupabaseDataService: Upload Failure Not Validated
**Location:** `apps/ios/MindFriendApp/Networking/Services/SupabaseDataService.swift:3888-3902` (uploadStoryCardImage)
**Status:** ❌ HIGH

```swift
func uploadStoryCardImage(imageData: Data, weekStart: String, cardIndex: Int) async throws -> String {
    let uid = try userId
    let filename = "story_\(weekStart)_card\(cardIndex).png"
    let path = "\(uid.uuidString)/stories/\(filename)"

    _ = try await supabase.storage
        .from("user-content")
        .upload(path, data: imageData, options: .init(contentType: "image/png", upsert: true))

    let publicUrl = supabase.storage
        .from("user-content")
        .getPublicURL(path: path)

    return publicUrl.absoluteString
}
```

**Issue:** 
- Upload result is discarded (`_ =`)
- No check if file actually uploaded
- `getPublicURL()` called even if upload failed
- No size validation (could upload 100MB image)

**Impact:** Share fails if storage upload fails but error isn't caught.

**Fix:** Check upload result, add size limit (max 5MB), validate URL.

---

### MEDIUM PRIORITY (Nice to Have)

#### 12. ProgressStoryViewModel: Missing Offline Strategy
**Status:** ⚠️ MEDIUM

**Issue:** 
- No cached story from previous week
- If offline when loading, user sees empty state
- No "last known good" fallback

**Fix:** Cache latest story in UserDefaults on successful load.

---

#### 13. Edge Function: Date Validation Edge Cases
**Location:** `supabase/functions/generate-weekly-story/index.ts:177-192`
**Status:** ⚠️ MEDIUM

```typescript
const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
if (!dateRegex.test(body.weekStart)) {
    // ...
}

const weekStartDate = new Date(body.weekStart + "T00:00:00Z");
if (weekStartDate.getUTCDay() !== 1) {
    // ...
}
```

**Issue:** 
- Regex allows invalid dates like "2026-99-99"
- Timezone handling assumes UTC but user may be in different zone
- No leap-year validation

**Fix:** Use explicit date parsing or validation library.

---

#### 14. CircleShareSheet: No Fallback UI for Empty Circles
**Location:** `apps/ios/MindFriendApp/Features/ProgressStories/CircleShareSheet.swift:110-121`
**Status:** ⚠️ MEDIUM

```swift
} else if circles.isEmpty {
    Text("You're not in any circles yet.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
```

**Issue:** User can't create circle from here; must go elsewhere then return.

**Fix:** Add button: "Create a Circle" → navigates to circles tab.

---

---

## Summary Table of Issues

| # | Issue | File | Severity | Impact |
|----|-------|------|----------|--------|
| 1 | Uncaught query failures in stat aggregation | Edge Function | CRITICAL | 500 error, story generation fails |
| 2 | No retry logic on failure | ViewModel | CRITICAL | Transient errors = permanent failure |
| 3 | Missing timeout protection | ViewModel | CRITICAL | User trapped in loading state |
| 4 | Silent failure on circle load | CircleShareSheet | CRITICAL | Confusing empty state, no feedback |
| 5 | Unsafe array access | ViewModel | CRITICAL | Potential crash |
| 6 | Missing profile query error handling | Edge Function | HIGH | Story fails if profile row is missing |
| 7 | No network error translation | DataService | HIGH | Can't distinguish transient vs. permanent errors |
| 8 | Share sheet error not propagated | CircleShareSheet | HIGH | User unsure if post succeeded |
| 9 | Upsert failure silently ignored | Edge Function | HIGH | Data persistence violated |
| 10 | No loading timeout indicator | Viewer | HIGH | User thinks app frozen |
| 11 | Upload failure not validated | DataService | HIGH | Storage failure not caught |
| 12 | No offline strategy | ViewModel | MEDIUM | No cached fallback |
| 13 | Date validation edge cases | Edge Function | MEDIUM | Invalid dates may pass |
| 14 | No fallback UI for empty circles | CircleShareSheet | MEDIUM | Poor UX for new users |

---

## Recommendations to Reach 10/10

### Phase 1: Fix Critical Issues (Crashes + Silent Failures)
1. Wrap all Edge Function DB queries in try-catch
2. Add retry logic to ViewModel (exponential backoff, max 3 tries)
3. Implement timeout wrapper (30s) in ViewModel
4. Show error in CircleShareSheet on load failure
5. Fix array access bounds checking

### Phase 2: Fix High Priority Issues (Data Integrity + UX)
6. Translate Supabase errors to classification (transient/permanent)
7. Propagate share success feedback to UI
8. Validate upsert succeeded or throw
9. Show "taking longer" message after 10 seconds
10. Add image size validation + upload verification

### Phase 3: Polish (Medium Priority)
11. Implement offline cache (UserDefaults)
12. Improve date validation
13. Add circle creation shortcut in share sheet

---

## Testing Checklist

- [ ] Simulate Edge Function DB query timeout
- [ ] Simulate transient network error during story load
- [ ] Simulate storage upload failure
- [ ] Test with user having no circles
- [ ] Test with invalid weekStart date
- [ ] Test with missing profile row
- [ ] Verify retry happens 3x then fails
- [ ] Verify timeout shows after 10 seconds
- [ ] Verify exported image is <5MB
- [ ] Verify offline mode shows cached story

