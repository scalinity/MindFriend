# Partner Mode UX Implementation Plan

**Architect:** Claude Opus 4.5  
**Date:** 2026-01-20  
**Spec:** `/Users/danny/Documents/Codez/Apps/MindFriend/.claude/specs/partner-mode-ux-spec.md`  
**Status:** Ready for Implementation

---

## Executive Summary

Implement Partner Mode UX to enable users to connect with a partner, share wellness data (moods, exercises), and complete couples exercises together. The system reuses existing buddy infrastructure (`buddy_relationships` table + RPCs) for invite/accept flows, while adding new `partner_links` table for sharing settings and `couples_exercises`/`couples_exercise_sessions` for shared activities.

**Key Design Decisions:**
- Reuse existing buddy invite system (`generate_buddy_code()`, `accept_buddy_invite()` RPCs)
- Polling-based sync (30s interval) instead of Realtime subscriptions
- Bidirectional column mapping in `partner_links` for per-user sharing settings
- Optimistic UI updates with database as source of truth
- Rate limiting: 10 invites/day (DB-enforced), 1 encouragement/hour (local)

---

## Change Impact

### Files to Create

| File | Purpose | Dependencies | Lines (Est.) |
|------|---------|--------------|--------------|
| `Features/Partner/PartnerModeView.swift` | Main container - routes to onboarding or dashboard | PartnerModeViewModel | 120 |
| `Features/Partner/PartnerModeViewModel.swift` | State management, business logic | SupabaseDataService | 450 |
| `Features/Partner/PartnerOnboardingView.swift` | Tabbed UI: Send Invite / Enter Code | InviteCodeDisplay, CodeEntryField | 280 |
| `Features/Partner/AcceptInviteView.swift` | Code entry + validation flow | CodeEntryField | 180 |
| `Features/Partner/PartnerDashboardView.swift` | Main dashboard with partner data | Status/Mood/Quest cards | 320 |
| `Features/Partner/PartnerSharingSettingsView.swift` | Toggle sharing preferences | SharingToggleRow | 200 |
| `Features/Partner/SharedExercisesView.swift` | List of couples exercises | None | 240 |
| `Features/Partner/SharedExerciseSessionView.swift` | Active session UI (P2) | None | 280 |
| `Features/Partner/EncouragementPickerSheet.swift` | Select encouragement type | None | 150 |
| `Features/Partner/Components/PartnerStatusCard.swift` | Partner info display | None | 140 |
| `Features/Partner/Components/SharedMoodCard.swift` | Mood history display | None | 160 |
| `Features/Partner/Components/SharedQuestCard.swift` | Quest status display | None | 130 |
| `Features/Partner/Components/InviteCodeDisplay.swift` | Code display with copy/share | None | 120 |
| `Features/Partner/Components/CodeEntryField.swift` | 6-char code input | None | 180 |
| `Features/Partner/Components/PartnerPlaceholder.swift` | "Not shared" placeholder | None | 80 |
| `Features/Partner/Components/SharingToggleRow.swift` | Individual toggle control | None | 100 |
| `MindFriendAppTests/PartnerModeViewModelTests.swift` | Unit tests | PartnerModeViewModel | 600 |

**Total: 17 files, ~3,910 lines**

### Files to Modify

| File | Change Type | Description | Risk |
|------|-------------|-------------|------|
| `Networking/Services/SupabaseDataService.swift` | Add Methods | Add 13 new partner-related methods | Low |
| `Core/Models/CouplesModels.swift` | Extend | Add `PartnerLink` extension methods | Low |
| `Features/Profile/SettingsView.swift` | Add Link | NavigationLink to PartnerModeView | Low |
| `App/MindFriendApp.swift` | Add Handler | Deep link handler for `mindfriend://partner/accept?code=XXX` | Low |
| `App/AppState.swift` | Add Property | `pendingPartnerCode: String?` for deep link routing | Low |

### Files to Reference (No Changes)

| File | Usage |
|------|-------|
| `Features/Buddy/InviteBuddySheet.swift` | Reference for code UI patterns |
| `Features/Home/HomeView.swift` | Reference for BuddyWidget polling pattern |
| `Core/Models.swift` | Use existing `BuddyRelationship`, `BuddyEncouragement` |

---

## Component Design

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         PartnerModeView                         │
│  (Container - decides: onboarding vs dashboard based on state) │
└────────────┬───────────────────────────────┬────────────────────┘
             │                               │
    ┌────────▼────────┐            ┌────────▼────────────────┐
    │  Onboarding     │            │  Dashboard              │
    │  (no partner)   │            │  (has active partner)   │
    └────────┬────────┘            └────────┬────────────────┘
             │                               │
    ┌────────▼────────────┐         ┌───────▼──────────────┐
    │ Send Invite Tab     │         │ PartnerStatusCard    │
    │ ├─ InviteCodeDisplay│         │ SharedMoodCard       │
    │ └─ Share Actions    │         │ SharedQuestCard      │
    │                     │         │ SharedExercisesLink  │
    │ Enter Code Tab      │         │ EncouragementButton  │
    │ ├─ CodeEntryField   │         │ SharingSettings Link │
    │ └─ Accept Button    │         └──────────────────────┘
    └─────────────────────┘
```

### Component Hierarchy

```
PartnerModeView
├── @StateObject viewModel: PartnerModeViewModel
├── NavigationStack
│   ├── if viewModel.partnerState == .noPartner:
│   │   └── PartnerOnboardingView(viewModel: viewModel)
│   │       ├── TabView
│   │       │   ├── SendInviteTab
│   │       │   │   ├── InviteCodeDisplay(code: viewModel.inviteCode)
│   │       │   │   └── ShareButton
│   │       │   └── EnterCodeTab
│   │       │       ├── CodeEntryField(code: $viewModel.codeInput)
│   │       │       └── AcceptButton
│   │       └── .onAppear { viewModel.generateInviteCode() }
│   │
│   └── if viewModel.partnerState == .hasPartner(let info):
│       └── PartnerDashboardView(viewModel: viewModel, partnerInfo: info)
│           ├── PartnerStatusCard(info: info)
│           ├── if info.isSharingMood:
│           │   └── SharedMoodCard(moods: viewModel.partnerMoods)
│           │   else:
│           │   └── PartnerPlaceholder(type: "mood")
│           ├── if info.isSharingExercises:
│           │   └── SharedQuestCard(quest: viewModel.partnerQuest)
│           │   else:
│           │   └── PartnerPlaceholder(type: "quest")
│           ├── NavigationLink(destination: SharedExercisesView)
│           ├── EncouragementButton { viewModel.showEncouragementPicker = true }
│           └── NavigationLink(destination: PartnerSharingSettingsView)
│               └── .sheet(isPresented: $viewModel.showEncouragementPicker)
│                   └── EncouragementPickerSheet(onSelect: viewModel.sendEncouragement)
└── .onAppear { viewModel.loadPartnerData() }
```

---

## Data Models

### New Models (Add to CouplesModels.swift)

```swift
// MARK: - PartnerLink Extensions

