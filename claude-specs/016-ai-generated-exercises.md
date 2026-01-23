# F013: AI-Generated Personalized Exercises

## Overview

### Summary

Dynamic exercise generation system that creates personalized breathing, meditation, grounding, and journaling exercises tailored to user's current emotional state, preferences, and wellness goals.

### Business Value

- Infinite content variety preventing staleness
- Deep personalization driving engagement
- Premium differentiator vs static exercise libraries

### User Benefit

- Exercises that feel uniquely crafted for their situation
- Fresh content that evolves with their journey
- Higher effectiveness through personalization

### Dependencies

- F004: Companion Memory Enhancement (for personalization context)
- F011: Voice-First Companion (for voice-guided exercises)

---

## Requirements

### Functional Requirements

| ID     | Requirement                                                      | Priority    |
| ------ | ---------------------------------------------------------------- | ----------- |
| FR-001 | Generate breathing exercises with custom patterns and durations  | Must Have   |
| FR-002 | Generate meditation scripts with personalized themes and imagery | Must Have   |
| FR-003 | Generate grounding exercises based on current environment        | Must Have   |
| FR-004 | Generate journaling prompts based on emotional context           | Must Have   |
| FR-005 | Generate movement/stretching routines with instructions          | Should Have |
| FR-006 | Adapt exercise difficulty based on user capacity                 | Must Have   |
| FR-007 | Incorporate user's preferred themes, imagery, and metaphors      | Should Have |
| FR-008 | Save generated exercises for reuse                               | Should Have |
| FR-009 | Voice narration of generated exercises                           | Should Have |
| FR-010 | Rate and provide feedback on generated exercises                 | Must Have   |

### Non-Functional Requirements

| ID      | Requirement                    | Target                                   |
| ------- | ------------------------------ | ---------------------------------------- |
| NFR-001 | Exercise generation latency    | < 3s for short, < 8s for full meditation |
| NFR-002 | Generation quality consistency | 4+ star average rating                   |
| NFR-003 | Streaming for long content     | Progressive display                      |
| NFR-004 | Offline saved exercises        | Full playback without network            |

### Acceptance Criteria

```gherkin
Feature: AI-Generated Exercises

Scenario: Generate breathing exercise for anxiety
  Given user reports feeling anxious
  When user requests a breathing exercise
  Then a calming breathing pattern should be generated
  And pattern should include slower exhales than inhales
  And duration should match user's preferred exercise length
  And exercise should reference user's preferred calming imagery

Scenario: Generate personalized meditation
  Given user has preferences for nature imagery
  And user's current mood is stressed
  When user requests a meditation
  Then meditation script should be generated
  And script should incorporate nature themes
  And script should address stress relief
  And duration should be 5-15 minutes based on preferences

Scenario: Save and reuse generated exercise
  Given user just completed a generated breathing exercise
  And user rated it 5 stars
  When user taps "Save to Library"
  Then exercise should be saved to personal library
  And exercise should be available offline
  And exercise should appear in "My Exercises" section

Scenario: Environment-aware grounding
  Given user is at home (based on location/time)
  When user requests a grounding exercise
  Then exercise should reference home environment
  And instructions should use familiar indoor objects
  And exercise should adapt to seated vs standing
```

---

