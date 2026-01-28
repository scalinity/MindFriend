// MindFriend Generate Content Edge Function
// AI-powered content generation with TTS for personalized wellness content
// Supports: sleep stories, meditations, breathing exercises, grounding, mindfulness, affirmations

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
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

// deno-lint-ignore no-explicit-any
type AnySupabaseClient = any;

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
    // === DEBUG LOGGING START ===
    console.log(
      `[generate-content] Request received at ${new Date().toISOString()}`,
    );
    console.log(`[generate-content] Method: ${req.method}, URL: ${req.url}`);

    // Auth validation
    const authHeader = req.headers.get("Authorization");
    console.log(`[generate-content] Auth header present: ${!!authHeader}`);
    console.log(
      `[generate-content] Auth header starts with Bearer: ${authHeader?.startsWith("Bearer ")}`,
    );

    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      console.error(
        `[generate-content] REJECTED: Missing or malformed authorization header`,
      );
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    console.log(`[generate-content] Token length: ${token.length}`);
    console.log(
      `[generate-content] Token prefix: ${token.substring(0, 30)}...`,
    );

    // Create Supabase clients
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: {
          headers: { Authorization: `Bearer ${token}` },
        },
      },
    ) as AnySupabaseClient;

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    ) as AnySupabaseClient;

    // Get authenticated user
    console.log(`[generate-content] Calling supabaseUser.auth.getUser()...`);
    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();

    console.log(
      `[generate-content] getUser result - user: ${user?.id ?? "null"}, error: ${authError?.message ?? "none"}`,
    );

    if (authError || !user) {
      console.error(`[generate-content] REJECTED: Auth validation failed`);
      console.error(`[generate-content] Auth error code: ${authError?.status}`);
      console.error(`[generate-content] Auth error name: ${authError?.name}`);
      console.error(
        `[generate-content] Auth error message: ${authError?.message}`,
      );
      return new Response(JSON.stringify({ error: "Invalid authentication" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    console.log(
      `[generate-content] SUCCESS: User authenticated - ID: ${user.id}, email: ${user.email}`,
    );

    // Rate limiting
    const rateLimitResult = await checkRateLimit(
      supabaseAdmin,
      user.id,
      "content_generation",
    );
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
    console.log(
      `[generate-content] About to call supabaseAdmin.rpc for quota check`,
    );
    console.log(
      `[generate-content] supabaseAdmin type: ${typeof supabaseAdmin}`,
    );
    console.log(
      `[generate-content] supabaseAdmin.rpc type: ${typeof supabaseAdmin.rpc}`,
    );
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

    console.log(
      `[generate-content] Quota check result:`,
      JSON.stringify(quota),
    );

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

      // Extract readable text from JSON response for display/TTS
      const displayText = extractDisplayText(textContent, request.contentType);

      // Update record with generated content and context
      const updateData: any = {
        text_content: displayText,
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

      console.log(`[generate-content] isPremium: ${isPremium}`);
      if (isPremium) {
        // Check monthly TTS character budget ($5/month cap)
        // Use displayText (extracted readable content) not raw JSON
        const charCount = displayText.length;
        console.log(
          `[generate-content] Premium user - checking TTS budget for ${charCount} characters`,
        );
        const { data: budgetResult, error: budgetError } =
          await supabaseAdmin.rpc("check_tts_monthly_budget", {
            p_user_id: user.id,
            p_character_count: charCount,
          });

        console.log(
          `[generate-content] TTS budget check - error: ${budgetError?.message || "none"}, result:`,
          JSON.stringify(budgetResult),
        );
        const budget = budgetResult?.[0];
        if (budgetError || !budget?.allowed) {
          // Monthly budget exceeded — fall back to text-only like free tier
          console.log(
            `Premium user ${user.id}: monthly TTS budget exceeded (${budget?.chars_used || "?"}/${budget?.chars_limit || "?"} chars), returning text-only`,
          );
          actualDuration = estimateDuration(displayText);
        }

        if (budget?.allowed) {
          console.log(
            `[generate-content] TTS budget allowed, synthesizing audio...`,
          );
          try {
            const googleTTS = createGoogleTTSClient();
            const voiceId = request.params.voiceId || DEFAULT_VOICE_ID;
            console.log(`[generate-content] Using voiceId: ${voiceId}`);

            // Synthesize voice with Google Cloud TTS (premium feature)
            // Use displayText (extracted readable content) not raw JSON
            const ttsResult = await googleTTS.textToSpeech({
              text: displayText,
              voiceId,
            });
            console.log(
              `[generate-content] TTS synthesis successful, ${ttsResult.audioData?.length || 0} bytes, ${ttsResult.characterCount} chars`,
            );

            // Upload to Supabase Storage
            const fileName = `${user.id}/${contentId}.mp3`;
            const { error: uploadError } = await supabaseAdmin.storage
              .from("generated-audio")
              .upload(fileName, ttsResult.audioData, {
                contentType: ttsResult.contentType,
                upsert: true,
              });

            if (!uploadError) {
              console.log(
                `[generate-content] Audio uploaded successfully to: ${fileName}`,
              );
              // Get public URL
              const { data: urlData } = supabaseAdmin.storage
                .from("generated-audio")
                .getPublicUrl(fileName);

              audioUrl = urlData?.publicUrl;
              console.log(`[generate-content] Audio URL: ${audioUrl}`);
              actualDuration = estimateDuration(textContent);
              generationCost = estimateTTSCost(ttsResult.characterCount);
            } else {
              console.error(
                "[generate-content] Audio upload error:",
                uploadError,
              );
            }
          } catch (ttsError) {
            // Log TTS error but don't fail the request
            console.error("TTS error (non-fatal):", ttsError);
            if (ttsError instanceof GoogleTTSError) {
              console.error("Google TTS error code:", ttsError.code);
            }
          }

          // Record synthesis for monthly budget tracking
          await supabaseAdmin.rpc("check_and_increment_synthesis_quota", {
            p_user_id: user.id,
            p_is_premium: true,
            p_character_count: charCount,
          });
        } // end budget?.allowed
      } else {
        // Free tier: estimate duration from displayText for UI display
        actualDuration = estimateDuration(displayText);
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
      console.log(
        `[generate-content] Updating DB record ${contentId} with audio_url: ${audioUrl ? "present" : "null"}`,
      );
      const { error: finalUpdateError } = await supabaseAdmin
        .from("generated_content")
        .update({
          audio_url: audioUrl,
          duration_seconds: actualDuration,
          quality_score: qualityScore,
          generation_cost_usd: generationCost,
          status: "completed",
        })
        .eq("id", contentId);

      if (finalUpdateError) {
        console.error(
          `[generate-content] CRITICAL: Failed to update DB record: ${finalUpdateError.message}`,
        );
      } else {
        console.log(
          `[generate-content] DB record updated successfully with audio_url`,
        );
      }

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
      // Ensure quota values are valid numbers (fallback to defaults if undefined)
      const quotaUsedValue =
        typeof quota.quota_used === "number" ? quota.quota_used + 1 : 1;
      // For premium users, quota_limit is -1 (unlimited). Convert to 999 for iOS display.
      const rawQuotaLimit =
        typeof quota.quota_limit === "number" ? quota.quota_limit : 3;
      const quotaLimitValue = rawQuotaLimit === -1 ? 999 : rawQuotaLimit;

      const response: GenerateContentResponse = {
        contentId,
        status: "completed",
        textContent,
        audioUrl,
        title,
        duration: actualDuration,
        qualityScore,
        quotaUsed: quotaUsedValue,
        quotaLimit: quotaLimitValue,
        disclaimer: getContentDisclaimer(),
        triggerWarnings:
          triggerWarnings.length > 0 ? triggerWarnings : undefined,
      };

      console.log(
        `[generate-content] SUCCESS - Returning response:`,
        JSON.stringify(response, null, 2),
      );

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

  console.log(
    `[generate-content] Calling xAI API with model: grok-4-1-fast-reasoning`,
  );
  const response = await fetch(XAI_API_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${xaiApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "grok-4-1-fast-reasoning",
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
    console.error(
      `[generate-content] xAI API error - Status: ${response.status}`,
    );
    console.error(`[generate-content] xAI API error - Response: ${errorText}`);
    throw new Error(
      `xAI API error (${response.status}): ${errorText.substring(0, 200)}`,
    );
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

/**
 * Extract readable display text from JSON response
 * Converts structured JSON content to plain text suitable for display and TTS
 */
function extractDisplayText(
  jsonContent: string,
  contentType: ContentType,
): string {
  try {
    // Try to parse as JSON
    const parsed = JSON.parse(jsonContent);

    // Extract based on content type
    switch (contentType) {
      case "meditation":
      case "mindfulness": {
        // Extract script segments and join them
        const script = parsed.content?.script || [];
        if (Array.isArray(script) && script.length > 0) {
          return script
            .map((segment: { text: string }) => segment.text)
            .join("\n\n");
        }
        // Fallback to description if no script
        return parsed.description || jsonContent;
      }

      case "breathing": {
        // Extract intro, breathing guidance, and outro
        const intro = parsed.content?.introText || "";
        const outro = parsed.content?.outroText || "";
        const pattern = parsed.content?.pattern;
        const cycles = parsed.content?.cycles || 4;

        let text = intro;
        if (pattern) {
          text += `\n\n[Breathing Pattern: ${pattern.patternName || "Guided Breathing"}]`;
          text += `\nInhale for ${pattern.inhaleSeconds} seconds`;
          if (pattern.holdInSeconds > 0)
            text += `\nHold for ${pattern.holdInSeconds} seconds`;
          text += `\nExhale for ${pattern.exhaleSeconds} seconds`;
          if (pattern.holdOutSeconds > 0)
            text += `\nHold for ${pattern.holdOutSeconds} seconds`;
          text += `\n\nRepeat for ${cycles} cycles.`;
        }
        if (outro) text += `\n\n${outro}`;
        return text.trim() || jsonContent;
      }

      case "grounding": {
        // Extract prompts and join them
        const prompts = parsed.content?.prompts || [];
        if (Array.isArray(prompts) && prompts.length > 0) {
          return prompts.map((p: { text: string }) => p.text).join("\n\n");
        }
        return parsed.description || jsonContent;
      }

      case "journaling": {
        // Extract journaling prompts
        const prompts = parsed.content?.prompts || [];
        const questions = parsed.content?.reflectionQuestions || [];
        let text = "";

        if (Array.isArray(prompts) && prompts.length > 0) {
          text = prompts
            .map((p: { text: string }, i: number) => `${i + 1}. ${p.text}`)
            .join("\n\n");
        }

        if (Array.isArray(questions) && questions.length > 0) {
          text += "\n\nReflection Questions:\n";
          text += questions.map((q: string) => `• ${q}`).join("\n");
        }

        return text.trim() || parsed.description || jsonContent;
      }

      case "affirmation": {
        // Handle affirmations (may be array or text)
        if (Array.isArray(parsed.affirmations)) {
          return parsed.affirmations.map((a: string) => `• ${a}`).join("\n");
        }
        return parsed.description || jsonContent;
      }

      case "sleep_story":
      case "cbt":
      default: {
        // For sleep stories and CBT, return the main text content
        return (
          parsed.content?.script ||
          parsed.content?.text ||
          parsed.description ||
          jsonContent
        );
      }
    }
  } catch {
    // Not valid JSON, return as-is (it's already plain text)
    console.log("[generate-content] Content is not JSON, using as plain text");
    return jsonContent;
  }
}