extension PartnerLink {
    /// Returns current user's sharing settings
    func mySharingSettings(for userId: UUID) -> SharingSettings {
        if userId == userId1 {
            return SharingSettings(shareMood: user1ShareMood, shareExercises: user1ShareExercises)
        } else {
            return SharingSettings(shareMood: user2ShareMood, shareExercises: user2ShareExercises)
        }
    }
    
    /// Returns partner's sharing settings (what they share with me)
    func partnerSharingSettings(for userId: UUID) -> SharingSettings {
        if userId == userId1 {
            return SharingSettings(shareMood: user2ShareMood, shareExercises: user2ShareExercises)
        } else {
            return SharingSettings(shareMood: user1ShareMood, shareExercises: user1ShareExercises)
        }
    }
    
    /// Returns partner's user ID
    func partnerId(for userId: UUID) -> UUID? {
        if userId == userId1 { return userId2 }
        if userId == userId2 { return userId1 }
        return nil
    }
}

// MARK: - View Models

struct SharingSettings: Equatable {
    var shareMood: Bool
    var shareExercises: Bool
}

struct PartnerInfo: Equatable {
    let partnerId: UUID
    let partnerName: String
    let partnerStreak: Int
    let hasCompletedToday: Bool
    let lastActive: Date
    let isSharingMood: Bool
    let isSharingExercises: Bool
}

enum PartnerState: Equatable {
    case loading
    case noPartner
    case hasPartner(PartnerInfo)
}
```

---

## Service Methods (Add to SupabaseDataService.swift)

### Location in File

Add after existing buddy methods (~line 1972, after `getPendingBuddyInvites()`)

### Method Signatures

```swift
// MARK: - Partner Links (Couples Mode)

/// Get active partner link for current user
/// Returns: PartnerLink if user has active partner, nil if no partner
/// Throws: DataError.notAuthenticated if not logged in
func getActivePartnerLink() async throws -> PartnerLink? {
    let currentUserId = try userId
    
    let links: [PartnerLink] = try await supabase
        .from("partner_links")
        .select()
        .or("user_id_1.eq.\(currentUserId),user_id_2.eq.\(currentUserId)")
        .eq("status", value: "active")
        .limit(1)
        .execute()
        .value
    
    return links.first
}

/// Update current user's sharing settings
/// Parameters:
///   - shareMood: Whether to share mood data with partner
///   - shareExercises: Whether to share exercise data with partner
/// Throws: CouplesModeError.notPartnered if no active partner
func updatePartnerSharingSettings(shareMood: Bool, shareExercises: Bool) async throws {
    guard let link = try await getActivePartnerLink() else {
        throw CouplesModeError.notPartnered
    }
    
    let currentUserId = try userId
    let isUser1 = link.userId1 == currentUserId
    
    let updateData: [String: AnyEncodable] = isUser1
        ? ["user_1_share_mood": AnyEncodable(shareMood),
           "user_1_share_exercises": AnyEncodable(shareExercises)]
        : ["user_2_share_mood": AnyEncodable(shareMood),
           "user_2_share_exercises": AnyEncodable(shareExercises)]
    
    try await supabase
        .from("partner_links")
        .update(updateData)
        .eq("id", value: link.id)
        .execute()
}

/// End current partnership
/// Throws: CouplesModeError.notPartnered if no active partner
func endPartnership() async throws {
    guard let link = try await getActivePartnerLink() else {
        throw CouplesModeError.notPartnered
    }
    
    try await supabase
        .from("partner_links")
        .update([
            "status": AnyEncodable("ended"),
            "ended_at": AnyEncodable(Date())
        ])
        .eq("id", value: link.id)
        .execute()
}

/// Get partner's mood history (respects sharing settings)
/// Parameters:
///   - partnerId: UUID of partner user
/// Returns: Array of MoodEntry for past 7 days
/// Throws: CouplesModeError.partnerNotSharing if partner hasn't enabled mood sharing
func getPartnerMoodHistory(partnerId: UUID) async throws -> [MoodEntry] {
    guard let link = try await getActivePartnerLink() else {
        throw CouplesModeError.notPartnered
    }
    
    let currentUserId = try userId
    let partnerSettings = link.partnerSharingSettings(for: currentUserId)
    
    guard partnerSettings.shareMood else {
        throw CouplesModeError.partnerNotSharing
    }
    
    // Get moods from past 7 days
    let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withFullDate]
    
    let startDate = dateFormatter.string(from: sevenDaysAgo)
    let endDate = dateFormatter.string(from: Date())
    
    let moods: [DBMood] = try await supabase
        .from("moods")
        .select()
        .eq("user_id", value: partnerId)
        .gte("local_date", value: startDate)
        .lte("local_date", value: endDate)
        .order("local_date", ascending: false)
        .execute()
        .value
    
    return moods.map { $0.toMoodEntry() }
}

/// Get partner's today's quest status (respects sharing settings)
/// Parameters:
///   - partnerId: UUID of partner user
/// Returns: Quest if partner has quest today, nil otherwise
/// Throws: CouplesModeError.partnerNotSharing if partner hasn't enabled exercise sharing
func getPartnerQuestStatus(partnerId: UUID) async throws -> Quest? {
    guard let link = try await getActivePartnerLink() else {
        throw CouplesModeError.notPartnered
    }
    
    let currentUserId = try userId
    let partnerSettings = link.partnerSharingSettings(for: currentUserId)
    
    guard partnerSettings.shareExercises else {
        throw CouplesModeError.partnerNotSharing
    }
    
    let today = ISO8601DateFormatter().string(from: Date()).prefix(10) // YYYY-MM-DD
    
    let quests: [DBQuest] = try await supabase
        .from("quests")
        .select()
        .eq("user_id", value: partnerId)
        .eq("local_date", value: String(today))
        .limit(1)
        .execute()
        .value
    
    return quests.first?.toQuest()
}

/// Get list of couples exercises
/// Returns: Array of CouplesExercise
/// Throws: DataError on network failure
func getCouplesExercises() async throws -> [CouplesExercise] {
    let exercises: [CouplesExercise] = try await supabase
        .from("couples_exercises")
        .select()
        .order("type")
        .order("name")
        .execute()
        .value
    
    return exercises
}

