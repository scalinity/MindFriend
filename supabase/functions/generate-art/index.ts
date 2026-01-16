// MindFriend Generate Art Edge Function
// Handles AI art generation with quota enforcement using OpenAI gpt-image-1-mini

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { decode as base64Decode } from "https://deno.land/std@0.168.0/encoding/base64.ts";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";

// Security constants - OpenAI gpt-image-1 supports up to 32000 chars, but we keep it reasonable
const MAX_PROMPT_LENGTH = 1000;
const API_TIMEOUT_MS = 60000; // 60 second timeout for OpenAI API

// Art style presets with their prompts
const STYLE_PRESETS: Record<string, { name: string; enhancer: string }> = {
  watercolor: {
    name: "Watercolor",
    enhancer:
      "soft watercolor painting style, delicate brushstrokes, pastel colors, artistic",
  },
  abstract: {
    name: "Abstract",
    enhancer:
      "abstract art style, bold colors, geometric shapes, modern art aesthetic",
  },
  serene: {
    name: "Serene",
    enhancer:
      "peaceful and calming scene, soft lighting, nature elements, tranquil atmosphere",
  },
  vibrant: {
    name: "Vibrant",
    enhancer:
      "bright vibrant colors, energetic composition, joyful and uplifting mood",
  },
  dreamy: {
    name: "Dreamy",
    enhancer:
      "dreamlike ethereal quality, soft focus, magical lighting, surreal elements",
  },
  minimalist: {
    name: "Minimalist",
    enhancer:
      "minimalist style, clean lines, simple composition, negative space",
  },
  expressive: {
    name: "Expressive",
    enhancer:
      "expressive emotional art, bold brushwork, dynamic movement, raw feeling",
  },
};

interface GenerateArtRequest {
  prompt: string;
  style?: string;
  moodScore?: number;
  moodTags?: string[];
}

interface GenerationRow {
  id: string;
  creative_work_id: string | null;
  image_url: string | null;
  storage_path: string | null;
  generation_status: string;
  error_message: string | null;
  completed_at: string | null;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: baseCorsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    // Rate limiting (5 per minute)
    const rateLimitResult = await checkRateLimit(
      supabaseAdmin,
      user.id,
      "generate-art",
      { windowMs: 60 * 1000, maxRequests: 5 },
    );
    if (!rateLimitResult.allowed) {
      return new Response(
        JSON.stringify({
          error: "Too many requests",
          message: "Please wait before generating more art.",
          retryAfter: rateLimitResult.retryAfter,
        }),
        {
          status: 429,
          headers: {
            ...baseCorsHeaders,
            "Content-Type": "application/json",
            ...getRateLimitHeaders(rateLimitResult),
          },
        },
      );
    }

    const responseHeaders = {
      ...baseCorsHeaders,
      "Content-Type": "application/json",
      ...getRateLimitHeaders(rateLimitResult),
    };

