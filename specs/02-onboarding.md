# Onboarding That Hooks

## Overview

**Goal:** The first 3 minutes determine whether users stay or churn. Replace the current generic onboarding with a personalized AI conversation that makes users feel immediately understood.

**Why it matters:** Most wellness apps lose 70-80% of users in week 1. The current flow (Sign up → Home screen) misses the opportunity to create an emotional connection. A personalized quiz + immediate AI greeting hooks users by showing the app "gets them."

**Impact:** P2 priority - Fixes day-1 drop-off

---

## User Stories

- As a new user, I want to tell the app what I'm struggling with so that it can help me specifically
- As a new user, I want to feel like the AI understands me from the start so that I trust it
- As a new user, I want to experience the core value immediately so that I know this app is worth my time
- As a new user, I want a quick setup so that I can start using the app fast

---

## Product Requirements

### Must Have (MVP)

1. **Personalization Quiz** (single screen, 4 options)
   - "What brings you here today?"
   - Options: Managing anxiety, Reducing stress, Feeling less lonely, Staying productive
   - Store selection in `profiles.wellness_focus`

2. **Immediate AI Greeting** (after quiz)
   - AI sends first message based on wellness focus
   - User can respond naturally
   - 2-3 message exchange before home screen

3. **Skip Option**
   - Allow users to skip quiz (default wellness_focus: 'general')
   - Skip AI greeting with "Get started" button

4. **Progress Indicator**
   - Show step progress (Quiz → AI Greeting → Ready)
   - Feels quick, not like a long form

### Nice to Have (V2)

- Multiple quiz questions (mood level, experience with wellness apps)
- Photo/avatar selection during onboarding
- Choose AI personality/tone
- Set preferred check-in time
- Tutorial tooltips on first home screen visit

### Out of Scope

- Detailed intake questionnaire
- Mental health assessments (clinical)
- Onboarding videos

---

## Technical Design

### Data Model Changes

**Alter Table: `profiles`**

```sql
-- Migration: 20260116_add_wellness_focus.sql

ALTER TABLE profiles ADD COLUMN wellness_focus TEXT
  DEFAULT 'general'
  CHECK (wellness_focus IN ('anxiety', 'stress', 'loneliness', 'productivity', 'general'));

ALTER TABLE profiles ADD COLUMN onboarding_completed_at TIMESTAMPTZ;

COMMENT ON COLUMN profiles.wellness_focus IS 'Primary wellness goal selected during onboarding';
COMMENT ON COLUMN profiles.onboarding_completed_at IS 'Timestamp when user completed onboarding flow';
```

### iOS Implementation

**New Model** (`Core/Models.swift`):

```swift
enum WellnessFocus: String, Codable, CaseIterable {
    case anxiety
    case stress
    case loneliness
    case productivity
    case general

    var displayTitle: String {
        switch self {
        case .anxiety: return "Managing anxiety"
        case .stress: return "Reducing stress"
        case .loneliness: return "Feeling less lonely"
        case .productivity: return "Staying productive"
        case .general: return "General wellness"
        }
    }

    var emoji: String {
        switch self {
        case .anxiety: return "😰"
        case .stress: return "😓"
        case .loneliness: return "💙"
        case .productivity: return "🎯"
        case .general: return "✨"
        }
    }

    var aiGreeting: String {
        switch self {
        case .anxiety:
            return "I hear you - anxiety can feel overwhelming. I'm here to help you find moments of calm. What's been weighing on you lately?"
        case .stress:
            return "Life can pile up fast. I'm here to help you decompress and find some balance. What's been stressing you out most?"
        case .loneliness:
            return "It takes courage to reach out. I'm glad you're here - you don't have to go through things alone. How are you feeling today?"
        case .productivity:
            return "I love that you're investing in yourself! Mental clarity is key to getting things done. What would you like to focus on?"
        case .general:
            return "Hey there! I'm your AI wellness buddy. I'm here to help however you need - whether that's venting, building habits, or just checking in. What's on your mind?"
        }
    }
}

// Extend UserProfile
extension UserProfile {
    var wellnessFocus: WellnessFocus {
        get { WellnessFocus(rawValue: _wellnessFocus ?? "general") ?? .general }
    }
}
```

