# Partner Mode UX - Implementation Summary

**Plan Location:** `/Users/danny/Documents/Codez/Apps/MindFriend/.claude/plans/partner-mode-ux-plan.md`  
**Spec Location:** `/Users/danny/Documents/Codez/Apps/MindFriend/.claude/specs/partner-mode-ux-spec.md`  
**Status:** Ready for Implementation  
**Estimated Timeline:** 27 hours (3-4 days)

---

## Quick Stats

- **Files to Create:** 17 files (~3,910 lines)
- **Files to Modify:** 5 files (low risk)
- **Service Methods:** 13 new methods in SupabaseDataService
- **Test Cases:** 15+ unit tests, 2 integration tests, 3 UI tests
- **Implementation Phases:** 8 phases

---

## What Gets Built

### Core Features (P0)
1. **Onboarding Flow** - Generate/accept invite codes (reuses buddy system)
2. **Partner Dashboard** - View partner's streak, mood, quest status
3. **Sharing Settings** - Toggle what data to share (mood, exercises)
4. **Deep Linking** - Accept invites via `mindfriend://partner/accept?code=XXX`

### Enhanced Features (P1)
5. **Shared Exercises** - Browse couples exercise library
6. **Encouragement** - Send encouragement messages (rate limited)

### Future Features (P2)
7. **Exercise Sessions** - Complete exercises together with progress sync

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Reuse buddy invite system | Avoids duplicating code generation/validation logic |
| Polling (30s) vs Realtime | Data changes infrequently, simpler implementation |
| Bidirectional column mapping | `partner_links` supports asymmetric sharing settings |
| Rate limiting | 10 invites/day (DB), 1 encouragement/hour (local) |

---

## Architecture at a Glance

```
PartnerModeView (container)
├── if no partner: PartnerOnboardingView
│   ├── Send Invite tab (InviteCodeDisplay)
│   └── Enter Code tab (CodeEntryField)
└── if has partner: PartnerDashboardView
    ├── PartnerStatusCard
    ├── SharedMoodCard (or PartnerPlaceholder)
    ├── SharedQuestCard (or PartnerPlaceholder)
    ├── SharedExercisesView link
    ├── EncouragementPickerSheet
    └── PartnerSharingSettingsView link
```

---

## Implementation Phases

| Phase | Focus | Time | Checkpoint |
|-------|-------|------|------------|
| 1 | Foundation (ViewModel + Service Methods) | 3h | Tests compile |
| 2 | Onboarding Views | 4h | Can generate/accept codes |
| 3 | Dashboard Views | 5h | Shows partner data |
| 4 | Sharing Settings | 3h | Toggles save, changes visible |
| 5 | Shared Exercises | 4h | Can browse exercises |
| 6 | Encouragement | 2h | Can send messages |
| 7 | Deep Linking & Navigation | 2h | Deep links work |
| 8 | Testing & Polish | 4h | All tests pass |

**Total: 27 hours**

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking buddy system | Reuse RPCs, no schema changes |
| Race conditions | DB constraints, first-wins |
| Polling performance | 30s interval, conservative |
| Toggle save failures | Auto-retry 3x, revert on failure |
| Deep link injection | Validate format before processing |

---

## Rollback Plan

1. **Feature flag:** `PARTNER_MODE_ENABLED = false` hides UI
2. **Code removal:** All files isolated in `Features/Partner/`
3. **Database:** No schema changes needed (tables already exist)

---

## Next Steps

1. **Review plan** with team
2. **Begin Phase 1:** ViewModel + Service Methods
3. **Checkpoint after each phase** before proceeding
4. **Log progress** in `docs/PROGRESS.md` after each phase

---

## File Structure Preview

```
apps/ios/MindFriendApp/
├── Features/
│   └── Partner/                           # NEW DIRECTORY
│       ├── PartnerModeView.swift          # Main container
│       ├── PartnerModeViewModel.swift     # Business logic
│       ├── PartnerOnboardingView.swift    # Invite/accept UI
│       ├── PartnerDashboardView.swift     # Main dashboard
│       ├── PartnerSharingSettingsView.swift
│       ├── SharedExercisesView.swift
│       ├── SharedExerciseSessionView.swift
│       ├── EncouragementPickerSheet.swift
│       └── Components/
│           ├── PartnerStatusCard.swift
│           ├── SharedMoodCard.swift
│           ├── SharedQuestCard.swift
│           ├── InviteCodeDisplay.swift
│           ├── CodeEntryField.swift
│           ├── PartnerPlaceholder.swift
│           └── SharingToggleRow.swift
├── Networking/Services/
│   └── SupabaseDataService.swift          # MODIFY: Add 13 methods
└── MindFriendAppTests/
    └── PartnerModeViewModelTests.swift    # NEW: Unit tests
```

---

## Service Methods Added

```swift
// Partner Links
func getActivePartnerLink() async throws -> PartnerLink?
func updatePartnerSharingSettings(shareMood: Bool, shareExercises: Bool) async throws
func endPartnership() async throws

// Partner Data (respects sharing)
func getPartnerMoodHistory(partnerId: UUID) async throws -> [MoodEntry]
func getPartnerQuestStatus(partnerId: UUID) async throws -> Quest?

// Couples Exercises
func getCouplesExercises() async throws -> [CouplesExercise]
func startCouplesSession(exerciseId: UUID) async throws -> CouplesExerciseSession
func joinCouplesSession(sessionId: UUID) async throws -> CouplesExerciseSession
func updateSessionProgress(sessionId: UUID, progress: Int) async throws
func completeSession(sessionId: UUID, rating: Int, notes: String?) async throws

// Invites (reuses buddy system)
func getOrCreatePartnerInviteCode() async throws -> String
func acceptPartnerInvite(code: String) async throws -> BuddyRelationship
```

---

*See full plan: `.claude/plans/partner-mode-ux-plan.md`*
