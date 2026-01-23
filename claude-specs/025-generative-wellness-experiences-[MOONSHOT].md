# F026: Generative Wellness Experiences

## Overview

### Summary

AI-powered dynamic content generation system that creates unique, personalized wellness experiences on-demand—including custom meditations, personalized journaling prompts, adaptive story-based exercises, and creative therapeutic activities tailored to each user's current state and preferences.

### Business Value

- Unlimited fresh content without manual creation costs
- Highly personalized experiences drive premium conversion
- Eliminates content fatigue that causes churn
- Positions MindFriend at cutting edge of AI wellness innovation

### User Benefit

- Every experience feels fresh and personally crafted
- Content that adapts to their current mood and needs
- Creative therapeutic activities beyond standard exercises
- Sense of having a truly personalized wellness companion

### Dependencies

- F004 (Companion Memory Enhancement) - Personalization context
- F013 (AI-Generated Exercises) - Foundation for generation
- F003 (Predictive Mood Intelligence) - Current state awareness
- Core Exercise System - Delivery infrastructure

---

## Requirements

### Functional Requirements

| ID        | Requirement                                         | Priority |
| --------- | --------------------------------------------------- | -------- |
| FR-026-01 | Generate personalized guided meditations with voice | P0       |
| FR-026-02 | Create contextual journaling prompts                | P0       |
| FR-026-03 | Produce adaptive breathing patterns                 | P0       |
| FR-026-04 | Generate story-based therapeutic experiences        | P1       |
| FR-026-05 | Create personalized affirmations                    | P1       |
| FR-026-06 | Generate creative visualization scripts             | P1       |
| FR-026-07 | Produce mood-specific music/soundscapes             | P2       |
| FR-026-08 | Create gratitude prompt sequences                   | P2       |
| FR-026-09 | Generate relationship reflection exercises          | P2       |
| FR-026-10 | Allow users to save favorite generated content      | P0       |

### Non-Functional Requirements

| ID         | Requirement                       | Target                       |
| ---------- | --------------------------------- | ---------------------------- |
| NFR-026-01 | Content generation time (text)    | < 3 seconds                  |
| NFR-026-02 | Voice synthesis time (per minute) | < 5 seconds                  |
| NFR-026-03 | Generation quality rating         | > 4.0/5.0                    |
| NFR-026-04 | Content safety compliance         | 100%                         |
| NFR-026-05 | Personalization accuracy          | > 90%                        |
| NFR-026-06 | Generated content diversity       | No duplicates within 30 days |

### Acceptance Criteria (Gherkin)

```gherkin
Feature: Generative Wellness Experiences

  Scenario: User requests personalized meditation
    Given the user's current mood is anxious
    And they have 10 minutes available
    When they request a custom meditation
    Then the system generates a unique meditation script
    And the script addresses anxiety specifically
    And includes personalized elements (name, preferences)
    And is synthesized into natural voice audio

  Scenario: Contextual journaling prompt generation
    Given the user has had a challenging day at work
    And their recent entries mention workplace stress
    When they open journaling
    Then they see prompts relevant to work challenges
    And prompts build on their previous reflections
    And offer new perspective angles

  Scenario: Story-based therapeutic experience
    Given the user selects "Guided Story" exercise
    And they indicate feeling stuck in life
    When the story is generated
    Then it features a protagonist facing similar challenges
    And includes therapeutic metaphors for their situation
    And ends with subtle insights for their real situation

  Scenario: User saves generated content
    Given the user completes a generated meditation
    And they found it helpful
    When they tap "Save to Favorites"
    Then the generated content is preserved
    And accessible in their saved content library
    And marked with the context it was generated for
```

---

## Technical Design

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                Generative Wellness Experience                    │
├─────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                  Content Orchestrator                       │ │
│  │  • Request Analysis  • Context Assembly  • Quality Control │ │
│  └───────────────────────────┬────────────────────────────────┘ │
├──────────────────────────────┼──────────────────────────────────┤
│                              │                                  │
│  ┌───────────────────────────▼───────────────────────────────┐  │
│  │                   Generation Engines                       │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐ │  │
│  │  │ Meditation   │ │ Story        │ │ Prompt             │ │  │
│  │  │ Generator    │ │ Generator    │ │ Generator          │ │  │
│  │  └──────────────┘ └──────────────┘ └────────────────────┘ │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐ │  │
│  │  │ Affirmation  │ │ Visualization│ │ Breathing          │ │  │
│  │  │ Generator    │ │ Generator    │ │ Pattern Gen        │ │  │
│  │  └──────────────┘ └──────────────┘ └────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   Output Processors                        │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐ │  │
│  │  │ Voice        │ │ Music        │ │ Content            │ │  │
│  │  │ Synthesizer  │ │ Generator    │ │ Formatter          │ │  │
│  │  └──────────────┘ └──────────────┘ └────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   Context Layer                            │  │
│  │  • User Profile  • Mood State  • Preferences  • History   │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Database Schema

