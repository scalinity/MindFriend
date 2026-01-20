# Partner Mode UX Implementation Specification

## 1. Feature Scope

### Views to Build

| View                         | Purpose                                                               | Priority |
| ---------------------------- | --------------------------------------------------------------------- | -------- |
| `PartnerModeView`            | Main container - shows onboarding OR dashboard based on partner state | P0       |
| `PartnerOnboardingView`      | Tabbed: "Send Invite" / "Enter Code"                                  | P0       |
| `AcceptInviteView`           | Code entry + validation UI                                            | P0       |
| `PartnerDashboardView`       | Shows partner's shared data (streak, mood, quests)                    | P0       |
| `PartnerSharingSettingsView` | Toggles for mood/exercises sharing preferences                        | P1       |
| `SharedExercisesView`        | List of couples exercises with "Start Together" CTA                   | P1       |
| `SharedExerciseSessionView`  | Active session with partner progress indicators                       | P2       |
| `EncouragementPickerSheet`   | Select encouragement type before sending                              | P1       |

### Components to Build

| Component            | Purpose                                     |
| -------------------- | ------------------------------------------- |
| `PartnerStatusCard`  | Shows partner's name, streak, last active   |
| `SharedMoodCard`     | Displays partner's recent moods (if shared) |
| `SharedQuestCard`    | Shows partner's quest status (if shared)    |
| `SharingToggleRow`   | Individual toggle with description          |
| `InviteCodeDisplay`  | Shows code with copy/share actions          |
| `CodeEntryField`     | 6-character code input with validation      |
| `PartnerPlaceholder` | Shown when data not shared                  |

---

## 2. Functional Requirements

### FR-1: Partner Onboarding Flow

**FR-1.1: Generate Invite Code**

- User taps "Create Invite" button
- System calls `generate_buddy_code()` RPC
- Creates `buddy_relationships` row with 30-day expiry
- Display 6-char code with copy/share options
- Show deep link: `mindfriend://partner/accept?code=XXXXXX`

**Acceptance Criteria:**

- [ ] Code is 6 alphanumeric characters (no ambiguous chars: 0/O, 1/I/L)
- [ ] Code expires after 30 days
- [ ] Rate limit: max 10 invites per day per user
- [ ] Copy button copies code to clipboard with haptic feedback
- [ ] Share button opens iOS share sheet with message + code

**FR-1.2: Accept Invite Code**

- User enters 6-char code OR taps deep link
- System calls `accept_buddy_invite(code, user_id)` RPC
- On success: creates buddy circle, links profiles, awards XP
- Navigate to `PartnerDashboardView`

**Acceptance Criteria:**

- [ ] Code input accepts uppercase letters + digits
- [ ] Auto-uppercase input
- [ ] Validates length (exactly 6 chars)
- [ ] Shows loading state during validation
- [ ] Error: "Invalid code" for wrong codes
- [ ] Error: "Expired code" for expired codes
- [ ] Error: "Already partnered" if user has active partner
- [ ] Error: "Can't accept own invite" for self-invite
- [ ] Success shows partner name + celebration animation

### FR-2: Partner Dashboard

**FR-2.1: Partner Status Display**

- Shows partner's display name and avatar initial
- Shows partner's current streak (always visible)
- Shows "Active today" / "Last active X days ago"
- Shows encouragement button

**Acceptance Criteria:**

- [ ] Partner name truncates at 20 chars with ellipsis
- [ ] Streak shows flame icon + number
- [ ] "Active today" = quest completed today
- [ ] "Needs check-in" = no activity 2+ days

**FR-2.2: Shared Data Display**

- Mood card: shows partner's last 7 moods (if shared)
- Quest card: shows partner's today quest status (if shared)
- Placeholder: "Your partner hasn't shared this yet" (if not shared)

**Acceptance Criteria:**

- [ ] Mood card shows mood emoji + date for each entry
- [ ] Quest card shows quest title + completion status
- [ ] Placeholders have soft styling (muted colors)
- [ ] Refresh on pull-to-refresh

### FR-3: Sharing Settings

**FR-3.1: Toggle Controls**

- Toggle for "Share my mood with partner"
- Toggle for "Share my exercises with partner"
- Each toggle saves immediately to `partner_links` table

