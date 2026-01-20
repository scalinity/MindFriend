# Camera Biofeedback Breathing Coach

**Priority:** #5 (Implementation Roadmap)
**Scores:** Delight 8/10 | Differentiation 8/10 | Feasibility Medium | Revenue Medium

## Step 1: Feature Analysis

### Core purpose and value proposition
- Use on-device camera to detect respiration patterns (chest/shoulder movement, facial color changes).
- Provide real-time visual feedback showing breathing rhythm.
- Adapt pace until physiological calm is detected.

### Target users and use cases
- Users who want visible proof of calming effect.
- Users who don't respond to abstract breathing instructions.
- Users practicing breathing exercises who want feedback.

### Dependencies / prerequisites
- iOS AVFoundation for camera access.
- On-device motion/respiration detection (privacy-first).
- Vision framework for motion analysis.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Camera Biofeedback Breathing Coach
- **Description:** On-device camera respiration detection that provides immediate visual feedback on breathing patterns. Adapts guidance pace until physiological calm is detected, giving users tangible proof of their calming progress.
- **Business justification and user value:** Tangible biofeedback without wearables. Visible proof of calming effect builds confidence and reinforces practice.

### 2. Functional Requirements

#### FR1: Respiration Detection
- User stories:
  - As a user, I want to see my breathing visualized in real-time.
  - As a user, I want accurate detection without wearables.
- Acceptance criteria:
  - Detect chest/shoulder movement indicating breathing.
  - Measure breath rate (breaths per minute).
  - Detect breath depth (shallow vs deep).
  - Calculate regularity (rhythmic vs erratic).
  - Privacy indicator: All processing on-device.

#### FR2: Visual Biofeedback
- User stories:
  - As a user, I want to see my breathing on screen.
  - As a user, I want clear guidance on breathing pattern.
- Acceptance criteria:
  - Real-time visualization: Expanding/contracting circle synced to detected breath.
  - Guidance overlay: "Inhale" / "Exhale" prompts.
  - Current breath rate displayed.
  - Visual confirmation of each breath cycle.

#### FR3: Adaptive Pacing
- User stories:
  - As a user, I want breathing guidance that matches my current state.
  - As a user, I want the app to help me slow down.
- Acceptance criteria:
  - Target breath rate: 6 breaths/min (calming range) or 4-7 range.
  - Adaptive guidance: Starts at user's current rate, gradually slows.
  - Progress indicator: "Your breath is slowing down."
  - Calming threshold: Detects when physiology shifts (slower, deeper).

#### FR4: Session Flow
- User stories:
  - As a user, I want guided breathing sessions.
  - As a user, I want to see my progress over a session.
- Acceptance criteria:
  - Session durations: 1, 3, 5 minutes.
  - Session phases:
    - Baseline: Detect current pattern (10-30 seconds).
    - Guidance: Follow paced breathing (visual + audio optional).
    - Free: Continue at natural pace with feedback.
  - Session summary: Start rate, end rate, breaths taken.

#### FR5: Accessibility & Privacy
- User stories:
  - As a user, I want to use this feature without camera if I prefer.
  - As a user, I want to know my data stays private.
- Acceptance criteria:
  - All processing on-device; no video stored or transmitted.
  - Camera feed not visible to user (only visualization).
  - Clear privacy indicator throughout.
  - Alternative "manual" mode with tap-to-breathe.

### 3. Technical Specifications

#### Architecture and system design considerations
- On-device ML model for respiration detection (Vision framework or custom).
- Real-time processing with minimal latency.
- Battery efficiency considerations.
- No network calls for core functionality.

#### Data models and schemas (proposed)

