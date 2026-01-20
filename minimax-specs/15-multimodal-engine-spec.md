# Multimodal Emotional State Engine

**Moonshot Feature (Phase 4+)**
**Scores:** Delight 10/10 | Differentiation 10/10 | Feasibility Low | Revenue High

## Step 1: Feature Analysis

### Core purpose and value proposition
- Opt-in, on-device fusion of voice tone, typing cadence, and (optionally) respiration to dynamically shape AI support in real-time.
- Creates a closed-loop emotional co-regulation system without external integrations.
- The ultimate expression of emotional attunement in MindFriend.

### Target users and use cases
- Users who want deep, personalized emotional support.
- Users in active distress who need responsive, adaptive AI.
- Users who opt-in to share multiple data streams for better understanding.

### Dependencies / prerequisites
- Emotion-Aware Voice Companion (voice tone analysis).
- Camera Biofeedback Breathing Coach (respiration detection).
- Typing pattern analysis (keystroke dynamics).
- Adaptive AI response generation.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Multimodal Emotional State Engine
- **Description:** An opt-in, on-device system that fuses voice tone, typing cadence, and respiration data to understand user emotional state in real-time. Dynamically shapes AI support—adjusting pace, content type, and intensity—creating a closed-loop emotional co-regulation experience that feels like talking to someone who truly "gets" you.
- **Business justification and user value:** Transforms MindFriend from an AI chatbot into an emotional co-regulation companion. Creates category-defining differentiation. Premium tier feature with strong retention impact.

### 2. Functional Requirements

#### FR1: Multimodal Data Fusion
- User stories:
  - As a user, I want the AI to understand me from multiple signals.
  - As a user, I want the AI to know when I'm struggling before I say it.
- Acceptance criteria:
  - Voice stream: Tone, pace, stress, hesitation (from Emotion-Aware Voice).
  - Typing stream: Speed, rhythm, deletions, pauses (from text chat).
  - Respiration stream: Rate, depth, regularity (from Camera Biofeedback).
  - Fusion algorithm: Weighted combination based on data quality.
  - Confidence scoring for emotional state detection.

#### FR2: Real-Time State Detection
- User stories:
  - As a user, I want the AI to know my emotional state in real-time.
  - As a user, I want the AI to respond to changes as they happen.
- Acceptance criteria:
  - State detection latency: <500ms from signal to adaptation.
  - Detectable states:
    - Calm/Stable
    - Mild Anxiety/Concern
    - Moderate Anxiety/Stress
    - High Anxiety/Distress
    - Sadness/Grief
    - Anger/Frustration
    - Elevated/Excited
  - State transition detection (e.g., calm → anxious).
  - Crisis indicators (rapid escalation, distress spikes).

#### FR3: Dynamic AI Adaptation
- User stories:
  - As a user, I want the AI to adjust its support based on my state.
  - As a user, I want different levels of support for different states.
- Acceptance criteria:
  - Response pacing: Slow/simplified (distress) → Normal (neutral) → Quick/engaging (positive).
  - Content type:
    - Distress: Grounding, validation, reduced complexity.
    - Neutral: Normal support, can introduce suggestions.
    - Positive: Celebrating, can introduce challenges.
  - Intervention intensity: Gentle → Supportive → Active intervention.
  - Smooth transitions between states (no jarring changes).

#### FR4: Co-Regulation Feedback Loop
- User stories:
  - As a user, I want to see how my state changes during our conversation.
  - As a user, I want the AI to help me regulate in real-time.
- Acceptance criteria:
  - Real-time state visualization (subtle, non-intrusive).
  - "Co-regulation mode" visual indicator.
  - Regulation progress: Show when user is calming/shifting.
  - Adaptation to user's regulation style.

#### FR5: Opt-In Consent & Privacy
- User stories:
  - As a user, I want to control what data I share.
  - As a user, I want to understand how my data is used.
- Acceptance criteria:
  - Multi-step opt-in with clear explanation of each data stream.
  - Per-stream control: Enable voice, typing, respiration independently.
  - Privacy dashboard showing active data streams.
  - Clear data handling: All processing on-device.
  - Emergency exit: One-tap to disable all multimodal features.

### 3. Technical Specifications

#### Architecture and system design considerations
- All fusion and analysis on-device (privacy-first).
- Lightweight ML models for each modality.
- Real-time streaming architecture.
- Graceful degradation when streams unavailable.

#### Data models and schemas (proposed)