```sql
-- Generated content records
CREATE TABLE generated_content (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    content_type TEXT NOT NULL CHECK (content_type IN (
        'meditation', 'story', 'journaling_prompt', 'affirmation',
        'visualization', 'breathing_pattern', 'gratitude_prompt',
        'relationship_reflection', 'soundscape'
    )),
    title TEXT,
    content_text TEXT NOT NULL,
    audio_url TEXT,
    duration_seconds INTEGER,
    generation_context JSONB NOT NULL DEFAULT '{}',
    generation_params JSONB NOT NULL DEFAULT '{}',
    is_saved BOOLEAN DEFAULT FALSE,
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    feedback TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User's saved/favorited generated content
CREATE TABLE saved_generated_content (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    content_id UUID REFERENCES generated_content(id) ON DELETE CASCADE,
    saved_at TIMESTAMPTZ DEFAULT NOW(),
    notes TEXT,
    use_count INTEGER DEFAULT 0,
    last_used_at TIMESTAMPTZ,
    UNIQUE(user_id, content_id)
);

-- Generation templates and prompts
CREATE TABLE generation_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_type TEXT NOT NULL,
    name TEXT NOT NULL,
    system_prompt TEXT NOT NULL,
    user_prompt_template TEXT NOT NULL,
    voice_style TEXT,
    music_style TEXT,
    tags TEXT[] DEFAULT '{}',
    is_active BOOLEAN DEFAULT TRUE,
    version INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Content generation analytics
CREATE TABLE generation_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    content_id UUID REFERENCES generated_content(id),
    event_type TEXT NOT NULL CHECK (event_type IN (
        'generated', 'started', 'completed', 'abandoned',
        'saved', 'rated', 'shared'
    )),
    event_data JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Content diversity tracking (prevent repetition)
CREATE TABLE generation_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    content_type TEXT NOT NULL,
    theme_hash TEXT NOT NULL,  -- Hash of main themes for deduplication
    generated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, content_type, theme_hash)
);

-- Enable RLS
ALTER TABLE generated_content ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_generated_content ENABLE ROW LEVEL SECURITY;
ALTER TABLE generation_analytics ENABLE ROW LEVEL SECURITY;
ALTER TABLE generation_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own generated content"
    ON generated_content FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage saved content"
    ON saved_generated_content FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users view own analytics"
    ON generation_analytics FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage generation history"
    ON generation_history FOR ALL
    USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX idx_generated_content_user ON generated_content(user_id);
CREATE INDEX idx_generated_content_type ON generated_content(user_id, content_type);
CREATE INDEX idx_saved_content_user ON saved_generated_content(user_id);
CREATE INDEX idx_generation_history_user ON generation_history(user_id, content_type);
```

### Swift Models