## Technical Design

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iOS Application                       │
├─────────────────────────────────────────────────────────┤
│  ExerciseGenerationService                              │
│  ├── Context gathering (mood, time, environment)        │
│  ├── Preference loading                                 │
│  ├── Streaming response handling                        │
│  └── Exercise caching                                   │
├─────────────────────────────────────────────────────────┤
│  GeneratedExerciseViews                                 │
│  ├── BreathingExercisePlayer                            │
│  ├── MeditationPlayer (with TTS)                        │
│  ├── GroundingExerciseView                              │
│  └── JournalingPromptView                               │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Supabase Edge Functions                     │
├─────────────────────────────────────────────────────────┤
│  generate-exercise                                      │
│  ├── Context enrichment                                 │
│  ├── Prompt construction                                │
│  ├── AI generation (streaming)                          │
│  └── Response parsing                                   │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                  PostgreSQL Tables                       │
├─────────────────────────────────────────────────────────┤
│  generated_exercises │ exercise_preferences │ feedback  │
└─────────────────────────────────────────────────────────┘
```

### Data Models

#### Database Schema

```sql
-- User exercise preferences
CREATE TABLE exercise_generation_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Duration preferences
    preferred_breathing_duration INTEGER DEFAULT 300, -- seconds
    preferred_meditation_duration INTEGER DEFAULT 600,
    preferred_grounding_duration INTEGER DEFAULT 180,

    -- Content preferences
    preferred_imagery TEXT[] DEFAULT ARRAY['nature', 'water'],
    preferred_themes TEXT[] DEFAULT ARRAY['calm', 'peace'],
    avoided_themes TEXT[] DEFAULT ARRAY[],
    voice_preference TEXT DEFAULT 'warm', -- 'warm', 'calm', 'energetic'

    -- Style preferences
    guidance_level TEXT DEFAULT 'moderate', -- 'minimal', 'moderate', 'detailed'
    include_affirmations BOOLEAN DEFAULT true,
    include_body_scan BOOLEAN DEFAULT true,
    preferred_background_sounds TEXT[] DEFAULT ARRAY['ambient'],

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Generated exercises (saved)
CREATE TABLE generated_exercises (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    exercise_type TEXT NOT NULL CHECK (exercise_type IN (
        'breathing', 'meditation', 'grounding', 'journaling', 'movement'
    )),

    -- Content
    title TEXT NOT NULL,
    description TEXT,
    content JSONB NOT NULL, -- Type-specific structure
    duration_seconds INTEGER NOT NULL,

    -- Generation context
    generation_prompt TEXT,
    emotional_context TEXT,
    generation_model TEXT,

    -- Metadata
    is_favorite BOOLEAN NOT NULL DEFAULT false,
    use_count INTEGER NOT NULL DEFAULT 0,
    last_used_at TIMESTAMPTZ,
    avg_rating DECIMAL(3,2),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Generation history (including unsaved)
CREATE TABLE exercise_generation_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    exercise_type TEXT NOT NULL,
    emotional_context TEXT,
    duration_seconds INTEGER,
    was_completed BOOLEAN NOT NULL DEFAULT false,
    was_saved BOOLEAN NOT NULL DEFAULT false,
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    feedback TEXT,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_exercise_gen_prefs_user ON exercise_generation_preferences(user_id);
CREATE INDEX idx_generated_exercises_user ON generated_exercises(user_id);
CREATE INDEX idx_generated_exercises_type ON generated_exercises(user_id, exercise_type);
CREATE INDEX idx_generated_exercises_fav ON generated_exercises(user_id, is_favorite);
CREATE INDEX idx_exercise_gen_log_user ON exercise_generation_log(user_id, generated_at DESC);

-- RLS Policies
ALTER TABLE exercise_generation_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE generated_exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE exercise_generation_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own preferences" ON exercise_generation_preferences
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own generated exercises" ON generated_exercises
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own generation log" ON exercise_generation_log
    FOR ALL USING (auth.uid() = user_id);
```

#### Swift Models

```swift
// MARK: - Generated Exercise Models

struct ExerciseGenerationPreferences: Codable {
    let id: UUID
    let userId: UUID
    var preferredBreathingDuration: Int
    var preferredMeditationDuration: Int
    var preferredGroundingDuration: Int
    var preferredImagery: [String]
    var preferredThemes: [String]
    var avoidedThemes: [String]
    var voicePreference: VoicePreference
    var guidanceLevel: GuidanceLevel
    var includeAffirmations: Bool
    var includeBodyScan: Bool
    var preferredBackgroundSounds: [String]
}

enum VoicePreference: String, Codable, CaseIterable {
    case warm
    case calm
    case energetic

    var displayName: String {
        rawValue.capitalized
    }
}

enum GuidanceLevel: String, Codable, CaseIterable {
    case minimal
    case moderate
    case detailed

    var displayName: String {
        switch self {
        case .minimal: return "Minimal (quiet spaces)"
        case .moderate: return "Moderate (balanced)"
        case .detailed: return "Detailed (step-by-step)"
        }
    }
}

struct GeneratedExercise: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let exerciseType: GeneratedExerciseType
    let title: String
    let description: String?
    let content: ExerciseContent
    let durationSeconds: Int
    let generationPrompt: String?
    let emotionalContext: String?
    var isFavorite: Bool
    var useCount: Int
    var lastUsedAt: Date?
    var avgRating: Double?
    let createdAt: Date

    var durationFormatted: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes) min"
        }
        return "\(seconds)s"
    }
}

