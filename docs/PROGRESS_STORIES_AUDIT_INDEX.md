# Progress Stories Reliability Audit - Index & Quick Reference

**Audit Date:** 2026-01-20  
**Scope:** Edge Function + iOS ViewModel + Views  
**Overall Score:** 5/10 ❌

---

## Documents

| Document | Purpose | Length |
|----------|---------|--------|
| **PROGRESS_STORIES_RELIABILITY_AUDIT.md** | Complete analysis with all 14 issues, evidence, impact assessment | 490 lines |
| **PROGRESS_STORIES_FIXES.md** | Copy-paste code fixes organized by phase | 808 lines |
| **PROGRESS_STORIES_AUDIT_INDEX.md** | This file - quick reference & checklist | This file |

---

## Quick Issue Lookup

### Critical Issues (MUST FIX)

| # | Issue | File | Line Range | Fix |
|---|-------|------|-----------|-----|
| 1 | Uncaught query failures | `generate-weekly-story/index.ts` | 335-398 | Wrap in try-catch, return defaults |
| 2 | No retry logic | `ProgressStoryViewModel.swift` | 54-96 | Add exponential backoff helper |
| 3 | Missing timeout | `ProgressStoryViewModel.swift` | 54-96 | Add timeout wrapper (30s) |
| 4 | Silent circle load error | `CircleShareSheet.swift` | 235-245 | Show error state with retry |
| 5 | Unsafe array access | `ProgressStoryViewModel.swift` | 104-108 | Use bounds check instead of [safe:] |

### High Priority Issues (SHOULD FIX)

| # | Issue | File | Line Range | Fix |
|---|-------|------|-----------|-----|
| 6 | Profile query not validated | `generate-weekly-story/index.ts` | 231-246 | Add error handling |
| 7 | No error classification | `SupabaseDataService.swift` | 3817-3858 | Map to APIError |
| 8 | Share success not fed back | `CircleShareSheet.swift` | 260-267 | Add callback/state |
| 9 | Upsert failure ignored | `generate-weekly-story/index.ts` | 215-227 | Throw or retry |
| 10 | No timeout indicator | `ProgressStoryViewer.swift` | 54-70 | Show msg after 10s |
| 11 | Upload not validated | `SupabaseDataService.swift` | 3888-3902 | Add size check + verify |

### Medium Priority Issues (NICE TO HAVE)

| # | Issue | Fix |
|---|-------|-----|
| 12 | No offline caching | Cache story to UserDefaults |
| 13 | Date validation edge cases | Use explicit parsing |
| 14 | No circle creation shortcut | Add button in share sheet |

---

## Implementation Checklist

### Phase 1: Critical Fixes (2-3 hours)

- [ ] **Fix #1:** Edge Function query error handling
  - [ ] Add error checks to moods query
  - [ ] Add error checks to quest query
  - [ ] Add error checks to exercise query
  - [ ] Return sensible defaults on error
  
- [ ] **Fix #2:** iOS retry logic
  - [ ] Implement `retryWithBackoff()` helper
  - [ ] Update `loadStory()` to use retry
  - [ ] Update `generateStory()` to use retry
  - [ ] Test with simulated transient error
  
- [ ] **Fix #3:** Timeout protection
  - [ ] Implement `withTimeout()` helper
  - [ ] Wrap `loadStory()` operations
  - [ ] Wrap `generateStory()` operations
  - [ ] Test timeout at 30+ seconds
  
- [ ] **Fix #4:** Circle share error handling
  - [ ] Add `@State var circleLoadError`
  - [ ] Update `loadCircles()` to capture error
  - [ ] Update `circlePicker` view to show error state
  - [ ] Add retry button
  - [ ] Test with permission denied
  
- [ ] **Fix #5:** Array bounds checking
  - [ ] Replace `[safe: index]` with explicit bounds check
  - [ ] Add logging for invalid index
  - [ ] Test with out-of-bounds indices

### Phase 2: High Priority Fixes (1-2 hours)

- [ ] **Fix #6:** Profile query validation
  - [ ] Add error check to profile query
  - [ ] Use defaults if profile missing
  - [ ] Test with missing profile row
  
- [ ] **Fix #7:** Error classification
  - [ ] Implement `classifySupabaseError()` helper
  - [ ] Update `generateWeeklyStory()` to classify errors
  - [ ] Test with network timeout
  - [ ] Test with 503 server error
  
- [ ] **Fix #8:** Share success callback
  - [ ] Add completion handler to CircleShareSheet
  - [ ] Update `postToCircle()` to check error
  - [ ] Dismiss on success, show error on failure
  - [ ] Test success path
  
- [ ] **Fix #9:** Upsert validation
  - [ ] Check permanent vs transient upsert errors
  - [ ] Return 500 for permanent errors
  - [ ] Log transient errors but continue
  - [ ] Test with permission denied
  
- [ ] **Fix #10:** Loading timeout indicator
  - [ ] Add `@State var showLoadingTimeout`
  - [ ] Task that shows msg after 10s
  - [ ] Add retry button
  - [ ] Update loading view UI
  
- [ ] **Fix #11:** Image upload validation
  - [ ] Add size check (max 5MB)
  - [ ] Verify upload response is not nil
  - [ ] Validate generated URL is not empty
  - [ ] Optional: HEAD request to verify accessibility
  - [ ] Test with 10MB image
  - [ ] Test with network error during upload

