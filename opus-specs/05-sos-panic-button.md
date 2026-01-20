# SOS Panic Button

> One-tap emergency mode for immediate calming intervention during panic attacks and acute anxiety.

**Priority:** P0 - Critical
**Effort:** Low (1-2 weeks)
**Impact:** Critical safety feature; high emotional value

---

## 1. Overview

### 1.1 What It Does

A prominent, one-tap emergency button that immediately launches a calming intervention sequence (breathing exercise + grounding technique + crisis resources) with optional emergency contact notification.

### 1.2 Why It Exists

- **Urgent Need:** Panic attacks need IMMEDIATE intervention, not menu navigation
- **Safety Critical:** Acute anxiety can escalate to crisis without quick support
- **Competitor Gap:** Wysa has SOS; most apps don't
- **User Trust:** Shows MindFriend takes mental health seriously

### 1.3 Success Metrics

| Metric                    | Target                        | Measurement              |
| ------------------------- | ----------------------------- | ------------------------ |
| SOS usage                 | 5% of users activate 1+ times | Analytics                |
| Intervention completion   | 70%+                          | Started / Completed      |
| Post-SOS mood improvement | +2 points average             | Pre/post mood capture    |
| User satisfaction         | 4.5+                          | Post-intervention rating |

---

## 2. User Stories

| Persona            | Need           | Story                                                                                             |
| ------------------ | -------------- | ------------------------------------------------------------------------------------------------- |
| **Panic Sufferer** | Immediate help | "As someone having a panic attack, I need instant access to a calming exercise without thinking." |
| **Anxiety Prone**  | Quick relief   | "As someone with anxiety, I want a panic button I can press when I feel overwhelmed."             |
| **Caregiver**      | Peace of mind  | "As a parent, I want my child to have an emergency button that can alert me."                     |

---

## 3. Functional Requirements

### 3.1 SOS Button

| ID    | Requirement                                                      | Priority |
| ----- | ---------------------------------------------------------------- | -------- |
| SB-01 | SOS button visible on home screen                                | Must     |
| SB-02 | SOS accessible from any screen via gesture or persistent element | Should   |
| SB-03 | One tap activation (no confirmation dialog)                      | Must     |
| SB-04 | Button is prominent but not accidentally triggerable             | Must     |
| SB-05 | Works offline (intervention content cached)                      | Must     |

### 3.2 Intervention Sequence

| ID    | Requirement                                            | Priority |
| ----- | ------------------------------------------------------ | -------- |
| IS-01 | Immediate launch of breathing exercise (4-7-8 pattern) | Must     |
| IS-02 | Calming voice guidance option                          | Should   |
| IS-03 | Visual breathing pacer (expanding/contracting circle)  | Must     |
| IS-04 | After breathing: grounding exercise (5-4-3-2-1)        | Must     |
| IS-05 | Crisis resources available throughout                  | Must     |
| IS-06 | Option to chat with MindFriend AI                      | Should   |
| IS-07 | Option to call crisis line directly                    | Must     |
| IS-08 | Post-intervention check-in                             | Should   |

### 3.3 Emergency Contacts

| ID    | Requirement                                     | Priority |
| ----- | ----------------------------------------------- | -------- |
| EC-01 | User can set emergency contact                  | Should   |
| EC-02 | Optional auto-text to contact on SOS activation | Should   |
| EC-03 | Customizable message template                   | Should   |
| EC-04 | Require confirmation before sending             | Should   |
| EC-05 | Family admin notified for child accounts        | Should   |

### 3.4 Personalization

| ID    | Requirement                                     | Priority |
| ----- | ----------------------------------------------- | -------- |
| PE-01 | Remember user's preferred intervention sequence | Should   |
| PE-02 | Learn from past SOS usage (what worked)         | Could    |
| PE-03 | Customize breathing pattern                     | Could    |
| PE-04 | Choose between guided voice, music, or silence  | Should   |

