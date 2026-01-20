# Sensory Regulation Toolkit - Implementation Roadmap

**Status**: Phase 1 (BUILD) - In Progress
**Created**: 2026-01-20
**Context Budget**: Partially consumed - pausing for fresh session

## Completed Work

### Phase 0: PLAN ✅

- [x] Spec analyzed by spec-analyzer agent (verdict: NEEDS_REVISION with 6 blockers)
- [x] Architectural decisions made (see `docs/decisions.md` - "2026-01-20: Sensory Regulation Toolkit Architecture")
- [x] Implementation plan created by architect agent (comprehensive file manifest, component design)

### Phase 1: BUILD (Partial) ✅

- [x] Database migrations created:
  - `supabase/migrations/20260120280000_create_sensory_tables.sql`
  - `supabase/migrations/20260120280001_add_sensory_rls_policies.sql`
  - **STATUS**: Ready to apply (blocked by existing migration ordering issue in `20260119000200_couples_session_rating_rpc.sql`)
  - **ACTION NEEDED**: Fix blocking migration first, then run `supabase db push --local`

- [x] Core models implemented:
  - `apps/ios/MindFriendApp/Core/SensoryModels.swift`
  - Includes: `SensoryModality`, `SpeedPreset`, `TactilePattern`, `VisualAnimation`, `AudioSoundscape`, `SensorySession`, `SensoryFavorite`, `SensorySettings`
  - Pattern libraries hardcoded (6 tactile, 8 visual, 2 audio patterns)
  - Error types defined

- [x] Service scaffolds created:
  - `apps/ios/MindFriendApp/Core/Services/TactilePatternService.swift`
  - **STATUS**: Stub with TODO comments - needs Core Haptics implementation

---

## Remaining Work

### Phase 1: BUILD (Continue)

#### Services Layer (3-4 hours estimated)

- [ ] **TactilePatternService.swift** - Complete Core Haptics implementation
  - [ ] Implement `playPattern()` - AHAP loading, CHHapticPattern creation, playback
  - [ ] Implement `stopPattern()` - Stop player, clear references
  - [ ] Implement `setIntensity()` - Dynamic parameter adjustment
  - [ ] Implement AHAP pattern transformations (speed/intensity multipliers)
  - [ ] Add engine lifecycle handlers (reset, stopped)
  - [ ] Test: Unit tests in `TactilePatternServiceTests.swift`

- [ ] **VisualAnimationService.swift** - SwiftUI Canvas rendering engine
  - [ ] Implement `startAnimation()` - Load animation config, start frame loop
  - [ ] Implement `stopAnimation()` - Cancel frame timer
  - [ ] Implement `renderFrame()` - Canvas drawing for each animation type:
    - [ ] Expanding Circle (inhale/exhale sizing)
    - [ ] Pulsing Square
    - [ ] Wave animation
    - [ ] Bouncing Dot
    - [ ] Spiral (premium)
    - [ ] Flower Bloom (premium)
    - [ ] Dot Grid (premium)
    - [ ] Ribbon Flow
  - [ ] Apply speed multiplier to animation timing
  - [ ] Test: Frame rate validation (target: 60fps), animation state tests

- [ ] **AudioSoundscapeService.swift** - AVAudioPlayer wrapper
  - [ ] Implement `playSound()` - Load audio file, configure player, start playback
  - [ ] Implement `stopSound()` - Stop player, release resources
  - [ ] Implement looping logic
  - [ ] Add audio session configuration (ambient mode for background compatibility)
  - [ ] Test: Audio loading, playback, looping

- [ ] **SensoryRegulationService.swift** - Session orchestration
  - [ ] Implement `startSession()` - Validate premium, call create-session Edge Function, start modality service
  - [ ] Implement `pauseSession()` - Pause timer, pause modality service
  - [ ] Implement `resumeSession()` - Resume timer, resume modality service
  - [ ] Implement `endSession()` - Stop timer, call complete-session Edge Function, check achievements
  - [ ] Implement 30-minute auto-pause logic
  - [ ] Implement background/foreground handling
  - [ ] Test: Session state machine, 30-min limit, achievement triggers

#### UI Components (2-3 hours estimated)