/// Start a couples exercise session
/// Parameters:
///   - exerciseId: UUID of the exercise to start
/// Returns: CouplesExerciseSession
/// Throws: CouplesModeError.notPartnered, CouplesModeError.exercisePremiumOnly
func startCouplesSession(exerciseId: UUID) async throws -> CouplesExerciseSession {
    guard let link = try await getActivePartnerLink() else {
        throw CouplesModeError.notPartnered
    }
    
    guard let partnerId = link.partnerId(for: try userId) else {
        throw CouplesModeError.notPartnered
    }
    
    // Check if exercise requires premium
    let exercises: [CouplesExercise] = try await supabase
        .from("couples_exercises")
        .select()
        .eq("id", value: exerciseId)
        .execute()
        .value
    
    guard let exercise = exercises.first else {
        throw CouplesModeError.notFound
    }
    
    if exercise.requiresPremium {
        // TODO: Check if either user has premium entitlement
        // For MVP, throw error if premium required
        throw CouplesModeError.exercisePremiumOnly
    }
    
    let currentUserId = try userId
    let isUser1 = link.userId1 == currentUserId
    
    let insertData: [String: AnyEncodable] = [
        "partner_link_id": AnyEncodable(link.id),
        "exercise_id": AnyEncodable(exerciseId),
        "user_id_1": AnyEncodable(isUser1 ? currentUserId : partnerId),
        "user_id_2": AnyEncodable(isUser1 ? partnerId : currentUserId),
        "status": AnyEncodable("pending"),
        "user_1_progress_percent": AnyEncodable(0),
        "user_2_progress_percent": AnyEncodable(0),
        "started_at": AnyEncodable(Date()),
        "last_activity_at": AnyEncodable(Date())
    ]
    
    let session: CouplesExerciseSession = try await supabase
        .from("couples_exercise_sessions")
        .insert(insertData)
        .select()
        .single()
        .execute()
        .value
    
    // Send notification to partner
    do {
        try await supabase.functions.invoke("send-notification", options: .init(body: [
            "type": "couples_exercise_invite",
            "recipientId": partnerId.uuidString,
            "data": ["sessionId": session.id.uuidString, "exerciseName": exercise.name]
        ]))
    } catch {
        Log.data.warning("[Data] Failed to send exercise invite notification: \(error)")
    }
    
    return session
}

/// Join a pending couples exercise session
/// Parameters:
///   - sessionId: UUID of the session to join
/// Returns: Updated CouplesExerciseSession
/// Throws: CouplesModeError.sessionExpired, CouplesModeError.notFound
func joinCouplesSession(sessionId: UUID) async throws -> CouplesExerciseSession {
    let sessions: [CouplesExerciseSession] = try await supabase
        .from("couples_exercise_sessions")
        .select()
        .eq("id", value: sessionId)
        .execute()
        .value
    
    guard let session = sessions.first else {
        throw CouplesModeError.notFound
    }
    
    // Check if session expired (24 hours)
    if Date().timeIntervalSince(session.startedAt) > 24 * 3600 {
        throw CouplesModeError.sessionExpired
    }
    
    // Update status to in_progress
    let updatedSession: CouplesExerciseSession = try await supabase
        .from("couples_exercise_sessions")
        .update([
            "status": AnyEncodable("in_progress"),
            "last_activity_at": AnyEncodable(Date())
        ])
        .eq("id", value: sessionId)
        .select()
        .single()
        .execute()
        .value
    
    return updatedSession
}

/// Update session progress
/// Parameters:
///   - sessionId: UUID of the session
///   - progress: Progress percentage (0-100)
/// Throws: CouplesModeError.notFound
func updateSessionProgress(sessionId: UUID, progress: Int) async throws {
    let currentUserId = try userId
    
    // Determine which user column to update
    let sessions: [CouplesExerciseSession] = try await supabase
        .from("couples_exercise_sessions")
        .select()
        .eq("id", value: sessionId)
        .execute()
        .value
    
    guard let session = sessions.first else {
        throw CouplesModeError.notFound
    }
    
    let isUser1 = session.userId1 == currentUserId
    let progressColumn = isUser1 ? "user_1_progress_percent" : "user_2_progress_percent"
    
    try await supabase
        .from("couples_exercise_sessions")
        .update([
            progressColumn: AnyEncodable(progress),
            "last_activity_at": AnyEncodable(Date())
        ])
        .eq("id", value: sessionId)
        .execute()
}

/// Complete a session with rating and notes
/// Parameters:
///   - sessionId: UUID of the session
///   - rating: Rating 1-5
///   - notes: Optional notes
/// Throws: CouplesModeError.alreadyCompleted, CouplesModeError.notFound
func completeSession(sessionId: UUID, rating: Int, notes: String?) async throws {
    let currentUserId = try userId
    
    let sessions: [CouplesExerciseSession] = try await supabase
        .from("couples_exercise_sessions")
        .select()
        .eq("id", value: sessionId)
        .execute()
        .value
    
    guard let session = sessions.first else {
        throw CouplesModeError.notFound
    }
    
    let isUser1 = session.userId1 == currentUserId
    
    // Check if already rated
    if (isUser1 && session.user1Rating != nil) || (!isUser1 && session.user2Rating != nil) {
        throw CouplesModeError.alreadyCompleted
    }
    
    let ratingColumn = isUser1 ? "user_1_rating" : "user_2_rating"
    let notesColumn = isUser1 ? "user_1_notes" : "user_2_notes"
    var updateData: [String: AnyEncodable] = [
        ratingColumn: AnyEncodable(rating),
        "last_activity_at": AnyEncodable(Date())
    ]
    
    if let notes = notes {
        updateData[notesColumn] = AnyEncodable(notes)
    }
    
    // If both rated, mark as completed
    let bothRated = (isUser1 && session.user2Rating != nil) || (!isUser1 && session.user1Rating != nil)
    if bothRated {
        updateData["status"] = AnyEncodable("completed")
        updateData["completed_at"] = AnyEncodable(Date())
    }
    
    try await supabase
        .from("couples_exercise_sessions")
        .update(updateData)
        .eq("id", value: sessionId)
        .execute()
}

/// Get or create partner link invite code (reuses buddy system)
/// Returns: Invite code string
/// Throws: CouplesModeError.quotaExceeded if rate limited
func getOrCreatePartnerInviteCode() async throws -> String {
    // Check for existing pending buddy invite
    let existingInvites = try await getPendingBuddyInvites()
    
    if let existing = existingInvites.first {
        return existing.inviteCode
    }
    
    // Create new invite via buddy system
    do {
        let relationship = try await createBuddyInvite(contact: "", method: .link)
        return relationship.inviteCode
    } catch {
        // Check if it's a rate limit error
        if error.localizedDescription.contains("quota") || error.localizedDescription.contains("limit") {
            throw CouplesModeError.quotaExceeded(retryAfterSeconds: 3600)
        }
        throw error
    }
}