---

## 4. Technical Requirements

### 4.1 Data Models

```sql
-- SOS events tracking
CREATE TABLE sos_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    triggered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Context
    trigger_location TEXT, -- 'home', 'chat', 'exercise', etc.
    mood_before INTEGER,

    -- Intervention
    intervention_started BOOLEAN DEFAULT true,
    intervention_completed BOOLEAN DEFAULT false,
    intervention_duration_seconds INTEGER,
    steps_completed TEXT[], -- ['breathing', 'grounding', 'chat']

    -- Outcome
    mood_after INTEGER,
    helpful_rating INTEGER CHECK (helpful_rating BETWEEN 1 AND 5),

    -- Emergency contact
    contact_notified BOOLEAN DEFAULT false,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User SOS settings
CREATE TABLE sos_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Emergency contact
    emergency_contact_name TEXT,
    emergency_contact_phone TEXT,
    auto_notify_contact BOOLEAN DEFAULT false,
    contact_message_template TEXT DEFAULT 'I''m having a hard time right now. Just wanted you to know I''m using my MindFriend app to help.',

    -- Preferences
    preferred_breathing_pattern TEXT DEFAULT '4-7-8', -- '4-7-8', 'box', 'simple'
    include_voice_guidance BOOLEAN DEFAULT true,
    include_grounding BOOLEAN DEFAULT true,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE sos_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE sos_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own SOS events"
    ON sos_events FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own SOS settings"
    ON sos_settings FOR ALL
    USING (auth.uid() = user_id);
```

### 4.2 Swift Models

```swift
// MARK: - SOS Models

struct SOSEvent: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let triggeredAt: Date
    let triggerLocation: String?
    var moodBefore: Int?
    var interventionStarted: Bool
    var interventionCompleted: Bool
    var interventionDurationSeconds: Int?
    var stepsCompleted: [String]
    var moodAfter: Int?
    var helpfulRating: Int?
    var contactNotified: Bool
}

struct SOSSettings: Codable {
    var emergencyContactName: String?
    var emergencyContactPhone: String?
    var autoNotifyContact: Bool
    var contactMessageTemplate: String
    var preferredBreathingPattern: BreathingPattern
    var includeVoiceGuidance: Bool
    var includeGrounding: Bool

    enum BreathingPattern: String, Codable, CaseIterable {
        case fourSevenEight = "4-7-8"
        case box = "box"
        case simple = "simple"

        var displayName: String {
            switch self {
            case .fourSevenEight: return "4-7-8 Relaxing Breath"
            case .box: return "Box Breathing"
            case .simple: return "Simple Deep Breaths"
            }
        }

        var phases: [(name: String, duration: TimeInterval)] {
            switch self {
            case .fourSevenEight:
                return [("Breathe In", 4), ("Hold", 7), ("Breathe Out", 8)]
            case .box:
                return [("Breathe In", 4), ("Hold", 4), ("Breathe Out", 4), ("Hold", 4)]
            case .simple:
                return [("Breathe In", 4), ("Breathe Out", 6)]
            }
        }
    }

    static var defaults: SOSSettings {
        SOSSettings(
            emergencyContactName: nil,
            emergencyContactPhone: nil,
            autoNotifyContact: false,
            contactMessageTemplate: "I'm having a hard time right now. Just wanted you to know I'm using my MindFriend app to help.",
            preferredBreathingPattern: .fourSevenEight,
            includeVoiceGuidance: true,
            includeGrounding: true
        )
    }
}

// Grounding exercise (5-4-3-2-1 technique)
struct GroundingExercise {
    static let steps: [(count: Int, sense: String, prompt: String)] = [
        (5, "See", "Name 5 things you can SEE around you"),
        (4, "Touch", "Name 4 things you can TOUCH or feel"),
        (3, "Hear", "Name 3 things you can HEAR"),
        (2, "Smell", "Name 2 things you can SMELL"),
        (1, "Taste", "Name 1 thing you can TASTE")
    ]
}
```

