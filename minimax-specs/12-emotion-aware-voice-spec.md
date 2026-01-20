# Emotion-Aware Voice Companion

**Priority:** #6 (Implementation Roadmap)
**Scores:** Delight 9/10 | Differentiation 8/10 | Feasibility Medium | Revenue Medium

## Step 1: Feature Analysis

### Core purpose and value proposition
- Detect emotional cues in user's voice (tone, pace, stress) during voice conversations.
- Adjust AI response pacing, empathy level, and intervention type in real-time.
- Create a more human-like, attuned conversational experience.

### Target users and use cases
- Users who prefer voice to text for emotional expression.
- Users in states of high distress where voice conveys more than text.
- Users seeking a more human-feeling AI companion.

### Dependencies / prerequisites
- Existing Voice Mode infrastructure (voice tokens, audio session).
- Real-time audio analysis capabilities.
- AI response generation with variable pacing.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Emotion-Aware Voice Companion
- **Description:** A voice mode enhancement that analyzes speech prosody (tone, pace, stress, hesitation) to detect emotional state. The AI dynamically adjusts response pacing, empathy level, and intervention approach based on what it hears.
- **Business justification and user value:** Emotional attunement creates a genuinely "heard" feeling. Text-only competitors can't match this intimacy. Major differentiation for voice-first users.

### 2. Functional Requirements

#### FR1: Audio Prosody Analysis
- User stories:
  - As a user, I want the AI to understand how I'm feeling from my voice.
  - As a user, I want the AI to respond to my emotional state, not just my words.
- Acceptance criteria:
  - Real-time analysis of: pitch variation, speech rate, volume dynamics, pause patterns, voice tremor.
  - Detect emotional states: calm, anxious, sad, frustrated, excited, neutral.
  - Confidence scoring for each detection.
  - Privacy indicator showing when analysis is active.

#### FR2: Dynamic Response Adaptation
- User stories:
  - As a user, I want the AI to slow down when I'm stressed.
  - As a user, I want the AI to be more direct when I'm calm.
- Acceptance criteria:
  - Response pacing: Slower speech for distressed users, normal for calm.
  - Empathy level: High empathy responses for anxiety/sadness, more matter-of-fact for neutral/positive.
  - Intervention type:
    - High distress: Gentle grounding, reduced complexity.
    - Moderate distress: Normal support + suggestions.
    - Low distress: Normal conversation, can introduce challenges/exercises.
  - Smooth transitions between states.

#### FR3: Real-Time Feedback
- User stories:
  - As a user, I want to know the AI is understanding my emotional state.
  - As a user, I want to see my emotional state being reflected.
- Acceptance criteria:
  - Visual indicator of detected emotional state (non-intrusive).
  - Subtle audio cues acknowledging state changes.
  - Option to correct AI's perception: "I notice you sound anxious—am I right?"
  - History of emotional states during conversation.

#### FR4: Calibration
- User stories:
  - As a user, I want the AI to learn my voice patterns over time.
  - As a user, I want to adjust how the AI responds to my emotions.
- Acceptance criteria:
  - Initial calibration: "Let's talk for a minute so I can learn your voice."
  - Personalization: AI learns individual baseline patterns.
  - User controls: Adjust sensitivity, disable specific adaptations.
  - Opt-in for emotional analysis (not enabled by default).

### 3. Technical Specifications

#### Architecture and system design considerations
- Real-time audio streaming to analysis service.
- On-device processing preferred for privacy (Core ML model).
- Edge Function for complex analysis if needed.
- Clear separation between voice recording and prosody analysis.

#### Data models and schemas (proposed)