    // Parse request
    let requestBody: GenerateArtRequest;
    try {
      requestBody = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: "Invalid request format" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    const { prompt, style, moodScore, moodTags } = requestBody;

    // Validate prompt
    if (!prompt || typeof prompt !== "string") {
      return new Response(JSON.stringify({ error: "Prompt is required" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    if (prompt.length > MAX_PROMPT_LENGTH) {
      return new Response(
        JSON.stringify({
          error: `Prompt must be under ${MAX_PROMPT_LENGTH} characters`,
        }),
        { status: 400, headers: responseHeaders },
      );
    }

    // Validate and sanitize optional fields
    const validMoodScore =
      typeof moodScore === "number" &&
      !isNaN(moodScore) &&
      moodScore >= 1 &&
      moodScore <= 10
        ? moodScore
        : null;
    const validMoodTags = Array.isArray(moodTags)
      ? moodTags
          .filter((t): t is string => typeof t === "string" && t.length <= 50)
          .slice(0, 10)
      : null;

    // Check quota
    const { data: quotaData, error: quotaError } =
      await supabaseAdmin.rpc("get_creative_quota");

    if (quotaError) {
      console.error("Quota check error:", quotaError);
      return new Response(JSON.stringify({ error: "Failed to check quota" }), {
        status: 500,
        headers: responseHeaders,
      });
    }

    const quota = quotaData?.[0];
    if (quota && quota.ai_art_count >= quota.ai_art_limit) {
      return new Response(
        JSON.stringify({
          error: "Daily limit reached",
          message: quota.is_premium
            ? "You've used all 20 of today's AI art generations."
            : "You've used your free daily AI art generation. Upgrade to MindFriend Premium for 20 generations per day!",
          quotaExceeded: true,
        }),
        { status: 429, headers: responseHeaders },
      );
    }

    // Build enhanced prompt
    const stylePreset = style ? STYLE_PRESETS[style] : null;
    let enhancedPrompt = prompt;

    if (stylePreset) {
      enhancedPrompt = `${prompt}, ${stylePreset.enhancer}`;
    }

    // Add mood context if provided
    if (validMoodScore) {
      if (validMoodScore >= 7) {
        enhancedPrompt += ", uplifting joyful mood";
      } else if (validMoodScore <= 3) {
        enhancedPrompt += ", gentle soothing calming atmosphere";
      }
    }

    // Create generation record
    const { data: generationRecord, error: insertError } = await supabaseAdmin
      .from("ai_art_generations")
      .insert({
        user_id: user.id,
        user_prompt: prompt,
        enhanced_prompt: enhancedPrompt,
        style_preset: style || null,
        model_used: "gpt-image-1-mini",
        generation_status: "processing",
        is_premium_generation: quota?.is_premium || false,
      })
      .select("id")
      .single();

    if (insertError || !generationRecord) {
      console.error("Insert error:", insertError);
      return new Response(
        JSON.stringify({ error: "Failed to create generation record" }),
        {
          status: 500,
          headers: responseHeaders,
        },
      );
    }

    // Call OpenAI image generation API (gpt-image-1-mini)
    // Docs: https://platform.openai.com/docs/guides/images
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiApiKey) {
      await updateGenerationStatus(
        supabaseAdmin,
        generationRecord.id,
        "failed",
        "API not configured",
      );
      return new Response(
        JSON.stringify({ error: "Art generation not available" }),
        {
          status: 503,
          headers: responseHeaders,
        },
      );
    }

    try {
      // OpenAI Images API - gpt-image-1-mini returns base64 encoded images
      // Reference: https://platform.openai.com/docs/api-reference/images/create
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), API_TIMEOUT_MS);

      let openaiResponse: Response;
      try {
        openaiResponse = await fetch(
          "https://api.openai.com/v1/images/generations",
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${openaiApiKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              model: "gpt-image-1-mini",
              prompt: enhancedPrompt,
              n: 1,
              size: "1024x1024",
              quality: "medium",
            }),
            signal: controller.signal,
          },
        );
      } finally {
        clearTimeout(timeoutId);
      }

      if (!openaiResponse.ok) {
        const errorText = await openaiResponse.text();
        console.error("OpenAI API error:", errorText);
        await updateGenerationStatus(
          supabaseAdmin,
          generationRecord.id,
          "failed",
          "Generation failed",
        );
        return new Response(
          JSON.stringify({
            error: "Art generation failed",
            generationId: generationRecord.id,
          }),
          { status: 502, headers: responseHeaders },
        );
      }

      const openaiData = await openaiResponse.json();

      // GPT image models return base64 encoded images in b64_json field
      const imageBase64 = openaiData.data?.[0]?.b64_json;

      if (!imageBase64) {
        await updateGenerationStatus(
          supabaseAdmin,
          generationRecord.id,
          "failed",
          "No image returned",
        );
        return new Response(
          JSON.stringify({
            error: "No image generated",
            generationId: generationRecord.id,
          }),
          { status: 502, headers: responseHeaders },
        );
      }

      // Decode base64 to binary for storage upload
      const imageBuffer = base64Decode(imageBase64);

      const storagePath = `${user.id}/ai-art/${generationRecord.id}.png`;

      // Upload to Supabase Storage
      const { error: uploadError } = await supabaseAdmin.storage
        .from("creative-works")
        .upload(storagePath, imageBuffer, {
          contentType: "image/png",
          upsert: true,
        });

      if (uploadError) {
        console.error("Upload error:", uploadError);
        await updateGenerationStatus(
          supabaseAdmin,
          generationRecord.id,
          "failed",
          "Failed to store image",
        );
        return new Response(
          JSON.stringify({
            error: "Failed to store generated image",
            generationId: generationRecord.id,
          }),
          { status: 500, headers: responseHeaders },
        );
      }

      // Get public URL
      const { data: publicUrlData } = supabaseAdmin.storage
        .from("creative-works")
        .getPublicUrl(storagePath);

      const finalImageUrl = publicUrlData.publicUrl;

      // Create creative work entry
      const { data: creativeWork, error: workError } = await supabaseAdmin
        .from("creative_works")
        .insert({
          user_id: user.id,
          work_type: "ai_art",
          storage_path: storagePath,
          generation_prompt: prompt,
          art_style: style || null,
          generation_model: "gpt-image-1-mini",
          generation_params: { enhanced_prompt: enhancedPrompt },
          mood_score: validMoodScore,
          mood_tags: validMoodTags,
        })
        .select("id")
        .single();

      if (workError || !creativeWork) {
        console.error(
          "Work creation error:",
          workError?.message || "No data returned",
        );
        await updateGenerationStatus(
          supabaseAdmin,
          generationRecord.id,
          "failed",
          "Failed to create creative work record",
        );
        return new Response(
          JSON.stringify({
            error: "Failed to save generated art",
            generationId: generationRecord.id,
            imageUrl: finalImageUrl, // Provide URL for potential recovery
          }),
          { status: 500, headers: responseHeaders },
        );
      }

      // Update generation record
      await supabaseAdmin
        .from("ai_art_generations")
        .update({
          creative_work_id: creativeWork?.id || null,
          image_url: finalImageUrl,
          storage_path: storagePath,
          generation_status: "completed",
          completed_at: new Date().toISOString(),
        })
        .eq("id", generationRecord.id);

      // Increment quota
      await supabaseAdmin.rpc("increment_ai_art_quota");

      return new Response(
        JSON.stringify({
          success: true,
          generationId: generationRecord.id,
          creativeWorkId: creativeWork?.id || null,
          imageUrl: finalImageUrl,
          prompt: prompt,
          enhancedPrompt: enhancedPrompt,
          style: style || null,
        }),
        { status: 200, headers: responseHeaders },
      );
    } catch (apiError) {
      console.error("API call error:", apiError);
      await updateGenerationStatus(
        supabaseAdmin,
        generationRecord.id,
        "failed",
        "API error",
      );
      return new Response(
        JSON.stringify({
          error: "Art generation failed",
          generationId: generationRecord.id,
        }),
        { status: 502, headers: responseHeaders },
      );
    }
  } catch (error) {
    console.error("Unhandled error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    });
  }
});

async function updateGenerationStatus(
  supabase: SupabaseClient,
  generationId: string,
  status: string,
  errorMessage?: string,
) {
  await supabase
    .from("ai_art_generations")
    .update({
      generation_status: status,
      error_message: errorMessage || null,
      completed_at: status === "failed" ? new Date().toISOString() : null,
    })
    .eq("id", generationId);
}