/// Accept partner invite (reuses buddy system)
/// Parameters:
///   - code: 6-character invite code
/// Returns: BuddyRelationship
/// Throws: CouplesModeError.inviteInvalid, .inviteExpired, .selfInvite, .alreadyPartnered
func acceptPartnerInvite(code: String) async throws -> BuddyRelationship {
    // Check if already partnered
    if let _ = try await getActivePartnerLink() {
        throw CouplesModeError.alreadyPartnered
    }
    
    do {
        let relationship = try await acceptBuddyInvite(code: code)
        
        // Create corresponding partner_link entry
        let currentUserId = try userId
        let partnerId = relationship.buddy(currentUserId: currentUserId.uuidString)?.id ?? ""
        guard let partnerUUID = UUID(uuidString: partnerId) else {
            throw CouplesModeError.internalError
        }
        
        // Determine user order (user_id_1 < user_id_2)
        let (user1, user2) = currentUserId < partnerUUID
            ? (currentUserId, partnerUUID)
            : (partnerUUID, currentUserId)
        
        let linkData: [String: AnyEncodable] = [
            "user_id_1": AnyEncodable(user1),
            "user_id_2": AnyEncodable(user2),
            "created_by": AnyEncodable(currentUserId),
            "status": AnyEncodable("active"),
            "activated_at": AnyEncodable(Date()),
            "expires_at": AnyEncodable(Date().addingTimeInterval(365 * 24 * 60 * 60)), // 1 year
            "user_1_share_mood": AnyEncodable(false),
            "user_1_share_exercises": AnyEncodable(false),
            "user_2_share_mood": AnyEncodable(false),
            "user_2_share_exercises": AnyEncodable(false)
        ]
        
        try await supabase
            .from("partner_links")
            .insert(linkData)
            .execute()
        
        return relationship
    } catch let error as DataError {
        if error.localizedDescription.contains("Invalid or expired") {
            throw CouplesModeError.inviteExpired
        }
        throw error
    }
}
```

---

## Implementation Sequence

### Phase 1: Foundation (No Dependencies)
**Estimated Time:** 3 hours  
**Checkpoint:** Tests pass, ViewModel compiles

- [ ] Create `PartnerModeViewModel.swift`
  - Define `PartnerState`, `PartnerInfo`, `SharingSettings` enums/structs
  - Implement all `@Published` properties
  - Add skeleton methods (empty async functions)
- [ ] Extend `CouplesModels.swift`
  - Add `PartnerLink` extension methods
  - Add `mySharingSettings()`, `partnerSharingSettings()`, `partnerId()` helpers
- [ ] Add service methods to `SupabaseDataService.swift`
  - Copy all 13 method signatures from Component Design section
  - Implement full logic for each method
- [ ] Create test file `PartnerModeViewModelTests.swift`
  - Add empty test stubs for all test cases
- [ ] **Verify:** Run `xcodebuild test -scheme MindFriendApp` - should compile (tests can fail)

---

### Phase 2: Onboarding Views (Depends on Phase 1)
**Estimated Time:** 4 hours  
**Checkpoint:** Can generate code, accept code, see errors

- [ ] Create `Components/InviteCodeDisplay.swift`
  - Input: `code: String?`, `expiresAt: Date?`
  - Display code in 6-char format with spacing
  - Copy button with haptic feedback
  - Share button with iOS share sheet
  - Message: "Expires in X days"
- [ ] Create `Components/CodeEntryField.swift`
  - Input: `code: Binding<String>`
  - 6 individual text fields (auto-focus next on input)
  - Auto-uppercase, filter non-alphanumeric
  - Validation: exactly 6 chars, no ambiguous (0/O, 1/I/L)
  - Accessibility: announce each digit
- [ ] Create `PartnerOnboardingView.swift`
  - TabView: "Send Invite" / "Enter Code"
  - Send tab: calls `viewModel.generateInviteCode()` on appear
  - Send tab: shows `InviteCodeDisplay` with loading state
  - Enter tab: shows `CodeEntryField` + "Connect" button
  - Enter tab: calls `viewModel.acceptInviteCode()` on button tap
  - Show errors via `.alert()` modifier
- [ ] Create `PartnerModeView.swift` (shell only)
  - `@StateObject var viewModel = PartnerModeViewModel(...)`
  - If `viewModel.partnerState == .noPartner`: show `PartnerOnboardingView`
  - Else: show `Text("Dashboard placeholder")`
  - `.onAppear { Task { await viewModel.loadPartnerData() } }`
- [ ] Implement ViewModel logic:
  - `generateInviteCode()`: call `getOrCreatePartnerInviteCode()`, set `inviteCode`
  - `acceptInviteCode()`: validate length, call `acceptPartnerInvite()`, handle errors
  - `loadPartnerData()`: check for active partner link, populate `partnerState`
- [ ] **Verify:** 
  - Run app, navigate to PartnerModeView
  - Generate code → see 6-char code
  - Copy code → clipboard has code
  - Share code → iOS share sheet appears
  - Enter invalid code → see error
  - Enter valid code (in 2 devices/simulators) → connection succeeds

---

### Phase 3: Dashboard Views (Depends on Phase 1, 2)
**Estimated Time:** 5 hours  
**Checkpoint:** Dashboard shows partner data, respects sharing settings

- [ ] Create `Components/PartnerStatusCard.swift`
  - Input: `partnerInfo: PartnerInfo`
  - Display avatar initial (first char of name)
  - Show name (truncate at 20 chars)
  - Show streak: flame icon + number
  - Show status: "Active today" vs "Last active X days ago"
  - Show encouragement button
- [ ] Create `Components/SharedMoodCard.swift`
  - Input: `moods: [MoodEntry]`
  - Horizontal scroll of mood emojis + dates
  - Show last 7 moods
  - Empty state: "No moods logged recently"
- [ ] Create `Components/SharedQuestCard.swift`
  - Input: `quest: Quest?`
  - Show quest title + completion status
  - Checkmark icon if completed
  - Empty state: "No quest today"
- [ ] Create `Components/PartnerPlaceholder.swift`
  - Input: `type: String` (e.g., "mood", "quest")
  - Show muted card with message: "Your partner hasn't shared this yet"
  - Suggestion: "Ask them to enable sharing in settings"
- [ ] Create `PartnerDashboardView.swift`
  - Input: `viewModel: PartnerModeViewModel`, `partnerInfo: PartnerInfo`
  - ScrollView with VStack:
    - `PartnerStatusCard(info: partnerInfo)`
    - If `partnerInfo.isSharingMood`: `SharedMoodCard` else `PartnerPlaceholder`
    - If `partnerInfo.isSharingExercises`: `SharedQuestCard` else `PartnerPlaceholder`
    - NavigationLink to `SharedExercisesView` (placeholder)
    - Button for encouragement (shows sheet)
    - NavigationLink to `PartnerSharingSettingsView` (placeholder)
  - `.refreshable { await viewModel.loadPartnerData() }`
  - Polling timer (30s interval) in `.onAppear/.onDisappear`
- [ ] Update `PartnerModeView.swift`:
  - Replace placeholder with `PartnerDashboardView` when `.hasPartner`
- [ ] Implement ViewModel logic:
  - `loadPartnerData()`: fetch partner link, get partner moods/quest if shared
  - Set up polling in dashboard (Timer that calls `loadPartnerData()` every 30s)
- [ ] **Verify:**
  - Two partnered users
  - User A sees User B's name, streak, status
  - User B hasn't enabled sharing → User A sees placeholders
  - User B enables mood sharing → User A sees mood card after 30s
  - Pull-to-refresh → data updates immediately

---

### Phase 4: Sharing Settings (Depends on Phase 1, 3)
**Estimated Time:** 3 hours  
**Checkpoint:** Toggles save, changes reflect in partner's view

- [ ] Create `Components/SharingToggleRow.swift`
  - Input: `title: String`, `description: String`, `isOn: Binding<Bool>`, `isLoading: Bool`
  - Show toggle switch
  - Show loading spinner overlay when `isLoading`
  - Accessibility label: "\(title), \(isOn ? "enabled" : "disabled")"
- [ ] Create `PartnerSharingSettingsView.swift`
  - Input: `viewModel: PartnerModeViewModel`
  - List:
    - Section "What I Share":
      - `SharingToggleRow(title: "Mood", ...)`
      - `SharingToggleRow(title: "Exercises", ...)`
    - Section footer: "Your partner will see these updates in real-time"
  - On toggle change:
    - Set `viewModel.isSavingSharingSettings = true`
    - Call `viewModel.updateSharingSettings()`
    - Wait for completion
    - Set `viewModel.isSavingSharingSettings = false`
  - Show error toast on save failure
- [ ] Implement ViewModel logic:
  - `updateSharingSettings()`: call `updatePartnerSharingSettings()` with retry (3x)
  - Track retry count, show error toast after 3 failures
  - Optimistic update: set local state immediately, revert on failure
- [ ] **Verify:**
  - User A toggles "Mood" on → saves within 500ms
  - User B's dashboard shows mood card after next poll
  - Network failure → auto-retry 3x → show error toast
  - User A toggles back off → User B sees placeholder again

---

### Phase 5: Shared Exercises (Depends on Phase 1, 3) [P1]
**Estimated Time:** 4 hours  
**Checkpoint:** Can browse exercises, premium badge shows correctly

- [ ] Create `SharedExercisesView.swift`
  - Input: `viewModel: PartnerModeViewModel`
  - `.onAppear { Task { await viewModel.loadCouplesExercises() } }`
  - List grouped by category:
    - Section "Communication"
    - Section "Intimacy"
    - Section "Goal Setting"
    - Section "Mindfulness"
  - Each row:
    - Exercise name
    - Duration + difficulty badges
    - Premium lock icon (if `requiresPremium && !hasPremium`)
  - Tap → NavigationLink to detail view (placeholder)
- [ ] Implement ViewModel logic:
  - `loadCouplesExercises()`: call `getCouplesExercises()`, set `couplesExercises`
  - Filter/group exercises by `type`
- [ ] **Verify:**
  - List shows all exercises grouped by category
  - Premium exercises show lock icon for free users
  - Tap exercise → navigate to detail (placeholder)

---

### Phase 6: Encouragement (Depends on Phase 1, 3) [P1]
**Estimated Time:** 2 hours  
**Checkpoint:** Can send encouragement, rate limited, notification sent

- [ ] Create `EncouragementPickerSheet.swift`
  - Input: `onSelect: (BuddyEncouragement.MessageType) -> Void`
  - List of options:
    - "Encouragement" (🙌) - "You've got this!"
    - "Celebration" (🎉) - "Great job!"
    - "Check-in" (💙) - "Thinking of you"
  - Tap → call `onSelect()` → dismiss
- [ ] Update `PartnerDashboardView.swift`:
  - Encouragement button shows `.sheet(isPresented: $viewModel.showEncouragementPicker)`
  - Sheet: `EncouragementPickerSheet(onSelect: viewModel.sendEncouragement)`
- [ ] Implement ViewModel logic:
  - `sendEncouragement(type)`: 
    - Check local cache for last send time (1 hour rate limit)
    - If < 1 hour ago: throw `CouplesModeError.rateLimited(retryAfterSeconds: ...)`
    - Call `sendEncouragement(to: partnerId, relationshipId: ..., type: type)`
    - Update local cache with current time
    - Show success animation
- [ ] **Verify:**
  - User A sends encouragement → User B receives push notification
  - User A tries again within 1 hour → see error "Try again in X minutes"
  - After 1 hour → can send again

---

### Phase 7: Deep Linking & Navigation (Depends on Phase 2)
**Estimated Time:** 2 hours  
**Checkpoint:** Deep link pre-fills code, navigates to partner screen

- [ ] Update `App/AppState.swift`:
  - Add `@Published var pendingPartnerCode: String?`
- [ ] Update `App/MindFriendApp.swift`:
  - Add `.onOpenURL { url in ... }` handler
  - Parse `mindfriend://partner/accept?code=XXXXXX`
  - Set `appState.pendingPartnerCode = code`
  - Set `appState.selectedTab = .profile` (or wherever PartnerModeView is)