**Acceptance Criteria:**

- [ ] Toggles default to OFF for new partnerships
- [ ] Changes save within 500ms of toggle
- [ ] Show loading indicator during save
- [ ] Error toast if save fails (auto-retry)
- [ ] Changes take effect immediately in partner's view

### FR-4: Shared Exercises

**FR-4.1: Exercise Library**

- List of couples exercises (from `couples_exercises` table)
- Categories: communication, intimacy, goal-setting, mindfulness
- Premium badge on premium-only exercises

**Acceptance Criteria:**

- [ ] Group by category with section headers
- [ ] Show exercise name, duration, difficulty
- [ ] Premium exercises show lock icon for free users
- [ ] Either partner's premium unlocks for both

**FR-4.2: Start Session**

- Tap exercise → detail view with instructions
- "Start Together" button creates session
- Partner receives notification with "Join" action

**Acceptance Criteria:**

- [ ] Session expires after 24 hours if not joined
- [ ] Show "Waiting for partner" state after starting
- [ ] Partner can join from notification or app
- [ ] Both see synchronized progress indicators

### FR-5: Encouragement Messages

**FR-5.1: Send Encouragement**

- User taps encouragement button
- Shows picker: "encouragement", "celebration", "check_in"
- Sends to `buddy_encouragements` table
- Triggers push notification to partner

**Acceptance Criteria:**

- [ ] Rate limit: 1 encouragement per hour
- [ ] Show confirmation animation on send
- [ ] Notification includes sender name + message type
- [ ] Tapping notification opens app to partner dashboard

---

## 3. Technical Specifications

### 3.1 Architecture

```
PartnerModeView
├── PartnerOnboardingView (no partner)
│   ├── SendInviteTab
│   │   ├── InviteCodeDisplay
│   │   └── ShareActions
│   └── AcceptInviteTab
│       ├── CodeEntryField
│       └── ValidationFeedback
│
└── PartnerDashboardView (has partner)
    ├── PartnerStatusCard
    ├── SharedMoodCard (or PartnerPlaceholder)
    ├── SharedQuestCard (or PartnerPlaceholder)
    ├── SharedExercisesSection
    └── EncouragementButton
```

### 3.2 ViewModel

```swift
@MainActor
final class PartnerModeViewModel: ObservableObject {
    // State
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

    enum PartnerState {
        case loading
        case noPartner
        case hasPartner(PartnerInfo)
    }

    struct PartnerInfo {
        let partnerId: UUID
        let partnerName: String
        let partnerStreak: Int
        let hasCompletedToday: Bool
        let lastActive: Date
        let isSharingMood: Bool
        let isSharingExercises: Bool
    }

    struct SharingSettings {
        var shareMood: Bool
        var shareExercises: Bool
    }

    // Actions
    func loadPartnerData() async
    func generateInviteCode() async
    func acceptInviteCode(_ code: String) async
    func updateSharingSettings(_ settings: SharingSettings) async
    func sendEncouragement(_ type: BuddyEncouragement.MessageType) async
    func loadCouplesExercises() async
    func startExerciseSession(_ exerciseId: UUID) async
}
```

### 3.3 Service Methods (add to SupabaseDataService)

```swift
// Partner Links
func getActivePartnerLink() async throws -> PartnerLink?
func updatePartnerSharingSettings(shareMood: Bool, shareExercises: Bool) async throws
func endPartnership() async throws

// Partner Data (respects sharing settings)
func getPartnerMoodHistory(partnerId: UUID) async throws -> [MoodEntry]
func getPartnerQuestStatus(partnerId: UUID) async throws -> Quest?

// Couples Exercises
func getCouplesExercises() async throws -> [CouplesExercise]
func startCouplesSession(exerciseId: UUID) async throws -> CouplesExerciseSession
func joinCouplesSession(sessionId: UUID) async throws -> CouplesExerciseSession
func updateSessionProgress(sessionId: UUID, progress: Int) async throws
func completeSession(sessionId: UUID, rating: Int, notes: String?) async throws
```

### 3.4 Data Flow

```
User Action → ViewModel → SupabaseDataService → Supabase RPC/Table
                                                      ↓
UI Update ← ViewModel ← Response/Error ←─────────────┘
```

### 3.5 Navigation