- [ ] **Components/ModalityCardView.swift** - Reusable card for Home dashboard
- [ ] **Components/PatternPreviewCell.swift** - Grid cell with thumbnail, name, premium badge
- [ ] **Components/TactileCanvasView.swift** - Visual feedback for haptic patterns (optional)
- [ ] **Components/VisualCanvasView.swift** - 60fps Canvas renderer (CRITICAL)
- [ ] **Components/AudioWaveformView.swift** - Simulated waveform visualization
- [ ] **Components/HeartRateSimulator.swift** - Animated BPM display (80-120 range)

#### Feature Views (3-4 hours estimated)

- [ ] **Features/Sensory/SensoryHomeView.swift** - Main entry: modality cards, recent sessions
- [ ] **Features/Sensory/TactileLibraryView.swift** - Grid of tactile patterns
- [ ] **Features/Sensory/VisualLibraryView.swift** - Grid of visual animations
- [ ] **Features/Sensory/AudioLibraryView.swift** - List of soundscapes
- [ ] **Features/Sensory/SessionViewModel.swift** - UI state management
  - [ ] Implement `togglePlayPause()`, `endSession()`, `changeSpeed()`
  - [ ] Implement progress calculation, elapsed time formatting
  - [ ] Implement simulated heart rate logic
  - [ ] Implement premium paywall check
- [ ] **Features/Sensory/SessionView.swift** - Active session UI
  - [ ] Timer display
  - [ ] Play/pause/stop controls
  - [ ] Speed selector
  - [ ] Modality-specific display (Canvas/Waveform/Haptic feedback)
  - [ ] Heart rate simulator
  - [ ] Progress bar
- [ ] **Features/Sensory/SettingsView.swift** - User preferences form
- [ ] **Features/Sensory/HistoryView.swift** - Session log list

#### Edge Functions (2-3 hours estimated)

- [ ] **supabase/functions/create-sensory-session/index.ts**
  - [ ] Validate JWT, extract user_id
  - [ ] Check premium pattern access (query subscriptions table)
  - [ ] Insert sensory_sessions record (status='active')
  - [ ] Return session_id, premium status, access granted
  - [ ] Test: Premium validation, free tier blocking

- [ ] **supabase/functions/complete-sensory-session/index.ts**
  - [ ] Validate JWT, extract user_id
  - [ ] Update sensory_sessions (status='completed', duration, completed_at)
  - [ ] Check achievement triggers:
    - [ ] First session (SEN-001)
    - [ ] 10 sessions (SEN-002)
    - [ ] Try all 3 modalities (SEN-003)
    - [ ] 30-minute session (SEN-004)
    - [ ] 7-day streak (SEN-005)
  - [ ] Query sensory session stats
  - [ ] Return achievements unlocked + stats
  - [ ] Test: Achievement unlocking, stat calculation

- [ ] **supabase/functions/save-sensory-favorite/index.ts**
  - [ ] Validate JWT, extract user_id
  - [ ] Upsert/delete sensory_favorites record
  - [ ] Return success status
  - [ ] Test: Add/remove favorite

- [ ] **supabase/functions/get-sensory-stats/index.ts**
  - [ ] Validate JWT, extract user_id
  - [ ] Aggregate sensory_sessions: total sessions, total minutes, current streak, longest streak
  - [ ] Determine favorite modality (most sessions)
  - [ ] Query recent sessions (limit 10)
  - [ ] Return stats object
  - [ ] Test: Stat calculation, streak logic

#### Integration Updates (1-2 hours estimated)

- [ ] **Update `AchievementModels.swift`** - Add 5 sensory achievements:

  ```swift
  // SEN-001: First Session
  // SEN-002: 10 Sessions
  // SEN-003: All 3 Modalities
  // SEN-004: 30-Minute Session
  // SEN-005: 7-Day Streak
  ```

- [ ] **Update `AchievementService.swift`** - Add sensory completion triggers
  - [ ] Add `.sensorySessionCompleted` event case
  - [ ] Implement achievement check logic in `checkAchievements()`

- [ ] **Update `HomeView.swift`** - Add Sensory card to dashboard
  - [ ] Add `ModalityCardView` after Quest card
  - [ ] Pass last-used pattern from UserDefaults

- [ ] **Update `MainTabView.swift`** - Add Sensory tab
  - [ ] Add `.sensory` enum case
  - [ ] Add tab item with icon "waveform.path.ecg"
  - [ ] Add `SensoryHomeView()` destination