```sql
-- Emotional state detections (stored temporarily, not permanently)
CREATE TABLE emotion_detections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    dominant_emotion TEXT NOT NULL,  -- 'calm', 'anxious', 'sad', 'frustrated', 'excited', 'neutral'
    confidence_score FLOAT NOT NULL,  -- 0-1 scale
    metrics JSONB NOT NULL,  -- Raw prosody metrics
    adapted_responses JSONB  -- Which adaptations were applied
);

-- User voice calibration profiles
CREATE TABLE voice_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    baseline_metrics JSONB NOT NULL,  -- Learned baseline for this user
    is_calibrated BOOLEAN DEFAULT FALSE,
    calibration_completed_at TIMESTAMPTZ,
    sensitivity_level TEXT DEFAULT 'balanced' CHECK (sensitivity_level IN ('minimal', 'balanced', 'responsive')),
    disabled_adaptations TEXT[],  -- Emotions user doesn't want adaptation for
    last_calibration_at TIMESTAMPTZ
);

-- Voice session emotional summary
CREATE TABLE voice_session_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NOT NULL,
    dominant_emotions JSONB NOT NULL,  -- Array of emotions with duration
    peak_distress_emotion TEXT,
    peak_distress_timestamp TIMESTAMPTZ,
    adaptations_applied JSONB,
    emotional_arc JSONB  -- Visualization data
);

-- Adaptation rules configuration
CREATE TABLE adaptation_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emotion TEXT NOT NULL UNIQUE,
    speech_rate_multiplier FLOAT DEFAULT 1.0,  -- 0.8 = slower, 1.2 = faster
    empathy_level INTEGER DEFAULT 5,  -- 1-10 scale
    response_complexity TEXT DEFAULT 'normal' CHECK (response_complexity IN ('simple', 'normal', 'detailed')),
    intervention_type TEXT DEFAULT 'support' CHECK (intervention_type IN ('grounding', 'support', 'normal', 'challenging')),
    pause_duration_ms INTEGER DEFAULT 500,  -- Extra pause before responding
    tone_adjustment JSONB  -- Voice generation parameters
);
```

