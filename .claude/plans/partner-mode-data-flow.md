# Partner Mode - Data Flow Diagrams

## 1. Onboarding Flow (Code Generation)

```
User A                    ViewModel               SupabaseDataService       Database
  |                          |                           |                      |
  |-- Tap "Create Invite" -->|                           |                      |
  |                          |-- generateInviteCode() -->|                      |
  |                          |                           |-- getPendingBuddyInvites() ->|
  |                          |                           |<-- [BuddyRelationship] --|
  |                          |                           |                      |
  |                          |   (if no existing code)   |                      |
  |                          |                           |-- createBuddyInvite() ---->|
  |                          |                           |                      |-- generate_buddy_code() RPC
  |                          |                           |                      |-- INSERT buddy_relationships
  |                          |                           |<-- BuddyRelationship --|
  |                          |<-- inviteCode: "ABC123" --|                      |
  |<-- Display code "ABC123" |                           |                      |
  |                          |                           |                      |
  |-- Tap "Copy" ----------->|                           |                      |
  |<-- UIPasteboard.string --|                           |                      |
  |                          |                           |                      |
```

## 2. Onboarding Flow (Code Acceptance)

```
User B                    ViewModel               SupabaseDataService       Database
  |                          |                           |                      |
  |-- Enter code "ABC123" -->|                           |                      |
  |                          | codeInput = "ABC123"      |                      |
  |                          |                           |                      |
  |-- Tap "Connect" -------->|                           |                      |
  |                          |-- acceptInviteCode() ---->|                      |
  |                          |                           |-- getActivePartnerLink() ->|
  |                          |                           |<-- nil (no partner) --|
  |                          |                           |                      |
  |                          |                           |-- acceptBuddyInvite() ---->|
  |                          |                           |                      |-- accept_buddy_invite() RPC
  |                          |                           |                      |-- UPDATE buddy_relationships
  |                          |                           |                      |-- CREATE circles entry
  |                          |                           |<-- BuddyRelationship --|
  |                          |                           |                      |
  |                          |                           |-- INSERT partner_links ---->|
  |                          |                           |                      |-- status = 'active'
  |                          |                           |                      |-- both sharing = false
  |                          |                           |<-- PartnerLink ---------|
  |                          |<-- BuddyRelationship -----|                      |
  |                          |                           |                      |
  |                          | partnerState = .hasPartner|                      |
  |<-- Navigate to Dashboard |                           |                      |
  |                          |                           |                      |
```

## 3. Dashboard Data Loading

```
User                      ViewModel               SupabaseDataService       Database
  |                          |                           |                      |
  |-- View dashboard ------->|                           |                      |
  |                          |-- loadPartnerData() ----->|                      |
  |                          |                           |                      |
  |                          |                           |-- getActivePartnerLink() ->|
  |                          |                           |<-- PartnerLink ---------|
  |                          |                           |                      |
  |                          |                           | partnerId = link.partnerId(userId)
  |                          |                           | partnerSettings = link.partnerSharingSettings(userId)
  |                          |                           |                      |
  |                          |                           | if partnerSettings.shareMood:
  |                          |                           |-- getPartnerMoodHistory() ->|
  |                          |                           |<-- [MoodEntry] ---------|
  |                          |                           |                      |
  |                          |                           | if partnerSettings.shareExercises:
  |                          |                           |-- getPartnerQuestStatus() ->|
  |                          |                           |<-- Quest? -------------|
  |                          |                           |                      |
  |                          |<-- PartnerInfo ----------|                      |
  |                          |                           |                      |
  |                          | partnerState = .hasPartner(PartnerInfo)
  |<-- Display cards --------|                           |                      |
  |                          |                           |                      |
  |                          | [Start polling timer: 30s]|                      |
  |                          | ... wait 30s ...          |                      |
  |                          |-- loadPartnerData() ----->|                      |
  |                          |   (loop)                  |                      |
  |                          |                           |                      |
```

## 4. Sharing Settings Update