```swift
import Foundation

// MARK: - Content Types

enum GeneratedContentType: String, Codable, CaseIterable {
    case meditation
    case story
    case journalingPrompt = "journaling_prompt"
    case affirmation
    case visualization
    case breathingPattern = "breathing_pattern"
    case gratitudePrompt = "gratitude_prompt"
    case relationshipReflection = "relationship_reflection"
    case soundscape

    var displayName: String {
        switch self {
        case .meditation: return "Guided Meditation"
        case .story: return "Therapeutic Story"
        case .journalingPrompt: return "Journaling Prompt"
        case .affirmation: return "Affirmation"
        case .visualization: return "Visualization"
        case .breathingPattern: return "Breathing Exercise"
        case .gratitudePrompt: return "Gratitude Prompt"
        case .relationshipReflection: return "Relationship Reflection"
        case .soundscape: return "Soundscape"
        }
    }

    var icon: String {
        switch self {
        case .meditation: return "brain.head.profile"
        case .story: return "book"
        case .journalingPrompt: return "pencil.line"
        case .affirmation: return "heart.text.square"
        case .visualization: return "eye"
        case .breathingPattern: return "wind"
        case .gratitudePrompt: return "hands.sparkles"
        case .relationshipReflection: return "person.2"
        case .soundscape: return "waveform"
        }
    }

    var hasAudio: Bool {
        switch self {
        case .meditation, .visualization, .breathingPattern, .soundscape:
            return true
        default:
            return false
        }
    }
}

// MARK: - Generated Content

struct GeneratedContent: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let contentType: GeneratedContentType
    let title: String?
    let contentText: String
    let audioUrl: String?
    let durationSeconds: Int?
    let generationContext: GenerationContext
    let generationParams: GenerationParams
    var isSaved: Bool
    var rating: Int?
    var feedback: String?
    let createdAt: Date
}

struct GenerationContext: Codable {
    let moodScore: Double?
    let moodLabel: String?
    let timeOfDay: String?
    let recentThemes: [String]?
    let userPreferences: UserContentPreferences?
    let triggerEvent: String?
}

struct UserContentPreferences: Codable {
    let preferredVoice: VoiceStyle
    let meditationStyle: MeditationStyle
    let languageComplexity: LanguageComplexity
    let spiritualInclination: SpiritualInclination
    let contentLength: ContentLength

    enum VoiceStyle: String, Codable {
        case warm, calm, energetic, nurturing
    }

    enum MeditationStyle: String, Codable {
        case breathFocused = "breath_focused"
        case bodyBased = "body_based"
        case visualization
        case mantrabased = "mantra_based"
        case natureSounds = "nature_sounds"
    }

    enum LanguageComplexity: String, Codable {
        case simple, moderate, sophisticated
    }

    enum SpiritualInclination: String, Codable {
        case secular, lightlySpiritual = "lightly_spiritual", spiritual
    }

    enum ContentLength: String, Codable {
        case brief       // 3-5 min
        case moderate    // 8-12 min
        case extended    // 15-20 min
    }
}

struct GenerationParams: Codable {
    let temperature: Double
    let maxTokens: Int
    let templateId: UUID?
    let seedThemes: [String]?
    let avoidThemes: [String]?
}

// MARK: - Saved Content

struct SavedGeneratedContent: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let contentId: UUID
    let savedAt: Date
    var notes: String?
    var useCount: Int
    var lastUsedAt: Date?

    // Joined from generated_content
    var content: GeneratedContent?
}

// MARK: - Generation Request

struct GenerationRequest: Codable {
    let contentType: GeneratedContentType
    let durationMinutes: Int?
    let focusArea: String?
    let moodContext: String?
    let specificRequest: String?
    let includeAudio: Bool
}

struct GenerationResponse: Codable {
    let content: GeneratedContent
    let generationTimeMs: Int
}

// MARK: - Story Elements

struct TherapeuticStory: Codable {
    let title: String
    let chapters: [StoryChapter]
    let therapeuticThemes: [String]
    let reflectionPrompts: [String]
    let totalDurationMinutes: Int
}

struct StoryChapter: Codable {
    let chapterNumber: Int
    let title: String
    let content: String
    let audioUrl: String?
    let durationSeconds: Int
    let pauseForReflection: Bool
}
```

### API Contracts

```typescript
// Edge Function: generate-content
// POST /functions/v1/generate-content

interface GenerateContentRequest {
  content_type: GeneratedContentType;
  duration_minutes?: number;
  focus_area?: string;
  mood_context?: string;
  specific_request?: string;
  include_audio: boolean;
}

interface GenerateContentResponse {
  content: {
    id: string;
    content_type: string;
    title: string;
    content_text: string;
    audio_url?: string;
    duration_seconds?: number;
  };
  generation_time_ms: number;
}

// Edge Function: synthesize-voice
// POST /functions/v1/synthesize-voice

interface SynthesizeVoiceRequest {
  text: string;
  voice_style: "warm" | "calm" | "energetic" | "nurturing";
  speed: number; // 0.5 - 2.0
  include_pauses: boolean;
  background_music?: string;
}

interface SynthesizeVoiceResponse {
  audio_url: string;
  duration_seconds: number;
}

// REST API
// POST /rest/v1/saved_generated_content
// PATCH /rest/v1/generated_content?id=eq.{id}
// GET /rest/v1/generated_content?user_id=eq.{userId}&is_saved=eq.true
```

---

## Implementation Details

### Step-by-Step Approach

1. **Phase 1: Core Generation Engine** (Week 1)
   - Create content orchestrator
   - Build meditation generator with prompts
   - Implement journaling prompt generator
   - Set up content storage

2. **Phase 2: Voice Synthesis** (Week 2)
   - Integrate voice synthesis API
   - Create voice styling options
   - Implement background music mixing
   - Build audio caching system

3. **Phase 3: Story Generator** (Week 3)
   - Design therapeutic story framework
   - Create story generation prompts
   - Build chapter-based delivery
   - Add reflection prompts

4. **Phase 4: Personalization** (Week 4)
   - Build context assembly system
   - Create diversity tracking
   - Implement preference learning
   - Add content quality scoring

