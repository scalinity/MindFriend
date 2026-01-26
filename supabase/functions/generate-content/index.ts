// MindFriend Generate Content Edge Function
// AI-powered content generation with TTS for personalized wellness content
// Supports: sleep stories, meditations, breathing exercises, grounding, mindfulness, affirmations

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import {
  validateContentRequest,
  validateGeneratedContent,
  detectTriggerWarnings,
  getContentDisclaimer,
} from "../_shared/content-validation.ts";
import {
  createGoogleTTSClient,
  estimateTTSCost,
  estimateDuration,
  DEFAULT_VOICE_ID,
  GoogleTTSError,
} from "../_shared/google-tts.ts";
import { checkRateLimit } from "../_shared/ratelimit.ts";
// NEW: Import context-aware generation modules
import {
  gatherGenerationContext,
  GenerationContext,
} from "./context-gatherer.ts";
import { buildContextualPrompt } from "./prompt-builder.ts";

// Type alias for untyped Supabase client
type UntypedSupabaseClient = SupabaseClient<unknown, "public", unknown>;

// Constants
const XAI_API_URL = "https://api.x.ai/v1/chat/completions";
const MAX_GENERATION_TIME_MS = 60000; // 60 second timeout

// Content type definitions
type ContentType =
  | "sleep_story"
  | "meditation"
  | "breathing"
  | "grounding"
  | "mindfulness"
  | "cbt"
  | "journaling"
  | "affirmation";

interface GenerateContentRequest {
  contentType: ContentType;
  params: {
    // Common params
    duration?: number; // Target duration in seconds (300-1800)
    voiceId?: string;
    backgroundSound?: string; // 'rain', 'ocean', 'forest', 'silence'
    language?: string;

    // Sleep story specific
    theme?: string; // 'forest', 'ocean', 'space', custom
    narratorStyle?: string; // 'whisper', 'calm_male', 'grandmother'
    customPrompt?: string;
    continuationOf?: string; // UUID of previous story for serial

    // Meditation specific
    focus?: "anxiety" | "focus" | "sleep" | "gratitude";
    approach?: "mindfulness" | "body_scan" | "loving_kindness" | "cbt";
    scenario?: string; // 'meeting_stress', 'commute', etc.

    // Breathing specific
    pattern?: "4-4-4" | "4-7-8" | "custom";
    customPattern?: {
      inhale: number;
      hold1: number;
      exhale: number;
      hold2?: number;
    };

    // Grounding specific
    quickVersion?: boolean; // 2-min vs 5-min
    groundingScenario?: "panic" | "overwhelm" | "dissociation";
    location?: "indoor" | "outdoor";

    // Series
    seriesId?: string;
    seriesPosition?: number;
  };
}

interface GenerateContentResponse {
  contentId: string;
  status: "generating" | "completed" | "failed";
  textContent?: string;
  audioUrl?: string;
  title: string;
  duration?: number;
  qualityScore?: number;
  quotaUsed: number;
  quotaLimit: number;
  disclaimer: string;
  triggerWarnings?: string[];
  error?: string;
}