### 4.3 SOS Coordinator

```swift
// MARK: - SOSCoordinator

import SwiftUI
import AVFoundation

@MainActor
class SOSCoordinator: ObservableObject {
    static let shared = SOSCoordinator()

    @Published var isActive = false
    @Published var currentPhase: SOSPhase = .breathing
    @Published var settings: SOSSettings = .defaults

    private var currentEvent: SOSEvent?
    private var audioPlayer: AVAudioPlayer?
    private let dataService = SupabaseDataService.shared

    enum SOSPhase {
        case breathing
        case grounding
        case resources
        case checkin
        case complete
    }

    // MARK: - Activation

    func activate(from location: String) async {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // Create event
        currentEvent = SOSEvent(
            id: UUID(),
            userId: UUID(), // Will be set from auth
            triggeredAt: Date(),
            triggerLocation: location,
            moodBefore: nil,
            interventionStarted: true,
            interventionCompleted: false,
            interventionDurationSeconds: nil,
            stepsCompleted: [],
            moodAfter: nil,
            helpfulRating: nil,
            contactNotified: false
        )

        isActive = true
        currentPhase = .breathing

        // Start voice guidance if enabled
        if settings.includeVoiceGuidance {
            playVoiceGuidance("sos_intro")
        }

        // Notify emergency contact if configured
        if settings.autoNotifyContact, let phone = settings.emergencyContactPhone {
            await notifyEmergencyContact(phone: phone)
        }

        // Log event
        await logEvent()
    }

    func completePhase(_ phase: SOSPhase) {
        currentEvent?.stepsCompleted.append(phase.rawValue)

        switch phase {
        case .breathing:
            if settings.includeGrounding {
                currentPhase = .grounding
            } else {
                currentPhase = .resources
            }
        case .grounding:
            currentPhase = .resources
        case .resources:
            currentPhase = .checkin
        case .checkin:
            currentPhase = .complete
        case .complete:
            deactivate()
        }
    }

    func skipToResources() {
        currentPhase = .resources
    }

    func deactivate() {
        isActive = false
        currentPhase = .breathing
        currentEvent?.interventionCompleted = true

        Task {
            await updateEvent()
        }
    }

    func recordMoodBefore(_ mood: Int) {
        currentEvent?.moodBefore = mood
    }

    func recordMoodAfter(_ mood: Int) {
        currentEvent?.moodAfter = mood
    }

    func recordRating(_ rating: Int) {
        currentEvent?.helpfulRating = rating
    }

    // MARK: - Emergency Contact

    private func notifyEmergencyContact(phone: String) async {
        // Send SMS via system
        if let url = URL(string: "sms:\(phone)&body=\(settings.contactMessageTemplate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            await UIApplication.shared.open(url)
            currentEvent?.contactNotified = true
        }
    }

    // MARK: - Audio

    private func playVoiceGuidance(_ file: String) {
        guard let url = Bundle.main.url(forResource: file, withExtension: "m4a") else { return }
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
    }

    // MARK: - Persistence

    private func logEvent() async {
        guard let event = currentEvent else { return }
        // Save to Supabase
        try? await dataService.logSOSEvent(event)
    }

    private func updateEvent() async {
        guard let event = currentEvent else { return }
        try? await dataService.updateSOSEvent(event)
    }
}

extension SOSCoordinator.SOSPhase: RawRepresentable {
    var rawValue: String {
        switch self {
        case .breathing: return "breathing"
        case .grounding: return "grounding"
        case .resources: return "resources"
        case .checkin: return "checkin"
        case .complete: return "complete"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "breathing": self = .breathing
        case "grounding": self = .grounding
        case "resources": self = .resources
        case "checkin": self = .checkin
        case "complete": self = .complete
        default: return nil
        }
    }
}
```

