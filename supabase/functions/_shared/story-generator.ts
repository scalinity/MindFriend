/**
 * AI Sleep Story Generator
 * Generates calming bedtime stories using xAI Grok API
 * Optimized for sleep-inducing content with gentle pacing
 */

const XAI_API_URL = "https://api.x.ai/v1/chat/completions";

// Story generation typically needs more tokens for longer narratives
const STORY_TIMEOUT_MS = 120000; // 120 seconds for longer generation
const WORDS_PER_MINUTE = 150; // Average narration speed for sleep content

export interface StoryGenerationRequest {
  title: string;
  category: "fiction" | "nature" | "nonfiction" | "asmr";
  targetDurationMinutes: number;
  isKids: boolean;
  description?: string;
}

export interface GeneratedStory {
  script: string;
  estimatedDurationMinutes: number;
  wordCount: number;
  characterCount: number;
}

export interface StoryGenerationError {
  code: "API_ERROR" | "TIMEOUT" | "INVALID_RESPONSE" | "CONFIG_ERROR";
  message: string;
  details?: string;
}

/**
 * Generate a calming sleep story using AI
 * @param request Story generation parameters
 * @returns Generated story or error
 */
export async function generateSleepStory(
  request: StoryGenerationRequest,
): Promise<
  | { success: true; story: GeneratedStory }
  | { success: false; error: StoryGenerationError }
> {
  const apiKey = Deno.env.get("XAI_API_KEY");
  if (!apiKey) {
    return {
      success: false,
      error: {
        code: "CONFIG_ERROR",
        message: "XAI_API_KEY environment variable not set",
      },
    };
  }

  // Calculate target word count based on duration
  const targetWordCount = request.targetDurationMinutes * WORDS_PER_MINUTE;

  // Build the system prompt for sleep story generation
  const systemPrompt = buildSystemPrompt(request.isKids);
  const userPrompt = buildUserPrompt(request, targetWordCount);

  // Calculate max tokens (roughly 0.75 tokens per word for output)
  const maxTokens = Math.ceil(targetWordCount * 1.5);

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), STORY_TIMEOUT_MS);

  try {
    console.log(
      `[story-generator] Generating "${request.title}" (target: ${targetWordCount} words, ${maxTokens} tokens)`,
    );

    const response = await fetch(XAI_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "grok-4-1-fast-non-reasoning",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        max_tokens: maxTokens,
        temperature: 0.8, // Slightly higher for creative storytelling
      }),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      const errorText = await response.text();
      console.error(
        `[story-generator] API error (${response.status}): ${errorText}`,
      );
      return {
        success: false,
        error: {
          code: "API_ERROR",
          message: `xAI API error: ${response.status}`,
          details: errorText,
        },
      };
    }

    const data = await response.json();

    if (!data.choices || data.choices.length === 0) {
      return {
        success: false,
        error: {
          code: "INVALID_RESPONSE",
          message: "No content in API response",
        },
      };
    }

    const script = data.choices[0].message.content.trim();
    const wordCount = countWords(script);
    const characterCount = script.length;
    const estimatedDurationMinutes = Math.round(wordCount / WORDS_PER_MINUTE);

    console.log(
      `[story-generator] Generated "${request.title}": ${wordCount} words, ~${estimatedDurationMinutes} min`,
    );

    return {
      success: true,
      story: {
        script,
        estimatedDurationMinutes,
        wordCount,
        characterCount,
      },
    };
  } catch (err) {
    clearTimeout(timeoutId);
    const error = err as Error;

    if (error.name === "AbortError") {
      console.error(`[story-generator] Timeout after ${STORY_TIMEOUT_MS}ms`);
      return {
        success: false,
        error: {
          code: "TIMEOUT",
          message: `Story generation timed out after ${STORY_TIMEOUT_MS / 1000} seconds`,
        },
      };
    }

    console.error("[story-generator] Error:", error.message);
    return {
      success: false,
      error: {
        code: "API_ERROR",
        message: error.message || "Unknown error",
      },
    };
  }
}