5. **Phase 5: Polish & Analytics** (Week 5)
   - Create saving/favoriting system
   - Build usage analytics
   - Implement rating and feedback
   - Performance optimization

### File Structure

```
apps/ios/MindFriendApp/Features/GenerativeContent/
├── GenerativeContentView.swift
├── GenerativeContentViewModel.swift
├── ContentPlayer/
│   ├── MeditationPlayerView.swift
│   ├── StoryReaderView.swift
│   └── VisualizationPlayerView.swift
├── Generators/
│   ├── ContentGeneratorService.swift
│   ├── MeditationGenerator.swift
│   ├── StoryGenerator.swift
│   └── PromptGenerator.swift
├── Models/
│   └── GenerativeContentModels.swift
├── Components/
│   ├── GenerationProgressView.swift
│   ├── ContentPreviewCard.swift
│   ├── SavedContentRow.swift
│   └── RatingPromptView.swift
└── Library/
    ├── SavedContentListView.swift
    └── ContentHistoryView.swift

supabase/functions/
├── generate-content/
│   └── index.ts
├── synthesize-voice/
│   └── index.ts
└── _shared/
    ├── generation-prompts.ts
    ├── content-templates.ts
    └── voice-config.ts
```

### Key Algorithms

#### Content Generation Engine

```typescript
// supabase/functions/generate-content/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  getGenerationPrompt,
  buildSystemContext,
} from "../_shared/generation-prompts.ts";

interface GenerateRequest {
  content_type: string;
  duration_minutes?: number;
  focus_area?: string;
  mood_context?: string;
  specific_request?: string;
  include_audio: boolean;
}

serve(async (req) => {
  const startTime = Date.now();

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization")!;
  const {
    data: { user },
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  if (!user) {
    return new Response("Unauthorized", { status: 401 });
  }

  const request: GenerateRequest = await req.json();

  // Build context from user data
  const context = await buildUserContext(supabase, user.id);

  // Check for diversity (avoid recent similar content)
  const recentThemes = await getRecentThemes(
    supabase,
    user.id,
    request.content_type,
  );

  // Get generation template
  const template = await getTemplate(supabase, request.content_type);

  // Build prompts
  const systemPrompt = buildSystemContext(template, context, request);
  const userPrompt = buildUserPrompt(template, request, recentThemes);

  // Generate content
  const aiResponse = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("XAI_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "grok-beta",
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: getMaxTokens(request.content_type, request.duration_minutes),
      temperature: 0.8,
    }),
  });

  const aiResult = await aiResponse.json();
  const generatedText = aiResult.choices[0].message.content;

  // Parse and structure content
  const parsedContent = parseGeneratedContent(
    request.content_type,
    generatedText,
  );

  // Generate audio if requested
  let audioUrl: string | undefined;
  let durationSeconds: number | undefined;

  if (request.include_audio && hasAudioContent(request.content_type)) {
    const audioResult = await synthesizeAudio(
      parsedContent.text,
      context.preferences,
    );
    audioUrl = audioResult.url;
    durationSeconds = audioResult.duration;
  }

  // Save to database
  const { data: content, error } = await supabase
    .from("generated_content")
    .insert({
      user_id: user.id,
      content_type: request.content_type,
      title: parsedContent.title,
      content_text: parsedContent.text,
      audio_url: audioUrl,
      duration_seconds: durationSeconds || estimateDuration(parsedContent.text),
      generation_context: {
        mood_score: context.recentMood?.score,
        mood_label: context.recentMood?.label,
        time_of_day: getTimeOfDay(),
        recent_themes: recentThemes,
        user_preferences: context.preferences,
        trigger_event: request.focus_area,
      },
      generation_params: {
        temperature: 0.8,
        max_tokens: getMaxTokens(
          request.content_type,
          request.duration_minutes,
        ),
        seed_themes: parsedContent.themes,
      },
    })
    .select()
    .single();

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
    });
  }

  // Track themes for diversity
  await trackGeneratedThemes(
    supabase,
    user.id,
    request.content_type,
    parsedContent.themes,
  );

  // Log analytics
  await supabase.from("generation_analytics").insert({
    user_id: user.id,
    content_id: content.id,
    event_type: "generated",
    event_data: { generation_time_ms: Date.now() - startTime },
  });

  return new Response(
    JSON.stringify({
      content,
      generation_time_ms: Date.now() - startTime,
    }),
    {
      headers: { "Content-Type": "application/json" },
    },
  );
});

async function buildUserContext(supabase: any, userId: string) {
  const [profileResult, moodResult, preferencesResult, historyResult] =
    await Promise.all([
      supabase.from("profiles").select("*").eq("id", userId).single(),
      supabase
        .from("moods")
        .select("*")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(1)
        .single(),
      supabase
        .from("user_content_preferences")
        .select("*")
        .eq("user_id", userId)
        .single(),
      supabase
        .from("journal_entries")
        .select("themes, emotions")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(5),
    ]);

  return {
    profile: profileResult.data,
    recentMood: moodResult.data,
    preferences: preferencesResult.data || getDefaultPreferences(),
    recentJournalThemes: extractThemes(historyResult.data),
  };
}

function getMaxTokens(contentType: string, durationMinutes?: number): number {
  const baseTokens: Record<string, number> = {
    meditation: 1500,
    story: 2500,
    journaling_prompt: 300,
    affirmation: 200,
    visualization: 1200,
    breathing_pattern: 400,
    gratitude_prompt: 250,
    relationship_reflection: 400,
  };

  const base = baseTokens[contentType] || 500;
  const durationMultiplier = durationMinutes
    ? Math.min(durationMinutes / 10, 2)
    : 1;

  return Math.floor(base * durationMultiplier);
}

async function getRecentThemes(
  supabase: any,
  userId: string,
  contentType: string,
): Promise<string[]> {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const { data } = await supabase
    .from("generation_history")
    .select("theme_hash")
    .eq("user_id", userId)
    .eq("content_type", contentType)
    .gte("generated_at", thirtyDaysAgo.toISOString());

  return data?.map((d: any) => d.theme_hash) || [];
}

function parseGeneratedContent(
  contentType: string,
  rawText: string,
): ParsedContent {
  // Content-type specific parsing
  // Extract title, main content, themes, etc.

  // Try to parse as JSON first (structured responses)
  try {
    const json = JSON.parse(rawText);
    return {
      title: json.title || generateTitle(contentType),
      text: json.content || json.text || rawText,
      themes: json.themes || extractThemesFromText(rawText),
    };
  } catch {
    // Plain text response
    const lines = rawText.split("\n");
    const title =
      lines[0].replace(/^#\s*/, "").trim() || generateTitle(contentType);
    const text = lines.slice(1).join("\n").trim() || rawText;

    return {
      title,
      text,
      themes: extractThemesFromText(rawText),
    };
  }
}

interface ParsedContent {
  title: string;
  text: string;
  themes: string[];
}
```