enum GeneratedExerciseType: String, Codable, CaseIterable {
    case breathing
    case meditation
    case grounding
    case journaling
    case movement

    var iconName: String {
        switch self {
        case .breathing: return "wind"
        case .meditation: return "brain.head.profile"
        case .grounding: return "leaf.fill"
        case .journaling: return "pencil.and.outline"
        case .movement: return "figure.walk"
        }
    }
}

// Type-specific content structures
enum ExerciseContent: Codable {
    case breathing(BreathingContent)
    case meditation(MeditationContent)
    case grounding(GroundingContent)
    case journaling(JournalingContent)
    case movement(MovementContent)
}

struct BreathingContent: Codable {
    let pattern: BreathingPattern
    let cycles: Int
    let introText: String
    let holdText: String?
    let outroText: String
    let backgroundSound: String?
}

struct BreathingPattern: Codable {
    let inhaleSeconds: Double
    let holdInSeconds: Double
    let exhaleSeconds: Double
    let holdOutSeconds: Double
    let name: String

    var cycleSeconds: Double {
        inhaleSeconds + holdInSeconds + exhaleSeconds + holdOutSeconds
    }
}

struct MeditationContent: Codable {
    let script: [MeditationSegment]
    let totalWords: Int
    let estimatedDuration: Int

    struct MeditationSegment: Codable, Identifiable {
        let id: UUID
        let text: String
        let pauseAfterSeconds: Double
        let type: SegmentType

        enum SegmentType: String, Codable {
            case intro
            case breathingGuide
            case bodyAwareness
            case visualization
            case affirmation
            case closing
        }
    }
}

struct GroundingContent: Codable {
    let technique: String // "5-4-3-2-1", "body_scan", "object_focus"
    let steps: [GroundingStep]
    let environment: String // "indoor", "outdoor", "any"

    struct GroundingStep: Codable, Identifiable {
        let id: UUID
        let instruction: String
        let sense: String? // "sight", "touch", "hearing", "smell", "taste"
        let durationSeconds: Int
    }
}

struct JournalingContent: Codable {
    let prompts: [JournalPrompt]
    let theme: String
    let reflectionQuestions: [String]

    struct JournalPrompt: Codable, Identifiable {
        let id: UUID
        let prompt: String
        let hint: String?
        let category: String
    }
}

struct MovementContent: Codable {
    let movements: [MovementStep]
    let intensity: String // "gentle", "moderate", "active"
    let focusAreas: [String]

    struct MovementStep: Codable, Identifiable {
        let id: UUID
        let name: String
        let instruction: String
        let durationSeconds: Int
        let repetitions: Int?
        let imageHint: String?
    }
}

// Generation request
struct ExerciseGenerationRequest: Codable {
    let exerciseType: GeneratedExerciseType
    let currentMood: String?
    let currentEnergy: Int? // 1-5
    let specificFocus: String?
    let durationPreference: Int? // seconds
    let environmentContext: String?
}

