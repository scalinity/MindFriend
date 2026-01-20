# Photo Mood Logging - Implementation Decisions

## 2026-01-19: Architectural Decisions for MVP

### Decision 1: No Client-Side Encryption (Security vs Complexity Trade-off)

**Decision:** Remove PV-01 "encrypted at rest" claim. Use Supabase Storage's default access-controlled private bucket with RLS policies instead of client-side encryption.

**Rationale:**

- Supabase Storage uses standard S3-compatible storage with server-side access control
- Client-side encryption would require:
  - Key management infrastructure (where to store encryption keys?)
  - Key derivation from user password (PBKDF2/Argon2)
  - Encrypted blob storage (can't generate thumbnails server-side)
  - Complex key recovery flow if user forgets password
- This is P3 "Nice to Have" feature - encryption complexity would delay MVP
- RLS policies + private bucket + signed URLs provide adequate access control
- Photos are still inaccessible to other users via database-level RLS

**Alternatives Considered:**

- Option A: Client-side AES-256-GCM before upload → Too complex for MVP
- Option B: Server-side encryption with Supabase → Not supported by platform
- Option C: Access-controlled private bucket (SELECTED)

**Implications:**

- Update privacy documentation to state "access-controlled" not "encrypted"
- Photos accessible to Supabase administrators (standard SaaS trust model)
- Post-MVP: Can add E2E encryption as premium privacy feature
- Document in PROGRESS.md and decisions.md

---

### Decision 2: Client-Side EXIF Stripping (Privacy)

**Decision:** Implement EXIF metadata stripping in Swift using ImageIO framework before upload.

**Rationale:**

- Privacy-critical: GPS, device model, timestamps must be removed
- Client-side stripping prevents sensitive data from ever leaving device
- iOS ImageIO framework provides native support via CGImageDestination
- Preserves image orientation while removing all other metadata

**Implementation:**

```swift
func stripExifAndCompress(image: UIImage, quality: CGFloat) -> Data? {
    guard let cgImage = image.cgImage else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data as CFMutableData,
        "public.jpeg" as CFString,
        1,
        nil
    ) else { return nil }

    // Only include compression quality, exclude all EXIF
    let properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: quality
    ]

    CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
    return data as Data
}
```

**Alternatives Considered:**

- Option A: Strip server-side in Edge Function → Metadata already exposed in transit
- Option B: Strip client-side (SELECTED) → Privacy-first approach
- Option C: User opt-in for EXIF preservation → Adds complexity, most users want privacy

**Implications:**

- Original photo timestamps lost (use logged_at instead)
- Image orientation preserved via CGImage properties
- Test with EXIF-rich sample photos

---

### Decision 3: Caption Length Limit (500 characters)

**Decision:** Enforce 500-character maximum for captions with CHECK constraint and client-side validation.

**Rationale:**

- Prevents database bloat and UI rendering issues
- 500 chars ≈ 3-4 sentences, sufficient for context
- Matches Twitter's extended character limit (familiar UX)
- CHECK constraint provides server-side enforcement

**Implementation:**

```sql
ALTER TABLE photo_moods
ADD CONSTRAINT caption_length_check
CHECK (caption IS NULL OR LENGTH(caption) <= 500);
```

**Alternatives Considered:**

- Option A: Unbounded TEXT field → Database/UX risk
- Option B: 280 chars (Twitter classic) → Too short for journaling
- Option C: 500 chars (SELECTED) → Sweet spot

**Implications:**

- Show character counter in UI (e.g., "245/500")
- Trim whitespace before saving
- Truncate on paste if >500 chars

---

### Decision 4: Maximum 5 Emotion Tags

**Decision:** Limit emotion tag selection to 5 tags per photo mood with client-side validation.

**Rationale:**

- Prevents "select all" behavior that dilutes meaning
- 5 tags sufficient to capture nuanced emotional state
- Improves UI/UX (avoids cluttered tag display)
- Reduces database array size

**Implementation:**

```swift
// In PhotoMoodCaptureView
var canAddMoreEmotions: Bool {
    selectedEmotions.count < 5
}
```

**Alternatives Considered:**

- Option A: Unlimited tags → Too noisy, less meaningful
- Option B: Single tag → Too restrictive for complex moods
- Option C: 3 tags → Too few for nuanced emotions
- Option D: 5 tags (SELECTED) → Balanced

**Implications:**

- Show "X/5 emotions selected" in UI
- Disable unselected chips when limit reached
- Alert: "Maximum 5 emotions per mood" if user taps 6th

---

### Decision 5: Signed URL Refresh on Error (Transparent)

**Decision:** Automatically refresh expired signed URLs (1-hour expiry) by retrying with new URL on 401/403 errors.

**Rationale:**

- User should never see "URL expired" errors
- Gallery thumbnails expire after 1 hour if user browses long session
- Transparent retry maintains seamless UX
- Supabase SDK generates URLs instantly (<50ms)

**Implementation:**

```swift
func loadPhotoUrl(for photoMood: PhotoMood) async throws -> URL {
    do {
        return try await photoMoodService.getPhotoUrl(for: photoMood)
    } catch let error as URLError where error.code == .badServerResponse {
        // Retry once with fresh signed URL
        return try await photoMoodService.getPhotoUrl(for: photoMood)
    }
}
```

**Alternatives Considered:**

- Option A: Show error to user → Poor UX
- Option B: Extend expiry to 24 hours → Security risk for shared devices
- Option C: Auto-refresh on error (SELECTED) → Best UX

**Implications:**

- Add retry logic in AsyncImage loading
- Cache URLs in memory for 50 minutes
- Log errors if retry also fails

---

### Decision 6: No Offline Support (MVP Scope)

**Decision:** Block photo mood creation when offline. Show clear "No internet connection" message.

**Rationale:**

- Offline upload queue requires background task infrastructure
- Complexity: Resume interrupted uploads, handle errors, sync state
- MVP priority is happy-path functionality
- Most mood logging happens with active internet (after events)

**Implementation:**

```swift
func createPhotoMood(...) async throws -> PhotoMood {
    guard NetworkMonitor.shared.isConnected else {
        throw PhotoMoodError.networkRequired
    }
    // ... proceed with upload
}
```

**Alternatives Considered:**

- Option A: Queue uploads for background retry → Too complex for MVP
- Option B: Block when offline (SELECTED) → Clear, simple
- Option C: Allow offline capture, manual retry → Confusing state management

**Implications:**

- Show network status indicator during upload
- Alert: "Internet connection required to save photo moods"
- Post-MVP: Can add upload queue if user feedback requests it

---

### Decision 7: Client-Side Mood Filtering (Memory-Efficient)

**Decision:** Implement PM-07 mood filtering client-side by filtering loaded `photoMoods` array in memory.

**Rationale:**

- Gallery loads 50 moods initially (small dataset)
- Client-side filter responds instantly (no network round-trip)
- Reduces server queries and complexity
- Users rarely have >200 photo moods (fits in memory)

**Implementation:**

```swift
var filteredPhotoMoods: [PhotoMood] {
    guard let filter = selectedMoodFilter else { return photoMoods }
    return photoMoods.filter { $0.moodScore == filter }
}
```

**Alternatives Considered:**

- Option A: Server-side SQL filtering → Extra queries, slower UX
- Option B: Client-side filtering (SELECTED) → Fast, simple
- Option C: Remove filtering entirely → Reduces feature value

**Implications:**

- Filter applies only to loaded moods (not entire history)
- Loading more moods respects active filter
- Simple implementation, no schema changes

---

### Decision 8: Camera/Library Permission Denial Flows

**Decision:** Show iOS system alerts with Settings deep link when permissions denied.

**Rationale:**

- Standard iOS pattern for permission requests
- Users familiar with Settings deep link flow
- Clear call-to-action to resolve permission issue

**Implementation:**

```swift
if cameraStatus == .denied {
    showAlert(
        title: "Camera Access Needed",
        message: "MindFriend needs camera access to capture photos. Go to Settings > Privacy > Camera to enable.",
        primaryButton: .default(Text("Open Settings")) {
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        },
        secondaryButton: .cancel()
    )
}
```

**Alternatives Considered:**

- Option A: Silent failure → Confusing UX
- Option B: In-app permission tutorial → Too much friction
- Option C: System alert with Settings link (SELECTED) → iOS standard

**Implications:**

- Request permissions on first use (lazy)
- Don't block onboarding with permission requests
- Explain value before requesting ("Add photos to your moods")

---

### Decision 9: Delete Operation Atomicity (Storage-First)

**Decision:** Delete storage files first, then database record. Implement cleanup cron job for orphaned files.

**Rationale:**

- Orphaned storage files cost money, orphaned DB records are harmless
- If storage delete fails, keep DB record intact (user can retry)
- If DB delete fails after storage delete, orphan cleanup cron removes files
- Idempotent: Re-running delete is safe

**Implementation Order:**

1. Delete full photo from storage
2. Delete thumbnail from storage
3. Delete database record
4. Update local `photoMoods` array

**Alternatives Considered:**

- Option A: DB-first delete → Orphaned storage files (worse)
- Option B: Storage-first delete (SELECTED) → Orphaned files auto-cleanup
- Option C: Two-phase commit → Over-engineered for MVP

**Implications:**

- Create Edge Function cron job: "cleanup-orphaned-photos" (daily)
- Log errors if storage delete fails (alert user to retry)
- Acceptable eventual consistency

---

### Decision 10: Photo Compression Strategy

**Decision:** Auto-compress photos to <5MB using iterative quality reduction (0.8 → 0.6 → 0.4) until size acceptable.

**Rationale:**

- Supabase Storage has 5MB hard limit per file
- Modern iPhone photos can be 10-20MB at full quality
- Iterative compression maintains best possible quality under limit
- User never sees "file too large" error

**Implementation:**

```swift
func compressToLimit(image: UIImage, maxBytes: Int = 5_242_880) -> Data? {
    let qualities: [CGFloat] = [0.8, 0.6, 0.4, 0.2]
    for quality in qualities {
        if let data = stripExifAndCompress(image: image, quality: quality),
           data.count <= maxBytes {
            return data
        }
    }
    return nil // Failed to compress under limit
}
```

**Alternatives Considered:**

- Option A: Reject if >5MB → Frustrating UX
- Option B: Fixed 0.8 quality (may exceed limit) → Fails for large photos
- Option C: Iterative compression (SELECTED) → Best quality possible

**Implications:**

- Very large photos may compress to 0.2 quality (visible artifacts)
- Show compression quality in logs for debugging
- If still >5MB after 0.2 quality, show error: "Photo too large. Try a different photo."

---

## Out of Scope for MVP

The following features are explicitly deferred to post-MVP:

1. **AI Mood Suggestion (PM-09)** - Requires AI model evaluation, opt-in flow, quota management
2. **Share to Circles (PM-10)** - Requires circle feed integration, privacy controls
3. **Local-Only Mode (PV-04)** - Requires offline storage architecture, sync conflicts
4. **Face ID Gallery Protection** - Nice-to-have privacy feature, not blocking
5. **Photo Editing/Filters** - Scope creep, not in original spec
6. **Signed URL Caching** - Optimization, not critical for MVP
7. **Orphan Cleanup Cron** - Can be manual for MVP, automate post-launch

Schema fields for PM-09 and PM-10 included for future-proofing, but no UI or Edge Functions implemented.

---

## Summary

**MVP Implementation will include:**

- ✅ Photo capture (camera/library) with permission handling
- ✅ EXIF stripping for privacy
- ✅ Mood score (1-5) + optional caption (max 500 chars) + emotion tags (max 5)
- ✅ Photo upload to private Supabase Storage bucket
- ✅ Thumbnail generation (200x200px)
- ✅ Gallery view with client-side mood filtering
- ✅ Photo mood detail view with metadata
- ✅ Delete individual photo mood
- ✅ Delete all photo moods (privacy feature)
- ✅ RLS policies for privacy enforcement

**Explicitly excluded from MVP:**

- ❌ Client-side encryption (access-controlled instead)
- ❌ Offline upload queue
- ❌ AI mood suggestions
- ❌ Circle sharing
- ❌ Local-only mode
- ❌ Face ID protection

All decisions prioritize shipping a functional, privacy-respecting photo mood feature that integrates cleanly with existing MindFriend architecture.