- [ ] Update `PartnerModeView.swift`:
  - `.onAppear { if let code = appState.pendingPartnerCode { ... } }`
  - Pre-fill `viewModel.codeInput = code`
  - Switch to "Enter Code" tab
  - Clear `appState.pendingPartnerCode`
- [ ] Update `Features/Profile/SettingsView.swift`:
  - Add NavigationLink to `PartnerModeView`
  - Icon: `person.2.fill`
  - Title: "Partner Mode"
- [ ] **Verify:**
  - Tap deep link `mindfriend://partner/accept?code=ABC123`
  - App opens to Partner Mode → Enter Code tab
  - Code pre-filled: "ABC123"
  - Accept → connection succeeds

---

### Phase 8: Testing & Polish (Depends on All Phases)
**Estimated Time:** 4 hours  
**Checkpoint:** All tests pass, accessibility verified

- [ ] Implement unit tests in `PartnerModeViewModelTests.swift`:
  - `test_generateInviteCode_success()`
  - `test_generateInviteCode_rateLimited()`
  - `test_acceptCode_success()`
  - `test_acceptCode_invalidCode()`
  - `test_acceptCode_expiredCode()`
  - `test_acceptCode_selfInvite()`
  - `test_acceptCode_alreadyPartnered()`
  - `test_updateSharingSettings_success()`
  - `test_updateSharingSettings_networkFailure_retries()`
  - `test_sendEncouragement_success()`
  - `test_sendEncouragement_rateLimited()`
  - `test_loadPartnerData_noPartner()`
  - `test_loadPartnerData_hasPartner()`
  - `test_loadPartnerData_partnerNotSharing()`