```swift
// In Settings or Profile
NavigationLink(destination: PartnerModeView()) {
    SettingsRow(icon: "person.2.fill", title: "Partner Mode")
}

// Deep link handler (in App)
.onOpenURL { url in
    if url.host == "partner", url.pathComponents.contains("accept"),
       let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
           .queryItems?.first(where: { $0.name == "code" })?.value {
        // Navigate to PartnerModeView with pre-filled code
        appState.pendingPartnerCode = code
        appState.selectedTab = .profile
    }
}
```

---

## 4. UI/UX Details

### 4.1 PartnerOnboardingView Layout

```
┌─────────────────────────────────────┐
│        Partner Mode                  │
│  ══════════════════════════════════ │
│                                      │
│  [👥 Icon]                          │
│                                      │
│  "Partner up for accountability"     │
│  "Share progress and encourage"      │
│                                      │
│  ┌───────────────────────────────┐  │
│  │ [Send Invite] │ [Enter Code]  │  │
│  └───────────────────────────────┘  │
│                                      │
│  ── Send Invite Tab ──              │
│  ┌───────────────────────────────┐  │
│  │  Your invite code:            │  │
│  │     [A B 7 X 2 Q]             │  │
│  │  Expires in 30 days           │  │
│  │                               │  │
│  │  [Copy Code] [Share]          │  │
│  └───────────────────────────────┘  │
│                                      │
│  ── Enter Code Tab ──               │
│  ┌───────────────────────────────┐  │
│  │  Enter partner's code:        │  │
│  │  [ _ ] [ _ ] [ _ ] [ _ ]      │  │
│  │  [ _ ] [ _ ]                  │  │
│  │                               │  │
│  │  [Connect]                    │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### 4.2 PartnerDashboardView Layout

```
┌─────────────────────────────────────┐
│        Your Partner                  │
│  ══════════════════════════════════ │
│                                      │
│  ┌───────────────────────────────┐  │
│  │ [J] Jamie           🔥 12     │  │
│  │ Active today ✓                │  │
│  │ [👋 Send Encouragement]       │  │
│  └───────────────────────────────┘  │
│                                      │
│  ┌─ Their Mood ─────────────────┐   │
│  │ 😊 Mon  😐 Tue  😊 Wed ...   │   │
│  └───────────────────────────────┘  │
│                                      │
│  ┌─ Today's Quest ──────────────┐   │
│  │ "Take a 5-minute walk"       │   │
│  │ ✅ Completed                  │   │
│  └───────────────────────────────┘  │
│                                      │
│  ── Together ──                     │
│  ┌───────────────────────────────┐  │
│  │ 🧘 Start an exercise together │  │
│  │ →                             │  │
│  └───────────────────────────────┘  │
│                                      │
│  [⚙️ Sharing Settings]              │
└─────────────────────────────────────┘
```

### 4.3 Styling

- Use `Color.accentColor` for primary actions
- Partner avatar: rounded circle with first initial
- Cards: `.secondarySystemBackground` with 16pt corner radius
- Spacing: 16pt between sections, 12pt within sections
- Icons: SF Symbols, 20pt size for inline, 60pt for headers

### 4.4 Accessibility

- VoiceOver labels on all interactive elements
- Dynamic Type support (up to accessibility sizes)
- Minimum tap targets: 44x44pt
- Code entry field: announce each digit as entered
- Encouragement button: announce rate limit if blocked

---

## 5. Edge Cases

### 5.1 Network Failures

| Scenario                | Handling                                    |
| ----------------------- | ------------------------------------------- |
| Generate code fails     | Show error + retry button                   |
| Accept code fails       | Show specific error message                 |
| Load partner data fails | Show cached data if available, retry banner |
| Sharing toggle fails    | Auto-retry 3x, then show error toast        |
| Start session fails     | Show error + retry option                   |

### 5.2 Partnership States

| State                       | Behavior                                        |
| --------------------------- | ----------------------------------------------- |
| No partner                  | Show PartnerOnboardingView                      |
| Pending invite (as inviter) | Show "Waiting for partner" + code               |
| Active partner              | Show PartnerDashboardView                       |
| Partner ended partnership   | Show "Partnership ended" + return to onboarding |
| Partner deleted account     | Same as ended                                   |

### 5.3 Premium Access

| Scenario            | Behavior               |
| ------------------- | ---------------------- |
| Neither has premium | Lock premium exercises |
| User has premium    | Unlock all for both    |
| Partner has premium | Unlock all for both    |
| Both have premium   | Unlock all             |

### 5.4 Offline Behavior

| Feature            | Offline Handling                      |
| ------------------ | ------------------------------------- |
| View dashboard     | Show cached data with "offline" badge |
| Generate code      | Block - requires network              |
| Accept code        | Block - requires network              |
| Toggle sharing     | Queue change, apply when online       |
| Send encouragement | Queue, send when online               |
| Start session      | Block - requires network              |

---

## 6. Test Cases

### 6.1 Unit Tests (PartnerModeViewModelTests.swift)

```swift
// Code Generation
func test_generateInviteCode_success()
func test_generateInviteCode_rateLimited()

