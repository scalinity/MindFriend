// MindFriend Generate Profile Picture Edge Function
// Handles AI profile picture generation with quota enforcement using OpenAI gpt-image-1-mini

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";

// Security constants
const MAX_PROMPT_LENGTH = 200;
const API_TIMEOUT_MS = 60000; // 60 second timeout for OpenAI API

interface GenerateProfilePictureRequest {
  prompt: string;
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
      "generate-profile-picture",
      { windowMs: 60 * 1000, maxRequests: 5 },
    );
    if (!rateLimitResult.allowed) {
      return new Response(
        JSON.stringify({
          error: "Too many requests",
          message: "Please wait before generating more profile pictures.",
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
    let requestBody: GenerateProfilePictureRequest;
    try {
      requestBody = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: "Invalid request format" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    const { prompt } = requestBody;

    // Validate prompt
    if (!prompt || typeof prompt !== "string") {
      return new Response(JSON.stringify({ error: "Prompt is required" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    const trimmedPrompt = prompt.trim();
    if (trimmedPrompt.length < 3) {
      return new Response(
        JSON.stringify({ error: "Prompt must be at least 3 characters" }),
        { status: 400, headers: responseHeaders },
      );
    }

    if (trimmedPrompt.length > MAX_PROMPT_LENGTH) {
      return new Response(
        JSON.stringify({
          error: `Prompt must be under ${MAX_PROMPT_LENGTH} characters`,
        }),
        { status: 400, headers: responseHeaders },
      );
    }

    // Check quota (shared with AI art generation)
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
            ? "You've used all 20 of today's AI profile picture generations."
            : "You've used your 3 free daily AI profile picture generations. Upgrade to MindFriend Premium for 20 generations per day!",
          quotaExceeded: true,
        }),
        { status: 429, headers: responseHeaders },
      );
    }
    
    // CRITICAL: Increment quota BEFORE generation to prevent race condition
    // If OpenAI call fails, quota will still be consumed (prevents abuse)
    const { error: incrementError } = await supabaseAdmin.rpc(
      "increment_ai_art_quota",
      { user_id: user.id },
    );
    
    if (incrementError) {
      console.error("Failed to increment quota:", incrementError);
      return new Response(JSON.stringify({ error: "Failed to update quota" }), {
        status: 500,
        headers: responseHeaders,
      });
    }

    // Content moderation using OpenAI Moderation API
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiApiKey) {
      return new Response(
        JSON.stringify({
          error: "AI generation not available",
          message: "Profile picture generation is temporarily unavailable.",
        }),
        { status: 503, headers: responseHeaders },
      );
    }

    try {
      const moderationResponse = await fetch(
        "https://api.openai.com/v1/moderations",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${openaiApiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ input: trimmedPrompt }),
        },
      );

      if (!moderationResponse.ok) {
        // CRITICAL: Fail-closed - don't proceed if moderation unavailable
        console.error(
          "Moderation API failed:",
          moderationResponse.status,
          await moderationResponse.text(),
        );
        return new Response(
          JSON.stringify({
            error: "Moderation unavailable",
            message:
              "Content moderation is temporarily unavailable. Please try again later.",
          }),
          { status: 503, headers: responseHeaders },
        );
      }

      const moderationData = await moderationResponse.json();
      const flagged = moderationData.results?.[0]?.flagged;

      if (flagged) {
        return new Response(
          JSON.stringify({
            error: "Inappropriate content",
            message:
              "This prompt contains inappropriate content. Please try a different description.",
          }),
          { status: 400, headers: responseHeaders },
        );
      }
    } catch (moderationError) {
      // CRITICAL: Fail-closed - don't proceed if moderation fails
      console.error("Moderation API error:", moderationError);
      return new Response(
        JSON.stringify({
          error: "Moderation failed",
          message:
            "Unable to verify content safety. Please try again later.",
        }),
        { status: 503, headers: responseHeaders },
      );
    }

    // Build enhanced prompt for therapeutic/appropriate content
    const enhancedPrompt = `A friendly, professional, therapeutic-appropriate profile picture: ${trimmedPrompt}. Style: warm, approachable, positive, suitable for all ages. Avoid: text, logos, realistic faces, violence, drugs.`;

    // Call OpenAI Image Generation API
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), API_TIMEOUT_MS);

    try {
      const openaiResponse = await fetch(
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
            size: "512x512",
            quality: "standard",
            response_format: "b64_json",
            // Removed: stream and partial_images are not supported by Images API
          }),
          signal: controller.signal,
        },
      );

      if (!openaiResponse.ok) {
        const errorText = await openaiResponse.text();
        console.error("OpenAI API error:", openaiResponse.status, errorText);
        return new Response(
          JSON.stringify({
            error: "Image generation failed",
            message: "Failed to generate image. Please try again.",
          }),
          {
            status: 500,
            headers: responseHeaders,
          },
        );
      }

      const openaiData = await openaiResponse.json();
      const finalImageBase64 = openaiData.data?.[0]?.b64_json;

      if (!finalImageBase64) {
        console.error("No image data in OpenAI response");
        return new Response(
          JSON.stringify({
            error: "Generation failed",
            message: "No image was generated. Please try again.",
          }),
          {
            status: 500,
            headers: responseHeaders,
          },
        );
      }

      // Calculate remaining quota for free users
      let quotaRemaining: number | null = null;
      if (quota && !quota.is_premium) {
        quotaRemaining = Math.max(
          0,
          quota.ai_art_limit - (quota.ai_art_count + 1),
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          imageBase64: finalImageBase64,
          quotaRemaining: quotaRemaining,
        }),
        { status: 200, headers: responseHeaders },
      );
    } catch (apiError) {
      console.error("API call error:", apiError);
      return new Response(
        JSON.stringify({
          error: "Generation failed",
          message:
            apiError instanceof Error && apiError.name === "AbortError"
              ? "Generation timed out. Please try again."
              : "Failed to generate profile picture. Please try again.",
        }),
        { status: 502, headers: responseHeaders },
      );
    } finally {
      clearTimeout(timeoutId);
    }
  } catch (error) {
    console.error("Unhandled error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
    });
  }
});
