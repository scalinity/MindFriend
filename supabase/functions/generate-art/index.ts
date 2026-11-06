// MindFriend Generate Art Edge Function
// Handles AI art generation with quota enforcement using OpenAI gpt-image-1-mini
// Supports streaming partial images for interactive UX

import {
  createClient,
  type SupabaseClient,
} from "jsr:@supabase/supabase-js@2.118.0";
import {
  MonthlyAIBudgetExhaustedError,
  reserveMonthlyAIBudget,
} from "../_shared/monthly-ai-budget.ts";

// --- Inlined from _shared/cors.ts (eliminates bundler path resolution issues) ---

const ALLOWED_ORIGINS = [
  "capacitor://localhost",
  "ionic://localhost",
  "http://localhost:3000",
  "http://localhost:5173",
  "https://getmindfriend.app",
];

function getCorsHeaders(origin: string | null): Record<string, string> {
  let allowedOrigin: string;
  if (!origin) {
    allowedOrigin = "null";
  } else if (ALLOWED_ORIGINS.includes(origin)) {
    allowedOrigin = origin;
  } else {
    allowedOrigin = "null";
  }
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "X-XSS-Protection": "1; mode=block",
  };
}

// --- Inlined from _shared/ratelimit.ts (eliminates bundler path resolution issues) ---

interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetAt: Date;
  retryAfter?: number;
}

interface RateLimitConfig {
  windowMs: number;
  maxRequests: number;
}

async function checkRateLimit(
  supabase: SupabaseClient,
  userId: string,
  endpoint: string,
  config: RateLimitConfig = { windowMs: 60 * 1000, maxRequests: 10 },
): Promise<RateLimitResult> {
  const now = new Date();
  const windowStart = new Date(now.getTime() - config.windowMs);

  try {
    const { data, error } = await supabase.rpc("check_rate_limit", {
      p_user_id: userId,
      p_endpoint: endpoint,
      p_window_start: windowStart.toISOString(),
      p_max_requests: config.maxRequests,
      p_window_ms: config.windowMs,
    });

    if (error) {
      console.error("[generate-art] Operation failed");
      return {
        allowed: false,
        remaining: 0,
        resetAt: new Date(now.getTime() + config.windowMs),
        retryAfter: Math.ceil(config.windowMs / 1000),
      };
    }

    const result = data?.[0];
    if (!result) {
      return {
        allowed: false,
        remaining: 0,
        resetAt: new Date(now.getTime() + config.windowMs),
      };
    }

    const resetAt = new Date(result.reset_at);
    const retryAfter = result.allowed
      ? undefined
      : Math.ceil((resetAt.getTime() - now.getTime()) / 1000);

    return {
      allowed: result.allowed,
      remaining: result.remaining,
      resetAt,
      retryAfter,
    };
  } catch (err) {
    console.error("[generate-art] Operation failed");
    return {
      allowed: false,
      remaining: 0,
      resetAt: new Date(now.getTime() + config.windowMs),
      retryAfter: Math.ceil(config.windowMs / 1000),
    };
  }
}

function getRateLimitHeaders(result: RateLimitResult): Record<string, string> {
  const headers: Record<string, string> = {
    "X-RateLimit-Remaining": String(result.remaining),
    "X-RateLimit-Reset": String(Math.floor(result.resetAt.getTime() / 1000)),
  };
  if (result.retryAfter) {
    headers["Retry-After"] = String(result.retryAfter);
  }
  return headers;
}

// Catch unhandled promise rejections to prevent worker crashes
globalThis.addEventListener("unhandledrejection", (event) => {
  console.error("[generate-art] Operation failed");
  if (event.reason instanceof Error) {
    console.error("[generate-art] Operation failed");
  }
  event.preventDefault();
});

// Catch uncaught errors
globalThis.addEventListener("error", (event) => {
  console.error("[generate-art] Operation failed");
  if (event.error instanceof Error) {
    console.error("[generate-art] Operation failed");
  }
});

