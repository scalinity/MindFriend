# Privacy Quick Lock

**Quick Win:** Low Effort / High Perceived Value

## Overview

- **Feature name:** Privacy Quick Lock
- **Description:** Optional app-level biometric authentication with auto-lock after inactivity. Adds a security layer for users who share devices or want extra privacy.
- **Business justification and user value:** Trust-building feature for privacy-conscious users. Minimal effort, high perceived value.

## Functional Requirements

### FR1: App Lock
- As a user, I want to lock the app with Face ID/Touch ID.
- As a user, I want the app to require authentication when opening.

**Acceptance criteria:**
- Toggle in Settings: "Enable App Lock"
- On enable: Immediate biometric prompt
- On disable: Confirm with biometric or passcode
- Re-authentication on app switch (backgrounding)

### FR2: Auto-Lock
- As a user, I want the app to auto-lock after inactivity.
- As a user, I want to customize the auto-lock timing.

**Acceptance criteria:**
- Auto-lock timeout options: 1 min, 5 min, 15 min, 30 min, Never
- Default: 5 minutes
- Timer resets on any interaction
- Visual countdown in settings (optional)

### FR3: Quick Re-Lock
- As a user, I want to quickly lock the app without leaving the screen.
- As a user, I want a discreet lock option.

**Acceptance criteria:**
- Long-press app icon or menu option: "Lock App"
- Or triple-tap (configurable)
- Immediate lock, no animation/attention

## Technical Specifications

### Data Model

```sql
CREATE TABLE privacy_lock_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    app_lock_enabled BOOLEAN DEFAULT FALSE,
    auto_lock_seconds INTEGER DEFAULT 300,  -- 5 minutes
    quick_lock_method TEXT DEFAULT 'menu' CHECK (quick_lock_method IN ('menu', 'triple_tap')),
    triple_tap_enabled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/privacy-lock-settings` | GET/PUT | Get or update settings |
| `/functions/v1/verify-lock` | POST | Verify authentication for settings change |

### Integration Points
- **Settings View:** Toggle and auto-lock options
- **App Lifecycle:** Backgrounding detection
- **LocalAuthentication:** Biometric prompts

## User Interface

### Settings Screen Addition
```
┌─────────────────────────────────────────────────┐
│  Privacy                                        │
├─────────────────────────────────────────────────┤
│                                                 │
│  🔒 App Lock                                    │
│  ┌─────────────────────────────────────────┐   │
│  │ [ON]  Enable app lock                   │   │
│  │       Requires Face ID to open          │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  Auto-Lock After                               │
│  ┌─────────────────────────────────────────┐   │
│  │ [5 minutes ▼]                           │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  Quick Lock                                    │
│  ┌─────────────────────────────────────────┐   │
│  │ Add to menu for one-tap locking         │   │
│  │ [○] Enable                              │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  🔒 When locked, app requires authentication   │
│     to access any content.                     │
└─────────────────────────────────────────────────┘
```

### Lock Screen
```
┌─────────────────────────────────────────────────┐
│                                                 │
│                                                 │
│                    🔐                           │
│                                                 │
│           MindFriend is locked                  │
│                                                 │
│        [Unlock with Face ID]                   │
│                                                 │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Biometric unavailable | Fallback to device passcode |
| Biometric enrollment changes | Prompt re-enable on next access |
| Auto-lock with notification | Show lock screen over notification |
| User forgets passcode | Account recovery flow |

## Testing Requirements

- Enable/disable lock flow
- Auto-lock timing accuracy
- Quick lock functionality
- Background/foreground transitions
- Biometric fallback behavior

## Implementation Notes

- Use iOS LocalAuthentication framework
- Store lock state in Keychain for persistence
- Timer reset on any touch event
- Low battery impact

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Adoption | 30% of users enable | Enabled / DAU |
| Lock engagement | 10 locks/day per enabled user | Lock events |
| User satisfaction | 4.5/5.0 rating | In-app survey |