```
User A                    ViewModel               SupabaseDataService       Database
  |                          |                           |                      |
  |-- Toggle "Share Mood" -->|                           |                      |
  |                          | isSavingSharingSettings = true                   |
  |                          |-- updateSharingSettings() ->|                     |
  |                          |                           |                      |
  |                          |                           |-- getActivePartnerLink() ->|
  |                          |                           |<-- PartnerLink ---------|
  |                          |                           |                      |
  |                          |                           | isUser1 = (userId == link.userId1)
  |                          |                           |                      |
  |                          |                           |-- UPDATE partner_links ---->|
  |                          |                           |   SET user_1_share_mood = true
  |                          |                           |<-- SUCCESS --------------|
  |                          |<-- void ------------------|                      |
  |                          |                           |                      |
  |                          | isSavingSharingSettings = false
  |<-- Toggle switches ------|                           |                      |
  |                          |                           |                      |
  |                          |                           |                      |
User B (30s later)          |                           |                      |
  |                          |                           |                      |
  |                          |-- loadPartnerData() ----->|                      |
  |                          |   (via polling timer)     |                      |
  |                          |                           |-- getActivePartnerLink() ->|
  |                          |                           |<-- PartnerLink ---------|
  |                          |                           |   (user_1_share_mood = true)
  |                          |                           |                      |
  |                          |                           |-- getPartnerMoodHistory() ->|
  |                          |                           |<-- [MoodEntry] ---------|
  |                          |<-- PartnerInfo ----------|                      |
  |                          |                           |                      |
  |<-- Mood card appears ----|                           |                      |
  |                          |                           |                      |
```

## 5. Encouragement Flow

```
User A                    ViewModel               SupabaseDataService       Database
  |                          |                           |                      |
  |-- Tap "Send Encourage" ->|                           |                      |
  |                          | showEncouragementPicker = true
  |<-- Show sheet -----------|                           |                      |
  |                          |                           |                      |
  |-- Tap "Encouragement" -->|                           |                      |
  |                          |-- sendEncouragement() --->|                      |
  |                          |                           |                      |
  |                          |                           | Check local cache:   |
  |                          |                           | lastEncouragement_<relationshipId>
  |                          |                           | if < 1 hour ago:     |
  |                          |                           |   throw rateLimited  |
  |                          |                           |                      |
  |                          |                           |-- INSERT buddy_encouragements ->|
  |                          |                           |<-- SUCCESS --------------|
  |                          |                           |                      |
  |                          |                           |-- invoke send-notification Edge Function ->|
  |                          |                           |   (type: buddy_encouragement)
  |                          |                           |   (recipientId: partnerId)
  |                          |                           |<-- SUCCESS --------------|
  |                          |                           |                      |
  |                          |                           | Update local cache:  |
  |                          |                           | UserDefaults.set(Date())
  |                          |<-- void ------------------|                      |
  |                          |                           |                      |
  |<-- Success animation ----|                           |                      |
  |                          |                           |                      |
  |                          |                           |                      |
User B                      |                           |                      |
  |                          |                           |                      |
  |<-- Push notification ----|                           |                      |
  |   "Your partner sent you encouragement!"             |                      |
  |                          |                           |                      |
```

## 6. Couples Exercise Session Flow

