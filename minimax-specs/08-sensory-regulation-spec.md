# Sensory Regulation Toolkit (Non-Audio)

**Priority:** #9 (Implementation Roadmap)
**Scores:** Delight 7/10 | Differentiation 7/10 | Feasibility High | Revenue Low

## Step 1: Feature Analysis

### Core purpose and value proposition
- Provide visual and haptic regulation patterns for discreet calming without headphones.
- Offer alternative sensory inputs when audio isn't appropriate or available.
- Create calming experiences that work in any setting (meetings, public transit, etc.).

### Target users and use cases
- Users in situations where audio isn't appropriate (meetings, libraries).
- Users who prefer visual or tactile sensory input.
- Users seeking discreet anxiety management.
- Users with hearing sensitivities who avoid audio content.

### Dependencies / prerequisites
- Device haptic API access (Core Haptics on iOS).
- Display animation capabilities (SwiftUI animations).
- No external hardware required.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Sensory Regulation Toolkit (Non-Audio)
- **Description:** A collection of visual and haptic patterns designed for discreet emotional regulation. Includes pulsing light sequences, rhythmic animations, and tactile pacing—calming without sound for use anywhere.
- **Business justification and user value:** Silent, discreet regulation not offered by most competitors. Addresses users who can't or don't want to use audio-based calming.

### 2. Functional Requirements

#### FR1: Visual Breathing Patterns
- User stories:
  - As a user, I want visual breathing guidance without audio.
  - As a user, I want to practice breathing discreetly in public.
- Acceptance criteria:
  - Minimum 8 visual-only breathing patterns:
    - Expanding/contracting circle
    - Pulsing square
    - Wave animation
    - Bouncing dot
    - Spiral motion
    - Flower bloom
    - Dot grid expansion
    - Ribbon flow
  - Adjustable speed (slow: 4-6 breaths/min, medium: 8-10, fast: 12+).
  - Duration selector (1, 3, 5 minutes or infinite).
  - Screen dimming option (reduce brightness during practice).

#### FR2: Rhythmic Visual Patterns
- User stories:
  - As a user, I want repetitive visual patterns that calm me.
  - As a user, I want options for different stimulation levels.
- Acceptance criteria:
  - Minimum 6 rhythm patterns:
    - Slow wave (calming)
    - Gentle pulse (grounding)
    - Flowing particles (meditative)
    - Geometric symmetry (focusing)
    - Soft oscillation (relaxing)
    - Minimal pulse (subtle)
  - Intensity slider: low, medium, high.
  - Pattern opacity control for discretion.

#### FR3: Haptic Patterns
- User stories:
  - As a user, I want tactile cues for breathing and pacing.
  - As a user, I want haptics I can feel without looking.
- Acceptance criteria:
  - Minimum 5 haptic patterns:
    - Breath cue (inhale/exhale timing)
    - Pulse (heartbeat-like rhythm)
    - Wave (rising and falling intensity)
    - Count (numbered taps for pacing)
    - SOS (emergency pattern)
  - Intensity control (light, moderate, strong).
  - Combine with visual patterns or use alone.

#### FR4: Pacing Tools
- User stories:
  - As a user, I want tools to help me slow down my breathing.
  - As a user, I want tactile pacing for panic moments.
- Acceptance criteria:
  - Haptic countdown for breathing exercises.
  - Visual countdown bar.
  - "Slow down" alert (gentle haptic pulse pattern).
  - Heart rate visualization that responds to pacing.

#### FR5: Quick Access
- User stories:
  - As a user in crisis, I want one-tap access to calming.
  - As a user, I want to customize my quick-access options.
- Acceptance criteria:
  - Home screen quick-access widget (configurable).
  - Widget shows last-used pattern.
  - One-tap to start, one-tap to stop.
  - "Saved for later" patterns.

### 3. Technical Specifications

#### Architecture and system design considerations
- All patterns run locally with no server dependency.
- Core Haptics for precise haptic control.
- SwiftUI for smooth animations.
- Background execution allowed for duration timers.
- Low power mode compatibility.

#### Data models and schemas (proposed)