// Generation response (streaming)
struct ExerciseGenerationResponse: Codable {
    let exercise: GeneratedExercise
    let generationTime: Double
    let tokensUsed: Int
}
```

### API Contracts

#### Generate Exercise

```
POST /functions/v1/generate-exercise

Request:
{
  "exerciseType": "breathing",
  "currentMood": "anxious",
  "currentEnergy": 2,
  "specificFocus": "calming",
  "durationPreference": 300,
  "environmentContext": "home_evening"
}

Response 200 (streaming):
{
  "exercise": {
    "id": "temp-uuid",
    "exerciseType": "breathing",
    "title": "Ocean Calm Breathing",
    "description": "A gentle breathing exercise inspired by ocean waves",
    "content": {
      "breathing": {
        "pattern": {
          "inhaleSeconds": 4,
          "holdInSeconds": 2,
          "exhaleSeconds": 6,
          "holdOutSeconds": 2,
          "name": "Extended Exhale"
        },
        "cycles": 12,
        "introText": "Find a comfortable position and let your shoulders relax...",
        "outroText": "As you return to natural breathing, carry this calm with you..."
      }
    },
    "durationSeconds": 300
  }
}
```

#### Save Generated Exercise

```
POST /rest/v1/generated_exercises

Request:
{
  "exercise_type": "breathing",
  "title": "Ocean Calm Breathing",
  "content": {...},
  "duration_seconds": 300,
  "emotional_context": "anxious"
}

Response 201:
{
  "id": "uuid",
  "created_at": "2024-01-15T10:30:00Z"
}
```

#### Rate Generated Exercise

```
POST /rest/v1/exercise_generation_log

Request:
{
  "exercise_type": "breathing",
  "emotional_context": "anxious",
  "duration_seconds": 300,
  "was_completed": true,
  "was_saved": true,
  "rating": 5,
  "feedback": "Very calming, loved the ocean imagery"
}
```

---

## Implementation Details

### Step-by-Step Approach

1. **Preferences Setup**
   - Preferences onboarding flow
   - Theme and imagery selection
   - Duration preferences per type
   - Voice/guidance preferences

2. **Generation Engine**
   - Context gathering (mood, time, history)
   - Prompt construction with preferences
   - Streaming response handling
   - Content parsing and validation

3. **Exercise Players**
   - Breathing: Animated circle + haptics
   - Meditation: TTS + background audio
   - Grounding: Step-by-step with timers
   - Journaling: Text entry with prompts
   - Movement: Instruction cards

4. **Personalization Loop**
   - Track ratings and feedback
   - Adjust generation parameters
   - Learn preferred patterns
   - Avoid disliked elements

5. **Saved Library**
   - Save exercises to personal library
   - Offline caching
   - Favorite management
   - Usage tracking

### File Structure

```
apps/ios/MindFriendApp/
├── Features/
│   └── GeneratedExercises/
│       ├── ExerciseGenerationService.swift
│       ├── ExerciseContentParser.swift
│       ├── Views/
│       │   ├── GenerateExerciseView.swift
│       │   ├── SavedExercisesView.swift
│       │   ├── PreferencesView.swift
│       │   └── Players/
│       │       ├── GeneratedBreathingPlayer.swift
│       │       ├── GeneratedMeditationPlayer.swift
│       │       ├── GroundingExerciseView.swift
│       │       ├── JournalingPromptView.swift
│       │       └── MovementGuideView.swift
│       └── Components/
│           ├── ExerciseTypeSelector.swift
│           ├── MoodContextInput.swift
│           └── GenerationProgress.swift
│
supabase/
├── functions/
│   └── generate-exercise/
│       ├── index.ts
│       ├── prompts/
│       │   ├── breathing.ts
│       │   ├── meditation.ts
│       │   ├── grounding.ts
│       │   ├── journaling.ts
│       │   └── movement.ts
│       └── parsers/
│           └── content-parser.ts
├── migrations/
│   └── YYYYMMDD_generated_exercises.sql
```

### Key Algorithms

#### Exercise Generation Prompt Construction (TypeScript)

```typescript
interface GenerationContext {
  userId: string;
  exerciseType: string;
  currentMood?: string;
  currentEnergy?: number;
  specificFocus?: string;
  durationSeconds: number;
  environmentContext?: string;
  preferences: ExerciseGenerationPreferences;
  recentExercises: string[]; // Titles to avoid repetition
}

