# Edge Case Testing: submit-pathway-checkin

## Test Case 1: Day 1 of Phase 1

**Initial State:**

- `current_day = 1`
- `current_phase = 1`
- Phase 1 duration: 14 days

**Expected Behavior:**

- `newDay = 2`
- `daysSoFar = 0` (no previous phases)
- `dayInCurrentPhase = 1` (using newDay: 2 - 0 = 2, but currently uses old value)
- `shouldAdvancePhase = false` (1 < 14)
- Result: day 2, phase 1

**ACTUAL BUG:**
Line 170 uses `userPathway.current_day` instead of `newDay`:

```typescript
const dayInCurrentPhase = userPathway.current_day - daysSoFar;
// Should be: const dayInCurrentPhase = newDay - daysSoFar;
```

---

## Test Case 2: Last Day of Phase 1 (Day 14/14)

**Initial State:**

- `current_day = 14`
- `current_phase = 1`
- Phase 1 duration: 14 days

**Expected Behavior:**

- `newDay = 15`
- `daysSoFar = 0`
- `dayInCurrentPhase = 15` (after increment)
- `shouldAdvancePhase = true` (15 >= 14)
- Result: day 15, phase 2

**ACTUAL BUG:**
Using old `current_day`:

- `dayInCurrentPhase = 14 - 0 = 14`
- `shouldAdvancePhase = true` (14 >= 14) ✅ Happens to work!

BUT this is off-by-one and will cause issues in multi-day phases.

---

## Test Case 3: First Day of Phase 2 (Day 15)

**Initial State:**

- `current_day = 15`
- `current_phase = 2`
- Phase 1 duration: 14 days
- Phase 2 duration: 21 days

**Expected Behavior:**

- `newDay = 16`
- `daysSoFar = 14` (Phase 1)
- `dayInCurrentPhase = 2` (16 - 14)
- `shouldAdvancePhase = false` (2 < 21)
- Result: day 16, phase 2

**ACTUAL BUG:**
Using old `current_day`:

- `dayInCurrentPhase = 15 - 14 = 1` ← OFF BY ONE!
- This means we're always checking if YESTERDAY completed the phase, not today

---

## Test Case 4: Last Day of Final Phase (Day 63/63, Phase 4)

**Initial State:**

- `current_day = 63`
- `current_phase = 4`
- Total pathway duration: 63 days (14 + 21 + 14 + 14)
- Phase 4 duration: 14 days

**Expected Behavior:**

- `newDay = 64`
- `daysSoFar = 49` (Phases 1-3)
- `dayInCurrentPhase = 15` (64 - 49)
- `shouldAdvancePhase = true` (15 >= 14)
- **SHOULD SET STATUS TO COMPLETED, NOT ADVANCE TO PHASE 5!**

**ACTUAL BUG:**
Lines 180-182 have no validation:

```typescript
if (shouldAdvancePhase) {
  updateData.current_phase = userPathway.current_phase + 1; // = 5 ❌
}
```

This creates:

- `current_phase = 5` (INVALID!)
- Next day's query for Phase 5 will fail
- Pathway is broken forever

**MISSING:**

```typescript
// Query pathway total phases
const { data: allPhases } = await supabaseClient
  .from("pathway_phases")
  .select("phase_number")
  .eq("pathway_id", userPathway.pathway_id)
  .order("phase_number", { ascending: false })
  .limit(1)
  .single();

const maxPhase = allPhases?.phase_number || 4;

if (shouldAdvancePhase) {
  if (userPathway.current_phase < maxPhase) {
    updateData.current_phase = userPathway.current_phase + 1;
  } else {
    // Pathway complete!
    updateData.status = "completed";
    updateData.completed_at = new Date().toISOString();
  }
}
```

---

## Test Case 5: Phase Boundary Edge (Day 14→15, Phase 1→2)

**Scenario:** User completes check-in on last day of phase

**Current Code Flow:**

1. User submits check-in for day 14
2. Progress record created with `day_number = 14`
3. `newDay = 15`
4. `dayInCurrentPhase = 14 - 0 = 14` ← USING OLD VALUE!
5. `shouldAdvancePhase = true`
6. Update: `current_day = 15, current_phase = 2`

**Next Day (Day 15, now Phase 2):**

1. `get-pathway-content` called
2. `current_day = 15, current_phase = 2`
3. `calculateDayInPhase(15, 2)`:
   - `daysSoFar = 14` (Phase 1)
   - Result: `15 - 14 = 1` ✅ CORRECT

**The bug is subtle:** Phase advancement happens correctly by accident because we're checking if the OLD day number completed the phase. But this is semantically wrong and will break if we change the increment order.

---

## Recommended Fixes

### Fix 1: Use newDay for calculation (Line 170)

```typescript
const dayInCurrentPhase = newDay - daysSoFar;
```

### Fix 2: Add max phase validation (Lines 180-194)

```typescript
// Query max phase for this pathway
const { data: maxPhaseData } = await supabaseClient
  .from("pathway_phases")
  .select("phase_number")
  .eq("pathway_id", userPathway.pathway_id)
  .order("phase_number", { ascending: false })
  .limit(1)
  .single();

const maxPhase = maxPhaseData?.phase_number || 4;

if (shouldAdvancePhase) {
  if (userPathway.current_phase < maxPhase) {
    updateData.current_phase = userPathway.current_phase + 1;
  } else {
    // Mark pathway as completed
    updateData.status = "completed";
    updateData.completed_at = new Date().toISOString();
  }
}
```

### Fix 3: Add comprehensive logging

```typescript
console.log({
  action: "submit-pathway-checkin",
  userId: user.id,
  userPathwayId: body.userPathwayId,
  oldDay: userPathway.current_day,
  newDay,
  oldPhase: userPathway.current_phase,
  newPhase: updateData.current_phase,
  daysSoFar,
  dayInCurrentPhase,
  shouldAdvancePhase,
  phaseDuration: currentPhase?.duration_days,
});
```