```sql
-- Visual pattern definitions (for reference, patterns are local)
CREATE TABLE visual_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_key TEXT NOT NULL UNIQUE,  -- e.g., 'expanding_circle'
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,  -- 'breathing', 'rhythmic', 'pacing'
    default_duration_seconds INTEGER,
    default_speed INTEGER,  -- breaths per minute or animation speed
    is_premium BOOLEAN DEFAULT FALSE,
    icon TEXT,
    animation_config JSONB  -- Local rendering config
);

-- Haptic pattern definitions
CREATE TABLE haptic_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_key TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,  -- 'breathing', 'pacing', 'alert'
    haptic_schema JSONB NOT NULL,  -- Core Haptics pattern
    default_intensity FLOAT DEFAULT 0.5,
    is_premium BOOLEAN DEFAULT FALSE
);

-- User preferences for toolkit
CREATE TABLE toolkit_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    default_pattern_key TEXT,
    default_duration INTEGER,  -- seconds
    haptic_enabled BOOLEAN DEFAULT TRUE,
    haptic_intensity FLOAT DEFAULT 0.5,
    visual_intensity FLOAT DEFAULT 0.7,
    dim_during_use BOOLEAN DEFAULT FALSE,
    quick_access_enabled BOOLEAN DEFAULT TRUE,
    quick_access_pattern_keys TEXT[],  -- Array of pattern keys
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Usage tracking (local-first, privacy-preserving)
CREATE TABLE toolkit_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    pattern_key TEXT NOT NULL,
    duration_seconds INTEGER NOT NULL,
    completed BOOLEAN DEFAULT TRUE,
    helpful_rating INTEGER,  -- 1-5, optional
    occurred_at TIMESTAMPTZ DEFAULT NOW(),
    client_generated_id TEXT NOT NULL
);
```

#### API endpoints / interfaces

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/get-patterns` | GET | List available patterns (for UI) |
| `/functions/v1/save-preferences` | PUT | Save user preferences |
| `/functions/v1/get-preferences` | GET | Retrieve user preferences |
| `/functions/v1/record-usage` | POST | Track pattern usage (privacy-preserving) |
| `/functions/v1/get-stats` | GET | Get usage statistics |

#### Integration points with existing systems
- **Home View:** Quick-access widget.
- **SOS Flow:** Emergency haptic patterns.
- **Exercises:** Visual patterns as part of exercise completion.
- **Achievements:** Usage-based badges.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions

**Toolkit Home**
```
┌─────────────────────────────────────────────────┐
│  Sensory Regulation                             │
│  Silent calming tools                           │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 🫁 Breathing                              │ │
│  │ Visual guides for breathing               │ │
│  │ [Expanding Circle] [Wave] [Spiral]        │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 🌊 Rhythmic                               │ │
│  │ Calming visual patterns                   │ │
│  │ [Flowing] [Pulse] [Symmetry]              │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 💓 Haptics                                │ │
│  │ Tactile calming patterns                  │ │
│  │ [Heartbeat] [Wave] [Counting]             │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ⚙️ Settings     ⭐ Quick Access               │
└─────────────────────────────────────────────────┘
```

**Visual Breathing Pattern**
```
┌─────────────────────────────────────────────────┐
│  ← Back     Expanding Circle    [⚙️] [Save]    │
├─────────────────────────────────────────────────┤
│                                                 │
│                                                 │
│                                                 │
│                                                 │
│                    ●                           │
│                 ●     ●                        │
│              ●         ●                       │
│           ●             ●                     │
│              ●         ●                       │
│                 ●     ●                        │
│                    ●                           │
│                                                 │
│          inhale      exhale      inhale        │
│                                                 │
│                                                 │
│  Speed: [●━━━━━━━●━━━━━━━●] 8 breaths/min     │
│  Duration: [ 3 min ▼]                          │
│  Dim Screen: [○]                                │
│                                                 │
│           [▶ Start Session]                     │
│                                                 │
│  💓 Haptics: [On - Light ▼]                     │
└─────────────────────────────────────────────────┘
```

**Haptic Pattern Selector**
```
┌─────────────────────────────────────────────────┐
│  Haptic Patterns                                │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 💓 Heartbeat                              │ │
│  │ 60 bpm pulse pattern                      │ │
│  │ ┌─────────────────────────────────────┐   │ │
│  │ │ •  •  •  •  •  •  •  •  •  •       │   │ │
│  │ └─────────────────────────────────────┘   │ │
│  │ Intensity: [●━━━━━●] Light               │ │
│  │ [Preview]                                 │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 🌊 Wave                                   │ │
│  │ Rising and falling intensity             │ │
│  │ ┌─────────────────────────────────────┐   │ │
│  │ │ •  ••  •••  ••••  •••  ••  •       │   │ │
│  │ └─────────────────────────────────────┘   │ │
│  │ Intensity: [●━━━━━●] Moderate            │ │
│  │ [Preview]                                 │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 🔢 Counting                               │ │
│  │ Taps for breathing count                  │ │
│  │ 4-7-8 pattern support                     │ │
│  │ [Preview]                                 │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