---

## 5. UI/UX Specifications

### 5.1 SOS Button on Home

```
┌─────────────────────────────────┐
│                                 │
│  ┌─────┐                        │
│  │ SOS │  ← Top-right corner    │
│  │ 🆘  │     Always visible     │
│  └─────┘                        │
│                                 │
│  Good evening, Sarah            │
│  How are you feeling?           │
│                                 │
│  ... rest of home screen ...    │
│                                 │
└─────────────────────────────────┘
```

### 5.2 SOS Breathing Screen

```
┌─────────────────────────────────┐
│                            ✕    │
├─────────────────────────────────┤
│                                 │
│         You're safe.            │
│      Let's breathe together.    │
│                                 │
│                                 │
│           ┌─────────┐           │
│          ╱           ╲          │
│         │             │         │
│         │   BREATHE   │         │
│         │     IN      │         │
│         │             │         │
│          ╲           ╱          │
│           └─────────┘           │
│                                 │
│             4 sec               │
│                                 │
│         Cycle 2 of 4            │
│                                 │
│                                 │
│                                 │
│  🔇 Mute        [Skip to Help]  │
│                                 │
└─────────────────────────────────┘

(Circle expands/contracts with breath)
```

### 5.3 Grounding Exercise Screen

```
┌─────────────────────────────────┐
│                            ✕    │
├─────────────────────────────────┤
│                                 │
│      5-4-3-2-1 Grounding        │
│                                 │
│      Let's anchor you to        │
│      the present moment.        │
│                                 │
│  ─────────────────────────────  │
│                                 │
│          👁️ Step 1 of 5         │
│                                 │
│     Name 5 things you           │
│     can SEE around you          │
│                                 │
│  ┌─────────────────────────────┐│
│  │                             ││
│  │ 1. ________________________ ││
│  │ 2. ________________________ ││
│  │ 3. ________________________ ││
│  │ 4. ________________________ ││
│  │ 5. ________________________ ││
│  │                             ││
│  └─────────────────────────────┘│
│                                 │
│     (Typing optional)           │
│                                 │
│  [← Back]           [Next →]    │
│                                 │
└─────────────────────────────────┘
```

### 5.4 Crisis Resources Screen

```
┌─────────────────────────────────┐
│                            ✕    │
├─────────────────────────────────┤
│                                 │
│            ❤️                    │
│                                 │
│     How are you feeling now?    │
│                                 │
│  😢  😕  😐  🙂  😌            │
│                                 │
│  ─────────────────────────────  │
│                                 │
│     What would help?            │
│                                 │
│  ┌────────────────────────────┐ │
│  │ 💬 Chat with MindFriend    │ │
│  └────────────────────────────┘ │
│                                 │
│  ┌────────────────────────────┐ │
│  │ 📞 Call 988 (Crisis Line)  │ │
│  └────────────────────────────┘ │
│                                 │
│  ┌────────────────────────────┐ │
│  │ 💬 Text HOME to 741741     │ │
│  └────────────────────────────┘ │
│                                 │
│  ┌────────────────────────────┐ │
│  │ 👤 Contact: Mom            │ │
│  │    (Send "I need support") │ │
│  └────────────────────────────┘ │
│                                 │
│  [I'm feeling better]           │
│                                 │
└─────────────────────────────────┘
```

### 5.5 Post-SOS Check-In

```
┌─────────────────────────────────┐
│                                 │
│            💙                   │
│                                 │
│     You did great.              │
│                                 │
│     Taking a moment to          │
│     breathe takes courage.      │
│                                 │
│  ─────────────────────────────  │
│                                 │
│     Was this helpful?           │
│                                 │
│     ⭐ ⭐ ⭐ ⭐ ⭐              │
│                                 │
│  ─────────────────────────────  │
│                                 │
│     Remember: You can use       │
│     the SOS button anytime.     │
│                                 │
│     We're always here. 💙       │
│                                 │
│        [Back to Home]           │
│                                 │
└─────────────────────────────────┘
```