function buildBreathingPrompt(context: GenerationContext): string {
  const { preferences, currentMood, durationSeconds } = context;

  const moodGuidance = getMoodGuidance(currentMood);
  const cycleCount = Math.floor(durationSeconds / 15); // ~15s per cycle average

  return `You are an expert breathwork instructor creating a personalized breathing exercise.

USER CONTEXT:
- Current emotional state: ${currentMood || "not specified"}
- Energy level: ${context.currentEnergy || "not specified"}/5
- Environment: ${context.environmentContext || "not specified"}
- Preferred imagery: ${preferences.preferredImagery.join(", ")}
- Guidance level: ${preferences.guidanceLevel}

EXERCISE REQUIREMENTS:
- Duration: approximately ${durationSeconds} seconds (${cycleCount} cycles)
- Focus: ${context.specificFocus || moodGuidance.focus}

${moodGuidance.instructions}

AVOID these recently used themes: ${context.recentExercises.join(", ")}

Generate a breathing exercise in this exact JSON format:
{
  "title": "Creative descriptive title (3-5 words)",
  "description": "One sentence describing the exercise",
  "pattern": {
    "inhaleSeconds": number (2-6),
    "holdInSeconds": number (0-4),
    "exhaleSeconds": number (3-8),
    "holdOutSeconds": number (0-3),
    "name": "Pattern name (e.g., 'Box Breathing', 'Extended Exhale')"
  },
  "cycles": ${cycleCount},
  "introText": "Opening guidance (2-3 sentences, incorporate ${preferences.preferredImagery[0]} imagery)",
  "holdText": "Brief guidance during holds (optional, 1 sentence)",
  "outroText": "Closing message (1-2 sentences)"
}

Requirements:
- For anxiety/stress: Use extended exhales (exhale > inhale)
- For low energy: Use energizing patterns (equal inhale/exhale, shorter holds)
- Incorporate the user's preferred imagery naturally
- Keep text concise for ${preferences.guidanceLevel} guidance level
- Total cycle time should roughly equal ${durationSeconds / cycleCount} seconds`;
}

function buildMeditationPrompt(context: GenerationContext): string {
  const { preferences, currentMood, durationSeconds } = context;

  const wordCount = Math.floor(durationSeconds / 4); // ~4 seconds per word when spoken slowly

  return `You are a meditation guide creating a personalized meditation script.

USER CONTEXT:
- Current emotional state: ${currentMood || "seeking peace"}
- Preferred imagery: ${preferences.preferredImagery.join(", ")}
- Preferred themes: ${preferences.preferredThemes.join(", ")}
- Themes to AVOID: ${preferences.avoidedThemes.join(", ") || "none specified"}
- Include affirmations: ${preferences.includeAffirmations}
- Include body scan: ${preferences.includeBodyScan}
- Guidance level: ${preferences.guidanceLevel}

EXERCISE REQUIREMENTS:
- Total duration: ${durationSeconds} seconds (~${Math.floor(durationSeconds / 60)} minutes)
- Target word count: approximately ${wordCount} words
- Voice style: ${preferences.voicePreference}

Generate a meditation script in this JSON format:
{
  "title": "Creative meditation title",
  "description": "Brief description of this meditation",
  "script": [
    {
      "type": "intro",
      "text": "Opening text to settle into meditation...",
      "pauseAfterSeconds": 3
    },
    {
      "type": "breathingGuide",
      "text": "Brief breathing instruction...",
      "pauseAfterSeconds": 10
    },
    ${
      preferences.includeBodyScan
        ? `{
      "type": "bodyAwareness",
      "text": "Body scan or awareness section...",
      "pauseAfterSeconds": 5
    },`
        : ""
    }
    {
      "type": "visualization",
      "text": "Main visualization using ${preferences.preferredImagery[0]} imagery...",
      "pauseAfterSeconds": 8
    },
    ${
      preferences.includeAffirmations
        ? `{
      "type": "affirmation",
      "text": "Positive affirmation relevant to ${currentMood || "wellbeing"}...",
      "pauseAfterSeconds": 5
    },`
        : ""
    }
    {
      "type": "closing",
      "text": "Gentle return to awareness...",
      "pauseAfterSeconds": 3
    }
  ],
  "totalWords": number
}

Requirements:
- Use second person ("you")
- Write in a ${preferences.voicePreference} tone
- Include natural pauses indicated by pauseAfterSeconds
- Avoid clichés and overly spiritual language
- Make imagery specific and sensory
- Address the user's current emotional state naturally`;
}