#### Meditation Generation Prompts

```typescript
// supabase/functions/_shared/generation-prompts.ts

interface GenerationTemplate {
  systemPrompt: string;
  userPromptTemplate: string;
}

export function getGenerationPrompt(
  contentType: string,
  context: UserContext,
  request: GenerateRequest,
): GenerationTemplate {
  const templates: Record<string, GenerationTemplate> = {
    meditation: {
      systemPrompt: `You are an expert meditation guide creating personalized guided meditation scripts.

USER CONTEXT:
- Name: ${context.profile?.display_name || "friend"}
- Current mood: ${context.recentMood?.label || "unknown"}
- Preferred style: ${context.preferences?.meditation_style || "breath_focused"}
- Language preference: ${context.preferences?.language_complexity || "moderate"}
- Spiritual inclination: ${context.preferences?.spiritual_inclination || "secular"}

GUIDELINES:
- Use second person ("you")
- Include natural pauses (marked as [PAUSE X seconds])
- Vary sentence length for natural rhythm
- Include body awareness cues
- End with gentle transition back to awareness
- Keep tone ${context.preferences?.voice_style || "calm"} throughout
- Duration target: ${request.duration_minutes || 10} minutes (approximately ${(request.duration_minutes || 10) * 150} words)

AVOID:
${context.avoidThemes?.map((t) => `- ${t}`).join("\n") || "- Nothing specific to avoid"}`,

      userPromptTemplate: `Create a unique guided meditation focused on ${request.focus_area || "relaxation and presence"}.

${request.specific_request ? `User's specific request: ${request.specific_request}` : ""}
${request.mood_context ? `Current situation: ${request.mood_context}` : ""}

The meditation should:
1. Begin with arrival and settling (1-2 minutes)
2. Include a breath awareness section
3. Have a main theme exploration (${request.focus_area || "calm and peace"})
4. Include a visualization or body scan component
5. End with integration and gentle return

Format as flowing prose with [PAUSE X seconds] markers for silence.`,
    },

    story: {
      systemPrompt: `You are a master storyteller creating therapeutic narratives.

USER CONTEXT:
- Name: ${context.profile?.display_name || "friend"}
- Current mood: ${context.recentMood?.label || "unknown"}
- Recent journal themes: ${context.recentJournalThemes?.join(", ") || "unknown"}

