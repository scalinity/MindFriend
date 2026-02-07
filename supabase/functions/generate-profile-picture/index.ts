// MindFriend Generate Profile Picture Edge Function
// Supports streaming partial images for interactive UX with full persistence

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";


// Helper: Convert base64 string to Uint8Array
function base64ToUint8Array(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);

  const requestId = crypto.randomUUID().slice(0, 8);
  console.log(`[${requestId}] Function started`);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    console.log(`[${requestId}] Initializing Supabase`);
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      console.error(`[${requestId}] Missing Supabase env vars`);
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

    // Authenticate
    console.log(`[${requestId}] Authenticating user`);
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      console.error(`[${requestId}] Auth failed:`, authError?.message);
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    console.log(`[${requestId}] User authenticated:`, user.id);

    // Create user-scoped client for quota RPCs
    const supabaseUser = createClient(supabaseUrl, anonKey!, {
      global: { headers: { Authorization: authHeader } },
    });

    // Parse request
    let body;
    try {
      body = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: "Invalid JSON" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const prompt = body?.prompt?.trim();
    const enableStreaming = body?.stream === true;

    if (!prompt || prompt.length < 3) {
      return new Response(
        JSON.stringify({ error: "Prompt must be at least 3 characters" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    console.log(`[${requestId}] Prompt: ${prompt.slice(0, 50)}..., Streaming: ${enableStreaming}`);

    // Check OpenAI API key
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiApiKey) {
      console.error(`[${requestId}] Missing OPENAI_API_KEY`);
      return new Response(JSON.stringify({ error: "AI not configured" }), {
        status: 503,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check quota (reuse creative quota system)
    console.log(`[${requestId}] Checking creative quota...`);
    const { data: quotaData, error: quotaError } = await supabaseUser.rpc("get_creative_quota");

    if (quotaError) {
      console.error(`[${requestId}] Quota check error:`, quotaError);
      return new Response(
        JSON.stringify({ error: "Failed to check quota", details: quotaError.message }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const quota = quotaData?.[0];
    console.log(`[${requestId}] Quota - count: ${quota?.ai_art_count}, limit: ${quota?.ai_art_limit}, premium: ${quota?.is_premium}`);

    if (quota && quota.ai_art_count >= quota.ai_art_limit) {
      console.log(`[${requestId}] Quota exceeded`);
      return new Response(
        JSON.stringify({
          error: "Daily limit reached",
          message: quota.is_premium
            ? "You've used all of today's AI generations."
            : "You've used your free daily AI generation. Upgrade to MindFriend Premium for more!",
          quotaExceeded: true,
        }),
        { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const enhancedPrompt = `A friendly profile picture: ${prompt}. Style: warm, approachable, suitable for all ages.`;

    // Generate unique ID for this generation
    const generationId = crypto.randomUUID();

    // Streaming mode - return SSE stream with partial images
    if (enableStreaming) {
      console.log(`[${requestId}] Starting streaming generation`);

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
            size: "1024x1024",
            output_format: "png",
            stream: true,
            partial_images: 2,
          }),
        },
      );

      if (!openaiResponse.ok) {
        const errorText = await openaiResponse.text();
        console.error(`[${requestId}] OpenAI streaming error:`, openaiResponse.status, errorText);
        return new Response(
          JSON.stringify({
            error: "Image generation failed",
            details: errorText,
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Create a TransformStream to proxy the SSE from OpenAI to the client
      const { readable, writable } = new TransformStream();
      const writer = writable.getWriter();
      const encoder = new TextEncoder();

      // Process the OpenAI SSE stream in the background
      (async () => {
        const reader = openaiResponse.body?.getReader();
        if (!reader) {
          await writer.write(
            encoder.encode(
              `data: ${JSON.stringify({ type: "error", error: "No response body" })}\n\n`,
            ),
          );
          await writer.close();
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
              console.log(`[${requestId}] Stream done, final image: ${finalImageBase64 ? "received" : "missing"}`);
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

                  // Handle partial image events
                  if (event.type === "image_generation.partial_image") {
                    partialCount++;
                    console.log(`[${requestId}] Partial image ${partialCount} received`);
                    await writer.write(
                      encoder.encode(
                        `data: ${JSON.stringify({
                          type: "partial",
                          index: event.partial_image_index,
                          imageBase64: event.b64_json,
                          generationId: generationId,
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
                    console.log(`[${requestId}] Data array completion received`);
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
            console.log(`[${requestId}] Processing final image (length: ${finalImageBase64.length})...`);
            const imageBuffer = base64ToUint8Array(finalImageBase64);
            const storagePath = `${user.id}/generated/${generationId}.png`;

            console.log(`[${requestId}] Uploading to storage: ${storagePath}`);
            const { error: uploadError } = await supabaseAdmin.storage
              .from("profile-pictures")
              .upload(storagePath, imageBuffer, {
                contentType: "image/png",
                upsert: true,
              });

            if (uploadError) {
              console.error(`[${requestId}] Upload error:`, uploadError);
              await writer.write(
                encoder.encode(
                  `data: ${JSON.stringify({ 
                    type: "error", 
                    error: "Failed to store image",
                    generationId: generationId 
                  })}\n\n`,
                ),
              );
            } else {
              console.log(`[${requestId}] Upload successful`);
              const { data: publicUrlData } = supabaseAdmin.storage
                .from("profile-pictures")
                .getPublicUrl(storagePath);

              const finalImageUrl = publicUrlData.publicUrl;
              console.log(`[${requestId}] Public URL: ${finalImageUrl}`);

              // Increment quota
              console.log(`[${requestId}] Incrementing quota...`);
              await supabaseUser.rpc("increment_ai_art_quota");

              // Get updated quota
              const { data: updatedQuota } = await supabaseUser.rpc("get_creative_quota");
              const remainingQuota = updatedQuota?.[0] 
                ? updatedQuota[0].ai_art_limit - updatedQuota[0].ai_art_count 
                : null;

              // Send complete event with full metadata
              await writer.write(
                encoder.encode(
                  `data: ${JSON.stringify({
                    type: "complete",
                    success: true,
                    generationId: generationId,
                    imageUrl: finalImageUrl,
                    imageBase64: finalImageBase64,
                    storagePath: storagePath,
                    quotaRemaining: remainingQuota,
                  })}\n\n`,
                ),
              );
              console.log(`[${requestId}] Complete event sent`);
            }
          } else {
            console.error(`[${requestId}] No final image received from stream`);
            await writer.write(
              encoder.encode(
                `data: ${JSON.stringify({ 
                  type: "error", 
                  error: "No image generated",
                  generationId: generationId 
                })}\n\n`,
              ),
            );
          }
        } catch (error) {
          console.error(`[${requestId}] Stream processing error:`, error);
          try {
            await writer.write(
              encoder.encode(
                `data: ${JSON.stringify({
                  type: "error",
                  error: error instanceof Error ? error.message : "Stream error",
                  generationId: generationId,
                })}\n\n`,
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
        }
      })().catch((err) => {
        console.error(`[${requestId}] [FATAL] Stream IIFE crash:`, err);
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

    // Non-streaming mode (backward compatible)
    console.log(`[${requestId}] Calling OpenAI API (non-streaming)`);

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
          size: "1024x1024",
          output_format: "png",
        }),
      },
    );

    console.log(`[${requestId}] OpenAI response status:`, openaiResponse.status);

    if (!openaiResponse.ok) {
      const errorText = await openaiResponse.text();
      console.error(`[${requestId}] OpenAI error:`, openaiResponse.status, errorText);
      return new Response(
        JSON.stringify({
          error: "Image generation failed",
          details: errorText,
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const openaiData = await openaiResponse.json();
    const imageBase64 = openaiData.data?.[0]?.b64_json;

    if (!imageBase64) {
      console.error(`[${requestId}] No image in response`);
      return new Response(JSON.stringify({ error: "No image generated" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    console.log(`[${requestId}] Success! Image size: ${imageBase64.length}`);

    // Upload to storage
    const imageBuffer = base64ToUint8Array(imageBase64);
    const storagePath = `${user.id}/generated/${generationId}.png`;

    console.log(`[${requestId}] Uploading to storage: ${storagePath}`);
    const { error: uploadError } = await supabaseAdmin.storage
      .from("profile-pictures")
      .upload(storagePath, imageBuffer, {
        contentType: "image/png",
        upsert: true,
      });

    if (uploadError) {
      console.error(`[${requestId}] Upload error:`, uploadError);
      // Still return the base64 even if storage fails
    }

    const { data: publicUrlData } = supabaseAdmin.storage
      .from("profile-pictures")
      .getPublicUrl(storagePath);

    const finalImageUrl = publicUrlData.publicUrl;

    // Increment quota
    console.log(`[${requestId}] Incrementing quota...`);
    await supabaseUser.rpc("increment_ai_art_quota");

    // Get updated quota
    const { data: updatedQuota } = await supabaseUser.rpc("get_creative_quota");
    const remainingQuota = updatedQuota?.[0] 
      ? updatedQuota[0].ai_art_limit - updatedQuota[0].ai_art_count 
      : null;

    return new Response(
      JSON.stringify({
        success: true,
        imageBase64,
        imageUrl: finalImageUrl,
        generationId: generationId,
        storagePath: storagePath,
        quotaRemaining: remainingQuota,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error(`[${requestId}] Unhandled:`, error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