**Quick Access Widget**
```
┌───────────────────┐
│ 🫁 3 min breathing│
│ ▶ [Stop]          │
└───────────────────┘

Or:

┌───────────────────┐
│ 💓 Heartbeat      │
│ ● 60 bpm          │
└───────────────────┘
```

#### User flow diagram (text)

1. **Quick session:**
   - Opens toolkit → Taps pattern → Adjusts settings → Starts → Uses → Stops → Rates.

2. **Custom session:**
   - Opens toolkit → Explores patterns → Selects "custom" → Adjusts speed/duration/haptics → Saves as preset → Uses.

3. **Crisis moment:**
   - One-tap from home or widget → Starts default calming pattern → Uses throughout crisis → Rates afterward.

#### Accessibility requirements
- All patterns work with VoiceOver enabled.
- Haptics clearly communicate state changes.
- Visual patterns respect reduced motion preference.
- High contrast mode support.
- Touch targets minimum 44x44pt.

### 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| Haptic engine unavailable | Fallback to visual-only patterns with notification |
| Device doesn't support haptics | Hide haptic options gracefully |
| Low power mode | Reduce animation complexity, offer simple haptics |
| Background app during session | Continue animation; haptics may pause |
| User rate limits | Warn if used excessively (>1 hour continuous) |
| Animation performance issues | Offer low-power mode option |

### 6. Testing Requirements

#### Unit tests
- Animation timing accuracy.
- Haptic pattern playback correctness.
- Duration timer accuracy.
- Settings persistence.

#### Integration tests
- Quick-access widget functionality.
- Home integration.
- Usage tracking accuracy.
- Background session handling.

#### UAT scenarios
- Start breathing pattern → Follow visual guide → Complete session.
- Use haptic-only mode → Feel distinct patterns.
- Enable dimming → Screen dims during session.
- Use quick-access widget → Pattern starts immediately.
- Switch between patterns → Transitions are smooth.

### 7. Implementation Notes

#### Suggested implementation approach
- **Phase 1:** Core visual breathing patterns + basic haptics.
- **Phase 2:** Additional rhythmic patterns + customization.
- **Phase 3:** Quick-access widget + usage tracking.
- **Phase 4:** Advanced patterns, integration with exercises.

#### Potential challenges and mitigations
- **Challenge:** Haptic API complexity. **Mitigation:** Use pre-built patterns; test on all supported devices.
- **Challenge:** Animation performance on older devices. **Mitigation:** Offer low-power mode; test on iPhone 12 and older.
- **Challenge:** User confusion about patterns. **Mitigation:** Clear previews; suggest starting with "expanding circle."

#### Performance considerations
- Animations use Core Animation for efficiency.
- Haptics use Core Haptics for precision.
- Sessions limit to prevent overheating.
- Clean up resources on session end.

## Step 3: Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Toolkit adoption | 40% of DAU use within 30 days | Toolkit opens / DAU |
| Session completion | 80% complete started sessions | Completed / started |
| Quick-access usage | 60% of users enable widget | Widget enabled / toolkit users |
| Haptic engagement | 50% of sessions use haptics | Sessions with haptics / total |
| Helpful ratings | 4.0/5.0 average rating | Session ratings |
| Crisis usage | 20% report using in crisis moments | Survey response |