- [ ] **Update `Models.swift`** - Import SensorySession, SensorySettings types

- [ ] **Update `DependencyContainer.swift`** - Register services
  - [ ] Add `@Published` lazy vars for all 4 sensory services
  - [ ] Initialize in `init()`

- [ ] **Update `SOSInterventionView.swift`** - Add quick action button
  - [ ] Button: "Try Sensory Toolkit"
  - [ ] Action: Navigate to `SensoryHomeView`, auto-start SOS haptic pattern

- [ ] **Update `ExerciseListView.swift`** - Add "Sensory" filter
  - [ ] Add filter enum case
  - [ ] Map to sensory patterns

#### Localization (1 hour estimated)

- [ ] **Update `Localizable.xcstrings`** - Add 100+ keys:
  - [ ] Pattern names (tactile/visual/audio)
  - [ ] Pattern descriptions
  - [ ] Category names
  - [ ] Settings labels
  - [ ] Error messages
  - [ ] Button labels
  - [ ] Instructions/tooltips

#### AHAP Files (1 hour estimated)

- [ ] **Create 6 AHAP pattern files** in `Resources/Haptics/`:
  - [ ] `heartbeat.ahap` - 60 BPM continuous pulse
  - [ ] `earth_pulse.ahap` - Deep, slow rhythm
  - [ ] `wave.ahap` - Rising/falling intensity
  - [ ] `breath_cue.ahap` - Inhale (4s) / Exhale (6s) cues
  - [ ] `counting.ahap` - 4-7-8 breathing pattern
  - [ ] `sos.ahap` - ... --- ... pattern

#### Xcode Project Management (Critical!)

- [ ] **Add all new files to Xcode project**:
  - [ ] Use Ruby `xcodeproj` gem (see CLAUDE.md Section 7.1)
  - [ ] Run bulk add script for all `Sensory*.swift` files
  - [ ] Verify with `xcodebuild -list`

#### Tests (2-3 hours estimated)

- [ ] **TactilePatternServiceTests.swift**
  - [ ] Test AHAP loading
  - [ ] Test pattern playback start/stop
  - [ ] Test intensity adjustment
  - [ ] Test haptics not supported fallback

- [ ] **VisualAnimationServiceTests.swift**
  - [ ] Test animation state transitions
  - [ ] Test frame rendering (mock Canvas context)
  - [ ] Test speed preset application

- [ ] **AudioSoundscapeServiceTests.swift**
  - [ ] Test audio loading
  - [ ] Test playback/stop
  - [ ] Test looping

- [ ] **SensoryRegulationServiceTests.swift**
  - [ ] Test session lifecycle (start/pause/resume/end)
  - [ ] Test 30-minute auto-pause
  - [ ] Test achievement triggers

- [ ] **SessionViewModelTests.swift**
  - [ ] Test UI state updates
  - [ ] Test progress calculation
  - [ ] Test premium gating

- [ ] **Edge Function Tests**
  - [ ] `create-sensory-session/test.ts`
  - [ ] `complete-sensory-session/test.ts`
  - [ ] Run: `deno test supabase/functions/*/test.ts`

#### Accessibility (1 hour estimated)

- [ ] Add VoiceOver labels to all interactive elements
- [ ] Test Dynamic Type scaling
- [ ] Test VoiceOver navigation
- [ ] Test Reduce Motion handling (disable Canvas animations)

---

## Phase 2: REVIEW

Once Phase 1 is complete, deploy 10 review agents in parallel:

- [ ] 3x code-reviewer (architecture, quality, best practices)
- [ ] 3x code-auditor (correctness, reliability, performance)
- [ ] 3x security-auditor (input/output, auth/access, data/secrets)
- [ ] 1x debugger (bug hunting)

**Gate**: All scores MUST be EXACTLY 10/10 before proceeding to Phase 3.

---

## Phase 3: VERIFY

- [ ] Build verification: `xcodebuild build -scheme MindFriendApp`
- [ ] Test suite: `xcodebuild test -scheme MindFriendApp`
- [ ] Lint: SwiftLint checks
- [ ] Security audit: Dependency vulnerabilities
- [ ] Performance: Instruments profiling (Canvas 60fps, memory <100MB)

---

## Phase 4: COMMIT

- [ ] Generate conventional commit messages
- [ ] Update CHANGELOG.md
- [ ] Push to main