// Security constants - OpenAI gpt-image-1 supports up to 32000 chars, but we keep it reasonable
const MAX_PROMPT_LENGTH = 1000;
const API_TIMEOUT_MS = 120000; // 120 second timeout for OpenAI API (streaming needs more time)

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
  stream?: boolean;
}

Deno.serve(async (req) => {
  const requestId = crypto.randomUUID().slice(0, 8);

  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: baseCorsHeaders });
  }

  try {
    // Check environment variables

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      console.error("[generate-art] Operation failed");
      return new Response(
        JSON.stringify({
          error: "Server configuration error",
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Initialize Supabase admin client

    let supabaseAdmin: SupabaseClient;
    try {
      supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);
    } catch (err) {
      console.error("[generate-art] Operation failed");
      return new Response(
        JSON.stringify({
          error: "Failed to initialize database client",
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Authenticate user

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");

    let user;
    let authError;
    try {
      const authResult = await supabaseAdmin.auth.getUser(token);
      user = authResult.data?.user;
      authError = authResult.error;
    } catch (err) {
      console.error("[generate-art] Operation failed");
      return new Response(
        JSON.stringify({ error: "Auth check failed" }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid token" }),
        {
          status: 401,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create a user-scoped client for RPCs that depend on auth.uid()

    let supabaseUser: SupabaseClient;
    try {
      supabaseUser = createClient(supabaseUrl, anonKey!, {
        global: { headers: { Authorization: authHeader } },
      });
    } catch (err) {
      console.error("[generate-art] Operation failed");
      return new Response(
        JSON.stringify({
          error: "Failed to initialize user client",
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Rate limiting (5 per minute)

    let rateLimitResult: RateLimitResult;
    try {
      rateLimitResult = await checkRateLimit(
        supabaseAdmin,
        user.id,
        "generate-art",
        { windowMs: 60 * 1000, maxRequests: 5 },
      );
    } catch (err) {
      console.error("[generate-art] Operation failed");
      return new Response(
        JSON.stringify({
          error: "Rate limit check failed",
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

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

    // Parse request body

    let requestBody: GenerateArtRequest;
    try {
      const bodyText = await req.text();

      requestBody = JSON.parse(bodyText);
    } catch (err) {
      console.error("[generate-art] Operation failed");
      return new Response(
        JSON.stringify({ error: "Invalid request format" }),
        {
          status: 400,
          headers: responseHeaders,
        },
      );
    }

    const {
      prompt,
      style,
      moodScore,
      moodTags,
      stream: enableStreaming,
    } = requestBody;

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
    const validMoodScore = typeof moodScore === "number" &&
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

    let quotaData;
    let quotaError;
    try {
      const quotaResult = await supabaseUser.rpc("get_creative_quota");
      quotaData = quotaResult.data;
      quotaError = quotaResult.error;
    } catch (err) {
      console.error("[generate-art] Operation failed");
      return new Response(
        JSON.stringify({ error: "Failed to check quota" }),
        {
          status: 500,
          headers: responseHeaders,
        },
      );
    }

    if (quotaError) {
      console.error("[generate-art] Operation failed");
      return new Response(
        JSON.stringify({
          error: "Failed to check quota",
        }),
        {
          status: 500,
          headers: responseHeaders,
        },
      );
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

    if (!openaiApiKey) {
      return new Response(
        JSON.stringify({ error: "Art generation not available" }),
        { status: 503, headers: responseHeaders },
      );
    }
    const providerAbort = new AbortController();
    const providerSignal = AbortSignal.any([
      req.signal,
      providerAbort.signal,
      AbortSignal.timeout(120000),
    ]);

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

    // The request is pinned to one 1024-square generation with no image inputs.
    // Omitted quality is priced at high ($0.036); each partial adds 100 output
    // tokens ($0.0008). UTF-8 prompt bytes bound text tokens at $2/M, with
    // 1024 additional input tokens covering request framing conservatively.
    const providerBody = JSON.stringify({
      model: "gpt-image-1-mini",
      prompt: enhancedPrompt,
      n: 1,
      size: "1024x1024",
      output_format: "png",
      ...(enableStreaming ? { stream: true, partial_images: 2 } : {}),
    });
    try {
      await reserveMonthlyAIBudget(supabaseAdmin, {
        requestId: crypto.randomUUID(),
        userId: user.id,
        feature: "art.image",
        reserveMicrodollars: Math.ceil(
          (new TextEncoder().encode(JSON.stringify(enhancedPrompt)).length +
                1024) *
              2 + 36_000 + (enableStreaming ? 2 * 800 : 0),
        ),
      }, req.signal);
    } catch (error) {
      const exhausted = error instanceof MonthlyAIBudgetExhaustedError;
      return new Response(
        JSON.stringify({
          error: exhausted
            ? "Monthly AI budget reached"
            : "AI budget unavailable",
          code: exhausted
            ? "monthly_ai_budget_exhausted"
            : "monthly_ai_budget_unavailable",
        }),
        {
          status: exhausted ? 429 : 503,
          headers: responseHeaders,
        },
      );
    }

    const { data: reserved, error: reservationError } = await supabaseAdmin.rpc(
      "reserve_ai_image_quota",
      { p_user_id: user.id },
    );
    if (reservationError || !reserved) {
      return new Response(
        JSON.stringify({
          error: reservationError
            ? "Image quota unavailable"
            : "Daily image allowance reached",
          quotaExceeded: !reservationError,
        }),
        { status: reservationError ? 503 : 429, headers: responseHeaders },
      );
    }

    // Create generation record

    let generationRecord;
    let insertError;
    try {
      const insertResult = await supabaseAdmin
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
      generationRecord = insertResult.data;
      insertError = insertResult.error;
    } catch (err) {
      console.error("[generate-art] Operation failed");
      return new Response(
        JSON.stringify({
          error: "Failed to create generation record",
        }),
        {
          status: 500,
          headers: responseHeaders,
        },
      );
    }

    if (insertError || !generationRecord) {
      console.error("[generate-art] Operation failed");
      return new Response(
        JSON.stringify({
          error: "Failed to create generation record",
        }),
        {
          status: 500,
          headers: responseHeaders,
        },
      );
    }

    // Check OpenAI API key
    if (!openaiApiKey) {
      console.error("[generate-art] Operation failed");
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

    // Streaming mode - return SSE stream with partial images
    if (enableStreaming) {
      let openaiResponse: Response;
      try {
        openaiResponse = await fetch(
          "https://api.openai.com/v1/images/generations",
          {
            method: "POST",
            signal: providerSignal,
            headers: {
              Authorization: `Bearer ${openaiApiKey}`,
              "Content-Type": "application/json",
            },
            body: providerBody,
          },
        );
      } catch (err) {
        console.error("[generate-art] Operation failed");
        await updateGenerationStatus(
          supabaseAdmin,
          generationRecord.id,
          "failed",
          "Network error",
        );
        return new Response(
          JSON.stringify({
            error: "Failed to connect to AI service",
          }),
          { status: 502, headers: responseHeaders },
        );
      }

      if (!openaiResponse.ok) {
        await openaiResponse.body?.cancel();
        console.error("[generate-art] Operation failed");
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
            openaiStatus: openaiResponse.status,
          }),
          { status: 502, headers: responseHeaders },
        );
      }

      // Create a TransformStream to proxy the SSE from OpenAI to the client

      const { readable, writable } = new TransformStream();
      const writer = writable.getWriter();
      void writer.closed.catch(() => providerAbort.abort());
      const encoder = new TextEncoder();

      // Process the OpenAI SSE stream in the background
      (async () => {
        const reader = openaiResponse.body?.getReader();
        if (!reader) {
          console.error("[generate-art] Operation failed");
          await writer.write(
            encoder.encode(
              `data: ${
                JSON.stringify({ type: "error", error: "No response body" })
              }\n\n`,
            ),
          );
          try {
            await writer.close();
          } catch {
            /* already closed */
          }
          return;
        }

        const decoder = new TextDecoder();
        let buffer = "";
        let finalImageBase64: string | null = null;
        let partialCount = 0;

        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) {
              break;
            }

            buffer += decoder.decode(value, { stream: true });
            if (buffer.length > 8 * 1024 * 1024) {
              throw new Error("Image stream exceeded the size limit");
            }
            const lines = buffer.split("\n");
            buffer = lines.pop() || "";

            for (const line of lines) {
              if (line.startsWith("data: ")) {
                const data = line.slice(6);
                if (data === "[DONE]") {
                  continue;
                }

                let event;
                try {
                  event = JSON.parse(data);
                } catch {
                  continue;
                }
                {
                  // Handle partial image events
                  if (event.type === "image_generation.partial_image") {
                    partialCount++;

                    await writer.write(
                      encoder.encode(
                        `data: ${
                          JSON.stringify({
                            type: "partial",
                            index: event.partial_image_index,
                            imageBase64: event.b64_json,
                            generationId: generationRecord.id,
                          })
                        }\n\n`,
                      ),
                    );
                  }

                  // Handle completion event
                  if (event.type === "image_generation.completed") {
                    finalImageBase64 = event.b64_json;
                  }

                  // Handle result event (final image for some API versions)
                  if (event.data?.[0]?.b64_json) {
                    finalImageBase64 = event.data[0].b64_json;
                  }
                }
              }
            }
          }

          // After streaming completes, save the final image
          if (finalImageBase64) {
            const imageBuffer = base64ToUint8Array(finalImageBase64);
            const storagePath = `${user.id}/ai-art/${generationRecord.id}.png`;

            const { error: uploadError } = await supabaseAdmin.storage
              .from("creative-works")
              .upload(storagePath, imageBuffer, {
                contentType: "image/png",
                upsert: true,
              });

            if (uploadError) {
              console.error("[generate-art] Operation failed");
              await updateGenerationStatus(
                supabaseAdmin,
                generationRecord.id,
                "failed",
                "Failed to store image",
              );
              await writer.write(
                encoder.encode(
                  `data: ${
                    JSON.stringify({
                      type: "error",
                      error: "Failed to store image",
                      generationId: generationRecord.id,
                    })
                  }\n\n`,
                ),
              );
            } else {
              const { data: publicUrlData, error: signingError } =
                await supabaseAdmin.storage
                  .from("creative-works")
                  .createSignedUrl(storagePath, 3600);

              if (signingError || !publicUrlData?.signedUrl) {
                throw new Error("Unable to open generated art");
              }
              const finalImageUrl = publicUrlData.signedUrl;

              // Create creative work entry

              const { data: creativeWork, error: workError } =
                await supabaseAdmin
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
                console.error("[generate-art] Operation failed");
                await updateGenerationStatus(
                  supabaseAdmin,
                  generationRecord.id,
                  "failed",
                  "Failed to create work record",
                );
                throw new Error("Unable to save generated art");
              } else {
                await supabaseAdmin
                  .from("ai_art_generations")
                  .update({
                    creative_work_id: creativeWork.id,
                    image_url:
                      `${supabaseUrl}/storage/v1/object/public/creative-works/${storagePath}`,
                    storage_path: storagePath,
                    generation_status: "completed",
                    completed_at: new Date().toISOString(),
                  })
                  .eq("id", generationRecord.id);

                // Usage was reserved before contacting the provider.

                await writer.write(
                  encoder.encode(
                    `data: ${
                      JSON.stringify({
                        type: "complete",
                        success: true,
                        generationId: generationRecord.id,
                        creativeWorkId: creativeWork.id,
                        imageUrl: finalImageUrl,
                        imageBase64: finalImageBase64,
                        prompt: prompt,
                        enhancedPrompt: enhancedPrompt,
                        style: style || null,
                      })
                    }\n\n`,
                  ),
                );
              }
            }
          } else {
            console.error("[generate-art] Operation failed");
            await updateGenerationStatus(
              supabaseAdmin,
              generationRecord.id,
              "failed",
              "No image generated",
            );
            await writer.write(
              encoder.encode(
                `data: ${
                  JSON.stringify({
                    type: "error",
                    error: "No image generated",
                    generationId: generationRecord.id,
                  })
                }\n\n`,
              ),
            );
          }
        } catch (error) {
          console.error("[generate-art] Operation failed");
          if (error instanceof Error) {
            console.error("[generate-art] Operation failed");
          }
          try {
            await updateGenerationStatus(
              supabaseAdmin,
              generationRecord.id,
              "failed",
              "Stream error",
            );
          } catch (e) {
            console.error("[generate-art] Operation failed");
          }
          try {
            await writer.write(
              encoder.encode(
                `data: ${
                  JSON.stringify({
                    type: "error",
                    error: "Image stream failed",
                    generationId: generationRecord.id,
                  })
                }\n\n`,
              ),
            );
          } catch (e) {
            console.error("[generate-art] Operation failed");
          }
        } finally {
          await reader.cancel().catch(() => {});
          reader.releaseLock();
          try {
            await writer.close();
          } catch {
            /* already closed */
          }
        }
      })().catch((err) => {
        console.error("[generate-art] Operation failed");
        if (err instanceof Error) {
          console.error("[generate-art] Operation failed");
        }
      });

      return new Response(readable, {
        headers: {
          ...baseCorsHeaders,
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          Connection: "keep-alive",
        },
      });
    }

    // Non-streaming mode (backward compatible)

    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => {
        controller.abort();
      }, API_TIMEOUT_MS);

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
            body: providerBody,
            signal: AbortSignal.any([providerSignal, controller.signal]),
          },
        );
      } finally {
        clearTimeout(timeoutId);
      }

      if (!openaiResponse.ok) {
        await openaiResponse.body?.cancel();
        console.error("[generate-art] Operation failed");
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
            openaiStatus: openaiResponse.status,
          }),
          { status: 502, headers: responseHeaders },
        );
      }

      const openaiData = await openaiResponse.json();
      const imageBase64 = openaiData.data?.[0]?.b64_json;

      if (!imageBase64) {
        console.error("[generate-art] Operation failed");
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

      const imageBuffer = base64ToUint8Array(imageBase64);
      const storagePath = `${user.id}/ai-art/${generationRecord.id}.png`;

      const { error: uploadError } = await supabaseAdmin.storage
        .from("creative-works")
        .upload(storagePath, imageBuffer, {
          contentType: "image/png",
          upsert: true,
        });

      if (uploadError) {
        console.error("[generate-art] Operation failed");
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

      const { data: publicUrlData, error: signingError } = await supabaseAdmin
        .storage
        .from("creative-works")
        .createSignedUrl(storagePath, 3600);

      if (signingError || !publicUrlData?.signedUrl) {
        throw new Error("Unable to open generated art");
      }
      const finalImageUrl = publicUrlData.signedUrl;

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
        console.error("[generate-art] Operation failed");
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
            imageUrl: finalImageUrl,
          }),
          { status: 500, headers: responseHeaders },
        );
      }

      await supabaseAdmin
        .from("ai_art_generations")
        .update({
          creative_work_id: creativeWork?.id || null,
          image_url:
            `${supabaseUrl}/storage/v1/object/public/creative-works/${storagePath}`,
          storage_path: storagePath,
          generation_status: "completed",
          completed_at: new Date().toISOString(),
        })
        .eq("id", generationRecord.id);

      // Usage was reserved before contacting the provider.

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
      console.error("[generate-art] Operation failed");
      if (apiError instanceof Error) {
        console.error("[generate-art] Operation failed");
      }
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
    console.error("[generate-art] Operation failed");
    console.error("[generate-art] Operation failed");
    if (error instanceof Error) {
      console.error("[generate-art] Operation failed");
      console.error("[generate-art] Operation failed");
    }
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

// Helper: Convert base64 string to Uint8Array using built-in atob
function base64ToUint8Array(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function updateGenerationStatus(
  supabase: SupabaseClient,
  generationId: string,
  status: string,
  errorMessage?: string,
) {
  try {
    await supabase
      .from("ai_art_generations")
      .update({
        generation_status: status,
        error_message: errorMessage || null,
        completed_at: status === "failed" ? new Date().toISOString() : null,
      })
      .eq("id", generationId);
  } catch (err) {
    console.error("[generate-art] Operation failed");
  }
}
