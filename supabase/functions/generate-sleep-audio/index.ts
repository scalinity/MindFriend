/**
 * Generate Sleep Audio - Admin Edge Function
 * Batch generate AI sleep stories and synthesize audio using Google Cloud TTS
 *
 * Actions:
 * - generate: Generate audio for all pending stories (or specific IDs)
 * - regenerate: Force regenerate specific stories (new script + audio)
 * - preview: Dry run showing what would be generated
 * - status: Get current synthesis status for all stories
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// deno-lint-ignore no-explicit-any
type SupabaseClient = any;
import { getCorsHeaders } from "../_shared/cors.ts";
import {
  createGoogleTTSClient,
  estimateTTSCost,
  GoogleTTSError,
} from "../_shared/google-tts.ts";
import {
  generateSleepStory,
  estimateNarrationDuration,
} from "../_shared/story-generator.ts";
import {
  chunkTextBySentence,
  concatenateAudioBuffers,
  isValidMP3,
} from "../_shared/audio-utils.ts";

// Voice preset keys by tier (mapped to GOOGLE_VOICE_PRESETS in google-tts.ts)
const VOICE_BY_TIER = {
  free: "sleep_story",
  premium: "sleep_story",
  kids: "sleep_story_kids",
};

// Rate limiting configuration
const RATE_LIMIT = {
  delayBetweenStories: 2000, // 2 seconds between stories
  delayBetweenChunks: 500, // 0.5 seconds between chunks
  maxRetries: 2,
  retryDelays: [5000, 15000], // Backoff
};

// Default target duration for generated stories (minutes)
const DEFAULT_TARGET_DURATION_MINUTES = 7;

interface GenerateSleepAudioRequest {
  action: "generate" | "regenerate" | "preview" | "status";
  storyIds?: string[];
  regenerateScript?: boolean;
  voiceIdOverride?: string;
  maxConcurrent?: number;
  maxCost?: number; // Optional cost cap in USD
  targetDurationMinutes?: number; // Override story duration (default: 7)
}

interface StoryResult {
  storyId: string;
  title: string;
  tier: "free" | "premium" | "kids";
  status: "completed" | "failed" | "skipped";
  audioUrl?: string;
  durationSeconds?: number;
  characterCount?: number;
  error?: string;
  recommendedAction?: string;
}

interface GenerateSleepAudioResponse {
  success: boolean;
  summary: {
    total: number;
    completed: number;
    failed: number;
    skipped: number;
    byTier: {
      free: { total: number; completed: number; failed: number };
      premium: { total: number; completed: number; failed: number };
      kids: { total: number; completed: number; failed: number };
    };
  };
  results: StoryResult[];
  estimatedCost: number;
  actualCost: number;
  completionStatus: "SUCCESS" | "PARTIAL" | "FAILED";
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Validate admin authentication (service role key required)
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return errorResponse(
        "Missing authorization",
        "UNAUTHORIZED",
        401,
        corsHeaders,
      );
    }

    const token = authHeader.replace("Bearer ", "");

    // Decode JWT payload to check role claim (more robust than string comparison)
    try {
      const payloadB64 = token.split(".")[1];
      const payload = JSON.parse(atob(payloadB64));
      if (payload.role !== "service_role") {
        return errorResponse(
          "This endpoint requires service role authentication",
          "FORBIDDEN",
          403,
          corsHeaders,
        );
      }
    } catch {
      return errorResponse(
        "Invalid authorization token",
        "UNAUTHORIZED",
        401,
        corsHeaders,
      );
    }

    // Create admin Supabase client using the provided service role token
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      token,
    ) as SupabaseClient;

    // Parse request
    const request: GenerateSleepAudioRequest = await req.json();

    // Route to action handler
    switch (request.action) {
      case "status":
        return await handleStatus(supabase, corsHeaders);

      case "preview":
        return await handlePreview(supabase, request, corsHeaders);

      case "generate":
        return await handleGenerate(supabase, request, false, corsHeaders);

      case "regenerate":
        return await handleGenerate(supabase, request, true, corsHeaders);

      default:
        return errorResponse(
          `Invalid action: ${request.action}`,
          "INVALID_REQUEST",
          400,
          corsHeaders,
        );
    }
  } catch (error) {
    console.error("[generate-sleep-audio] Error:", error);
    return errorResponse(
      "An unexpected error occurred",
      "INTERNAL_ERROR",
      500,
      corsHeaders,
    );
  }
});

/**
 * Handle status action - return current synthesis status for all stories
 */