**Update AppState** (`Core/AppState.swift`):

```swift
enum AuthState: Equatable {
    case unknown
    case unauthenticated
    case onboarding  // New state - after auth, before onboarding complete
    case authenticated
}
```

**New Views** (`Features/Onboarding/`):

```swift
// OnboardingContainerView.swift
struct OnboardingContainerView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var currentStep: OnboardingStep = .quiz
    @State private var selectedFocus: WellnessFocus?

    enum OnboardingStep {
        case quiz
        case aiGreeting
        case complete
    }

    var body: some View {
        VStack {
            // Progress indicator
            ProgressView(value: progressValue)
                .progressViewStyle(.linear)
                .padding()

            switch currentStep {
            case .quiz:
                OnboardingQuizView(
                    selectedFocus: $selectedFocus,
                    onContinue: { moveToAIGreeting() },
                    onSkip: { completeOnboarding(focus: .general) }
                )
            case .aiGreeting:
                OnboardingAIGreetingView(
                    wellnessFocus: selectedFocus ?? .general,
                    onComplete: { completeOnboarding(focus: selectedFocus ?? .general) }
                )
            case .complete:
                EmptyView()
            }
        }
    }

    var progressValue: Double {
        switch currentStep {
        case .quiz: return 0.33
        case .aiGreeting: return 0.66
        case .complete: return 1.0
        }
    }

    func moveToAIGreeting() {
        withAnimation { currentStep = .aiGreeting }
    }

    func completeOnboarding(focus: WellnessFocus) {
        Task {
            try await container.supabaseDataService.updateWellnessFocus(focus)
            try await container.supabaseDataService.markOnboardingComplete()
            container.appState.authState = .authenticated
        }
    }
}

// OnboardingQuizView.swift
struct OnboardingQuizView: View {
    @Binding var selectedFocus: WellnessFocus?
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("What brings you here today?")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("This helps me personalize your experience")
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                ForEach([WellnessFocus.anxiety, .stress, .loneliness, .productivity], id: \.self) { focus in
                    Button {
                        selectedFocus = focus
                    } label: {
                        HStack {
                            Text(focus.emoji)
                            Text(focus.displayTitle)
                                .fontWeight(.medium)
                            Spacer()
                            if selectedFocus == focus {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding()
                        .background(selectedFocus == focus ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedFocus != nil ? Color.accentColor : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(selectedFocus == nil)

                Button("Skip for now", action: onSkip)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
}

// OnboardingAIGreetingView.swift
struct OnboardingAIGreetingView: View {
    let wellnessFocus: WellnessFocus
    let onComplete: () -> Void

    @EnvironmentObject var container: DependencyContainer
    @State private var messages: [OnboardingMessage] = []
    @State private var inputText = ""
    @State private var isTyping = false
    @State private var messageCount = 0

    struct OnboardingMessage: Identifiable {
        let id = UUID()
        let role: String
        let content: String
    }

    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(
                            content: message.content,
                            isUser: message.role == "user"
                        )
                    }

                    if isTyping {
                        TypingIndicator()
                    }
                }
                .padding()
            }

            // Input bar
            HStack {
                TextField("Type a message...", text: $inputText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(inputText.isEmpty || isTyping)
            }
            .padding()

            // Skip button after 2+ messages
            if messageCount >= 2 {
                Button("Get started →", action: onComplete)
                    .fontWeight(.semibold)
                    .padding()
            }
        }
        .onAppear {
            // AI sends first message based on wellness focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                messages.append(OnboardingMessage(role: "assistant", content: wellnessFocus.aiGreeting))
            }
        }
    }

    func sendMessage() {
        let userMessage = inputText
        inputText = ""
        messages.append(OnboardingMessage(role: "user", content: userMessage))
        messageCount += 1
        isTyping = true

        // For onboarding, use a simple response (or call Edge Function)
        Task {
            try await Task.sleep(for: .seconds(1.5))
            let response = getOnboardingResponse(for: userMessage)
            messages.append(OnboardingMessage(role: "assistant", content: response))
            isTyping = false
        }
    }

    func getOnboardingResponse(for input: String) -> String {
        // Simple canned responses for onboarding
        // Could be enhanced with actual AI call
        return "Thank you for sharing that with me. I'm here for you, and together we'll work on building habits that help. Ready to explore the app?"
    }
}
```