```
User A                    ViewModel               SupabaseDataService       Database
  |                          |                           |                      |
  |-- Tap exercise --------->|                           |                      |
  |                          |-- loadCouplesExercises() ->|                     |
  |                          |                           |-- SELECT couples_exercises ->|
  |                          |                           |<-- [CouplesExercise] ---|
  |                          |<-- exercises -------------|                      |
  |<-- Display list ---------|                           |                      |
  |                          |                           |                      |
  |-- Tap "Start Together" ->|                           |                      |
  |                          |-- startExerciseSession() ->|                     |
  |                          |                           |                      |
  |                          |                           |-- getActivePartnerLink() ->|
  |                          |                           |<-- PartnerLink ---------|
  |                          |                           |                      |
  |                          |                           |-- SELECT couples_exercises ->|
  |                          |                           |   WHERE id = exerciseId
  |                          |                           |<-- CouplesExercise -----|
  |                          |                           |                      |
  |                          |                           | if exercise.requiresPremium:
  |                          |                           |   throw exercisePremiumOnly
  |                          |                           |                      |
  |                          |                           |-- INSERT couples_exercise_sessions ->|
  |                          |                           |   status = 'pending'
  |                          |                           |   user_1_progress = 0
  |                          |                           |<-- CouplesExerciseSession --|
  |                          |                           |                      |
  |                          |                           |-- invoke send-notification Edge Function ->|
  |                          |                           |   (type: couples_exercise_invite)
  |                          |                           |   (recipientId: partnerId)
  |                          |                           |<-- SUCCESS --------------|
  |                          |<-- CouplesExerciseSession |                      |
  |                          |                           |                      |
  |<-- "Waiting for partner" |                           |                      |
  |                          |                           |                      |
  |                          |                           |                      |
User B                      |                           |                      |
  |<-- Push notification ----|                           |                      |
  |   "Your partner wants to do an exercise together"    |                      |
  |                          |                           |                      |
  |-- Tap notification ----->|                           |                      |
  |                          |-- joinCouplesSession() -->|                      |
  |                          |                           |-- UPDATE couples_exercise_sessions ->|
  |                          |                           |   status = 'in_progress'
  |                          |                           |<-- CouplesExerciseSession --|
  |                          |<-- session ---------------|                      |
  |                          |                           |                      |
  |<-- Navigate to session --|                           |                      |
  |                          |                           |                      |
Both users                  |                           |                      |
  |-- Update progress ------>|-- updateSessionProgress() ->|                    |
  |                          |                           |-- UPDATE couples_exercise_sessions ->|
  |                          |                           |   user_X_progress_percent = N
  |                          |                           |<-- SUCCESS --------------|
  |                          |                           |                      |
  |-- Complete exercise ---->|-- completeSession() ----->|                      |
  |                          |                           |-- UPDATE couples_exercise_sessions ->|
  |                          |                           |   user_X_rating = 5
  |                          |                           |   (if both rated: status = 'completed')
  |                          |                           |<-- SUCCESS --------------|
  |                          |<-- void ------------------|                      |
  |<-- Success screen -------|                           |                      |
  |                          |                           |                      |
```

## 7. Error Recovery Flow (Sharing Settings)

```
User                      ViewModel               SupabaseDataService       Database
  |                          |                           |                      |
  |-- Toggle "Share Mood" -->|                           |                      |
  |                          | pendingValue = true       |                      |
  |                          |-- updateSharingSettings() ->| (Attempt 1)        |
  |                          |                           |-- UPDATE partner_links ---->|
  |                          |                           |<-- NETWORK ERROR -------|
  |                          |                           |                      |
  |                          |   ... wait 1s ...         |                      |
  |                          |                           |-- UPDATE partner_links ---->|
  |                          |                           |   (Attempt 2)        |
  |                          |                           |<-- NETWORK ERROR -------|
  |                          |                           |                      |
  |                          |   ... wait 2s ...         |                      |
  |                          |                           |-- UPDATE partner_links ---->|
  |                          |                           |   (Attempt 3)        |
  |                          |                           |<-- NETWORK ERROR -------|
  |                          |                           |                      |
  |                          |<-- throw internalError ---|                      |
  |                          |                           |                      |
  |                          | pendingValue = nil        |                      |
  |                          | (revert to original value)|                      |
  |<-- Toggle switches back -|                           |                      |
  |<-- Show error toast -----|                           |                      |
  |   "Failed to save. Please try again."                |                      |
  |                          |                           |                      |
```

---

## Database Table Relationships

```
profiles (auth.users)
    ↓
    ├─ buddy_relationships
    │    ├─ inviter_id → profiles.id
    │    ├─ invitee_id → profiles.id
    │    └─ buddy_circle_id → circles.id
    │
    └─ partner_links
         ├─ user_id_1 → auth.users.id
         ├─ user_id_2 → auth.users.id
         └─ couples_exercise_sessions
              ├─ partner_link_id → partner_links.id
              ├─ exercise_id → couples_exercises.id
              ├─ user_id_1 → auth.users.id
              └─ user_id_2 → auth.users.id
```

## Data Flow Summary

| Flow | Direction | Frequency | Trigger |
|------|-----------|-----------|---------|
| Generate invite code | User → DB | Once per partnership | Manual tap |
| Accept invite code | User → DB | Once per partnership | Manual tap |
| Load partner data | DB → User | Every 30s | Polling timer |
| Update sharing settings | User → DB | Rare (~1-2x per week) | Toggle change |
| Send encouragement | User → User (via DB) | ~1x per day | Manual tap |
| Start exercise session | User → User (via DB) | ~1x per week | Manual tap |
| Update session progress | User → DB | ~10x per session | Automatic |

EOF
