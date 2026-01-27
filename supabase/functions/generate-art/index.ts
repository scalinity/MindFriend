// MindFriend Generate Art Edge Function
// Handles AI art generation with quota enforcement using OpenAI gpt-image-1-mini
// Supports streaming partial images for interactive UX

console.log("[BOOT] generate-art function loading...");

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2.49.1";

console.log("[BOOT] Supabase client imported successfully");

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
  console.log(
    "[RATELIMIT] Checking rate limit for user:",
    userId,
    "endpoint:",
    endpoint,
  );
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
      console.error(
        "[RATELIMIT] Rate limit check failed (failing closed):",
        error.code,
        error.message,
        error.details,
      );
      return {
        allowed: false,
        remaining: 0,
        resetAt: new Date(now.getTime() + config.windowMs),
        retryAfter: Math.ceil(config.windowMs / 1000),
      };
    }

    console.log("[RATELIMIT] Raw result:", JSON.stringify(data));
    const result = data?.[0];
    if (!result) {
      console.log("[RATELIMIT] No result, allowing by default");
      return {
        allowed: true,
        remaining: config.maxRequests,
        resetAt: new Date(now.getTime() + config.windowMs),
      };
    }

    const resetAt = new Date(result.reset_at);
    const retryAfter = result.allowed
      ? undefined
      : Math.ceil((resetAt.getTime() - now.getTime()) / 1000);

    console.log(
      "[RATELIMIT] Result - allowed:",
      result.allowed,
      "remaining:",
      result.remaining,
    );
    return {
      allowed: result.allowed,
      remaining: result.remaining,
      resetAt,
      retryAfter,
    };
  } catch (err) {
    console.error("[RATELIMIT] Exception during rate limit check:", err);
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
  console.error("[FATAL] Unhandled rejection:", event.reason);
  if (event.reason instanceof Error) {
    console.error("[FATAL] Stack:", event.reason.stack);
  }
  event.preventDefault();
});

// Catch uncaught errors
globalThis.addEventListener("error", (event) => {
  console.error("[FATAL] Uncaught error:", event.error);
  if (event.error instanceof Error) {
    console.error("[FATAL] Stack:", event.error.stack);
  }
});

console.log("[BOOT] Error handlers registered");

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

console.log("[BOOT] All definitions loaded, registering Deno.serve handler...");