- [ ] Add integration tests:
  - `test_completeOnboardingFlow_bothUsers()`
  - `test_sharingToggles_affectPartnerView()`
- [ ] Accessibility audit:
  - VoiceOver labels on all buttons, toggles
  - Code entry announces each digit
  - Dynamic Type support tested up to accessibility sizes
  - Minimum tap targets 44x44pt verified
- [ ] Polish:
  - Add haptic feedback on code copy, encouragement sent
  - Add success animations (checkmark, confetti)
  - Add empty states for all lists
  - Add error recovery (retry buttons)
- [ ] **Verify:**
  - All tests pass: `xcodebuild test -scheme MindFriendApp`
  - VoiceOver navigation works correctly
  - Dynamic Type scales properly
  - No crashes, no console errors

---

## Interface Contracts

### PartnerModeViewModel API

```swift
@MainActor
final class PartnerModeViewModel: ObservableObject {
    // MARK: - Dependencies
    private let dataService: SupabaseDataService
    
    init(dataService: SupabaseDataService) {
        self.dataService = dataService
    }
    
    // MARK: - Published State
    @Published var partnerState: PartnerState = .loading
    @Published var inviteCode: String?
    @Published var codeInput: String = ""
    @Published var isValidating = false
    @Published var sharingSettings: SharingSettings?
    @Published var partnerMoods: [MoodEntry] = []
    @Published var partnerQuest: Quest?
    @Published var couplesExercises: [CouplesExercise] = []
    @Published var activeSession: CouplesExerciseSession?
    @Published var error: CouplesModeError?
    @Published var showEncouragementPicker = false
    @Published var isSavingSharingSettings = false
    
    // MARK: - Actions
    func loadPartnerData() async
    func generateInviteCode() async
    func acceptInviteCode(_ code: String) async
    func updateSharingSettings(_ settings: SharingSettings) async
    func sendEncouragement(_ type: BuddyEncouragement.MessageType) async
    func loadCouplesExercises() async
    func startExerciseSession(_ exerciseId: UUID) async
}
```

### Component Props

```swift
// InviteCodeDisplay
struct InviteCodeDisplay: View {
    let code: String?
    let expiresAt: Date?
    
    var body: some View { ... }
}

// CodeEntryField
struct CodeEntryField: View {
    @Binding var code: String
    let onComplete: (String) -> Void
    
    var body: some View { ... }
}

// PartnerStatusCard
struct PartnerStatusCard: View {
    let partnerInfo: PartnerInfo
    let onEncouragementTap: () -> Void
    
    var body: some View { ... }
}

// SharedMoodCard
struct SharedMoodCard: View {
    let moods: [MoodEntry]
    
    var body: some View { ... }
}

// SharedQuestCard
struct SharedQuestCard: View {
    let quest: Quest?
    
    var body: some View { ... }
}

// PartnerPlaceholder
struct PartnerPlaceholder: View {
    let type: String // "mood" | "quest"
    
    var body: some View { ... }
}

// SharingToggleRow
struct SharingToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    let isLoading: Bool
    
    var body: some View { ... }
}
```

---

## Error Handling Strategy

### Error Types

