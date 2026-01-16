// Spec 14: get-captions Edge Function
// Fetches audio captions with language fallback chain

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface CaptionsRequest {
  contentType: string;
  contentId: string;
  language: string;
}

serve(async (req) => {
  // CORS headers
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  try {
    // Validate JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    if (!token) {
      return new Response(
        JSON.stringify({ error: "Invalid Authorization header" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
    );

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const { contentType, contentId, language }: CaptionsRequest =
      await req.json();

    // Validate required parameters
    if (!contentType || !contentId || !language) {
      return new Response(
        JSON.stringify({
          error: "contentType, contentId, and language parameters are required",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Validate contentId format (UUID)
    const uuidRegex =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(contentId)) {
      return new Response(
        JSON.stringify({ error: "Invalid contentId format" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Validate language format (2-5 chars, alphanumeric and hyphens)
    if (!/^[a-z]{2}(-[a-zA-Z]{2,3})?$/.test(language)) {
      return new Response(
        JSON.stringify({ error: "Invalid language format" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Validate contentType
    const validContentTypes = ["exercise", "meditation", "story"];
    if (!validContentTypes.includes(contentType)) {
      return new Response(
        JSON.stringify({
          error: `contentType must be one of: ${validContentTypes.join(", ")}`,
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Fallback chain: Try exact language match first
    let captions = null;
    let error = null;

    // 1. Try exact language match
    const result1 = await supabase
      .from("audio_captions")
      .select("*")
      .eq("content_type", contentType)
      .eq("content_id", contentId)
      .eq("language", language)
      .maybeSingle();

    captions = result1.data;
    error = result1.error;

    // 2. If not found and language has region (e.g., 'en-US'), try base language (e.g., 'en')
    if (!captions && language.includes("-")) {
      const baseLanguage = language.split("-")[0];
      const result2 = await supabase
        .from("audio_captions")
        .select("*")
        .eq("content_type", contentType)
        .eq("content_id", contentId)
        .eq("language", baseLanguage)
        .maybeSingle();

      captions = result2.data;
      error = result2.error;
    }

    // 3. Final fallback to English
    if (!captions) {
      const result3 = await supabase
        .from("audio_captions")
        .select("*")
        .eq("content_type", contentType)
        .eq("content_id", contentId)
        .eq("language", "en")
        .maybeSingle();

      captions = result3.data;
      error = result3.error;
    }

    // If still not found, return 404 with available: false
    if (!captions || error) {
      return new Response(
        JSON.stringify({
          available: false,
          error: "Captions not available for this content",
        }),
        {
          status: 404,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Transform response to match iOS interface
    const response = {
      available: true,
      language: captions.language,
      format: captions.format,
      captionsUrl: captions.captions_url,
      captions: captions.captions_json,
      transcript: captions.full_transcript,
      duration: captions.duration_seconds,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=86400", // Cache for 24 hours
      },
    });
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: error instanceof Error ? error.message : "Unknown error",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