GUIDELINES:
- Create engaging narrative with therapeutic undertones
- Use metaphor and symbolism
- Include relatable protagonist facing similar challenges
- Build toward meaningful insight or resolution
- End with reflection opportunity
- Keep language ${context.preferences?.language_complexity || "moderate"}`,

      userPromptTemplate: `Create a therapeutic story addressing the theme of "${request.focus_area || "personal growth"}".

${request.mood_context ? `The reader is currently feeling: ${request.mood_context}` : ""}
${request.specific_request ? `Specific request: ${request.specific_request}` : ""}

Structure:
1. Opening scene establishing character and situation
2. Challenge or obstacle that mirrors the reader's situation
3. Journey of discovery or transformation
4. Meaningful resolution with subtle life lesson
5. Closing with reflection prompts

Include 2-3 natural pause points marked as [REFLECTION PAUSE].`,
    },

    journaling_prompt: {
      systemPrompt: `You are a thoughtful journaling guide creating personalized reflection prompts.

USER CONTEXT:
- Recent mood: ${context.recentMood?.label || "unknown"}
- Recent journal themes: ${context.recentJournalThemes?.join(", ") || "unknown"}

Create prompts that:
- Build on previous reflections when relevant
- Offer fresh perspectives
- Balance introspection with actionable thinking
- Feel personal and non-generic`,

      userPromptTemplate: `Create a set of 3 journaling prompts for someone ${request.mood_context || "reflecting on their day"}.

Focus area: ${request.focus_area || "self-discovery"}
${request.specific_request ? `Special request: ${request.specific_request}` : ""}

Format as JSON:
{
  "prompts": [
    {"main_prompt": "...", "follow_up": "...", "reflection_angle": "..."},
    ...
  ],
  "theme": "overall theme"
}`,
    },

    affirmation: {
      systemPrompt: `You are creating personalized affirmations.

USER CONTEXT:
- Current mood: ${context.recentMood?.label || "unknown"}
- Name: ${context.profile?.display_name || "friend"}

Create affirmations that:
- Feel authentic, not generic
- Address the person's current state
- Are specific enough to resonate
- Use "I" statements
- Balance aspiration with self-acceptance`,

      userPromptTemplate: `Create 5 personalized affirmations for someone ${request.mood_context || "seeking confidence"}.

Focus: ${request.focus_area || "general wellbeing"}

Format as JSON array of affirmation strings.`,
    },
  };

  return templates[contentType] || templates.meditation;
}

export function buildSystemContext(
  template: any,
  context: UserContext,
  request: GenerateRequest,
): string {
  return template.system_prompt.replace(/\${([^}]+)}/g, (_, key) => {
    const value = getNestedValue(context, key) || getNestedValue(request, key);
    return value || "";
  });
}

function getNestedValue(obj: any, path: string): any {
  return path.split(".").reduce((o, k) => o?.[k], obj);
}
```

#### Voice Synthesis