// Code Acceptance
func test_acceptCode_success()
func test_acceptCode_invalidCode()
func test_acceptCode_expiredCode()
func test_acceptCode_selfInvite()
func test_acceptCode_alreadyPartnered()

// Sharing Settings
func test_updateSharingSettings_success()
func test_updateSharingSettings_networkFailure_retries()

// Encouragement
func test_sendEncouragement_success()
func test_sendEncouragement_rateLimited()

// Sessions
func test_startSession_success()
func test_startSession_premiumRequired()
func test_joinSession_expired()
```

### 6.2 Integration Tests

```swift
// Full Flows
func test_completeOnboardingFlow_bothUsers()
func test_sharingToggles_affectPartnerView()
func test_encouragementNotification_delivered()
func test_couplesSession_synchronization()
```

### 6.3 UI Tests

```swift
func test_codeEntry_acceptsValidInput()
func test_codeEntry_rejectsInvalidChars()
func test_dashboard_showsPartnerData()
func test_dashboard_showsPlaceholder_whenNotShared()
func test_deepLink_prefillsCode()
```

---

## 7. Files to Create

| File                                                   | Type      |
| ------------------------------------------------------ | --------- |
| `Features/Partner/PartnerModeView.swift`               | View      |
| `Features/Partner/PartnerModeViewModel.swift`          | ViewModel |
| `Features/Partner/PartnerOnboardingView.swift`         | View      |
| `Features/Partner/AcceptInviteView.swift`              | View      |
| `Features/Partner/PartnerDashboardView.swift`          | View      |
| `Features/Partner/PartnerSharingSettingsView.swift`    | View      |
| `Features/Partner/SharedExercisesView.swift`           | View      |
| `Features/Partner/EncouragementPickerSheet.swift`      | View      |
| `Features/Partner/Components/PartnerStatusCard.swift`  | Component |
| `Features/Partner/Components/SharedMoodCard.swift`     | Component |
| `Features/Partner/Components/SharedQuestCard.swift`    | Component |
| `Features/Partner/Components/CodeEntryField.swift`     | Component |
| `Features/Partner/Components/InviteCodeDisplay.swift`  | Component |
| `Features/Partner/Components/PartnerPlaceholder.swift` | Component |
| `MindFriendAppTests/PartnerModeViewModelTests.swift`   | Test      |

---

## 8. Technical Clarifications

### 8.1 Data Synchronization Strategy

**Decision**: Use polling (30-second interval) rather than Supabase Realtime for Partner Mode.

**Rationale**:

- Existing buddy widget uses polling pattern (via `loadData()` in HomeView)
- Partner data changes infrequently (mood updates 1-2x/day, sharing toggles rarely)
- Simplifies implementation without subscription management

**Implementation**:

```swift
// In PartnerDashboardView
.onAppear { startPolling() }
.onDisappear { stopPolling() }
.refreshable { await viewModel.loadPartnerData() }