### Phase 3: Polish Fixes (1 hour)

- [ ] **Fix #12:** Offline caching
  - [ ] Implement cache helpers (save/get/clear)
  - [ ] Update `loadStory()` to use cache as fallback
  - [ ] Test offline path
  
- [ ] **Fix #13:** Date validation
  - [ ] Replace regex with explicit parsing
  - [ ] Handle leap years
  - [ ] Test with invalid dates
  
- [ ] **Fix #14:** Circle creation shortcut
  - [ ] Add "Create Circle" button in share sheet
  - [ ] Navigate to circles tab on tap
  - [ ] Test navigation

---

## Testing Checklist

Before marking fixes as complete, verify:

- [ ] Edge Function handles timeout on profile query
- [ ] Edge Function handles permission denied on moods query
- [ ] iOS retries 3 times on transient error then gives up
- [ ] iOS shows timeout after 30 seconds
- [ ] CircleShareSheet shows error state with retry button
- [ ] CircleShareSheet auto-selects circle if only one exists
- [ ] Loading view shows "taking longer" message after 10 seconds
- [ ] Image upload rejected if >5MB
- [ ] Cached story shown when offline
- [ ] Share to circle succeeds and shows feedback
- [ ] Share to circle fails and shows error message
- [ ] Array bounds violation doesn't crash (returns nil)
- [ ] Profile missing doesn't crash story generation

---

## Files to Review

```
Core files:
├─ supabase/functions/generate-weekly-story/index.ts (786 lines)
├─ apps/ios/MindFriendApp/Features/ProgressStories/ProgressStoryViewModel.swift (285 lines)
├─ apps/ios/MindFriendApp/Features/ProgressStories/ProgressStoryViewer.swift (377 lines)
├─ apps/ios/MindFriendApp/Features/ProgressStories/CircleShareSheet.swift (267 lines)
├─ apps/ios/MindFriendApp/Features/ProgressStories/StoryCardView.swift (354 lines)
└─ apps/ios/MindFriendApp/Networking/Services/SupabaseDataService.swift (story methods at 3782-3902)

Related models:
└─ apps/ios/MindFriendApp/Core/Models.swift (WeeklyStory, StoryCard, etc. at lines 4288+)
```

---

## Severity Reference

| Level | Criteria | Action |
|-------|----------|--------|
| CRITICAL | Crash, silent data loss, infinite wait, undefined behavior | **Must fix before production** |
| HIGH | Data integrity risk, poor error feedback, temporary hang | **Should fix before production** |
| MEDIUM | Missing nice-to-have features, edge cases | **Polish after MVP** |

---

## Risk Scoring

**Crash Risk:** 🔴 MEDIUM
- Unsafe array access (`[safe: index]` may not be globally available)
- Missing profile validation could fail story generation

**Data Loss Risk:** 🔴 MEDIUM
- Upsert failures silently ignored (story not persisted)
- No validation that upload succeeded

**User Confusion Risk:** 🔴 HIGH
- Silent circle loading failures
- No error messages for network issues
- Loading spinner with no timeout indication

**Network Resilience:** 🔴 CRITICAL
- No retry mechanism for transient errors
- No timeout protection (indefinite wait possible)
- No fallback for offline scenarios

---

## Implementation Order

1. **Start with Fix #3 (Timeout)** → Unblocks other async work, prevents hangs
2. **Then Fix #2 (Retry)** → Makes network more resilient
3. **Then Fix #1, #4, #5** → Fixes remaining critical issues
4. **Then Fix #6-#11** → Improves data integrity and feedback
5. **Then Fix #12-#14** → Polish and offline support

This order ensures the most impactful improvements happen first.

---

## Success Criteria for 10/10

All of the following must be true:

- [ ] All Edge Function queries have error handling
- [ ] All iOS async operations have timeout wrapper
- [ ] All iOS network failures have retry (max 3x) with backoff
- [ ] All user errors are shown with clear messaging
- [ ] No silent failures (errors logged + user notified)
- [ ] All array access bounds-checked
- [ ] Image uploads validated (size + success)
- [ ] Latest story cached for offline access
- [ ] Loading state shows timeout message after 10 seconds
- [ ] All verification tests pass

---

## Estimated Timeline

| Phase | Effort | Risk | Complexity |
|-------|--------|------|-----------|
| Phase 1 (Critical) | 2-3 hrs | Medium | Medium |
| Phase 2 (High) | 1-2 hrs | Low | Medium |
| Phase 3 (Polish) | 1 hr | Low | Low |
| **Total** | **4-6 hrs** | **Overall: Low** | **Overall: Medium** |

---

## Rollback Plan

If issues arise during implementation:

1. Most fixes are additive (new error handling doesn't remove existing logic)
2. Fixes are localized to specific functions (minimal blast radius)
3. To rollback: revert changes in reverse order
4. No database migrations required (all logic changes)

---

## Questions?

- See **PROGRESS_STORIES_RELIABILITY_AUDIT.md** for detailed analysis
- See **PROGRESS_STORIES_FIXES.md** for code implementation
- Each fix includes "why" and "how" rationale

---

**Last Updated:** 2026-01-20  
**Status:** ✅ Audit Complete, Ready for Implementation