async function handleStatus(
  supabase: SupabaseClient,
  corsHeaders: Record<string, string>,
): Promise<Response> {
  const { data: stories, error } = await supabase
    .from("sleep_content")
    .select(
      "id, title, is_premium, is_kids, synthesis_status, synthesis_error, synthesized_at",
    )
    .eq("content_type", "story")
    .order("title");

  if (error) {
    return errorResponse(
      "Failed to fetch stories",
      "DATABASE_ERROR",
      500,
      corsHeaders,
    );
  }

  const summary = {
    total: stories.length,
    pending: stories.filter(
      (s: { synthesis_status: string }) => s.synthesis_status === "pending",
    ).length,
    completed: stories.filter(
      (s: { synthesis_status: string }) => s.synthesis_status === "completed",
    ).length,
    failed: stories.filter(
      (s: { synthesis_status: string }) => s.synthesis_status === "failed",
    ).length,
    processing: stories.filter((s: { synthesis_status: string }) =>
      ["generating_script", "synthesizing"].includes(s.synthesis_status),
    ).length,
  };

  return new Response(
    JSON.stringify({
      success: true,
      summary,
      stories: stories.map(
        (s: {
          id: string;
          title: string;
          is_premium: boolean;
          is_kids: boolean;
          synthesis_status: string;
          synthesis_error: string | null;
          synthesized_at: string | null;
        }) => ({
          id: s.id,
          title: s.title,
          tier: getTier(s.is_premium, s.is_kids),
          status: s.synthesis_status,
          error: s.synthesis_error,
          synthesizedAt: s.synthesized_at,
        }),
      ),
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
}

/**
 * Handle preview action - dry run showing what would be generated
 */
async function handlePreview(
  supabase: SupabaseClient,
  request: GenerateSleepAudioRequest,
  corsHeaders: Record<string, string>,
): Promise<Response> {
  const stories = await fetchTargetStories(supabase, request.storyIds, false);

  if (!stories.success) {
    return errorResponse(stories.error!, "DATABASE_ERROR", 500, corsHeaders);
  }

  // Estimate costs
  let totalCharacters = 0;
  // deno-lint-ignore no-explicit-any
  const preview = stories.data!.map((story: any) => {
    const needsScript = !story.script;
    // Estimate ~3000 words * 5 chars/word = 15000 chars per story if no script
    const estimatedChars = story.script?.length || 15000;
    totalCharacters += estimatedChars;

    return {
      id: story.id,
      title: story.title,
      tier: getTier(story.is_premium, story.is_kids),
      hasScript: !needsScript,
      estimatedCharacters: estimatedChars,
      estimatedCost: estimateTTSCost(estimatedChars),
      voiceId:
        request.voiceIdOverride ||
        story.voice_id ||
        VOICE_BY_TIER[getTier(story.is_premium, story.is_kids)],
    };
  });

  return new Response(
    JSON.stringify({
      success: true,
      preview,
      summary: {
        totalStories: preview.length,
        needsScriptGeneration: preview.filter(
          (p: { hasScript: boolean }) => !p.hasScript,
        ).length,
        totalEstimatedCharacters: totalCharacters,
        totalEstimatedCost: estimateTTSCost(totalCharacters),
      },
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
}

/**
 * Handle generate/regenerate action
 */
async function handleGenerate(
  supabase: SupabaseClient,
  request: GenerateSleepAudioRequest,
  forceRegenerate: boolean,
  corsHeaders: Record<string, string>,
): Promise<Response> {
  const stories = await fetchTargetStories(
    supabase,
    request.storyIds,
    !forceRegenerate,
  );

  if (!stories.success) {
    return errorResponse(stories.error!, "DATABASE_ERROR", 500, corsHeaders);
  }

  if (stories.data!.length === 0) {
    return new Response(
      JSON.stringify({
        success: true,
        message: "No stories to process",
        summary: createEmptySummary(),
        results: [],
        estimatedCost: 0,
        actualCost: 0,
        completionStatus: "SUCCESS",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // Check cost cap if specified
  if (request.maxCost) {
    let totalEstimatedChars = 0;
    for (const story of stories.data!) {
      totalEstimatedChars += story.script?.length || 15000;
    }
    const estimatedCost = estimateTTSCost(totalEstimatedChars);
    if (estimatedCost > request.maxCost) {
      return errorResponse(
        `Estimated cost ($${estimatedCost.toFixed(2)}) exceeds max cost cap ($${request.maxCost})`,
        "COST_LIMIT_EXCEEDED",
        400,
        corsHeaders,
      );
    }
  }

  // Process stories
  const results: StoryResult[] = [];
  let totalCharsProcessed = 0;

  for (const story of stories.data!) {
    const tier = getTier(story.is_premium, story.is_kids);

    try {
      console.log(
        `[generate-sleep-audio] Processing: ${story.title} (${tier})`,
      );

      // Step 1: Generate script if needed
      let script = story.script;
      if (!script || request.regenerateScript || forceRegenerate) {
        await updateSynthesisStatus(supabase, story.id, "generating_script");

        const targetDuration =
          request.targetDurationMinutes || DEFAULT_TARGET_DURATION_MINUTES;
        const scriptResult = await generateSleepStory({
          title: story.title,
          category: story.category || "fiction",
          targetDurationMinutes: targetDuration,
          isKids: story.is_kids,
          description: story.description,
        });

        if (!scriptResult.success) {
          throw new Error(
            `Script generation failed: ${scriptResult.error.message}`,
          );
        }

        script = scriptResult.story.script;

        // Save the generated script
        await supabase
          .from("sleep_content")
          .update({ script })
          .eq("id", story.id);
      }

      // Step 2: Backup original audio URL if not already backed up
      if (story.audio_url && !story.original_audio_url) {
        await supabase
          .from("sleep_content")
          .update({ original_audio_url: story.audio_url })
          .eq("id", story.id);
      }

      // Step 3: Synthesize audio
      await updateSynthesisStatus(supabase, story.id, "synthesizing");

      const voiceId =
        request.voiceIdOverride || story.voice_id || VOICE_BY_TIER[tier];
      const audioResult = await synthesizeAudio(script, voiceId);

      if (!audioResult.success) {
        throw new Error(audioResult.error);
      }

      // Step 4: Upload to Supabase Storage
      const fileName = `stories/${story.id}.mp3`;
      const { error: uploadError } = await supabase.storage
        .from("sleep-content")
        .upload(fileName, audioResult.audioData!, {
          contentType: "audio/mpeg",
          upsert: true,
        });

      if (uploadError) {
        // Try creating the bucket if it doesn't exist
        if (uploadError.message.includes("not found")) {
          await supabase.storage.createBucket("sleep-content", {
            public: true,
          });
          const { error: retryError } = await supabase.storage
            .from("sleep-content")
            .upload(fileName, audioResult.audioData!, {
              contentType: "audio/mpeg",
              upsert: true,
            });
          if (retryError)
            throw new Error(`Upload failed: ${retryError.message}`);
        } else {
          throw new Error(`Upload failed: ${uploadError.message}`);
        }
      }

      // Get public URL
      const { data: urlData } = supabase.storage
        .from("sleep-content")
        .getPublicUrl(fileName);

      const audioUrl = urlData?.publicUrl || "";
      const durationSeconds = estimateNarrationDuration(script);

      // Step 5: Update database
      await supabase
        .from("sleep_content")
        .update({
          audio_url: audioUrl,
          voice_id: voiceId,
          duration_seconds: durationSeconds,
          synthesis_status: "completed",
          synthesis_error: null,
          synthesized_at: new Date().toISOString(),
        })
        .eq("id", story.id);

      totalCharsProcessed += script.length;

      results.push({
        storyId: story.id,
        title: story.title,
        tier,
        status: "completed",
        audioUrl,
        durationSeconds,
        characterCount: script.length,
      });

      console.log(`[generate-sleep-audio] Completed: ${story.title}`);

      // Rate limit delay between stories
      await delay(RATE_LIMIT.delayBetweenStories);
    } catch (err) {
      const error = err as Error;
      console.error(`[generate-sleep-audio] Failed: ${story.title}`, error);

      await updateSynthesisStatus(
        supabase,
        story.id,
        "failed",
        error.message || "Unknown error",
      );

      results.push({
        storyId: story.id,
        title: story.title,
        tier,
        status: "failed",
        error: error.message || "Unknown error",
        recommendedAction: getRecommendedAction(error.message || ""),
      });
    }
  }

  // Build response
  const response = buildResponse(results, totalCharsProcessed);

  return new Response(JSON.stringify(response), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Synthesize audio from text using Google Cloud TTS
 */
async function synthesizeAudio(
  text: string,
  voiceId: string,
): Promise<{ success: boolean; audioData?: Uint8Array; error?: string }> {
  try {
    const googleTTS = createGoogleTTSClient();
    const chunks = chunkTextBySentence(text);

    console.log(
      `[synthesize] Processing ${chunks.length} chunks for voice preset ${voiceId}`,
    );

    const audioBuffers: Uint8Array[] = [];

    for (let i = 0; i < chunks.length; i++) {
      let retries = 0;
      let lastError: string | undefined;

      while (retries <= RATE_LIMIT.maxRetries) {
        try {
          console.log(
            `[synthesize] Chunk ${i + 1}/${chunks.length} (${chunks[i].length} chars)`,
          );

          const result = await googleTTS.textToSpeech({
            text: chunks[i],
            voiceId,
          });

          if (!isValidMP3(result.audioData)) {
            throw new Error("Invalid MP3 data received");
          }

          audioBuffers.push(result.audioData);
          break; // Success, exit retry loop
        } catch (err) {
          const error = err as Error;
          lastError = error.message || "Unknown error";
          retries++;

          if (
            error instanceof GoogleTTSError &&
            error.code === "RATE_LIMIT_EXCEEDED"
          ) {
            if (retries <= RATE_LIMIT.maxRetries) {
              const delayMs = RATE_LIMIT.retryDelays[retries - 1] || 30000;
              console.log(
                `[synthesize] Rate limited, waiting ${delayMs}ms before retry ${retries}`,
              );
              await new Promise((r) => setTimeout(r, delayMs));
              continue;
            }
          }

          if (retries > RATE_LIMIT.maxRetries) {
            throw new Error(
              `Chunk ${i + 1} failed after ${retries} retries: ${lastError}`,
            );
          }
        }
      }

      // Delay between chunks
      if (i < chunks.length - 1) {
        await delay(RATE_LIMIT.delayBetweenChunks);
      }
    }

    // Concatenate all audio chunks
    const combinedAudio = concatenateAudioBuffers(audioBuffers);

    return { success: true, audioData: combinedAudio };
  } catch (err) {
    const error = err as Error;
    return { success: false, error: error.message || "Unknown error" };
  }
}

/**
 * Fetch stories to process
 */
async function fetchTargetStories(
  supabase: SupabaseClient,
  storyIds?: string[],
  pendingOnly: boolean = true,
) {
  let query = supabase
    .from("sleep_content")
    .select("*")
    .eq("content_type", "story")
    .eq("is_active", true);

  if (storyIds && storyIds.length > 0) {
    query = query.in("id", storyIds);
  } else if (pendingOnly) {
    query = query.eq("synthesis_status", "pending");
  }

  const { data, error } = await query.order("sort_order");

  if (error) {
    return { success: false, error: error.message };
  }

  return { success: true, data };
}

/**
 * Update synthesis status in database
 */
async function updateSynthesisStatus(
  supabase: SupabaseClient,
  storyId: string,
  status: string,
  error?: string,
) {
  await supabase
    .from("sleep_content")
    .update({
      synthesis_status: status,
      synthesis_error: error || null,
    })
    .eq("id", storyId);
}

/**
 * Get tier from premium/kids flags
 */
function getTier(
  isPremium: boolean,
  isKids: boolean,
): "free" | "premium" | "kids" {
  if (isKids) return "kids";
  if (isPremium) return "premium";
  return "free";
}

/**
 * Get recommended action for error
 */
function getRecommendedAction(errorMessage: string): string {
  if (
    errorMessage.includes("rate limit") ||
    errorMessage.includes("Rate limit")
  ) {
    return "Wait 60 seconds and retry";
  }
  if (errorMessage.includes("timeout") || errorMessage.includes("Timeout")) {
    return "Retry with longer timeout or smaller story";
  }
  if (
    errorMessage.includes("API key") ||
    errorMessage.includes("UNAUTHORIZED")
  ) {
    return "Check GOOGLE_CLOUD_TTS_KEY configuration";
  }
  if (errorMessage.includes("Upload failed")) {
    return "Check Supabase Storage permissions";
  }
  return "Review error and retry";
}

/**
 * Build final response
 */
function buildResponse(
  results: StoryResult[],
  totalCharsProcessed: number,
): GenerateSleepAudioResponse {
  const completed = results.filter((r) => r.status === "completed");
  const failed = results.filter((r) => r.status === "failed");
  const skipped = results.filter((r) => r.status === "skipped");

  const byTier = (tier: "free" | "premium" | "kids") => ({
    total: results.filter((r) => r.tier === tier).length,
    completed: completed.filter((r) => r.tier === tier).length,
    failed: failed.filter((r) => r.tier === tier).length,
  });

  let completionStatus: "SUCCESS" | "PARTIAL" | "FAILED";
  if (failed.length === 0 && completed.length > 0) {
    completionStatus = "SUCCESS";
  } else if (completed.length > 0) {
    completionStatus = "PARTIAL";
  } else {
    completionStatus = "FAILED";
  }

  return {
    success: completionStatus !== "FAILED",
    summary: {
      total: results.length,
      completed: completed.length,
      failed: failed.length,
      skipped: skipped.length,
      byTier: {
        free: byTier("free"),
        premium: byTier("premium"),
        kids: byTier("kids"),
      },
    },
    results,
    estimatedCost: estimateTTSCost(totalCharsProcessed),
    actualCost: estimateTTSCost(totalCharsProcessed),
    completionStatus,
  };
}

/**
 * Create empty summary
 */
function createEmptySummary() {
  return {
    total: 0,
    completed: 0,
    failed: 0,
    skipped: 0,
    byTier: {
      free: { total: 0, completed: 0, failed: 0 },
      premium: { total: 0, completed: 0, failed: 0 },
      kids: { total: 0, completed: 0, failed: 0 },
    },
  };
}

/**
 * Delay helper
 */
function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Error response helper
 */
function errorResponse(
  message: string,
  code: string,
  status: number,
  corsHeaders: Record<string, string>,
): Response {
  return new Response(
    JSON.stringify({ success: false, error: message, code }),
    {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
}