```typescript
// supabase/functions/synthesize-voice/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface SynthesizeRequest {
  text: string;
  voice_style: "warm" | "calm" | "energetic" | "nurturing";
  speed: number;
  include_pauses: boolean;
  background_music?: string;
}

const VOICE_CONFIGS: Record<string, { voiceId: string; settings: any }> = {
  warm: {
    voiceId: "warm_female_1",
    settings: { stability: 0.7, similarity_boost: 0.8 },
  },
  calm: {
    voiceId: "calm_female_1",
    settings: { stability: 0.8, similarity_boost: 0.7 },
  },
  energetic: {
    voiceId: "energetic_female_1",
    settings: { stability: 0.6, similarity_boost: 0.8 },
  },
  nurturing: {
    voiceId: "nurturing_female_1",
    settings: { stability: 0.75, similarity_boost: 0.75 },
  },
};

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization")!;
  const {
    data: { user },
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  if (!user) {
    return new Response("Unauthorized", { status: 401 });
  }

  const request: SynthesizeRequest = await req.json();

  // Process text for pauses
  const processedText = request.include_pauses
    ? convertPauseMarkers(request.text)
    : request.text.replace(/\[PAUSE \d+ seconds?\]/g, "");

  const voiceConfig = VOICE_CONFIGS[request.voice_style] || VOICE_CONFIGS.calm;

  // Call voice synthesis API (e.g., ElevenLabs, OpenAI TTS, etc.)
  const synthesisResponse = await fetch(Deno.env.get("VOICE_API_URL")!, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("VOICE_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      text: processedText,
      voice_id: voiceConfig.voiceId,
      voice_settings: {
        ...voiceConfig.settings,
        speaking_rate: request.speed,
      },
      output_format: "mp3",
    }),
  });

  if (!synthesisResponse.ok) {
    return new Response("Voice synthesis failed", { status: 500 });
  }

  const audioBuffer = await synthesisResponse.arrayBuffer();

  // Add background music if requested
  let finalAudio: ArrayBuffer;
  if (request.background_music) {
    finalAudio = await mixWithBackgroundMusic(
      audioBuffer,
      request.background_music,
    );
  } else {
    finalAudio = audioBuffer;
  }

  // Upload to Supabase Storage
  const fileName = `generated/${user.id}/${Date.now()}.mp3`;
  const { error: uploadError } = await supabase.storage
    .from("audio")
    .upload(fileName, finalAudio, {
      contentType: "audio/mpeg",
    });

  if (uploadError) {
    return new Response(JSON.stringify({ error: uploadError.message }), {
      status: 500,
    });
  }

  const {
    data: { publicUrl },
  } = supabase.storage.from("audio").getPublicUrl(fileName);

  // Estimate duration (rough: ~150 words per minute)
  const wordCount = request.text.split(/\s+/).length;
  const pauseSeconds = extractTotalPauseSeconds(request.text);
  const speechDuration = (wordCount / 150) * 60;
  const totalDuration = Math.ceil(speechDuration + pauseSeconds);

  return new Response(
    JSON.stringify({
      audio_url: publicUrl,
      duration_seconds: totalDuration,
    }),
    {
      headers: { "Content-Type": "application/json" },
    },
  );
});

function convertPauseMarkers(text: string): string {
  // Convert [PAUSE X seconds] to SSML breaks or silence
  return text.replace(
    /\[PAUSE (\d+) seconds?\]/g,
    (_, seconds) => `<break time="${seconds}s"/>`,
  );
}

function extractTotalPauseSeconds(text: string): number {
  const matches = text.matchAll(/\[PAUSE (\d+) seconds?\]/g);
  let total = 0;
  for (const match of matches) {
    total += parseInt(match[1]);
  }
  return total;
}

async function mixWithBackgroundMusic(
  voiceAudio: ArrayBuffer,
  musicType: string,
): Promise<ArrayBuffer> {
  // In production, use an audio processing library or service
  // to mix the voice audio with background music at lower volume
  // For now, return voice audio unchanged
  return voiceAudio;
}
```

---

## Dependencies

### Internal Dependencies

- F004 (Companion Memory Enhancement) - User context
- F013 (AI-Generated Exercises) - Foundation
- F003 (Predictive Mood Intelligence) - Mood awareness
- Core Exercise System - Delivery

### External Dependencies

- xAI Grok API - Content generation
- Voice synthesis API (ElevenLabs/OpenAI) - Audio
- Audio processing service - Music mixing

### Infrastructure

- Supabase Edge Functions - Generation
- Supabase Storage - Audio files
- CDN - Audio delivery

---

## Edge Cases & Error Handling

| Scenario                               | Handling                              |
| -------------------------------------- | ------------------------------------- |
| Generation takes too long              | Stream partial content, show progress |
| Voice synthesis fails                  | Offer text-only with graceful message |
| Content too similar to recent          | Regenerate with different seed        |
| Inappropriate content generated        | Content filter before delivery        |
| Audio storage full                     | Clean up old unsaved content          |
| User preference missing                | Use sensible defaults                 |
| Network interruption during generation | Cache partial result, allow resume    |
| Very short generation request          | Ensure minimum quality content        |
| API rate limits hit                    | Queue and retry with backoff          |

---

## Testing Requirements

### Unit Tests

```swift
import XCTest
@testable import MindFriendApp

final class GenerativeContentTests: XCTestCase {

    func testContentTypeHasAudio() {
        XCTAssertTrue(GeneratedContentType.meditation.hasAudio)
        XCTAssertTrue(GeneratedContentType.visualization.hasAudio)
        XCTAssertFalse(GeneratedContentType.journalingPrompt.hasAudio)
        XCTAssertFalse(GeneratedContentType.affirmation.hasAudio)
    }

    func testGenerationRequestEncoding() throws {
        let request = GenerationRequest(
            contentType: .meditation,
            durationMinutes: 10,
            focusArea: "stress relief",
            moodContext: "feeling anxious",
            specificRequest: nil,
            includeAudio: true
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(GenerationRequest.self, from: encoded)

        XCTAssertEqual(decoded.contentType, .meditation)
        XCTAssertEqual(decoded.durationMinutes, 10)
        XCTAssertTrue(decoded.includeAudio)
    }

    func testUserPreferencesDefaults() {
        let defaults = UserContentPreferences(
            preferredVoice: .calm,
            meditationStyle: .breathFocused,
            languageComplexity: .moderate,
            spiritualInclination: .secular,
            contentLength: .moderate
        )

        XCTAssertEqual(defaults.preferredVoice, .calm)
        XCTAssertEqual(defaults.spiritualInclination, .secular)
    }

    func testTherapeuticStoryStructure() {
        let story = TherapeuticStory(
            title: "The Path Through",
            chapters: [
                StoryChapter(
                    chapterNumber: 1,
                    title: "Beginning",
                    content: "Once upon...",
                    audioUrl: nil,
                    durationSeconds: 120,
                    pauseForReflection: false
                )
            ],
            therapeuticThemes: ["resilience", "acceptance"],
            reflectionPrompts: ["What challenges have you overcome?"],
            totalDurationMinutes: 10
        )

        XCTAssertEqual(story.chapters.count, 1)
        XCTAssertEqual(story.therapeuticThemes.count, 2)
    }
}
```