```sql
-- Biofeedback session data (local-only)
CREATE TABLE biofeedback_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    session_type TEXT NOT NULL,  -- 'guided', 'free', 'manual'
    started_at TIMESTAMPTZ NOT NULL,
    duration_seconds INTEGER NOT NULL,
    baseline_rate FLOAT,  -- Breaths per minute at start
    ending_rate FLOAT,  -- Breaths per minute at end
    lowest_rate FLOAT,  -- Minimum rate achieved
    breath_count INTEGER,
    calming_detected BOOLEAN,
    quality_score FLOAT,  -- 0-1 based on regularity
    metrics JSONB  -- Full session metrics
);

-- Breathing pattern templates
CREATE TABLE breathing_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_key TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    breaths_per_minute FLOAT NOT NULL,
    inhale_seconds FLOAT NOT NULL,
    hold_in_seconds FLOAT NOT NULL,
    exhale_seconds FLOAT NOT NULL,
    hold_out_seconds FLOAT NOT NULL,
    category TEXT NOT NULL,  -- 'calming', 'energizing', 'focus'
    difficulty TEXT DEFAULT 'beginner' CHECK (difficulty IN ('beginner', 'intermediate', 'advanced'))
);

-- User preferences for biofeedback
CREATE TABLE biofeedback_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    target_bpm FLOAT DEFAULT 6.0,
    session_duration_default INTEGER DEFAULT 3,
    show_guidance_overlay BOOLEAN DEFAULT TRUE,
    audio_enabled BOOLEAN DEFAULT FALSE,
    haptics_enabled BOOLEAN DEFAULT TRUE,
    privacy_mode TEXT DEFAULT 'camera' CHECK (privacy_mode IN ('camera', 'manual', 'tap')),
    camera_permission_shown BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Historical breathing data (aggregated, privacy-preserving)
CREATE TABLE breathing_history_aggregates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    sessions_count INTEGER DEFAULT 0,
    total_minutes FLOAT DEFAULT 0,
    average_starting_rate FLOAT,
    average_ending_rate FLOAT,
    average_improvement FLOAT,  -- Percentage slowing
    calming_sessions_count INTEGER DEFAULT 0,
    UNIQUE(user_id, date)
);
```