**Service Methods** (`Networking/Services/SupabaseDataService.swift`):

```swift
// MARK: - Onboarding

func updateWellnessFocus(_ focus: WellnessFocus) async throws {
    let userId = try await getCurrentUserId()
    try await supabase
        .from("profiles")
        .update(["wellness_focus": focus.rawValue])
        .eq("id", userId)
        .execute()
}

func markOnboardingComplete() async throws {
    let userId = try await getCurrentUserId()
    try await supabase
        .from("profiles")
        .update(["onboarding_completed_at": Date().ISO8601Format()])
        .eq("id", userId)
        .execute()
}
```

**Update App Entry** (`App/MindFriendApp.swift`):

```swift
// In ContentView
@ViewBuilder
var body: some View {
    switch appState.authState {
    case .unknown:
        SplashView()
    case .unauthenticated:
        SignInView()
    case .onboarding:
        OnboardingContainerView()  // New!
    case .authenticated:
        MainTabView()
    }
}

// In session restoration, check onboarding status
func checkOnboardingStatus(profile: UserProfile) {
    if profile.onboardingCompletedAt == nil {
        appState.authState = .onboarding
    } else {
        appState.authState = .authenticated
    }
}
```

### Backend Implementation

**Quest Selection Enhancement** (`supabase/functions/assign-quest/index.ts`):

```typescript
// Use wellness_focus to influence quest selection
async function selectQuestForUser(supabase: SupabaseClient, userId: string) {
  // Get user's wellness focus
  const { data: profile } = await supabase
    .from("profiles")
    .select("wellness_focus")
    .eq("id", userId)
    .single();

  const focus = profile?.wellness_focus || "general";

  // Weight quest templates based on focus
  const questWeights: Record<string, Record<string, number>> = {
    anxiety: {
      breathing: 3,
      meditation: 2,
      grounding: 2,
      journaling: 1,
      walk: 1,
      focus: 0.5,
    },
    stress: {
      breathing: 2,
      meditation: 2,
      walk: 2,
      stretch: 2,
      journaling: 1,
      focus: 1,
    },
    loneliness: { journaling: 3, gratitude: 2, walk: 2, meditation: 1 },
    productivity: {
      focus: 3,
      walk: 2,
      breathing: 1,
      stretch: 1,
      journaling: 1,
    },
    general: {
      breathing: 1,
      meditation: 1,
      grounding: 1,
      journaling: 1,
      walk: 1,
      focus: 1,
    },
  };

  // Weighted random selection based on focus
  // ... implementation
}
```

### API Contract

**Update Profile with Wellness Focus:**

```
PATCH /rest/v1/profiles?id=eq.<user_id>
Authorization: Bearer <jwt>
Content-Type: application/json

{
  "wellness_focus": "anxiety",
  "onboarding_completed_at": "2026-01-15T12:00:00Z"
}

Response: 204 No Content
```

---

## UI/UX

### Flow Diagram

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Sign Up    │ ──▶ │     Quiz     │ ──▶ │ AI Greeting  │ ──▶ │     Home     │
│  (existing)  │     │  (1 screen)  │     │ (2-3 msgs)   │     │  (MainTab)   │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                            │                    │
                            │ Skip               │ Get started
                            ▼                    ▼
                     ┌──────────────────────────────────────┐
                     │               Home                    │
                     └──────────────────────────────────────┘