#### API endpoints / interfaces

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/analyze-audio-stream` | WS | WebSocket for real-time analysis |
| `/functions/v1/calibrate-voice` | POST | Run voice calibration |
| `/functions/v1/update-calibration` | PUT | Update calibration settings |
| `/functions/v1/session-summary` | GET | Get emotional summary for session |
| `/functions/v1/emotion-history` | GET | Get user's emotional patterns |

#### Integration points with existing systems
- **Voice Mode:** Shared audio pipeline and token management.
- **Chat Edge Function:** Adapted response generation based on emotion.
- **Voice Synthesis:** Adjustable speech parameters.
- **SOS Flow:** Crisis detection from emotional analysis.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions

**Voice Mode with Emotion Indicator**
```
┌─────────────────────────────────────────────────┐
│  MindFriend         [💬 🎤 🔴]  [End]           │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │                                             ││
│  │         [Animated Voice Wave]               ││
│  │                                             ││
│  │         "I'm really stressed about         ││
│  │          this presentation tomorrow..."     ││
│  │                                             ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ 💭 Detecting: Anxious (82% confidence)     ││
│  │     Adjusting response for your state      ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  [Edit Adaptation Settings]                     │
└─────────────────────────────────────────────────┘
```

**Emotion Calibration Flow**
```
┌─────────────────────────────────────────────────┐
│  Voice Calibration                              │
├─────────────────────────────────────────────────┤
│                                                 │
│  🗣️ Let's get to know your voice               │
│                                                 │
│  This helps me understand how you're feeling   │
│  and respond appropriately.                     │
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │                                             ││
│  │   🎤                                        ││
│  │      Speak naturally for 30 seconds...     ││
│  │                                             ││
│  │   [██████░░░░░░]  18 seconds              ││
│  │                                             ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  Analyzing your speech patterns...              │
│                                                 │
│  [Skip for Now]                                 │
└─────────────────────────────────────────────────┘
```

**Adaptation Settings**
```
┌─────────────────────────────────────────────────┐
│  Voice Emotion Settings                         │
├─────────────────────────────────────────────────┤
│                                                 │
│  🧠 Emotion-Aware Voice                        │
│  ┌─────────────────────────────────────────┐   │
│  │ [ON]  When enabled, I'll adapt my       │   │
│  │       responses based on your tone      │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  Sensitivity                                    │
│  ┌─────────────────────────────────────────┐   │
│  │ ○ Minimal    (less adaptation)          │   │
│  │ ● Balanced   (recommended) ← SELECTED   │   │
│  │ ○ Responsive (more adaptation)          │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  What I adapt:                                  │
│  ┌─────────────────────────────────────────┐   │
│  │ [✓] Speed   [✓] Empathy   [✓] Pacing   │   │
│  │ [✓] Tone    [ ] Complex suggestions     │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  Privacy: Analysis happens on-device            │
│  [Learn More]                                   │
└─────────────────────────────────────────────────┘
```

**Session Emotional Summary**
```
┌─────────────────────────────────────────────────┐
│  Voice Session Summary                          │
├─────────────────────────────────────────────────┤
│                                                 │
│  12 minutes of conversation                     │
│                                                 │
│  📊 Emotional Arc:                              │
│  ┌─────────────────────────────────────────────┐│
│  │                                             ││
│  │  🟢🟢🟡🟡🟠🟠🟢🟢🟢🟢🟢🟢               ││
│  │  0  1  2  3  4  5  6  7  8  9  10 11 min   ││
│  │                                             ││
│  │  Started calm, peaked anxious at 4-5 min,  ││
│  │  ended calm with good grounding.           ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  💭 Detected Emotions                           │
│  • Calm: 7 minutes (58%)                        │
│  • Anxious: 3 minutes (25%)                     │
│  • Frustrated: 2 minutes (17%)                  │
│                                                 │
│  Adaptations Applied:                           │
│  • Slowed responses during anxious moments      │
│  • Added grounding exercise at 4:30             │
│  • Increased empathy level throughout           │
│                                                 │
│  [Start New Session]  [Share with Therapist]    │
└─────────────────────────────────────────────────┘
```

#### User flow diagram (text)

1. **First-time voice user:**
   - Enters voice mode → Receives calibration prompt → Calibrates (or skips) → Has first emotion-aware conversation → Sees summary.

2. **Returning user:**
   - Enters voice mode → AI uses calibration → Conversation adapts in real-time → User sees emotion indicator → End session → View summary.

3. **Calibration update:**
   - Opens settings → Adjusts sensitivity → Re-runs calibration → AI learns new patterns.

#### Accessibility requirements
- Emotion indicator readable by VoiceOver.
- Haptic feedback for emotion state changes.
- Option to disable visual indicators for privacy.
- All settings text accessible.

### 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| Unclear emotional detection | Default to neutral; no adaptation |
| Background noise | Show "hard to detect" indicator; continue |
| Contradictory signals (sad tone, happy words) | Ask for clarification; flag for user |
| User in crisis | Trigger SOS protocol; don't just adapt |
| Microphone issues | Fallback to text; explain limitation |
| User disables adaptation mid-session | Smooth transition back to standard mode |

### 6. Testing Requirements

#### Unit tests
- Emotion detection accuracy with sample audio.
- Response adaptation logic.
- Calibration baseline calculation.
- Session summary generation.

#### Integration tests
- Full voice session with emotion adaptation.
- Settings persistence and application.
- Audio stream processing pipeline.
- SOS integration from emotional detection.

#### UAT scenarios
- Speak anxiously → AI responds with slower, gentler responses.
- Speak calmly → AI responds normally, can introduce suggestions.
- Change sensitivity → Observe difference in adaptation.
- Complete calibration → AI learns personal patterns.

### 7. Implementation Notes

#### Suggested implementation approach
- **Phase 1:** Basic prosody detection (on-device ML), simple adaptations (speed, pauses).
- **Phase 2:** Full emotion detection, empathy level adaptation.
- **Phase 3:** Calibration system, session summaries.
- **Phase 4:** Advanced features (crisis detection, personalization).

#### Potential challenges and mitigations
- **Challenge:** On-device ML model size and performance. **Mitigation:** Use small, optimized model; test on older devices.
- **Challenge:** Accuracy of emotion detection. **Mitigation:** High confidence threshold; default to no adaptation if uncertain.
- **Challenge:** User acceptance of "being analyzed." **Mitigation:** Strong privacy messaging; on-device processing; clear opt-in.

#### Performance considerations
- Audio analysis should complete in <100ms for real-time feel.
- Model loaded once and cached.
- Battery impact monitored and minimized.
- Network usage minimal (on-device preferred).

## Appendix A: Emotion Detection Metrics

| Metric | Range | Emotional Indicators |
|--------|-------|---------------------|
| Pitch variation | Low-High | High = excited/anxious; Low = flat/depressed |
| Speech rate | Slow-Fast | Fast = anxious/excited; Slow = sad/calm |
| Volume dynamics | Flat-Dynamic | Flat = disengaged; Dynamic = engaged |
| Pause patterns | Few-Many | Many = hesitant/thinking; Few = confident |
| Voice tremor | Absent-Present | Present = stressed/anxious |

## Step 3: Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Adoption rate | 30% of voice users enable | Emotion-aware / voice users |
| Detection accuracy | 85% correct detection | User-corrected validations |
| User satisfaction | 4.5/5.0 with emotion-aware | Post-session survey |
| Perceived attunement | +20% vs standard voice | Comparative survey |
| Crisis detection | 90% of high-distress identified | SOS triggers / actual crises |
| Calibration completion | 70% complete initial calibration | Started / completed |