### 5.6 Design Specifications

| Element              | Specification                          |
| -------------------- | -------------------------------------- |
| **Background**       | Soft gradient (calming blue to purple) |
| **Breathing Circle** | Smooth animation, 60fps, soft shadow   |
| **Typography**       | Large, clear, easy to read in distress |
| **Voice**            | Calm, slow, reassuring (pre-recorded)  |
| **Haptics**          | Gentle pulse matching breath rhythm    |
| **Transitions**      | Slow fades (reduce jarring)            |
| **Exit Button**      | Always visible but not prominent       |

---

## 6. Acceptance Criteria

### 6.1 SOS Activation

- [ ] SOS button is visible on home screen
- [ ] One tap activates intervention immediately
- [ ] Works offline with cached content
- [ ] Haptic feedback on activation
- [ ] Event is logged for analytics

### 6.2 Breathing Exercise

- [ ] Expanding/contracting circle guides breathing
- [ ] Timer shows current phase duration
- [ ] Completes 4 cycles by default
- [ ] Voice guidance plays if enabled
- [ ] User can skip to resources anytime

### 6.3 Grounding Exercise

- [ ] 5-4-3-2-1 steps are guided sequentially
- [ ] Text input is optional (can proceed without typing)
- [ ] Progress through steps is tracked
- [ ] User can skip entire grounding

### 6.4 Crisis Resources

- [ ] Mood before/after is captured
- [ ] Crisis line call button works
- [ ] Text line opens SMS app
- [ ] Chat with AI opens conversation
- [ ] Emergency contact sends message if configured

### 6.5 Emergency Contact

- [ ] User can set emergency contact in settings
- [ ] Message template is customizable
- [ ] Auto-notify option requires confirmation
- [ ] SMS is sent via system (not MindFriend servers)

---

## 7. Edge Cases & Error Handling

| Scenario                        | Behavior                                   |
| ------------------------------- | ------------------------------------------ |
| User offline                    | All intervention content works (cached)    |
| User closes app mid-SOS         | Save progress; offer to continue on reopen |
| Multiple SOS in short time      | Log all; show "frequent use" care message  |
| Emergency contact fails to send | Show error; offer manual call option       |
| Voice guidance file missing     | Proceed without voice; show visual only    |
| User accidentally triggers      | Exit button always visible; no penalty     |

---

## 8. Security & Privacy

| Area                | Requirement                                 |
| ------------------- | ------------------------------------------- |
| SOS Events          | Logged locally; synced with RLS protection  |
| Emergency Contact   | Phone number stored encrypted               |
| Voice Guidance      | Processed on-device                         |
| Analytics           | Aggregate only; no individual event details |
| Family Notification | Opt-in only; minimal info shared            |

---

## 9. Performance Requirements

| Metric                     | Target                     |
| -------------------------- | -------------------------- |
| Activation to first screen | < 500ms                    |
| Breathing animation        | 60fps, no drops            |
| Voice guidance start       | < 1 second                 |
| Offline activation         | Same performance as online |

---

## 10. Dependencies

### Internal

| Dependency           | Reason                      |
| -------------------- | --------------------------- |
| Audio Player Service | Voice guidance playback     |
| Offline Cache        | Cached intervention content |
| Crisis Resources     | Crisis line integration     |
| Family Service       | Family notification         |

---

## 11. Rollout Plan

### Phase 1: Core (Week 1)

- SOS button on home
- Breathing exercise with animation
- Basic event logging

### Phase 2: Full Intervention (Week 2)

- Grounding exercise
- Voice guidance
- Crisis resources integration
- Post-SOS check-in

### Phase 3: Emergency Contact (Week 2+)

- Emergency contact settings
- SMS notification
- Family alerts for child accounts