```sql
-- Multimodal fusion state (temporary, session-scoped)
CREATE TABLE multimodal_state (
    session_id UUID NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    voice_confidence FLOAT,  -- 0-1, NULL if no voice
    typing_confidence FLOAT,  -- 0-1, NULL if no typing
    respiration_confidence FLOAT,  -- 0-1, NULL if no camera
    fused_state TEXT NOT NULL,  -- Detected emotional state
    fusion_confidence FLOAT NOT NULL,  -- Overall confidence
    state_vector JSONB,  -- Full state probabilities
    adaptations_applied JSONB,  -- Which adaptations triggered
    raw_signals JSONB  -- For debugging/analysis
);

-- User multimodal consent
CREATE TABLE multimodal_consent (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    is_enabled BOOLEAN DEFAULT FALSE,
    voice_consent BOOLEAN DEFAULT FALSE,
    typing_consent BOOLEAN DEFAULT FALSE,
    respiration_consent BOOLEAN DEFAULT FALSE,
    consent_timestamp TIMESTAMPTZ,
    last_active_at TIMESTAMPTZ,
    streams_active TEXT[],  -- Currently active streams
    privacy_settings JSONB  -- Additional privacy config
);

-- Fusion model configuration
CREATE TABLE fusion_models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_version TEXT NOT NULL,
    model_type TEXT NOT NULL,  -- 'voice', 'typing', 'respiration', 'fusion'
    model_blob BYTEA,  -- Encoded model weights
    accuracy_metrics JSONB,
    performance_metrics JSONB,
    deployed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Session multimodal summary
CREATE TABLE multimodal_session_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NOT NULL,
    streams_used TEXT[],  -- Which streams were active
    dominant_states JSONB,  -- Time in each state
    state_transitions INTEGER,  -- Number of state changes
    crisis_indicators INTEGER,  -- Count of crisis flags
    regulation_success_rate FLOAT,  -- % of distress resolved
    adaptations_applied JSONB,
    user_feedback TEXT  -- Optional rating
);
```