### Integration Tests

```swift
final class GenerativeContentIntegrationTests: XCTestCase {
    var service: ContentGeneratorService!

    override func setUp() async throws {
        service = ContentGeneratorService(supabase: TestSupabaseClient())
    }

    func testGenerateMeditation() async throws {
        let request = GenerationRequest(
            contentType: .meditation,
            durationMinutes: 5,
            focusArea: "relaxation",
            moodContext: nil,
            specificRequest: nil,
            includeAudio: false
        )

        let response = try await service.generate(request)

        XCTAssertNotNil(response.content.id)
        XCTAssertEqual(response.content.contentType, .meditation)
        XCTAssertFalse(response.content.contentText.isEmpty)
        XCTAssertGreaterThan(response.generationTimeMs, 0)
    }

    func testGenerateAndSave() async throws {
        // Generate content
        let content = try await service.generate(GenerationRequest(
            contentType: .affirmation,
            durationMinutes: nil,
            focusArea: "confidence",
            moodContext: nil,
            specificRequest: nil,
            includeAudio: false
        ))

        // Save it
        let saved = try await service.saveContent(contentId: content.content.id)

        XCTAssertTrue(saved.isSaved)

        // Verify in saved list
        let savedList = try await service.fetchSavedContent()
        XCTAssertTrue(savedList.contains { $0.contentId == content.content.id })
    }

    func testContentDiversity() async throws {
        // Generate multiple items
        for _ in 0..<3 {
            _ = try await service.generate(GenerationRequest(
                contentType: .journalingPrompt,
                durationMinutes: nil,
                focusArea: "gratitude",
                moodContext: nil,
                specificRequest: nil,
                includeAudio: false
            ))
        }

        // Fetch all generated content
        let allContent = try await service.fetchGeneratedContent(type: .journalingPrompt)

        // Verify they're different
        let texts = allContent.map { $0.contentText }
        let uniqueTexts = Set(texts)
        XCTAssertEqual(texts.count, uniqueTexts.count, "Content should be unique")
    }
}
```

### UI Tests

```swift
final class GenerativeContentUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        app = XCUIApplication()
        app.launch()
    }

    func testGenerateMeditationFlow() {
        navigateToGenerativeContent()
        app.buttons["Guided Meditation"].tap()

        // Configure
        app.buttons["10 minutes"].tap()
        app.textFields["Focus area"].tap()
        app.textFields["Focus area"].typeText("stress relief")

        // Generate
        app.buttons["Generate Meditation"].tap()

        // Wait for generation
        XCTAssertTrue(app.activityIndicators["Generating..."].exists)
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 30))
    }

    func testSaveGeneratedContent() {
        navigateToGenerativeContent()
        generateTestContent()

        // Save
        app.buttons["Save to Favorites"].tap()
        XCTAssertTrue(app.staticTexts["Saved!"].exists)

        // Verify in library
        app.buttons["Back"].tap()
        app.buttons["Saved Content"].tap()
        XCTAssertTrue(app.cells.count > 0)
    }

    func testRateGeneratedContent() {
        navigateToGenerativeContent()
        generateTestContent()

        // Complete and rate
        app.buttons["Complete"].tap()

        XCTAssertTrue(app.staticTexts["How was this meditation?"].exists)
        app.buttons["4 stars"].tap()

        XCTAssertTrue(app.staticTexts["Thanks for your feedback!"].exists)
    }

    private func navigateToGenerativeContent() {
        app.tabBars["TabBar"].buttons["Exercises"].tap()
        app.buttons["Create Custom"].tap()
    }

    private func generateTestContent() {
        app.buttons["Quick Affirmations"].tap()
        app.buttons["Generate"].tap()
        _ = app.buttons["Continue"].waitForExistence(timeout: 15)
    }
}
```