```

### Quiz Screen

```
┌─────────────────────────────────────┐
│ ━━━━━━━━━━━░░░░░░░░░░░░░░░░░░░░░  │  Progress: 33%
├─────────────────────────────────────┤
│                                     │
│     What brings you here today?     │
│                                     │
│   This helps me personalize your    │
│            experience               │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 😰  Managing anxiety      ○ │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │ 😓  Reducing stress       ● │   │  ← Selected
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │ 💙  Feeling less lonely   ○ │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │ 🎯  Staying productive    ○ │   │
│  └─────────────────────────────┘   │
│                                     │
│         ┌───────────────┐          │
│         │   Continue    │          │
│         └───────────────┘          │
│                                     │
│          Skip for now              │
│                                     │
└─────────────────────────────────────┘
```

### AI Greeting Screen

```
┌─────────────────────────────────────┐
│ ━━━━━━━━━━━━━━━━━━━━━░░░░░░░░░░░  │  Progress: 66%
├─────────────────────────────────────┤
│                                     │
│  ┌───────────────────────────────┐ │
│  │ Life can pile up fast. I'm   │ │
│  │ here to help you decompress  │ │
│  │ and find some balance.       │ │
│  │                              │ │
│  │ What's been stressing you    │ │
│  │ out most?                    │ │
│  └───────────────────────────────┘ │
│                                     │
│                  ┌───────────────┐  │
│                  │ Work has been │  │
│                  │ really busy   │  │
│                  │ lately...     │  │
│                  └───────────────┘  │
│                                     │
│  ┌───────────────────────────────┐ │
│  │ I hear you. When work piles  │ │
│  │ up, it's easy to feel        │ │
│  │ overwhelmed. Let's work on   │ │
│  │ finding small moments of     │ │
│  │ calm together. Ready to      │ │
│  │ explore?                     │ │
│  └───────────────────────────────┘ │
│                                     │
│  ┌─────────────────────────────┐   │
│  │     Type a message...    ↑  │   │
│  └─────────────────────────────┘   │
│                                     │
│          Get started →             │
│                                     │
└─────────────────────────────────────┘
```

---

## Verification

### Manual Testing

1. **Fresh Install Flow:**
   - Delete app, reinstall
   - Sign up with new account
   - Verify quiz appears after signup
   - Select focus, verify AI greeting matches
   - Complete onboarding, verify home screen

2. **Skip Flow:**
   - Sign up, skip quiz
   - Verify default wellness_focus = 'general'
   - Verify home screen appears

3. **Returning User:**
   - Sign out, sign back in
   - Verify onboarding does NOT appear (already completed)

4. **Quest Personalization:**
   - Complete onboarding with "anxiety" focus
   - Check quest assignments over several days
   - Verify breathing/meditation quests appear more often

### Edge Cases

- Network failure during quiz submission
- App killed during onboarding flow
- Profile already has wellness_focus from previous incomplete onboarding

---

## Dependencies

- Authentication flow complete
- Profiles table exists
- MainTabView/Home screen exists

---

## Risks & Mitigations

| Risk                           | Likelihood | Impact | Mitigation                                      |
| ------------------------------ | ---------- | ------ | ----------------------------------------------- |
| Users skip everything          | Medium     | Medium | Make quiz inviting, single screen, < 10 seconds |
| AI greeting feels generic      | Medium     | High   | Carefully craft focus-specific greetings        |
| Adds friction to signup        | Medium     | Medium | Keep entire flow under 60 seconds               |
| Quiz selection doesn't persist | Low        | High   | Verify database write before proceeding         |

---

## Implementation Estimate

| Task                      | Effort       |
| ------------------------- | ------------ |
| Database migration        | 30 min       |
| iOS Models + Enums        | 1 hour       |
| OnboardingContainerView   | 2 hours      |
| OnboardingQuizView        | 2 hours      |
| OnboardingAIGreetingView  | 3 hours      |
| Service methods           | 1 hour       |
| App entry point changes   | 1 hour       |
| Quest weighting (backend) | 2 hours      |
| Testing                   | 2 hours      |
| **Total**                 | **14 hours** |