#### API endpoints / interfaces

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/multimodal-consent` | PUT | Update multimodal consent |
| `/functions/v1/start-fusion` | POST | Initialize fusion engine |
| `/functions/v1/fusion-stream` | WS | WebSocket for real-time fusion |
| `/functions/v1/stop-fusion` | POST | Stop fusion engine |
| `/functions/v1/session-summary` | GET | Get session multimodal summary |
| `/functions/v1/fusion-stats` | GET | Get usage statistics |

#### Integration points with existing systems
- **Voice Mode:** Voice stream input.
- **Chat:** Typing stream input.
- **Camera Biofeedback:** Respiration stream input.
- **Chat Edge Function:** Adapted responses based on fusion state.
- **SOS Flow:** Crisis detection from multimodal signals.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions

**Consent Flow - Step 1**
```
┌─────────────────────────────────────────────────┐
│  🌟 Deeper Emotional Understanding              │
├─────────────────────────────────────────────────┤
│                                                 │
│  MindFriend can understand you even better     │
│  by combining what you say, how you say it,    │
│  and how you're breathing.                      │
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │                                             ││
│  │  🎤 Voice   +   ⌨️ Typing   +   📷 Breathing││
│  │                                             ││
│  │  = A companion who truly understands       ││
│  │                                             ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  This is optional and completely private.      │
│  All analysis happens on your device.           │
│                                                 │
│            [Learn More]  [Get Started]          │
│                                                 │
│  [Maybe Later]                                  │
└─────────────────────────────────────────────────┘
```

**Consent Flow - Step 2**
```
┌─────────────────────────────────────────────────┐
│  Choose What to Share                           │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ 🎤 Voice Tone                               ││
│  │ I can detect if you're stressed, sad, or   ││
│  │ calm from your speaking patterns.          ││
│  │                                             ││
│  │ [✓] Enable    [?] Learn more               ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ ⌨️ Typing Patterns                          ││
│  │ I can understand your emotional state from ││
│  │ how you type—speed, pauses, deletions.     ││
│  │                                             ││
│  │ [✓] Enable    [?] Learn more               ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ 📷 Breathing                               ││
│  │ I can see your breathing rate to help      ││
│  │ guide calming exercises.                   ││
│  │                                             ││
│  │ [✓] Enable    [?] Learn more               ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│            [Confirm & Enable]                   │
│                                                 │
│  [Back]                                         │
└─────────────────────────────────────────────────┘
```

**Active Multimodal Chat**
```
┌─────────────────────────────────────────────────┐
│  MindFriend         [💬 🎤 📷 ◉]  [End]         │
│  ◉ Multimodal Active                            │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ 💭 Calmly detected (92% confidence)        ││
│  │     Responding with gentle support         ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │                                             ││
│  │  MindFriend:                               ││
│  │  "I hear how you're feeling. Let's take    ││
│  │  a moment together. Follow along..."       ││
│  │                                             ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ You:                                       ││
│  │ "I just feel really overwhelmed with      ││
│  │  everything going on..."                  ││
│  │                                             ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  State Indicator (subtle):                      │
│  🟢 Calm → 🟡 Mild concern (detecting shift)   │
│                                                 │
│  [⚙️ Adjust Streams]  [🛡️ Pause Fusion]       │
└─────────────────────────────────────────────────┘
```

**State Transition Visualization**
```
┌─────────────────────────────────────────────────┐
│  Your Emotional Journey                         │
│  This conversation                             │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │                                             ││
│  │  8:00  🟢🟢🟢🟢🟡🟡🟠🟠🟢🟢🟢🟢          ││
│  │       │     │     │     │     │           ││
│  │       Start  ↑     ↑     ↑     End         ││
│  │            StressedDetectedCalmed          ││
│  │                                             ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  State Transitions: 7                          │
│  Peak Distress: 8:15 AM (brief)                │
│  Regulation Success: 85%                       │
│                                                 │
│  💡 You showed great self-regulation!          │
│  The app adapted support throughout.           │
│                                                 │
│  [See Details]                                  │
└─────────────────────────────────────────────────┘
```

**Privacy Dashboard**
```
┌─────────────────────────────────────────────────┐
│  Multimodal Privacy                             │
├─────────────────────────────────────────────────┤
│                                                 │
│  🧠 Multimodal Engine: Active                   │
│                                                 │
│  Current Streams:                               │
│  ┌───────────────────────────────────────────┐ │
│  │ [✓] Voice    - Active now                 │ │
│  │ [✓] Typing   - Active now                 │ │
│  │ [✓] Breathing - Camera off (low light)    │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  📊 Data This Session:                          │
│  • 12 minutes of voice analysis                 │
│  • 8 minutes of typing patterns                 │
│  • 5 minutes of breathing data                  │
│                                                 │
│  🔒 All processing is on-device.                │
│  No audio, video, or typing data is stored.     │
│                                                 │
│  [🔇 Emergency: Disable All]                    │
│                                                 │
│  [Manage Consent]                               │
└─────────────────────────────────────────────────┘
```

#### User flow diagram (text)

1. **Consent flow:**
   - User hears about multimodal → Reviews options → Chooses streams → Confirms → Enabled.

2. **First multimodal session:**
   - Enters chat → Active streams indicated → Normal chat with enhanced adaptation → Sees subtle state indicator → Ends session → Views summary.

3. **During distress:**
   - Chat detects escalation via fusion → Adapts to high-support mode → Triggers grounding if needed → Tracks regulation → Returns to normal when user stabilizes.

4. **Privacy management:**
   - Opens privacy dashboard → Reviews active streams → Adjusts consent → Disables if needed.

#### Accessibility requirements
- State changes announced via VoiceOver (optional).
- Haptic feedback for state transitions.
- All indicators have text alternatives.
- Emergency disable accessible via accessibility shortcuts.

### 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| One stream unavailable | Continue with remaining streams (degraded mode) |
| Conflicting signals | Weight by confidence; ask for clarification |
| User in crisis | Full SOS protocol triggered; multimodal aids detection |
| Privacy concern mid-session | One-tap disable all streams |
| Model detects error | Fallback to standard chat mode |
| Battery drain | Warn user; suggest charging or reduced mode |

### 6. Testing Requirements

#### Unit tests
- Fusion algorithm accuracy with synthetic data.
- State transition detection.
- Adaptation latency measurements.
- Privacy boundary enforcement.

#### Integration tests
- Full multimodal chat session.
- Crisis detection and SOS trigger.
- Consent flow completeness.
- Session summary accuracy.

#### UAT scenarios
- Speak anxiously → AI responds with slowed, gentle support.
- Type with long pauses → AI offers patience.
- Breathing rate detected as elevated → AI suggests calming exercise.
- All signals align (distress) → Full intervention triggered.
- User disables streams → Returns to standard mode smoothly.

### 7. Implementation Notes

#### Suggested implementation approach
- **Phase 1:** Voice + typing fusion only (no camera).
- **Phase 2:** Add respiration stream.
- **Phase 3:** Crisis detection improvements.
- **Phase 4:** Advanced co-regulation features.

#### Potential challenges and mitigations
- **Challenge:** Privacy concerns with multimodal. **Mitigation:** Strong consent, on-device only, clear communication.
- **Challenge:** Technical complexity of fusion. **Mitigation:** Start simple; iterate; use existing modality models.
- **Challenge:** User acceptance of "being analyzed." **Mitigation:** Clear value proposition; show benefits; easy opt-out.

#### Performance considerations
- Models optimized for on-device inference (<100ms latency).
- Battery impact managed (offer low-power mode).
- Memory efficient (stream processing, no buffering).
- Thermal throttling handled gracefully.

## Appendix A: Adaptation Matrix

| Detected State | Voice Pace | Response Length | Complexity | Intervention Type |
|----------------|------------|-----------------|------------|-------------------|
| Calm/Stable | Normal | Normal | Normal | Normal support |
| Mild Anxiety | Slightly slow | Shorter | Moderate | Gentle guidance |
| Moderate Anxiety | Slow | Short | Simple | Grounding available |
| High Distress | Very slow | Minimal | Simple | Active intervention |
| Sadness | Normal-slow | Normal | Moderate | Empathetic support |
| Anger/Frustration | Normal | Normal | Moderate | Validation, de-escalation |
| Excited/Positive | Normal | Normal | Higher | Celebratory, engaging |

## Step 3: Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Opt-in rate | 25% of engaged users | Enabled / DAU |
| Session engagement | +30% vs standard chat | Session duration |
| Regulation success | 75% distress reduction | State before/after |
| Crisis detection | 95% detection rate | SOS triggers / actual crises |
| User satisfaction | 4.8/5.0 rating | Post-session survey |
| Retention impact | +20% weekly retention | 30-day retention rate |
| NPS impact | +15 NPS for multimodal users | Survey comparison |
