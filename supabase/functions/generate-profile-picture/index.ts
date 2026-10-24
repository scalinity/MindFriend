// MindFriend Generate Profile Picture Edge Function
// Supports streaming partial images for interactive UX with full persistence

import { createClient } from "jsr:@supabase/supabase-js@2.49.1";
import {
  MonthlyAIBudgetExhaustedError,
  reserveMonthlyAIBudget,
} from "../_shared/monthly-ai-budget.ts";

import {
  AvatarError,
  decodeBase64,
  decodeJPEG,
  failure,
  MAX_PROVIDER_BYTES,
  readProviderEvents,
  readProviderJSON,
} from "./image.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};


export async function handler(req: Request): Promise<Response> {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const providerAbort = new AbortController();
  const signal = AbortSignal.any([req.signal, providerAbort.signal]);
  let timeout: ReturnType<typeof setTimeout> | undefined;
  let streaming = false;
  const cleanup = () => {
    clearTimeout(timeout);
    providerAbort.abort();
  };
  const errorBody = (error: AvatarError) => ({
    error: error.message,
    message: error.message,
    code: error.code,
  });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !supabaseServiceKey || !anonKey) {
      return json({
        error: "Server configuration error",
        code: "server_configuration_error",
      }, 500);
    }
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);
    const authHeader = req.headers.get("Authorization");
    const token = authHeader?.match(/^Bearer\s+(\S+)$/i)?.[1];
    if (!token) {
      return json(
        { error: "Missing authorization", code: "unauthorized" },
        401,
      );
    }
    const { data: { user }, error: authError } = await supabaseAdmin.auth
      .getUser(token);
    if (authError || !user) {
      return json({ error: "Invalid token", code: "unauthorized" }, 401);
    }
    if (user.is_anonymous) {
      return json({
        error: "Sign in to generate an avatar.",
        code: "sign_in_required",
      }, 403);
    }

    let body;
    try {
      body = await req.json();
    } catch {
      return json({ error: "Invalid JSON", code: "invalid_request" }, 400);
    }
    const prompt = typeof body?.prompt === "string" ? body.prompt.trim() : "";
    const enableStreaming = body?.stream === true;
    const promptLength =
      [...new Intl.Segmenter("en", { granularity: "grapheme" }).segment(prompt)]
        .length;
    if (promptLength < 3 || promptLength > 200) {
      return json({
        error: "Prompt must be between 3 and 200 characters",
        code: "invalid_prompt",
      }, 400);
    }
    for (const field of ["userId", "user_id", "ownerId", "owner_id", "owner"]) {
      if (body[field] !== undefined && body[field] !== user.id) {
        return json({
          error: "An avatar can only be generated for the signed-in account.",
          code: "owner_mismatch",
        }, 403);
      }
    }
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiApiKey) {
      return json({ error: "AI not configured", code: "ai_unavailable" }, 503);
    }

    // Storage and read-only quota calls carry the verified caller's JWT and obey RLS.
    const supabaseUser = createClient(supabaseUrl, anonKey, {
      global: {
        headers: { Authorization: authHeader! },
        fetch: (input, init) =>
          fetch(input, {
            ...init,
            signal: init?.signal
              ? AbortSignal.any([signal, init.signal])
              : signal,
          }),
      },
    });
    const { data: quotaData, error: quotaError } = await supabaseUser.rpc(
      "get_creative_quota",
    );
    if (quotaError) {
      return json({
        error: "Failed to check quota",
        code: "image_quota_unavailable",
      }, 503);
    }
    const quota = quotaData?.[0];
    if (quota && quota.ai_art_count >= quota.ai_art_limit) {
      return json({
        error: "Daily limit reached",
        message: quota.is_premium
          ? "You've used all of today's AI generations."
          : "You've used your free daily AI generation. Upgrade to MindFriend Premium for more!",
        quotaExceeded: true,
      }, 429);
    }

    const enhancedPrompt =
      `A friendly profile picture: ${prompt}. Style: warm, approachable, suitable for all ages.`;
    // One 1024-square image, no image inputs.
    // High bounds omitted quality ($0.036); each partial adds 100 output tokens.
    // UTF-8 prompt bytes bound $2/M text tokens plus 1024 framing tokens.
    const providerBody = JSON.stringify({
      model: "gpt-image-1-mini",
      prompt: enhancedPrompt,
      n: 1,
      size: "1024x1024",
      output_format: "jpeg",
      output_compression: 80,
      ...(enableStreaming ? { stream: true, partial_images: 2 } : {}),
    });
    try {
      await reserveMonthlyAIBudget(supabaseAdmin, {
        requestId: crypto.randomUUID(),
        userId: user.id,
        feature: "profile.image",
        reserveMicrodollars: Math.ceil(
          (new TextEncoder().encode(JSON.stringify(enhancedPrompt)).length +
                1024) *
              2 + 36_000 + (enableStreaming ? 2 * 800 : 0),
        ),
      }, req.signal);
    } catch (error) {
      const exhausted = error instanceof MonthlyAIBudgetExhaustedError;
      return json({
        error: exhausted
          ? "Monthly AI budget reached"
          : "AI budget unavailable",
        code: exhausted
          ? "monthly_ai_budget_exhausted"
          : "monthly_ai_budget_unavailable",
      }, exhausted ? 429 : 503);
    }
    const { data: reserved, error: reservationError } = await supabaseAdmin.rpc(
      "reserve_ai_image_quota",
      { p_user_id: user.id },
    );
    if (reservationError || reserved !== true) {
      return json({
        error: reservationError || reserved !== false
          ? "Image quota unavailable"
          : "Daily image allowance reached",
        code: reservationError || reserved !== false
          ? "image_quota_unavailable"
          : "image_quota_exhausted",
        quotaExceeded: !reservationError && reserved === false,
      }, reservationError || reserved !== false ? 503 : 429);
    }

    signal.throwIfAborted();
    const generationId = crypto.randomUUID();
    timeout = setTimeout(() =>
      providerAbort.abort(
        new AvatarError(
          "generation_timeout",
          "Avatar generation timed out. Please try again later.",
          504,
        ),
      ), 120_000);
    // There is one provider attempt. A reservation remains spent on unknown outcomes.
    const openaiResponse = await fetch(
      "https://api.openai.com/v1/images/generations",
      {
        method: "POST",
        signal,
        headers: {
          Authorization: `Bearer ${openaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: providerBody,
      },
    );
    if (!openaiResponse.ok) {
      await openaiResponse.body?.cancel();
      throw new AvatarError(
        "provider_failed",
        "The image provider could not generate an avatar. Please try again later.",
      );
    }

    const storeImage = async (imageBase64: unknown) => {
      signal.throwIfAborted();
      const image = decodeJPEG(imageBase64);
      const storagePath = `${user!.id}/generated/${generationId}.jpg`;
      let uploadError;
      try {
        ({ error: uploadError } = await supabaseUser.storage.from(
          "profile-pictures",
        ).upload(
          storagePath,
          image,
          { contentType: "image/jpeg", upsert: false },
        ));
      } catch {
        signal.throwIfAborted();
        throw new AvatarError(
          "avatar_upload_failed",
          "Unable to save the generated avatar. Please try again later.",
          503,
        );
      }
      signal.throwIfAborted();
      if (uploadError) {
        const storageError = uploadError as {
          statusCode?: string | number;
          status?: number;
        };
        const status = String(
          storageError.status ?? storageError.statusCode ?? "",
        );
        if (status === "403") {
          throw new AvatarError(
            "avatar_upload_denied",
            "Avatar storage denied permission. Sign in again before generating another avatar.",
            403,
          );
        }
        if (status === "415" || status === "413") {
          throw new AvatarError(
            "avatar_upload_rejected",
            "Avatar storage rejected the JPEG or its size. Try uploading a smaller JPEG photo.",
          );
        }
        throw new AvatarError(
          "avatar_upload_failed",
          "Unable to save the generated avatar. Please try again later.",
          503,
        );
      }
      const { data: publicUrlData } = supabaseUser.storage.from(
        "profile-pictures",
      ).getPublicUrl(storagePath);
      let quotaRemaining: number | null = null;
      try {
        const { data: updatedQuota } = await supabaseUser.rpc(
          "get_creative_quota",
        );
        const row = updatedQuota?.[0];
        if (
          row && Number.isFinite(row.ai_art_limit) &&
          Number.isFinite(row.ai_art_count)
        ) {
          quotaRemaining = Math.max(0, row.ai_art_limit - row.ai_art_count);
        }
      } catch { /* Quota metadata is optional after a successful upload. */ }
      signal.throwIfAborted();
      // Generating stores a candidate only. Applying it is the client's separate confirmation.
      return {
        success: true,
        imageBase64,
        imageUrl: publicUrlData.publicUrl,
        generationId,
        storagePath,
        quotaRemaining,
      };
    };

    if (enableStreaming) {
      streaming = true;
      let cancelled = false;
      const encoder = new TextEncoder();
      // Provider bytes (8 MiB total) and partial count bound this queue. Direct enqueue
      // avoids a stalled writer preventing cancellation when a client stops reading.
      const readable = new ReadableStream<Uint8Array>({
        start(controller) {
          const send = (event: unknown) => {
            if (!cancelled) {
              controller.enqueue(
                encoder.encode(`data: ${JSON.stringify(event)}\n\n`),
              );
            }
          };
          void (async () => {
            let finalImageBase64: unknown;
            let finalReceived = false;
            let partialCount = 0;
            try {
              for await (
                const event of readProviderEvents(openaiResponse, signal)
              ) {
                if (event.type === "done") break;
                if (
                  event.error || event.type === "error" ||
                  event.type === "image_generation.failed"
                ) {
                  throw new AvatarError(
                    "provider_failed",
                    "The image provider could not finish the avatar. Please try again later.",
                  );
                }
                if (event.type === "image_generation.partial_image") {
                  if (
                    ++partialCount > 2 ||
                    !Number.isInteger(event.partial_image_index)
                  ) {
                    throw new AvatarError(
                      "provider_response_invalid",
                      "The image provider returned an invalid preview event.",
                    );
                  }
                  decodeBase64(event.b64_json, MAX_PROVIDER_BYTES);
                  send({
                    type: "partial",
                    index: event.partial_image_index,
                    imageBase64: event.b64_json,
                    generationId,
                  });
                }
                if (
                  event.type === "image_generation.completed" ||
                  event.data?.[0]?.b64_json
                ) {
                  if (finalReceived) {
                    throw new AvatarError(
                      "provider_response_invalid",
                      "The image provider returned multiple final images.",
                    );
                  }
                  finalReceived = true;
                  finalImageBase64 = event.b64_json ??
                    event.data?.[0]?.b64_json;
                  // One image was requested. The terminal result need not wait for a keep-alive close.
                  break;
                }
              }
              if (!finalReceived) {
                throw new AvatarError(
                  "image_missing",
                  "The image provider did not return a final image. Please try again later.",
                );
              }
              const metadata = await storeImage(finalImageBase64);
              send({ type: "complete", ...metadata });
            } catch (error) {
              const problem = failure(error, signal);
              console.error("[generate-profile-picture]", problem.code);
              send({ type: "error", ...errorBody(problem), generationId });
            } finally {
              cleanup();
              if (!cancelled) controller.close();
            }
          })();
        },
        cancel() {
          cancelled = true;
          cleanup();
        },
      });
      return new Response(readable, {
        headers: {
          ...corsHeaders,
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          Connection: "keep-alive",
        },
      });
    }

    const openaiData = await readProviderJSON(openaiResponse, signal);
    if (openaiData?.error) {
      throw new AvatarError(
        "provider_failed",
        "The image provider could not generate an avatar. Please try again later.",
      );
    }
    const imageBase64 = openaiData?.data?.[0]?.b64_json;
    if (!imageBase64) {
      throw new AvatarError(
        "image_missing",
        "The image provider did not return a final image. Please try again later.",
      );
    }
    return json(await storeImage(imageBase64));
  } catch (error) {
    const problem = failure(error, signal);
    console.error("[generate-profile-picture]", problem.code);
    return json(errorBody(problem), problem.status);
  } finally {
    if (!streaming) cleanup();
  }
}

Deno.serve(handler);