Deno.serve(async (req) => {
  const requestId = crypto.randomUUID().slice(0, 8);
  console.log(`[${requestId}] ========== REQUEST START ==========`);
  console.log(`[${requestId}] Method: ${req.method}`);
  console.log(`[${requestId}] URL: ${req.url}`);
  console.log(
    `[${requestId}] Headers:`,
    JSON.stringify(Object.fromEntries(req.headers.entries())),
  );

  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);
  console.log(`[${requestId}] Origin: ${origin}, CORS headers generated`);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    console.log(`[${requestId}] Returning OPTIONS preflight response`);
    return new Response("ok", { headers: baseCorsHeaders });
  }

  try {
    // Check environment variables
    console.log(`[${requestId}] Checking environment variables...`);
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");

    console.log(
      `[${requestId}] SUPABASE_URL: ${supabaseUrl ? "SET (" + supabaseUrl.slice(0, 30) + "...)" : "MISSING"}`,
    );
    console.log(
      `[${requestId}] SUPABASE_SERVICE_ROLE_KEY: ${serviceRoleKey ? "SET (length: " + serviceRoleKey.length + ")" : "MISSING"}`,
    );
    console.log(
      `[${requestId}] SUPABASE_ANON_KEY: ${anonKey ? "SET (length: " + anonKey.length + ")" : "MISSING"}`,
    );
    console.log(
      `[${requestId}] OPENAI_API_KEY: ${openaiApiKey ? "SET (length: " + openaiApiKey.length + ")" : "MISSING"}`,
    );

    if (!supabaseUrl || !serviceRoleKey) {
      console.error(`[${requestId}] Missing required Supabase env vars`);
      return new Response(
        JSON.stringify({
          error: "Server configuration error",
          debug: "Missing Supabase env vars",
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Initialize Supabase admin client
    console.log(`[${requestId}] Creating Supabase admin client...`);
    let supabaseAdmin: SupabaseClient;
    try {
      supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);
      console.log(`[${requestId}] Supabase admin client created successfully`);
    } catch (err) {
      console.error(
        `[${requestId}] Failed to create Supabase admin client:`,
        err,
      );
      return new Response(
        JSON.stringify({
          error: "Failed to initialize database client",
          debug: String(err),
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Authenticate user
    console.log(`[${requestId}] Checking authorization header...`);
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      console.log(`[${requestId}] Missing authorization header`);
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }
    console.log(
      `[${requestId}] Auth header present, length: ${authHeader.length}`,
    );

    const token = authHeader.replace("Bearer ", "");
    console.log(
      `[${requestId}] Token extracted, length: ${token.length}, prefix: ${token.slice(0, 20)}...`,
    );

    console.log(`[${requestId}] Calling supabaseAdmin.auth.getUser()...`);
    let user;
    let authError;
    try {
      const authResult = await supabaseAdmin.auth.getUser(token);
      user = authResult.data?.user;
      authError = authResult.error;
      console.log(`[${requestId}] auth.getUser() completed`);
      console.log(`[${requestId}] User: ${user ? user.id : "null"}`);
      console.log(
        `[${requestId}] Auth error: ${authError ? JSON.stringify(authError) : "none"}`,
      );
    } catch (err) {
      console.error(`[${requestId}] Exception during auth.getUser():`, err);
      return new Response(
        JSON.stringify({ error: "Auth check failed", debug: String(err) }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (authError || !user) {
      console.log(
        `[${requestId}] Auth failed - error: ${authError?.message}, user: ${user ? "exists" : "null"}`,
      );
      return new Response(
        JSON.stringify({ error: "Invalid token", details: authError?.message }),
        {
          status: 401,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    console.log(`[${requestId}] User authenticated: ${user.id}`);

    // Create a user-scoped client for RPCs that depend on auth.uid()
    console.log(`[${requestId}] Creating user-scoped Supabase client...`);
    let supabaseUser: SupabaseClient;
    try {
      supabaseUser = createClient(supabaseUrl, anonKey!, {
        global: { headers: { Authorization: authHeader } },
      });
      console.log(`[${requestId}] User-scoped client created`);
    } catch (err) {
      console.error(`[${requestId}] Failed to create user-scoped client:`, err);
      return new Response(
        JSON.stringify({
          error: "Failed to initialize user client",
          debug: String(err),
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Rate limiting (5 per minute)
    console.log(`[${requestId}] Checking rate limit...`);
    let rateLimitResult: RateLimitResult;
    try {
      rateLimitResult = await checkRateLimit(
        supabaseAdmin,
        user.id,
        "generate-art",
        { windowMs: 60 * 1000, maxRequests: 5 },
      );
      console.log(
        `[${requestId}] Rate limit check completed - allowed: ${rateLimitResult.allowed}, remaining: ${rateLimitResult.remaining}`,
      );
    } catch (err) {
      console.error(`[${requestId}] Rate limit check exception:`, err);
      return new Response(
        JSON.stringify({
          error: "Rate limit check failed",
          debug: String(err),
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!rateLimitResult.allowed) {
      console.log(
        `[${requestId}] Rate limited - retry after: ${rateLimitResult.retryAfter}s`,
      );
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
    console.log(`[${requestId}] Parsing request body...`);
    let requestBody: GenerateArtRequest;
    try {
      const bodyText = await req.text();
      console.log(`[${requestId}] Body text length: ${bodyText.length}`);
      console.log(`[${requestId}] Body preview: ${bodyText.slice(0, 200)}`);
      requestBody = JSON.parse(bodyText);
      console.log(
        `[${requestId}] Body parsed successfully:`,
        JSON.stringify(requestBody),
      );
    } catch (err) {
      console.error(`[${requestId}] Failed to parse request body:`, err);
      return new Response(
        JSON.stringify({ error: "Invalid request format", debug: String(err) }),
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

    console.log(
      `[${requestId}] Request params - prompt: "${prompt?.slice(0, 50)}...", style: ${style}, stream: ${enableStreaming}`,
    );

    // Validate prompt
    if (!prompt || typeof prompt !== "string") {
      console.log(`[${requestId}] Invalid prompt: ${typeof prompt}`);
      return new Response(JSON.stringify({ error: "Prompt is required" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    if (prompt.length > MAX_PROMPT_LENGTH) {
      console.log(
        `[${requestId}] Prompt too long: ${prompt.length} > ${MAX_PROMPT_LENGTH}`,
      );
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
    console.log(`[${requestId}] Checking creative quota via RPC...`);
    let quotaData;
    let quotaError;
    try {
      const quotaResult = await supabaseUser.rpc("get_creative_quota");
      quotaData = quotaResult.data;
      quotaError = quotaResult.error;
      console.log(
        `[${requestId}] Quota RPC completed - data: ${JSON.stringify(quotaData)}, error: ${quotaError ? JSON.stringify(quotaError) : "none"}`,
      );
    } catch (err) {
      console.error(`[${requestId}] Quota RPC exception:`, err);
      return new Response(
        JSON.stringify({ error: "Failed to check quota", debug: String(err) }),
        {
          status: 500,
          headers: responseHeaders,
        },
      );
    }

    if (quotaError) {
      console.error(`[${requestId}] Quota check error:`, quotaError);
      return new Response(
        JSON.stringify({
          error: "Failed to check quota",
          details: quotaError.message,
        }),
        {
          status: 500,
          headers: responseHeaders,
        },
      );
    }

    const quota = quotaData?.[0];
    console.log(
      `[${requestId}] Quota - count: ${quota?.ai_art_count}, limit: ${quota?.ai_art_limit}, premium: ${quota?.is_premium}`,
    );

    if (quota && quota.ai_art_count >= quota.ai_art_limit) {
      console.log(`[${requestId}] Quota exceeded`);
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

    console.log(
      `[${requestId}] Enhanced prompt: "${enhancedPrompt.slice(0, 100)}..."`,
    );

    // Create generation record
    console.log(`[${requestId}] Creating generation record in database...`);
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
      console.log(
        `[${requestId}] Insert result - data: ${JSON.stringify(generationRecord)}, error: ${insertError ? JSON.stringify(insertError) : "none"}`,
      );
    } catch (err) {
      console.error(`[${requestId}] Insert exception:`, err);
      return new Response(
        JSON.stringify({
          error: "Failed to create generation record",
          debug: String(err),
        }),
        {
          status: 500,
          headers: responseHeaders,
        },
      );
    }

    if (insertError || !generationRecord) {
      console.error(`[${requestId}] Insert error:`, insertError);
      return new Response(
        JSON.stringify({
          error: "Failed to create generation record",
          details: insertError?.message,
        }),
        {
          status: 500,
          headers: responseHeaders,
        },
      );
    }

    console.log(
      `[${requestId}] Generation record created: ${generationRecord.id}`,
    );

    // Check OpenAI API key
    if (!openaiApiKey) {
      console.error(`[${requestId}] Missing OPENAI_API_KEY`);
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

    console.log(`[${requestId}] Streaming mode: ${!!enableStreaming}`);

    // Streaming mode - return SSE stream with partial images
    if (enableStreaming) {
      console.log(`[${requestId}] Starting streaming generation...`);

      console.log(`[${requestId}] Calling OpenAI streaming API...`);
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
              output_format: "png",
              stream: true,
              partial_images: 2,
            }),
          },
        );
        console.log(
          `[${requestId}] OpenAI response status: ${openaiResponse.status}`,
        );
      } catch (err) {
        console.error(`[${requestId}] OpenAI fetch exception:`, err);
        await updateGenerationStatus(
          supabaseAdmin,
          generationRecord.id,
          "failed",
          "Network error",
        );
        return new Response(
          JSON.stringify({
            error: "Failed to connect to AI service",
            debug: String(err),
          }),
          { status: 502, headers: responseHeaders },
        );
      }

      if (!openaiResponse.ok) {
        const errorText = await openaiResponse.text();
        console.error(
          `[${requestId}] OpenAI streaming error: ${openaiResponse.status} - ${errorText}`,
        );
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
            openaiError: errorText.slice(0, 500),
          }),
          { status: 502, headers: responseHeaders },
        );
      }

      // Create a TransformStream to proxy the SSE from OpenAI to the client
      console.log(`[${requestId}] Setting up TransformStream for SSE...`);
      const { readable, writable } = new TransformStream();
      const writer = writable.getWriter();
      const encoder = new TextEncoder();

      // Process the OpenAI SSE stream in the background
      (async () => {
        console.log(`[${requestId}] Starting background stream processor...`);
        const reader = openaiResponse.body?.getReader();
        if (!reader) {
          console.error(`[${requestId}] No response body reader`);
          await writer.write(
            encoder.encode(
              `data: ${JSON.stringify({ type: "error", error: "No response body" })}\n\n`,
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
              console.log(
                `[${requestId}] Stream done, final image: ${finalImageBase64 ? "received" : "missing"}`,
              );
              break;
            }

            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split("\n");
            buffer = lines.pop() || "";

            for (const line of lines) {
              if (line.startsWith("data: ")) {
                const data = line.slice(6);
                if (data === "[DONE]") {
                  console.log(`[${requestId}] Received [DONE] marker`);
                  continue;
                }

                try {
                  const event = JSON.parse(data);
                  console.log(
                    `[${requestId}] SSE event type: ${event.type || "unknown"}`,
                  );

                  // Handle partial image events
                  if (event.type === "image_generation.partial_image") {
                    partialCount++;
                    console.log(
                      `[${requestId}] Partial image ${partialCount} received`,
                    );
                    await writer.write(
                      encoder.encode(
                        `data: ${JSON.stringify({
                          type: "partial",
                          index: event.partial_image_index,
                          imageBase64: event.b64_json,
                          generationId: generationRecord.id,
                        })}\n\n`,
                      ),
                    );
                  }

                  // Handle completion event
                  if (event.type === "image_generation.completed") {
                    console.log(`[${requestId}] Completion event received`);
                    finalImageBase64 = event.b64_json;
                  }

                  // Handle result event (final image for some API versions)
                  if (event.data?.[0]?.b64_json) {
                    console.log(
                      `[${requestId}] Data array completion received`,
                    );
                    finalImageBase64 = event.data[0].b64_json;
                  }
                } catch {
                  // Skip non-JSON lines
                }
              }
            }
          }

          // After streaming completes, save the final image
          if (finalImageBase64) {
            console.log(
              `[${requestId}] Processing final image (length: ${finalImageBase64.length})...`,
            );
            const imageBuffer = base64ToUint8Array(finalImageBase64);
            const storagePath = `${user.id}/ai-art/${generationRecord.id}.png`;

            console.log(`[${requestId}] Uploading to storage: ${storagePath}`);
            const { error: uploadError } = await supabaseAdmin.storage
              .from("creative-works")
              .upload(storagePath, imageBuffer, {
                contentType: "image/png",
                upsert: true,
              });

            if (uploadError) {
              console.error(`[${requestId}] Upload error:`, uploadError);
              await updateGenerationStatus(
                supabaseAdmin,
                generationRecord.id,
                "failed",
                "Failed to store image",
              );
              await writer.write(
                encoder.encode(
                  `data: ${JSON.stringify({ type: "error", error: "Failed to store image", generationId: generationRecord.id })}\n\n`,
                ),
              );
            } else {
              console.log(`[${requestId}] Upload successful`);
              const { data: publicUrlData } = supabaseAdmin.storage
                .from("creative-works")
                .getPublicUrl(storagePath);

              const finalImageUrl = publicUrlData.publicUrl;
              console.log(`[${requestId}] Public URL: ${finalImageUrl}`);

              // Create creative work entry
              console.log(`[${requestId}] Creating creative work entry...`);
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
                console.error(`[${requestId}] Work creation error:`, workError);
                await updateGenerationStatus(
                  supabaseAdmin,
                  generationRecord.id,
                  "failed",
                  "Failed to create work record",
                );
              } else {
                console.log(
                  `[${requestId}] Creative work created: ${creativeWork.id}`,
                );

                await supabaseAdmin
                  .from("ai_art_generations")
                  .update({
                    creative_work_id: creativeWork.id,
                    image_url: finalImageUrl,
                    storage_path: storagePath,
                    generation_status: "completed",
                    completed_at: new Date().toISOString(),
                  })
                  .eq("id", generationRecord.id);

                console.log(`[${requestId}] Incrementing quota...`);
                await supabaseUser.rpc("increment_ai_art_quota");

                await writer.write(
                  encoder.encode(
                    `data: ${JSON.stringify({
                      type: "complete",
                      success: true,
                      generationId: generationRecord.id,
                      creativeWorkId: creativeWork.id,
                      imageUrl: finalImageUrl,
                      imageBase64: finalImageBase64,
                      prompt: prompt,
                      enhancedPrompt: enhancedPrompt,
                      style: style || null,
                    })}\n\n`,
                  ),
                );
                console.log(`[${requestId}] Complete event sent`);
              }
            }
          } else {
            console.error(`[${requestId}] No final image received from stream`);
            await updateGenerationStatus(
              supabaseAdmin,
              generationRecord.id,
              "failed",
              "No image generated",
            );
            await writer.write(
              encoder.encode(
                `data: ${JSON.stringify({ type: "error", error: "No image generated", generationId: generationRecord.id })}\n\n`,
              ),
            );
          }
        } catch (error) {
          console.error(`[${requestId}] Stream processing error:`, error);
          if (error instanceof Error) {
            console.error(`[${requestId}] Stack:`, error.stack);
          }
          try {
            await updateGenerationStatus(
              supabaseAdmin,
              generationRecord.id,
              "failed",
              "Stream error",
            );
          } catch (e) {
            console.error(
              `[${requestId}] Failed to update generation status:`,
              e,
            );
          }
          try {
            await writer.write(
              encoder.encode(
                `data: ${JSON.stringify({ type: "error", error: error instanceof Error ? error.message : "Stream error", generationId: generationRecord.id })}\n\n`,
              ),
            );
          } catch (e) {
            console.error(`[${requestId}] Failed to write error to stream:`, e);
          }
        } finally {
          try {
            await writer.close();
          } catch {
            /* already closed */
          }
          console.log(`[${requestId}] Stream processor finished`);
        }
      })().catch((err) => {
        console.error(`[${requestId}] [FATAL] Stream IIFE crash:`, err);
        if (err instanceof Error) {
          console.error(`[${requestId}] Stack:`, err.stack);
        }
      });

      console.log(`[${requestId}] Returning SSE response`);
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
    console.log(`[${requestId}] Starting non-streaming generation...`);
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => {
        console.log(`[${requestId}] Request timeout triggered`);
        controller.abort();
      }, API_TIMEOUT_MS);

      console.log(`[${requestId}] Calling OpenAI non-streaming API...`);
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
              output_format: "png",
            }),
            signal: controller.signal,
          },
        );
        console.log(
          `[${requestId}] OpenAI response status: ${openaiResponse.status}`,
        );
      } finally {
        clearTimeout(timeoutId);
      }

      if (!openaiResponse.ok) {
        const errorText = await openaiResponse.text();
        console.error(
          `[${requestId}] OpenAI API error: ${openaiResponse.status} - ${errorText}`,
        );
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
            openaiError: errorText.slice(0, 500),
          }),
          { status: 502, headers: responseHeaders },
        );
      }

      console.log(`[${requestId}] Parsing OpenAI response...`);
      const openaiData = await openaiResponse.json();
      const imageBase64 = openaiData.data?.[0]?.b64_json;

      if (!imageBase64) {
        console.error(
          `[${requestId}] No image in OpenAI response:`,
          JSON.stringify(openaiData).slice(0, 500),
        );
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

      console.log(
        `[${requestId}] Image received, length: ${imageBase64.length}`,
      );
      const imageBuffer = base64ToUint8Array(imageBase64);
      const storagePath = `${user.id}/ai-art/${generationRecord.id}.png`;

      console.log(`[${requestId}] Uploading to storage...`);
      const { error: uploadError } = await supabaseAdmin.storage
        .from("creative-works")
        .upload(storagePath, imageBuffer, {
          contentType: "image/png",
          upsert: true,
        });

      if (uploadError) {
        console.error(`[${requestId}] Upload error:`, uploadError);
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

      const { data: publicUrlData } = supabaseAdmin.storage
        .from("creative-works")
        .getPublicUrl(storagePath);

      const finalImageUrl = publicUrlData.publicUrl;
      console.log(`[${requestId}] Upload successful, URL: ${finalImageUrl}`);

      console.log(`[${requestId}] Creating creative work entry...`);
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
          `[${requestId}] Work creation error:`,
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
            imageUrl: finalImageUrl,
          }),
          { status: 500, headers: responseHeaders },
        );
      }

      console.log(`[${requestId}] Creative work created: ${creativeWork.id}`);

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

      console.log(`[${requestId}] Incrementing quota...`);
      await supabaseUser.rpc("increment_ai_art_quota");

      console.log(`[${requestId}] ========== REQUEST SUCCESS ==========`);
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
      console.error(`[${requestId}] API call error:`, apiError);
      if (apiError instanceof Error) {
        console.error(`[${requestId}] Stack:`, apiError.stack);
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
          debug: String(apiError),
        }),
        { status: 502, headers: responseHeaders },
      );
    }
  } catch (error) {
    console.error(`[${requestId}] ========== UNHANDLED ERROR ==========`);
    console.error(`[${requestId}] Error:`, error);
    if (error instanceof Error) {
      console.error(`[${requestId}] Message:`, error.message);
      console.error(`[${requestId}] Stack:`, error.stack);
    }
    return new Response(
      JSON.stringify({ error: "Internal server error", debug: String(error) }),
      {
        status: 500,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

console.log("[BOOT] Deno.serve handler registered successfully");

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
  console.log(
    `[STATUS] Updating generation ${generationId} to ${status}: ${errorMessage || "no error"}`,
  );
  try {
    await supabase
      .from("ai_art_generations")
      .update({
        generation_status: status,
        error_message: errorMessage || null,
        completed_at: status === "failed" ? new Date().toISOString() : null,
      })
      .eq("id", generationId);
    console.log(`[STATUS] Update successful`);
  } catch (err) {
    console.error(`[STATUS] Update failed:`, err);
  }
}
