# Calm Screen Mode

**Quick Win:** Low Effort / High Perceived Value

## Overview

- **Feature name:** Calm Screen Mode
- **Description:** Low-stimulus UI preset with reduced motion, softer typography, muted colors, and simplified navigation. An alternative to the standard interface for users seeking calm.
- **Business justification and user value:** Addresses accessibility and sensory needs. Positions MindFriend as inclusive. Low effort, high appreciation from target users.

## Functional Requirements

### FR1: Mode Activation
- As a user, I want to switch to a calmer interface.
- As a user, I want easy access to calm mode.

**Acceptance criteria:**
- Toggle in Settings: "Calm Screen Mode"
- Quick toggle in Home menu or control center
- Toggle can be placed on Home surface (optional)
- Instant transition with smooth fade

### FR2: Visual Changes
- As a user, I want a less stimulating interface.
- As a user, I want reduced visual noise.

**Acceptance criteria:**
- Reduced motion: All animations slower or removed
- Softer typography: More readable fonts, increased line height
- Muted colors: Reduced saturation, warmer tones
- Simplified navigation: Fewer visual elements, more whitespace
- No bouncing badges, subtle notifications only

### FR3: Interaction Changes
- As a user, I want calmer feedback when I interact.
- As a user, I want less attention-grabbing notifications.

**Acceptance criteria:**
- Reduced haptic feedback (softer or fewer)
- Quieter notifications (no sounds, subtle banners)
- Slower transitions between views
- Reduced button emphasis

### FR4: Mode Persistence
- As a user, I want the mode to stay on when I return.
- As a user, I want to exit calm mode easily.

**Acceptance criteria:**
- Mode persists across sessions
- Easy toggle to return to standard mode
- User preference saved to server
- No forced mode switching

## Technical Specifications

### Data Model

```sql
CREATE TABLE ui_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    screen_mode TEXT DEFAULT 'standard' CHECK (screen_mode IN ('standard', 'calm')),
    reduced_motion BOOLEAN DEFAULT FALSE,
    reduced_transparency BOOLEAN DEFAULT FALSE,
    reduced_noise BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Theme Configuration

```swift
enum ScreenMode {
    case standard
    case calm
    
    var colors: ColorScheme {
        // Calm: muted, warm, lower saturation
    }
    
    var animationDuration: Double {
        // Calm: 0.5x standard duration
    }
    
    var hapticIntensity: Float {
        // Calm: 0.3x standard intensity
    }
    
    var fontScaling: CGFloat {
        // Calm: 1.0x but with increased line height
    }
}
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/ui-preferences` | GET/PUT | Get or update UI preferences |
| `/functions/v1/toggle-calm-mode` | POST | Quick toggle endpoint |

### Integration Points
- **All Views:** Respect screen mode preference
- **Theme System:** Apply calm color scheme
- **Animation System:** Adjust timing based on mode
- **Haptic Engine:** Adjust intensity based on mode

## User Interface

### Standard vs Calm Comparison

**Standard Home:**
```
Good morning! ☀️            [💬][🔔][⚙️]
Monday, Jan 20

🌟 Today's Quest     [New!]    →
[Progress ██████░░░░░░░░]  2/5

😊 How are you?
[Great] [Good] [Okay] [Rough]

📈 Your streak: 5 days! 🔥
```

**Calm Home:**
```
Good morning.                 [Calm: ON ▼]
Monday, January 20

Today's focus
· Quest: Morning Gratitude
· Check-in when ready

How are you feeling?
[Great] [Good] [Okay] [Need support]
```

### Settings Toggle
```
Display

🖥️ Screen Mode
┌─────────────────────────────────────────┐
│ ○ Standard    ● Calm                    │
│       ← Selected                         │
└─────────────────────────────────────────┘

Calm mode includes:
• Slower animations
• Softer colors and typography
• Reduced notifications
• Quieter feedback

[Preview Calm Mode]

⬆️ Swipe down to exit calm mode anytime
```

### Quick Toggle (Control Center Style)
```
┌──────────┐
│ ☁️ Calm  │ ← Tap to toggle
│   ON     │
└──────────┘
```

## Visual Changes Detail

| Element | Standard | Calm |
|---------|----------|------|
| Background | Light/neutral | Warm cream/beige |
| Accent colors | Vibrant blue/green | Muted sage/lavender |
| Typography | System font | Increased line height, more readable |
| Animations | Bouncy, fast | Slow, smooth, no bounce |
| Icons | Bold, filled | Softer, outlined |
| Notifications | Banners, badges | Subtle, no bounce |
| Haptics | Standard intensity | Softer, fewer |
| Borders | Sharp | Rounded |
| Shadows | Prominent | Minimal |
| Progress indicators | Animated | Static or slow |

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Reduced motion enabled in iOS | Calm mode auto-enabled (optional) |
| User in crisis | Calm mode doesn't suppress SOS |
| Battery low | Offer to disable for battery saving |
| First-time user | Don't auto-enable, suggest in onboarding |
| Conflict with dark mode | Calm mode works with light/dark |

## Testing Requirements

- All views render correctly in calm mode
- Toggle transitions smoothly
- Animations disabled/reduced when specified
- Haptics adjusted correctly
- Preferences persist correctly
- Accessibility: VoiceOver works in calm mode

## Implementation Notes

- Use iOS `UIAccessibility.isReduceMotion` as signal
- Create calm color palette in app theme
- Adjust animation durations globally
- No new views needed, just styling changes
- Start with Home and Chat (highest usage)

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Adoption | 15% of users enable | Enabled / DAU |
| Retention of enabled | 80% stay enabled | Still enabled after 7 days |
| User satisfaction | 4.5/5.0 rating | In-app survey |
| Accessibility alignment | Positive feedback | Accessibility user feedback |
| Completion rate in calm | +5% vs standard | Quest completion / mode |