private func startPolling() {
    pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
        Task { await viewModel.loadPartnerData() }
    }
}
```

### 8.2 Bidirectional Column Mapping

The `partner_links` table uses `user_1_*` and `user_2_*` columns. Mapping logic:

```swift
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
```

### 8.3 Rate Limit Enforcement

**Invite Code Rate Limit**: Already enforced at database level via `check_buddy_invite_limit` trigger in migration `20260217000000_onboarding_buddy.sql` (max 10/day).

**Encouragement Rate Limit**: Implement in service layer with local check:

```swift
func sendEncouragement(to buddyId: String, relationshipId: String, type: MessageType) async throws {
    // Check local cache for last send time
    let lastSendKey = "lastEncouragement_\(relationshipId)"
    if let lastSend = UserDefaults.standard.object(forKey: lastSendKey) as? Date,
       Date().timeIntervalSince(lastSend) < 3600 {
        throw CouplesModeError.rateLimited(retryAfterSeconds: Int(3600 - Date().timeIntervalSince(lastSend)))
    }

    // Send encouragement (existing implementation)
    try await supabase.from("buddy_encouragements").insert(...)

    // Update local cache
    UserDefaults.standard.set(Date(), forKey: lastSendKey)
}
```

### 8.4 Code Regeneration Behavior

**Decision**: Return existing unexpired code if available; generate new code only if none exists or all are expired.

```swift
func getOrCreateInviteCode() async throws -> String {
    // Check for existing pending invite
    let existing: [BuddyRelationship] = try await supabase
        .from("buddy_relationships")
        .select()
        .eq("inviter_id", value: userId)
        .eq("status", value: "pending")
        .gt("expires_at", value: ISO8601DateFormatter().string(from: Date()))
        .limit(1)
        .execute()
        .value

    if let existingCode = existing.first?.inviteCode {
        return existingCode
    }

    // Generate new code
    return try await createBuddyInvite(contact: "", method: .link).inviteCode
}
```

### 8.5 Session State Management

**Decision**: Database is source of truth. Use optimistic updates with last-write-wins.

```swift
func updateSessionProgress(sessionId: UUID, progress: Int) async throws {
    // Optimistic update
    await MainActor.run { activeSession?.userProgress = progress }

    // Database update (last-write-wins)
    try await supabase
        .from("couples_exercise_sessions")
        .update(["user_1_progress_percent": progress, "last_activity_at": Date()])
        .eq("id", value: sessionId)
        .execute()
}
```

### 8.6 Sharing Toggle Failure Recovery

```swift
struct SharingToggleState {
    var value: Bool
    var pendingValue: Bool?  // Set when save in progress
    var retryCount: Int = 0

    mutating func onSaveSuccess() {
        value = pendingValue ?? value
        pendingValue = nil
        retryCount = 0
    }

    mutating func onSaveFailure() -> Bool {
        retryCount += 1
        if retryCount >= 3 {
            pendingValue = nil  // Revert to last known state
            retryCount = 0
            return false  // Show error toast
        }
        return true  // Will auto-retry
    }
}
```

---

## 9. Additional Edge Cases

### 9.1 Simultaneous Mutual Code Entry

**Scenario**: Alice enters Bob's code while Bob enters Alice's code.
**Behavior**: First to complete wins (database constraint). Second gets "Already partnered" error.

### 9.2 Code Used While Inviter Offline

**Scenario**: Alice generates code, goes offline. Bob accepts.
**Behavior**: Partnership created. Alice sees partner on next app launch.

### 9.3 Partner Changes Sharing While Viewing

**Scenario**: Bob views Alice's moods. Alice disables mood sharing.
**Behavior**: Next poll (30s) replaces mood card with placeholder.

### 9.4 In-Progress Session Partner Disconnects

**Scenario**: Mid-session, Alice force-quits app.
**Behavior**: Bob sees stale progress after 60s. Session remains active 24h. Alice can resume.

### 9.5 Deep Link When Already Partnered

**Scenario**: Alice has partner Bob. Carol sends Alice a code via deep link.
**Behavior**: Show alert: "You already have a partner. End partnership to accept new invite?" Options: Cancel / End & Accept.

---

## 10. Implementation Order

1. **Phase 1**: PartnerModeViewModel + service methods
2. **Phase 2**: PartnerModeView + PartnerOnboardingView (invite/accept)
3. **Phase 3**: PartnerDashboardView + status cards
4. **Phase 4**: PartnerSharingSettingsView + toggle persistence
5. **Phase 5**: SharedExercisesView + session management
6. **Phase 6**: EncouragementPickerSheet + notifications
7. **Phase 7**: Deep link handling + navigation integration
8. **Phase 8**: Tests + polish