| Error | Source | Handling | User Message |
|-------|--------|----------|--------------|
| `.inviteInvalid` | Code validation | Show alert | "Invalid invite code. Please check and try again." |
| `.inviteExpired` | RPC response | Show alert | "This invite code has expired. Ask your partner for a new one." |
| `.alreadyPartnered` | Pre-check | Show alert | "You already have an active partner. End partnership to accept new invite." |
| `.selfInvite` | RPC response | Show alert | "You cannot partner with yourself." |
| `.quotaExceeded` | Rate limit (DB) | Show alert | "You've reached your invite limit. Try again in X hours." |
| `.notPartnered` | Service calls | Log error | (Shouldn't happen - UI prevents) |
| `.partnerNotSharing` | Data fetch | Show placeholder | "Your partner hasn't shared this yet" |
| `.rateLimited` | Local check (encouragement) | Show alert | "Wait X minutes before sending another encouragement" |
| `.exercisePremiumOnly` | Premium check | Show paywall | "Upgrade to Premium to unlock this exercise" |
| Network timeout | API call | Auto-retry 3x | "Connection lost. Retrying..." |

### Retry Strategy

```swift
private func withRetry<T>(maxAttempts: Int = 3, operation: () async throws -> T) async throws -> T {
    var lastError: Error?
    
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            if attempt < maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000) // 1s, 2s, 3s
            }
        }
    }
    
    throw lastError!
}

// Usage in ViewModel
func updateSharingSettings(_ settings: SharingSettings) async {
    do {
        try await withRetry {
            try await dataService.updatePartnerSharingSettings(
                shareMood: settings.shareMood,
                shareExercises: settings.shareExercises
            )
        }
        await MainActor.run {
            self.sharingSettings = settings
            self.isSavingSharingSettings = false
        }
    } catch {
        await MainActor.run {
            self.error = .internalError
            self.isSavingSharingSettings = false
        }
    }
}
```

---

## State Management

### Partner State Lifecycle

```
User launches app
    ↓
loadPartnerData() called
    ↓
Check for active PartnerLink in DB
    ↓
┌─────────────────┬─────────────────────┐
│ No partner      │ Has active partner  │
│ found           │ found               │
└─────────────────┴─────────────────────┘
    ↓                   ↓
partnerState =      partnerState = 
.noPartner          .hasPartner(PartnerInfo)
    ↓                   ↓
Show               Fetch partner data:
PartnerOnboardingView  - Mood history (if shared)
                       - Quest status (if shared)
                       ↓
                   Show PartnerDashboardView
                       ↓
                   Start polling (30s interval)
```

### Polling Implementation

```swift
private var pollTimer: Timer?

private func startPolling() {
    pollTimer?.invalidate()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
            await self?.loadPartnerData()
        }
    }
}

private func stopPolling() {
    pollTimer?.invalidate()
    pollTimer = nil
}

// In PartnerDashboardView
.onAppear { viewModel.startPolling() }
.onDisappear { viewModel.stopPolling() }
```

### Sharing Settings State

```swift
struct SharingToggleState {
    var value: Bool
    var pendingValue: Bool?  // Non-nil when save in progress
    var retryCount: Int = 0
    
    mutating func beginSave(newValue: Bool) {
        pendingValue = newValue
    }
    
    mutating func onSaveSuccess() {
        value = pendingValue ?? value
        pendingValue = nil
        retryCount = 0
    }
    
    mutating func onSaveFailure() -> Bool {
        retryCount += 1
        if retryCount >= 3 {
            pendingValue = nil  // Revert
            retryCount = 0
            return false  // Show error
        }
        return true  // Will auto-retry
    }
}
```

---

## Test Strategy

### Unit Tests (Phase 8)

**File:** `MindFriendAppTests/PartnerModeViewModelTests.swift`

```swift
@MainActor
final class PartnerModeViewModelTests: XCTestCase {
    var viewModel: PartnerModeViewModel!
    var mockDataService: MockSupabaseDataService!
    
    override func setUp() async throws {
        mockDataService = MockSupabaseDataService()
        viewModel = PartnerModeViewModel(dataService: mockDataService)
    }
    
    // MARK: - Code Generation
    
    func test_generateInviteCode_success() async throws {
        // Given: Mock returns code "ABC123"
        mockDataService.nextInviteCode = "ABC123"
        
        // When: Generate code
        await viewModel.generateInviteCode()
        
        // Then: Code is set
        XCTAssertEqual(viewModel.inviteCode, "ABC123")
        XCTAssertNil(viewModel.error)
    }
    
    func test_generateInviteCode_rateLimited() async throws {
        // Given: Mock throws quota exceeded
        mockDataService.shouldThrowQuotaExceeded = true
        
        // When: Generate code
        await viewModel.generateInviteCode()
        
        // Then: Error is set
        XCTAssertNil(viewModel.inviteCode)
        XCTAssertEqual(viewModel.error, .quotaExceeded(retryAfterSeconds: 3600))
    }
    
    // MARK: - Code Acceptance
    
    func test_acceptCode_success() async throws {
        // Given: Valid code
        viewModel.codeInput = "ABC123"
        
        // When: Accept code
        await viewModel.acceptInviteCode(viewModel.codeInput)
        
        // Then: Partner state updated
        if case .hasPartner(let info) = viewModel.partnerState {
            XCTAssertEqual(info.partnerName, "Test Partner")
        } else {
            XCTFail("Expected hasPartner state")
        }
    }
    
    func test_acceptCode_invalidCode() async throws {
        // Given: Invalid code
        viewModel.codeInput = "INVALID"
        mockDataService.shouldThrowInvalidCode = true
        
        // When: Accept code
        await viewModel.acceptInviteCode(viewModel.codeInput)
        
        // Then: Error is set
        XCTAssertEqual(viewModel.error, .inviteInvalid)
    }
    
    func test_acceptCode_expiredCode() async throws {
        // Given: Expired code
        viewModel.codeInput = "EXPIRED"
        mockDataService.shouldThrowExpiredCode = true
        
        // When: Accept code
        await viewModel.acceptInviteCode(viewModel.codeInput)
        
        // Then: Error is set
        XCTAssertEqual(viewModel.error, .inviteExpired)
    }
    
    func test_acceptCode_selfInvite() async throws {
        // Given: User's own code
        mockDataService.shouldThrowSelfInvite = true
        
        // When: Accept code
        await viewModel.acceptInviteCode("SELF123")
        
        // Then: Error is set
        XCTAssertEqual(viewModel.error, .selfInvite)
    }
    
    func test_acceptCode_alreadyPartnered() async throws {
        // Given: User already has partner
        mockDataService.hasExistingPartner = true
        
        // When: Accept code
        await viewModel.acceptInviteCode("ABC123")
        
        // Then: Error is set
        XCTAssertEqual(viewModel.error, .alreadyPartnered)
    }
    
    // MARK: - Sharing Settings
    
    func test_updateSharingSettings_success() async throws {
        // Given: New settings
        let settings = SharingSettings(shareMood: true, shareExercises: false)
        
        // When: Update settings
        await viewModel.updateSharingSettings(settings)
        
        // Then: Settings saved
        XCTAssertEqual(viewModel.sharingSettings, settings)
        XCTAssertFalse(viewModel.isSavingSharingSettings)
    }
    
    func test_updateSharingSettings_networkFailure_retries() async throws {
        // Given: Network fails 2 times, succeeds on 3rd
        mockDataService.failCount = 2
        let settings = SharingSettings(shareMood: true, shareExercises: true)
        
        // When: Update settings
        await viewModel.updateSharingSettings(settings)
        
        // Then: Eventually succeeds after retries
        XCTAssertEqual(viewModel.sharingSettings, settings)
        XCTAssertEqual(mockDataService.updateSharingCallCount, 3)
    }
    
    // MARK: - Encouragement
    
    func test_sendEncouragement_success() async throws {
        // Given: No recent encouragement
        mockDataService.lastEncouragementTime = nil
        
        // When: Send encouragement
        await viewModel.sendEncouragement(.encouragement)
        
        // Then: Success
        XCTAssertNil(viewModel.error)
        XCTAssertNotNil(mockDataService.lastEncouragementTime)
    }
    
    func test_sendEncouragement_rateLimited() async throws {
        // Given: Encouragement sent 30 minutes ago
        mockDataService.lastEncouragementTime = Date().addingTimeInterval(-1800)
        
        // When: Send another
        await viewModel.sendEncouragement(.encouragement)
        
        // Then: Rate limited error
        if case .rateLimited(let seconds) = viewModel.error {
            XCTAssertGreaterThan(seconds, 0)
        } else {
            XCTFail("Expected rateLimited error")
        }
    }
}
```

### Integration Tests (Phase 8)

```swift
func test_completeOnboardingFlow_bothUsers() async throws {
    // Simulate two users pairing
    let user1VM = PartnerModeViewModel(dataService: dataService1)
    let user2VM = PartnerModeViewModel(dataService: dataService2)
    
    // User 1 generates code
    await user1VM.generateInviteCode()
    guard let code = user1VM.inviteCode else {
        XCTFail("Code not generated")
        return
    }
    
    // User 2 accepts code
    user2VM.codeInput = code
    await user2VM.acceptInviteCode(code)
    
    // Both users should now have partner state
    if case .hasPartner(let info1) = user1VM.partnerState,
       case .hasPartner(let info2) = user2VM.partnerState {
        XCTAssertEqual(info1.partnerId, user2VM.dataService.userId)
        XCTAssertEqual(info2.partnerId, user1VM.dataService.userId)
    } else {
        XCTFail("Both users should have partner state")
    }
}

func test_sharingToggles_affectPartnerView() async throws {
    // Given: User 1 and User 2 are partnered
    // User 1 enables mood sharing
    let settings = SharingSettings(shareMood: true, shareExercises: false)
    await user1VM.updateSharingSettings(settings)
    
    // User 2 loads partner data
    await user2VM.loadPartnerData()
    
    // User 2 should see User 1's moods
    if case .hasPartner(let info) = user2VM.partnerState {
        XCTAssertTrue(info.isSharingMood)
        XCTAssertFalse(user2VM.partnerMoods.isEmpty)
    } else {
        XCTFail("Expected partner state")
    }
}
```

### UI Tests (Phase 8)

```swift
func test_codeEntry_acceptsValidInput() throws {
    let app = XCUIApplication()
    app.launch()
    
    // Navigate to Partner Mode
    app.buttons["Settings"].tap()
    app.buttons["Partner Mode"].tap()
    
    // Switch to Enter Code tab
    app.buttons["Enter Code"].tap()
    
    // Enter valid code
    let codeFields = app.textFields.matching(identifier: "codeDigit")
    codeFields.element(boundBy: 0).tap()
    codeFields.element(boundBy: 0).typeText("A")
    codeFields.element(boundBy: 1).typeText("B")
    codeFields.element(boundBy: 2).typeText("C")
    codeFields.element(boundBy: 3).typeText("1")
    codeFields.element(boundBy: 4).typeText("2")
    codeFields.element(boundBy: 5).typeText("3")
    
    // Connect button should be enabled
    XCTAssertTrue(app.buttons["Connect"].isEnabled)
}

func test_dashboard_showsPartnerData() throws {
    // Given: User has active partner
    setupActivePartnership()
    
    let app = XCUIApplication()
    app.launch()
    
    // Navigate to Partner Mode
    app.buttons["Settings"].tap()
    app.buttons["Partner Mode"].tap()
    
    // Should show dashboard
    XCTAssertTrue(app.staticTexts["Your Partner"].exists)
    XCTAssertTrue(app.staticTexts["Test Partner"].exists)
    XCTAssertTrue(app.images["flame"].exists) // Streak icon
}
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Breaking existing buddy system | Low | High | Reuse existing RPCs, don't modify `buddy_relationships` schema |
| Race condition in code acceptance | Medium | Medium | Database unique constraint on `invite_code`, first-wins behavior |
| Polling performance impact | Low | Low | 30s interval is conservative, use background timer |
| Sharing toggle save failures | Medium | Low | Auto-retry 3x with exponential backoff, revert on failure |
| Premium check bypass | Low | Critical | Server-side validation in Edge Function (future enhancement) |
| Deep link code injection | Low | Medium | Validate code format (6 chars, alphanumeric) before processing |

---

## Dependencies

### External

None (all features use existing Supabase SDK)

### Internal

| Module | Usage | Version | Notes |
|--------|-------|---------|-------|
| `SupabaseDataService` | All data operations | Current | Add 13 new methods |
| `BuddyRelationship` | Invite/accept flow | Current | No changes needed |
| `CouplesModels` | All couples-specific models | Current | Add extension methods |
| `InviteBuddySheet` | Reference for UI patterns | Current | No changes needed |

---

## Rollback Plan

If issues are discovered post-implementation:

1. **Feature flag**: Add `PARTNER_MODE_ENABLED` bool to AppState
   - Set to `false` → hide NavigationLink in SettingsView
   - Existing partnerships remain in DB but inaccessible
2. **Database**: No schema changes required (tables already exist)
3. **Code removal**: All new files are isolated in `Features/Partner/` directory
   - Delete directory → remove from Xcode project → revert `SupabaseDataService` changes

---

## Performance Considerations

### Polling vs Realtime

**Decision:** Use polling (30s interval)

**Rationale:**
- Partner data changes infrequently (1-2x per day)
- Avoids Realtime subscription management complexity
- Matches existing buddy widget pattern
- Lower server resource usage

**Benchmarks:**
- Polling load: ~2 API calls per user per minute (dashboard + settings)
- Realtime load: 1 persistent connection per user + event streams
- For 10,000 partnered users: 20,000 API calls/min vs 10,000 connections

### Data Caching

```swift
// Cache partner data locally for 5 minutes
private var partnerDataCache: (data: PartnerInfo, timestamp: Date)?

func loadPartnerData() async {
    // Check cache
    if let cached = partnerDataCache,
       Date().timeIntervalSince(cached.timestamp) < 300 {
        partnerState = .hasPartner(cached.data)
        return
    }
    
    // Fetch fresh data
    // ...
    
    // Update cache
    partnerDataCache = (partnerInfo, Date())
}
```

---

## Accessibility Checklist

- [ ] All interactive elements have VoiceOver labels
- [ ] Code entry fields announce digit as typed
- [ ] Encouragement button announces rate limit state
- [ ] Toggle switches announce on/off state
- [ ] Dynamic Type supported (up to accessibility sizes)
- [ ] Minimum tap targets: 44x44pt
- [ ] Color contrast ratios meet WCAG AA (4.5:1)
- [ ] Focus order is logical (top to bottom)
- [ ] Error messages are announced immediately

---

## Localization Strategy

**Phase 1 (MVP):** English only

**Phase 2 (Future):** Add keys to `Localizable.strings`:

```swift
// Partner Mode
"partner_mode.title" = "Partner Mode";
"partner_mode.onboarding.title" = "Partner up for accountability";
"partner_mode.onboarding.subtitle" = "Share progress and encourage each other";
"partner_mode.invite.title" = "Your invite code";
"partner_mode.invite.expires" = "Expires in %d days";
"partner_mode.code.placeholder" = "Enter code";
"partner_mode.error.invalid_code" = "Invalid invite code. Please check and try again.";
"partner_mode.error.expired_code" = "This invite code has expired. Ask your partner for a new one.";
// ... etc
```

---

## Questions for Clarification

Before proceeding, confirm:

1. **Premium Logic:** Should we implement full premium check (either partner premium = unlock for both) in Phase 5, or defer to future?
   - **Recommendation:** Throw `exercisePremiumOnly` error for MVP, implement full logic in Phase 2
2. **Session Notifications:** Should partner receive push notification when session is started/joined?
   - **Recommendation:** Yes (already in spec), use existing `send-notification` Edge Function
3. **Encouragement History:** Should dashboard show "last encouragement received" timestamp?
   - **Recommendation:** Yes (already in `BuddyWidgetData`), reuse existing logic

---

## Verdict

**READY FOR IMPLEMENTATION**

This plan provides a clear path to implement Partner Mode UX with:

- [x] Minimal risk to existing buddy functionality (reuse RPCs, no schema changes)
- [x] Clear component boundaries (17 files, well-defined interfaces)
- [x] Comprehensive test coverage (unit + integration + UI tests)
- [x] Defined error handling (8 error types, retry logic)
- [x] Rollback capability (feature flag + isolated file structure)
- [x] Phased implementation (8 phases, ~27 hours total)

**Next Steps:**
1. Review this plan with team
2. Confirm answers to clarification questions
3. Begin Phase 1 (Foundation)
4. Checkpoint after each phase before proceeding

**Estimated Timeline:**
- Phase 1-4: 15 hours (P0 - Core functionality)
- Phase 5-6: 6 hours (P1 - Enhanced features)
- Phase 7-8: 6 hours (P1 - Polish + tests)
- **Total: ~27 hours** (3-4 days for single developer)

---

*Generated by: `architect` agent*  
*Model: Claude Opus 4.5*  
*Date: 2026-01-20*