function getMoodGuidance(mood?: string): {
  focus: string;
  instructions: string;
} {
  const moodMap: Record<string, { focus: string; instructions: string }> = {
    anxious: {
      focus: "calming and grounding",
      instructions:
        "Focus on extended exhales (longer exhale than inhale). Use imagery of settling, releasing, and safety.",
    },
    stressed: {
      focus: "tension release",
      instructions:
        "Include subtle body awareness. Use imagery of letting go and creating space.",
    },
    sad: {
      focus: "gentle comfort",
      instructions:
        "Be compassionate and warm. Avoid toxic positivity. Acknowledge feelings while offering gentle support.",
    },
    angry: {
      focus: "cooling and releasing",
      instructions:
        "Use cooling imagery (water, breeze). Include physical tension release.",
    },
    tired: {
      focus: "gentle restoration",
      instructions:
        "Keep energy low but nurturing. Avoid anything too stimulating.",
    },
    energetic: {
      focus: "channeling energy",
      instructions:
        "Can use more dynamic patterns. Focus on balance and intentional energy use.",
    },
  };

  return (
    moodMap[mood?.toLowerCase() || ""] || {
      focus: "general wellbeing",
      instructions: "Create a balanced, calming exercise suitable for anyone.",
    }
  );
}
```

#### Breathing Exercise Player (SwiftUI)

```swift
struct GeneratedBreathingPlayer: View {
    let exercise: GeneratedExercise
    @StateObject private var controller = BreathingController()
    @State private var showingCompletion = false

    var breathingContent: BreathingContent? {
        if case .breathing(let content) = exercise.content {
            return content
        }
        return nil
    }

    var body: some View {
        ZStack {
            // Background gradient based on phase
            LinearGradient(
                colors: controller.currentPhaseColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: controller.phase)

            VStack(spacing: 40) {
                // Phase indicator
                Text(controller.phaseText)
                    .font(.title2.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))

                // Animated breathing circle
                BreathingCircle(
                    scale: controller.circleScale,
                    phase: controller.phase
                )
                .frame(width: 200, height: 200)

                // Timer
                Text(controller.timeRemaining.formatted)
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()

                // Cycle counter
                Text("Cycle \(controller.currentCycle) of \(breathingContent?.cycles ?? 0)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .onAppear {
            guard let content = breathingContent else { return }
            controller.start(with: content.pattern, cycles: content.cycles)
        }
        .onChange(of: controller.isComplete) { complete in
            if complete {
                showingCompletion = true
            }
        }
        .sheet(isPresented: $showingCompletion) {
            ExerciseCompletionView(
                exercise: exercise,
                onSave: saveExercise,
                onRate: rateExercise
            )
        }
    }

    private func saveExercise() async {
        // Save to generated_exercises table
    }

    private func rateExercise(_ rating: Int, feedback: String?) async {
        // Log to exercise_generation_log
    }
}

class BreathingController: ObservableObject {
    enum Phase {
        case inhale, holdIn, exhale, holdOut