---

## Phase 5: MONITOR

- [ ] Watch CI pipeline
- [ ] Monitor for regressions

---

## Blockers

1. **Migration Ordering** - `20260119000200_couples_session_rating_rpc.sql` must be fixed before sensory migrations can apply
   - **Owner**: TBD
   - **Priority**: High
   - **Action**: Fix migration ordering or resequence

2. **AHAP Files Missing** - 6 haptic pattern files need to be created
   - **Owner**: Content team or iOS developer
   - **Priority**: Medium
   - **Action**: Design/create AHAP files per spec

3. **Audio Files Missing** - Soundscape audio files need to be sourced/licensed
   - **Owner**: Content team
   - **Priority**: Medium
   - **Action**: License or record soundscapes (rain, ocean waves, etc.)

---

## Next Steps

1. **Fix Blocking Migration**: Resolve `20260119000200` ordering issue
2. **Apply Sensory Migrations**: Run `supabase db push --local`
3. **Complete Service Implementation**: Focus on TactilePatternService first (most complex)
4. **Build UI Layer**: Start with SessionView (core UX)
5. **Create Edge Functions**: Parallel with UI development
6. **Integration Pass**: Update Home, SOS, Achievements
7. **Testing Pass**: Unit + Integration tests
8. **Review Pass**: Deploy 10 review agents
9. **Polish Pass**: Accessibility, localization, performance

**Estimated Total Time**: 15-20 hours of focused development

**Recommended Approach**: Resume dev-pipeline in fresh session with `/dev-pipeline:continue` after migration blocker is resolved.

---

## File Manifest (Quick Reference)

### Created (Ready)

- ✅ `supabase/migrations/20260120280000_create_sensory_tables.sql`
- ✅ `supabase/migrations/20260120280001_add_sensory_rls_policies.sql`
- ✅ `apps/ios/MindFriendApp/Core/SensoryModels.swift`
- ✅ `apps/ios/MindFriendApp/Core/Services/TactilePatternService.swift` (stub)

### To Create

- ❌ `apps/ios/MindFriendApp/Core/Services/VisualAnimationService.swift`
- ❌ `apps/ios/MindFriendApp/Core/Services/AudioSoundscapeService.swift`
- ❌ `apps/ios/MindFriendApp/Core/Services/SensoryRegulationService.swift`
- ❌ `apps/ios/MindFriendApp/Features/Sensory/` (entire directory - 9 view files)
- ❌ `apps/ios/MindFriendApp/Resources/Haptics/` (6 AHAP files)
- ❌ `supabase/functions/create-sensory-session/index.ts`
- ❌ `supabase/functions/complete-sensory-session/index.ts`
- ❌ `supabase/functions/save-sensory-favorite/index.ts`
- ❌ `supabase/functions/get-sensory-stats/index.ts`
- ❌ `apps/ios/MindFriendAppTests/SensoryRegulationServiceTests.swift`
- ❌ `apps/ios/MindFriendAppTests/TactilePatternServiceTests.swift`
- ❌ `apps/ios/MindFriendAppTests/VisualAnimationServiceTests.swift`
- ❌ `apps/ios/MindFriendAppTests/SessionViewModelTests.swift`
- ❌ `supabase/functions/create-sensory-session/test.ts`
- ❌ `supabase/functions/complete-sensory-session/test.ts`

### To Modify

- 🔄 `apps/ios/MindFriendApp/Core/AchievementModels.swift` (add 5 achievements)
- 🔄 `apps/ios/MindFriendApp/Core/Services/AchievementService.swift` (add triggers)
- 🔄 `apps/ios/MindFriendApp/Features/Home/HomeView.swift` (add card)
- 🔄 `apps/ios/MindFriendApp/Features/Home/MainTabView.swift` (add tab)
- 🔄 `apps/ios/MindFriendApp/Core/Models.swift` (import sensory types)
- 🔄 `apps/ios/MindFriendApp/App/DependencyContainer.swift` (register services)
- 🔄 `apps/ios/MindFriendApp/Features/SOS/SOSInterventionView.swift` (add button)
- 🔄 `apps/ios/MindFriendApp/Features/Exercises/ExerciseListView.swift` (add filter)
- 🔄 `apps/ios/MindFriendApp/Resources/Localizable.xcstrings` (add keys)

---

**End of Roadmap**