// System prompts for different content types
const CONTENT_PROMPTS: Record<ContentType, string> = {
  sleep_story: `You are a master storyteller creating soothing sleep stories. Your role is to:
- Create gentle, flowing narratives that help listeners drift off to sleep
- Use calming imagery: soft moonlight, peaceful forests, quiet beaches
- Avoid any conflict, excitement, or stimulating content
- Include sensory details that promote relaxation
- Use a slow, peaceful pacing with natural pauses
- Weave in subtle breathing cues
- Stories should feel like a warm, cozy blanket of words

Write a sleep story script of approximately {duration} minutes. Include natural pauses marked with [pause]. The theme is: {theme}`,

  meditation: `You are a skilled meditation guide creating personalized guided meditations. Your role is to:
- Guide listeners through a peaceful meditation experience
- Use present-moment awareness language
- Include body awareness and breath attention
- Keep instructions gentle and non-directive (invite, allow, notice)
- Create space for silence and internal experience
- Use a calm, unhurried pace

Write a {duration}-minute guided meditation script. Focus: {focus}. Approach: {approach}. Include [pause] markers for silent moments.`,

  breathing: `You are a wellness instructor guiding breathing exercises. Your role is to:
- Provide clear, calming guidance for each breath phase
- Count smoothly and reassuringly
- Remind listeners to breathe naturally between cycles
- Include encouraging phrases between rounds
- Keep the pace relaxed and sustainable

Write a breathing exercise script using the {pattern} pattern for {duration} minutes. Include timing markers like [inhale 4], [hold 4], [exhale 4].`,

  grounding: `You are a compassionate guide helping someone ground themselves in the present moment. Your role is to:
- Guide through 5-4-3-2-1 sensory awareness
- Provide specific, relatable sensory observations
- Progress from visual (easier) to taste (harder)
- Use reassuring, present-moment language
- Validate that the listener is safe right now

Write a {duration}-minute grounding exercise script for someone in a {location} environment experiencing {scenario}. Make observations specific and relatable.`,

  mindfulness: `You are a mindfulness teacher creating brief awareness prompts. Your role is to:
- Focus on present-moment awareness
- Use observing language (notice, allow, be curious)
- Keep prompts short and accessible
- Tie awareness to everyday moments
- Avoid judgment or goal-orientation

Write a {duration}-minute mindfulness prompt for {timeOfDay}. Theme: {theme}`,

  cbt: `You are a cognitive-behavioral guide helping someone examine their thoughts. Your role is to:
- Use gentle Socratic questioning
- Help identify thought patterns
- Suggest balanced alternative perspectives (not "positive thinking")
- Encourage curiosity about thoughts rather than fighting them
- Keep language non-clinical and accessible

Write a {duration}-minute cognitive reflection exercise. Help examine the thought: "{thought}". Guide toward balanced perspectives.`,

  journaling: `You are a reflective writing guide creating journaling prompts. Your role is to:
- Create specific, evocative prompts (not generic)
- Build on previous themes when provided
- Encourage exploration without forcing conclusions
- Keep prompts open-ended but focused
- Avoid questions that could trigger rumination

Write 3-5 journaling prompts for {duration} minutes of writing. Theme: {theme}`,

  affirmation: `You are a compassionate voice creating personalized affirmations. Your role is to:
- Create affirmations that feel authentic, not generic
- Use "I am" and "I can" statements
- Focus on strengths and values, not fixing problems
- Keep affirmations brief and memorable
- Make them specific to the user's situation

Write 10 personalized affirmations for someone dealing with {theme}. Each should be a single sentence.`,
};

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: baseCorsHeaders });
  }

  const startTime = Date.now();

  try {
    // Auth validation
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");

    // Create Supabase clients
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: {
          headers: { Authorization: `Bearer ${token}` },
        },
      },
    ) as UntypedSupabaseClient;

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    ) as UntypedSupabaseClient;

    // Get authenticated user
    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();

    if (authError || !user) {
      console.error("Auth error:", authError);
      return new Response(JSON.stringify({ error: "Invalid authentication" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    // Rate limiting
    const rateLimitResult = await checkRateLimit(user.id, "content_generation");
    if (!rateLimitResult.allowed) {
      return new Response(
        JSON.stringify({
          error: "RATE_LIMIT_EXCEEDED",
          message: "Too many requests. Please wait a moment.",
        }),
        {
          status: 429,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse request
    const request: GenerateContentRequest = await req.json();

    // Validate content type
    const validTypes: ContentType[] = [
      "sleep_story",
      "meditation",
      "breathing",
      "grounding",
      "mindfulness",
      "cbt",
      "journaling",
      "affirmation",
    ];
    if (!validTypes.includes(request.contentType)) {
      return new Response(
        JSON.stringify({
          error: "INVALID_CONTENT_TYPE",
          message: `Invalid content type. Must be one of: ${validTypes.join(", ")}`,
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate duration
    const duration = request.params.duration || 300; // Default 5 minutes
    if (duration < 60 || duration > 1800) {
      return new Response(
        JSON.stringify({
          error: "INVALID_DURATION",
          message: "Duration must be between 60 and 1800 seconds",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Content validation (crisis keywords, inappropriate content)
    const topic =
      request.params.theme || request.params.focus || request.contentType;
    const validationResult = validateContentRequest({
      topic,
      contentType: request.contentType,
      userInput: request.params.customPrompt,
    });

    if (!validationResult.approved) {
      return new Response(
        JSON.stringify({
          error: "CONTENT_VALIDATION_FAILED",
          message: validationResult.reason,
          flags: validationResult.flags,
          suggestions: validationResult.suggestions,
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check premium status for quota
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("subscription_tier")
      .eq("id", user.id)
      .single();

    const isPremium =
      profile?.subscription_tier === "premium" ||
      profile?.subscription_tier === "family";

    // Check and enforce quota
    const { data: quotaResult, error: quotaError } = await supabaseAdmin.rpc(
      "check_and_increment_content_quota",
      {
        p_user_id: user.id,
        p_is_premium: isPremium,
      },
    );

    if (quotaError) {
      console.error("Quota check error:", quotaError);
      return new Response(JSON.stringify({ error: "Failed to check quota" }), {
        status: 500,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const quota = quotaResult?.[0] || {
      allowed: false,
      quota_used: 0,
      quota_limit: 3,
    };

    if (!quota.allowed) {
      return new Response(
        JSON.stringify({
          error: "AI_QUOTA_EXCEEDED",
          message:
            "You've reached your daily generation limit. Upgrade to Premium for unlimited content!",
          quotaUsed: quota.quota_used,
          quotaLimit: quota.quota_limit,
        }),
        {
          status: 429,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate content title
    const title = generateTitle(request.contentType, request.params);

    // Create initial record in database
    const { data: contentRecord, error: insertError } = await supabaseAdmin
      .from("generated_content")
      .insert({
        user_id: user.id,
        content_type: request.contentType,
        request_params: request.params,
        title,
        text_content: "", // Will be updated
        voice_id: request.params.voiceId || DEFAULT_VOICE_ID,
        background_sound: request.params.backgroundSound || "silence",
        status: "generating",
        series_id: request.params.seriesId || null,
        series_position: request.params.seriesPosition || null,
      })
      .select("id")
      .single();

    if (insertError || !contentRecord) {
      console.error("Insert error:", insertError);
      return new Response(
        JSON.stringify({ error: "Failed to create content record" }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const contentId = contentRecord.id;

    try {
      // NEW: Gather user context for personalized generation (for exercise types)
      let generationContext: GenerationContext | null = null;
      const exerciseTypes = [
        "breathing",
        "meditation",
        "grounding",
        "journaling",
        "mindfulness",
      ];

      if (exerciseTypes.includes(request.contentType)) {
        try {
          generationContext = await gatherGenerationContext(
            supabaseAdmin,
            user.id,
            request.contentType,
          );
        } catch (contextError) {
          console.warn(
            "Context gathering failed, proceeding with minimal context:",
            contextError,
          );
          // Continue with null context - generateTextContent will handle this
        }
      }

      // Generate text content with xAI (now context-aware for exercises)
      const textContent = await generateTextContent(
        request,
        user.id,
        generationContext,
      );

      // Validate generated content
      const contentValidation = validateGeneratedContent(textContent);
      if (!contentValidation.approved) {
        // Mark as failed and return error
        await supabaseAdmin
          .from("generated_content")
          .update({
            status: "failed",
            error_message: contentValidation.reason,
            safety_flags: contentValidation.flags,
          })
          .eq("id", contentId);

        return new Response(
          JSON.stringify({
            error: "CONTENT_SAFETY_FAILED",
            message:
              "Generated content failed safety validation. Please try again.",
            contentId,
          }),
          {
            status: 400,
            headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Update record with generated content and context
      const updateData: any = {
        text_content: textContent,
        safety_flags: contentValidation.flags,
        status: "completed",
      };

      // NEW: Store generation context if available
      if (generationContext) {
        updateData.generation_context = generationContext;
      }

      const { error: updateError } = await supabaseAdmin
        .from("generated_content")
        .update(updateData)
        .eq("id", contentId);

      // TTS synthesis - PREMIUM ONLY to control costs
      // Free tier users get text_content only; iOS app uses native AVSpeechSynthesizer
      let audioUrl: string | undefined;
      let actualDuration: number | undefined;
      let generationCost = 0;

      if (isPremium) {
        try {
          const googleTTS = createGoogleTTSClient();
          const voiceId = request.params.voiceId || DEFAULT_VOICE_ID;

          // Synthesize voice with Google Cloud TTS (premium feature)
          const ttsResult = await googleTTS.textToSpeech({
            text: textContent,
            voiceId,
          });

          // Upload to Supabase Storage
          const fileName = `${user.id}/${contentId}.mp3`;
          const { error: uploadError } = await supabaseAdmin.storage
            .from("generated-audio")
            .upload(fileName, ttsResult.audioData, {
              contentType: ttsResult.contentType,
              upsert: true,
            });

          if (!uploadError) {
            // Get public URL
            const { data: urlData } = supabaseAdmin.storage
              .from("generated-audio")
              .getPublicUrl(fileName);

            audioUrl = urlData?.publicUrl;
            actualDuration = estimateDuration(textContent);
            generationCost = estimateTTSCost(ttsResult.characterCount);
          } else {
            console.error("Audio upload error:", uploadError);
          }
        } catch (ttsError) {
          // Log TTS error but don't fail the request
          console.error("TTS error (non-fatal):", ttsError);
          if (ttsError instanceof GoogleTTSError) {
            console.error("Google TTS error code:", ttsError.code);
          }
        }
      } else {
        // Free tier: estimate duration from text for UI display
        actualDuration = estimateDuration(textContent);
        console.log(
          `Free tier user ${user.id}: skipping TTS, text-only content`,
        );
      }

      // Calculate quality score (simple heuristic)
      const qualityScore = calculateQualityScore(
        textContent,
        request.contentType,
      );

      // Detect trigger warnings
      const triggerWarnings = detectTriggerWarnings(textContent);

      // Update final record
      const processingTime = Date.now() - startTime;
      await supabaseAdmin
        .from("generated_content")
        .update({
          audio_url: audioUrl,
          duration_seconds: actualDuration,
          quality_score: qualityScore,
          generation_cost_usd: generationCost,
          status: "completed",
        })
        .eq("id", contentId);

      // Also create request record for analytics
      await supabaseAdmin.from("gen_content_requests").insert({
        user_id: user.id,
        content_type: request.contentType,
        request_params: request.params,
        status: "completed",
        generated_content_id: contentId,
        processing_time_ms: processingTime,
        completed_at: new Date().toISOString(),
      });

      // Return success response
      const response: GenerateContentResponse = {
        contentId,
        status: "completed",
        textContent,
        audioUrl,
        title,
        duration: actualDuration,
        qualityScore,
        quotaUsed: quota.quota_used + 1,
        quotaLimit: quota.quota_limit,
        disclaimer: getContentDisclaimer(),
        triggerWarnings:
          triggerWarnings.length > 0 ? triggerWarnings : undefined,
      };

      return new Response(JSON.stringify(response), {
        status: 200,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    } catch (generationError) {
      // Update record as failed
      const errorMessage =
        generationError instanceof Error
          ? generationError.message
          : "Unknown generation error";

      await supabaseAdmin
        .from("generated_content")
        .update({
          status: "failed",
          error_message: errorMessage,
        })
        .eq("id", contentId);

      throw generationError;
    }
  } catch (error) {
    console.error("Generate content error:", error);
    const errorMessage =
      error instanceof Error ? error.message : "An unexpected error occurred";

    return new Response(
      JSON.stringify({
        error: "GENERATION_FAILED",
        message: errorMessage,
      }),
      {
        status: 500,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

/**
 * Generate text content using xAI Grok
 * Now context-aware for exercise types
 */
async function generateTextContent(
  request: GenerateContentRequest,
  userId: string,
  context: GenerationContext | null,
): Promise<string> {
  const xaiApiKey = Deno.env.get("XAI_API_KEY");
  if (!xaiApiKey) {
    throw new Error("XAI_API_KEY not configured");
  }

  // Check if this is an exercise type that should use contextual prompts
  const exerciseTypes = [
    "breathing",
    "meditation",
    "grounding",
    "journaling",
    "mindfulness",
  ];
  const useContextualPrompt =
    exerciseTypes.includes(request.contentType) && context !== null;

  let systemPrompt: string;
  let userPrompt: string;

  if (useContextualPrompt) {
    // NEW: Use context-aware prompt building for exercises
    const prompts = buildContextualPrompt(
      request.contentType,
      context!,
      request.params.duration,
      request.params.theme || request.params.customPrompt,
    );
    systemPrompt = prompts.systemPrompt;
    userPrompt = prompts.userPrompt;
  } else {
    // Legacy: Use template-based prompts for non-exercise types (sleep stories, affirmations, etc.)
    const basePrompt = CONTENT_PROMPTS[request.contentType];
    const durationMinutes = Math.round((request.params.duration || 300) / 60);

    userPrompt = basePrompt
      .replace("{duration}", String(durationMinutes))
      .replace(
        "{theme}",
        request.params.theme || request.params.focus || "general wellness",
      )
      .replace("{focus}", request.params.focus || "mindfulness")
      .replace("{approach}", request.params.approach || "mindfulness")
      .replace("{pattern}", request.params.pattern || "4-4-4")
      .replace("{location}", request.params.location || "indoor")
      .replace("{scenario}", request.params.groundingScenario || "general")
      .replace("{timeOfDay}", "anytime")
      .replace("{thought}", request.params.customPrompt || "anxious thoughts");

    // Add custom prompt if provided
    if (request.params.customPrompt) {
      userPrompt += `\n\nAdditional user request: ${request.params.customPrompt}`;
    }

    systemPrompt =
      "You are a professional wellness content creator specializing in mental health and relaxation content. Create calming, therapeutic content that promotes wellbeing.";
  }

  const response = await fetch(XAI_API_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${xaiApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "grok-2-latest",
      messages: [
        {
          role: "system",
          content: systemPrompt,
        },
        {
          role: "user",
          content: userPrompt,
        },
      ],
      max_tokens: 4000,
      temperature: 0.7,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error("xAI API error:", errorText);
    throw new Error(`Content generation failed: ${response.status}`);
  }

  const data = await response.json();
  const content = data.choices?.[0]?.message?.content;

  if (!content) {
    throw new Error("No content generated");
  }

  return content;
}

/**
 * Generate a title for the content
 */
function generateTitle(
  contentType: ContentType,
  params: GenerateContentRequest["params"],
): string {
  const theme = params.theme || params.focus || "Wellness";
  const titleMap: Record<ContentType, string> = {
    sleep_story: `Sleep Story: ${theme}`,
    meditation: `${params.focus || "Mindfulness"} Meditation`,
    breathing: `${params.pattern || "Box"} Breathing Exercise`,
    grounding: `Grounding Exercise`,
    mindfulness: `Mindfulness Moment`,
    cbt: `Thought Reflection`,
    journaling: `Journaling Prompts: ${theme}`,
    affirmation: `Affirmations: ${theme}`,
  };

  return titleMap[contentType];
}

/**
 * Calculate a simple quality score based on content characteristics
 */
function calculateQualityScore(
  content: string,
  contentType: ContentType,
): number {
  let score = 7; // Base score

  // Length check (appropriate for type)
  const wordCount = content.split(/\s+/).length;
  const expectedMin: Record<ContentType, number> = {
    sleep_story: 500,
    meditation: 300,
    breathing: 150,
    grounding: 200,
    mindfulness: 100,
    cbt: 200,
    journaling: 150,
    affirmation: 50,
  };

  if (wordCount >= expectedMin[contentType]) {
    score += 1;
  }

  // Pause markers check (for audio content)
  if (content.includes("[pause]") || content.includes("[")) {
    score += 1;
  }

  // Presence of calming language
  const calmingWords = [
    "breathe",
    "relax",
    "gentle",
    "peaceful",
    "calm",
    "soft",
    "quiet",
  ];
  const hasCalmingLanguage = calmingWords.some((word) =>
    content.toLowerCase().includes(word),
  );
  if (hasCalmingLanguage) {
    score += 1;
  }

  return Math.min(10, score);
}