        var text: String {
            switch self {
            case .inhale: return "Breathe In"
            case .holdIn: return "Hold"
            case .exhale: return "Breathe Out"
            case .holdOut: return "Pause"
            }
        }
    }

    @Published var phase: Phase = .inhale
    @Published var circleScale: CGFloat = 0.4
    @Published var timeRemaining: TimeInterval = 0
    @Published var currentCycle: Int = 1
    @Published var isComplete: Bool = false

    private var pattern: BreathingPattern?
    private var totalCycles: Int = 0
    private var timer: Timer?

    var phaseText: String { phase.text }

    var currentPhaseColors: [Color] {
        switch phase {
        case .inhale: return [.blue.opacity(0.6), .cyan.opacity(0.4)]
        case .holdIn: return [.purple.opacity(0.5), .blue.opacity(0.4)]
        case .exhale: return [.green.opacity(0.5), .teal.opacity(0.4)]
        case .holdOut: return [.indigo.opacity(0.5), .purple.opacity(0.4)]
        }
    }

    func start(with pattern: BreathingPattern, cycles: Int) {
        self.pattern = pattern
        self.totalCycles = cycles
        self.currentCycle = 1
        beginPhase(.inhale)
    }

    private func beginPhase(_ phase: Phase) {
        self.phase = phase

        guard let pattern = pattern else { return }

        let duration: Double
        let targetScale: CGFloat

        switch phase {
        case .inhale:
            duration = pattern.inhaleSeconds
            targetScale = 1.0
            triggerHaptic(.inhale)
        case .holdIn:
            duration = pattern.holdInSeconds
            targetScale = 1.0
        case .exhale:
            duration = pattern.exhaleSeconds
            targetScale = 0.4
            triggerHaptic(.exhale)
        case .holdOut:
            duration = pattern.holdOutSeconds
            targetScale = 0.4
        }

        timeRemaining = duration

        withAnimation(.easeInOut(duration: duration)) {
            circleScale = targetScale
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.transitionToNextPhase()
        }
    }

    private func tick() {
        timeRemaining = max(0, timeRemaining - 0.1)
    }

    private func transitionToNextPhase() {
        guard let pattern = pattern else { return }

        switch phase {
        case .inhale:
            if pattern.holdInSeconds > 0 {
                beginPhase(.holdIn)
            } else {
                beginPhase(.exhale)
            }
        case .holdIn:
            beginPhase(.exhale)
        case .exhale:
            if pattern.holdOutSeconds > 0 {
                beginPhase(.holdOut)
            } else {
                completeCycle()
            }
        case .holdOut:
            completeCycle()
        }
    }

    private func completeCycle() {
        if currentCycle >= totalCycles {
            isComplete = true
            timer?.invalidate()
        } else {
            currentCycle += 1
            beginPhase(.inhale)
        }
    }