/**
 * Build system prompt for sleep story generation
 */
function buildSystemPrompt(isKids: boolean): string {
  const audience = isKids ? "children ages 5-12" : "adults";
  const ageGuidance = isKids
    ? "Use simple vocabulary, avoid scary elements, and include gentle, reassuring themes."
    : "Use rich, calming imagery with mature but peaceful themes.";

  return `You are a master storyteller specializing in bedtime stories for ${audience}. Your stories are designed to help listeners relax and drift off to sleep.

WRITING STYLE:
- Write in a slow, meandering narrative style
- Use vivid but calming sensory descriptions (soft sounds, gentle light, warm feelings)
- Favor long, flowing sentences that encourage slow breathing
- Include natural pauses through paragraph breaks
- Gradually slow the pace toward the end of the story
- End with repetitive, dreamlike imagery that trails off peacefully

CONTENT GUIDELINES:
- ${ageGuidance}
- Avoid: tension, conflict, loud sounds, sudden events, cliffhangers, unresolved plots
- Include: nature imagery (soft rain, gentle breeze, moonlight, warm sun)
- Use colors: soft blues, warm golds, gentle greens, peaceful purples
- Include sensations: warmth, comfort, floating, drifting, peaceful breathing

STRUCTURE:
- Begin with a gentle setting description
- Introduce a calm protagonist or observer
- Include a simple, peaceful journey or transformation
- End with the subject settling into rest, sleep, or peaceful contemplation
- The final paragraphs should become increasingly dreamlike and repetitive

OUTPUT: Write ONLY the story text. Do not include titles, chapter headings, or meta-commentary.`;
}

/**
 * Build user prompt with specific story requirements
 */
function buildUserPrompt(
  request: StoryGenerationRequest,
  targetWordCount: number,
): string {
  const categoryGuidance = getCategoryGuidance(request.category);
  const description = request.description
    ? `\n\nADDITIONAL GUIDANCE: ${request.description}`
    : "";

  return `Write a calming bedtime story titled "${request.title}".

REQUIREMENTS:
- Category: ${request.category}
- Target length: approximately ${targetWordCount} words (~${request.targetDurationMinutes} minutes when narrated slowly)
- Audience: ${request.isKids ? "Children (ages 5-12)" : "Adults"}

${categoryGuidance}${description}

Remember: The story should help the listener fall asleep. Begin writing the story now.`;
}

/**
 * Get category-specific guidance
 */
function getCategoryGuidance(category: string): string {
  switch (category) {
    case "fiction":
      return "CATEGORY GUIDANCE (Fiction): Create an original fairy tale or gentle fantasy with magical but non-threatening elements. Include soft magic, friendly creatures, or enchanted peaceful places.";
    case "nature":
      return "CATEGORY GUIDANCE (Nature): Focus on natural settings like forests, meadows, oceans, or mountains. Include detailed descriptions of peaceful natural phenomena like sunset, rainfall, or seasons changing.";
    case "nonfiction":
      return "CATEGORY GUIDANCE (Non-Fiction): Create a gentle exploration of a real-world topic like astronomy, ocean life, or distant lands. Present facts in a dreamy, contemplative way.";
    case "asmr":
      return "CATEGORY GUIDANCE (ASMR): Include detailed sensory descriptions that trigger relaxation - soft textures, gentle sounds, whispered moments, slow movements. Focus heavily on the tactile and auditory experience.";
    default:
      return "";
  }
}

/**
 * Count words in text
 */
function countWords(text: string): number {
  return text
    .trim()
    .split(/\s+/)
    .filter((word) => word.length > 0).length;
}

/**
 * Estimate narration duration in seconds
 */
export function estimateNarrationDuration(text: string): number {
  const wordCount = countWords(text);
  // Sleep narration is slower than typical: ~130 words/minute
  const sleepNarrationWPM = 130;
  return Math.ceil((wordCount / sleepNarrationWPM) * 60);
}