#### API endpoints / interfaces

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/save-session` | POST | Save session data (privacy-preserving) |
| `/functions/v1/get-history` | GET | Get user's breathing history |
| `/functions/v1/get-patterns` | GET | Get available breathing patterns |
| `/functions/v1/save-preferences` | PUT | Save user preferences |
| `/functions/v1/get-preferences` | GET | Get user preferences |
| `/functions/v1/get-stats` | Get aggregated breathing statistics |

#### Integration points with existing systems
- **Sensory Regulation Toolkit:** Breathing patterns as visual patterns.
- **Exercises:** Breathing exercises link to biofeedback.
- **Home View:** Quick-access breathing widget.
- **Achievements:** Session-based badges.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions

**Session Start**
```
┌─────────────────────────────────────────────────┐
│  Breathing Coach                                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │                                             ││
│  │         📷 Camera Preview                   ││
│  │         (Processing on-device)             ││
│  │                                             ││
│  │         ○                                  ││
│  │        /│\   ← Your breath circle         ││
│  │         │                                 ││
│  │         ↓  ← Inhale cue                   ││
│  │                                             ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  Pattern: [4-7-8 Relaxing ▼]                   │
│  Duration: [3 min ▼]                           │
│                                                 │
│  🛡️ All processing happens on your device      │
│                                                 │
│           [Start Session]                       │
│                                                 │
│  [Manual Mode]  [Settings]                     │
└─────────────────────────────────────────────────┘
```

**Active Session**
```
┌─────────────────────────────────────────────────┐
│  ← Back     3:00 remaining     [⚙️]            │
├─────────────────────────────────────────────────┤
│                                                 │
│                    ▲                           │
│                   / \                          │
│                  /   \  ← Your breath         │
│                 /     \                        │
│                ▼       ▼                       │
│                                                 │
│         inhale      exhale      inhale         │
│           4s          7s          4s          │
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ 💓 Your breath: 8 bpm → 6 bpm (slowing!)   ││
│  │ 📈 Keep going! You're doing great.         ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  [Pause]                          [End Early]  │
└─────────────────────────────────────────────────┘
```

**Session Summary**
```
┌─────────────────────────────────────────────────┐
│  Session Complete!                              │
├─────────────────────────────────────────────────┤
│                                                 │
│  ✅ Great job!                                  │
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │                                             ││
│  │  Starting rate:  8 breaths/min             ││
│  │  Ending rate:    6 breaths/min             ││
│  │  Improvement:    25% slower               ││
│  │  Total breaths:  18                       ││
│  │                                             ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  📊 Your Progress Over Time                     │
│  ┌───────────────────────────────────────────┐ │
│  │  This week: 5 sessions, 15 min total     │ │
│  │  Avg improvement: 22%                    │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│         [Start Another Session]                 │
└─────────────────────────────────────────────────┘
```

**Manual/Tap Mode (No Camera)**
```
┌─────────────────────────────────────────────────┐
│  Tap Breathing                                   │
├─────────────────────────────────────────────────┐
│                                                 │
│              ○                                  │
│             /│\  ← Tap to sync with breath     │
│              │                                 │
│          [INHALE]                              │
│                                                 │
│  Tap along with your natural breathing.         │
│  The circle expands when you inhale,            │
│  contracts when you exhale.                     │
│                                                 │
│         [Start Tap Session]                     │
└─────────────────────────────────────────────────┘
```

#### User flow diagram (text)

1. **First-time user:**
   - Opens breathing coach → Receives privacy explanation → Camera permission (optional) → Chooses pattern → Completes session → Sees summary.

2. **Returning user:**
   - Opens coach → Quick-access to last pattern → Starts session → Uses visualization → Ends → Tracks progress.

3. **Camera-shy user:**
   - Opens coach → Chooses "Manual Mode" → Uses tap-to-breathe → Same session tracking without camera.

#### Accessibility requirements
- VoiceOver announces breath phases ("Inhale", "Exhale").
- Haptic feedback for breath phases.
- High contrast mode for visualization.
- Reduced motion option for animation.
- Minimum touch target 44x44pt.

### 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| Camera permission denied | Offer manual/tap mode; prompt for settings |
| Poor detection (low light, wrong position) | Show adjustment tips; fallback to manual |
| User moves out of frame | Pause session; prompt to return |
| Battery optimization | Suggest plugging in for longer sessions |
| Session interrupted | Offer resume or restart |
| Detection seems wrong | Allow manual override to tap mode |

### 6. Testing Requirements

#### Unit tests
- Breathing detection accuracy with sample video.
- Rate calculation correctness.
- Session metrics calculation.
- Pattern timing accuracy.

#### Integration tests
- Full session flow with camera.
- Manual mode functionality.
- Settings persistence.
- History tracking.

#### UAT scenarios
- Complete session → See accurate breath rate detection.
- Watch breathing slow → Visual confirmation matches feel.
- Use manual mode → Same functionality without camera.
- Check history → See accumulated progress.

### 7. Implementation Notes

#### Suggested implementation approach
- **Phase 1:** Basic camera detection with simple visualization.
- **Phase 2:** Adaptive pacing and session flow.
- **Phase 3:** Multiple breathing patterns, manual mode.
- **Phase 4:** Advanced analytics, progress tracking.

#### Potential challenges and mitigations
- **Challenge:** Respiration detection accuracy. **Mitigation:** Use chest/shoulder region; validate with user feedback; offer manual mode.
- **Challenge:** Lighting conditions. **Mitigation:** Detect poor conditions; prompt for better lighting.
- **Challenge:** User positioning. **Mitigation:** Guide frame positioning; pause if user out of frame.

#### Performance considerations
- ML model optimized for real-time (30fps+).
- Battery impact minimized (screen dimming option).
- Memory efficient (no frame buffering).
- Thermal throttling handled gracefully.

## Appendix A: Breathing Patterns Library

| Pattern | BPM | Inhale | Hold | Exhale | Hold | Effect |
|---------|-----|--------|------|--------|------|--------|
| 4-7-8 Relaxing | 6 | 4s | 7s | 8s | 0s | Deep calm |
| Box Breathing | 6 | 4s | 4s | 4s | 4s | Focus, balance |
| Coherent | 6 | 5s | 0s | 5s | 0s | Heart rate variability |
| Energizing | 12 | 2.5s | 0s | 2.5s | 0s | Wakefulness |
| Gentle | 8 | 4s | 2s | 4s | 0s | Accessible calming |

## Step 3: Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Session completion | 85% of started sessions | Completed / started |
| Detection accuracy | 80% match self-reported breath count | User validation |
| Breath rate improvement | 20% average slowing | Start rate vs end rate |
| Return rate | 50% of users return weekly | Weekly return rate |
| Calming detection | 70% sessions show calming | Sessions with detected calming |
| Manual mode usage | 30% of sessions (camera-optional) | Manual / total sessions |
| User satisfaction | 4.5/5.0 rating | Post-session survey |