    private func triggerHaptic(_ type: Phase) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
```

---

## Dependencies

### Internal Dependencies

- **F004 Companion Memory**: For personalization context and preferences
- **F011 Voice-First**: For TTS narration of meditations
- **Exercise library**: For reference patterns and content style

### External Dependencies

- AI provider for content generation
- AVSpeechSynthesizer or third-party TTS for meditation narration

### Infrastructure Requirements

- Streaming response support from Edge Functions
- Audio synthesis for meditation playback

---

## Edge Cases & Error Handling

| Scenario                       | Handling                                           |
| ------------------------------ | -------------------------------------------------- |
| Generation fails               | Retry once; offer curated fallback exercise        |
| Invalid JSON response          | Parse error recovery; request regeneration         |
| Response too long              | Truncate gracefully; adjust prompt parameters      |
| User cancels during generation | Stop stream; discard partial content               |
| Offensive content generated    | Content filter; report and regenerate              |
| Same exercise regenerated      | Check recent history; add diversity prompt         |
| No preferences set             | Use sensible defaults; prompt to set preferences   |
| Offline generation request     | Explain network requirement; offer saved exercises |

---

## Testing Requirements

### Unit Tests

```swift
// ExerciseGenerationServiceTests.swift

func testBreathingPatternValidation() {
    let pattern = BreathingPattern(
        inhaleSeconds: 4,
        holdInSeconds: 4,
        exhaleSeconds: 4,
        holdOutSeconds: 4,
        name: "Box Breathing"
    )

    XCTAssertEqual(pattern.cycleSeconds, 16)
}

func testMeditationWordCountEstimate() {
    let content = MeditationContent(
        script: MockData.meditationScript,
        totalWords: 150,
        estimatedDuration: 600
    )

    // ~4 seconds per word
    XCTAssertEqual(content.estimatedDuration, content.totalWords * 4)
}

func testExerciseContentParsing() throws {
    let json = MockData.breathingExerciseJSON
    let content = try ExerciseContentParser.parse(json, type: .breathing)

    if case .breathing(let breathing) = content {
        XCTAssertNotNil(breathing.pattern)
        XCTAssertGreaterThan(breathing.cycles, 0)
    } else {
        XCTFail("Expected breathing content")
    }
}

func testPreferenceApplication() {
    let preferences = MockData.exercisePreferences(imagery: ["ocean", "beach"])
    let prompt = BreathingPromptBuilder.build(
        context: MockData.generationContext,
        preferences: preferences
    )

    XCTAssertTrue(prompt.contains("ocean"))
    XCTAssertTrue(prompt.contains("beach"))
}
```

### Integration Tests

```typescript
// supabase/functions/generate-exercise/test.ts

Deno.test("generates valid breathing exercise", async () => {
  const userId = await createTestUser();
  await setExercisePreferences(userId, { preferredImagery: ["nature"] });

  const result = await invokeFunction(
    "generate-exercise",
    {
      exerciseType: "breathing",
      currentMood: "anxious",
      durationPreference: 300,
    },
    userId,
  );

  assertExists(result.exercise);
  assertEquals(result.exercise.exerciseType, "breathing");
  assertExists(result.exercise.content.pattern);
  assert(result.exercise.durationSeconds >= 240);
  assert(result.exercise.durationSeconds <= 360);
});

Deno.test("respects avoided themes", async () => {
  const userId = await createTestUser();
  await setExercisePreferences(userId, {
    avoidedThemes: ["ocean", "water"],
  });

  const result = await invokeFunction(
    "generate-exercise",
    {
      exerciseType: "meditation",
      durationPreference: 300,
    },
    userId,
  );

  const scriptText = result.exercise.content.script
    .map((s) => s.text)
    .join(" ")
    .toLowerCase();

  assert(!scriptText.includes("ocean"));
  assert(!scriptText.includes("water"));
});

Deno.test("meditation duration matches request", async () => {
  const userId = await createTestUser();

  const result = await invokeFunction(
    "generate-exercise",
    {
      exerciseType: "meditation",
      durationPreference: 600, // 10 minutes
    },
    userId,
  );

  // Should be within 20% of requested
  assert(result.exercise.durationSeconds >= 480);
  assert(result.exercise.durationSeconds <= 720);
});
```

### UI Tests

```swift
func testBreathingPlayerPhaseTransitions() async {
    let pattern = BreathingPattern(
        inhaleSeconds: 2, holdInSeconds: 1,
        exhaleSeconds: 2, holdOutSeconds: 1,
        name: "Test"
    )

    let controller = BreathingController()
    controller.start(with: pattern, cycles: 1)

    XCTAssertEqual(controller.phase, .inhale)

    try await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s
    XCTAssertEqual(controller.phase, .holdIn)

    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s more
    XCTAssertEqual(controller.phase, .exhale)
}
```
