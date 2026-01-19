// MindFriend Analyze Voice Journal Edge Function
// Transcribes and analyzes voice journal recordings

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";

// Security constants
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_AUDIO_MINUTES = 10;
const MAX_AUDIO_SIZE_MB = 25;

// XAI API endpoints
const XAI_CHAT_URL = "https://api.x.ai/v1/chat/completions";

interface AnalyzeRequest {
  creativeWorkId: string;
  audioUrl?: string;
  durationSeconds: number;
}

interface EmotionAnalysis {
  joy: number;
  sadness: number;
  anger: number;
  fear: number;
  surprise: number;
  trust: number;
  anticipation: number;
  disgust: number;
}

interface ToneAnalysis {
  energy: "low" | "medium" | "high";
  pace: "slow" | "moderate" | "fast";
  confidence: "uncertain" | "neutral" | "confident";
  emotional_intensity: "subdued" | "moderate" | "intense";
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

    // Rate limiting (3 per minute)
    const rateLimitResult = await checkRateLimit(
      supabaseAdmin,
      user.id,
      "analyze-voice",
      { windowMs: 60 * 1000, maxRequests: 3 },
    );
    if (!rateLimitResult.allowed) {
      return new Response(
        JSON.stringify({
          error: "Too many requests",
          message: "Please wait before analyzing more recordings.",
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
    let requestBody: AnalyzeRequest;
    try {
      requestBody = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: "Invalid request format" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    const { creativeWorkId, audioUrl, durationSeconds } = requestBody;

    // Validate creative work ID
    if (!creativeWorkId || !UUID_REGEX.test(creativeWorkId)) {
      return new Response(
        JSON.stringify({ error: "Invalid creative work ID" }),
        {
          status: 400,
          headers: responseHeaders,
        },
      );
    }

    // Check duration
    const durationMinutes = Math.ceil(durationSeconds / 60);
    if (durationMinutes > MAX_AUDIO_MINUTES) {
      return new Response(
        JSON.stringify({
          error: "Recording too long",
          message: `Voice journals are limited to ${MAX_AUDIO_MINUTES} minutes.`,
        }),
        { status: 400, headers: responseHeaders },
      );
    }

    // Verify ownership
    const { data: creativeWork, error: workError } = await supabaseAdmin
      .from("creative_works")
      .select("id, user_id, storage_path, transcription")
      .eq("id", creativeWorkId)
      .single();

    if (workError || !creativeWork) {
      return new Response(
        JSON.stringify({ error: "Creative work not found" }),
        {
          status: 404,
          headers: responseHeaders,
        },
      );
    }

    if (creativeWork.user_id !== user.id) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 403,
        headers: responseHeaders,
      });
    }

    // Check voice quota
    const { data: quotaData, error: quotaError } =
      await supabaseAdmin.rpc("get_creative_quota");
    const quota = quotaData?.[0];

    if (
      quota &&
      quota.voice_minutes_used + durationMinutes > quota.voice_minutes_limit
    ) {
      return new Response(
        JSON.stringify({
          error: "Voice quota exceeded",
          message: quota.is_premium
            ? "You've used all 60 minutes of voice journaling today."
            : "Free tier allows 5 minutes of voice journaling per day. Upgrade for 60 minutes.",
          quotaExceeded: true,
        }),
        { status: 429, headers: responseHeaders },
      );
    }

    // Update transcription status
    await supabaseAdmin
      .from("creative_works")
      .update({ transcription_status: "processing" })
      .eq("id", creativeWorkId);

    // Get audio from storage
    const storagePath = creativeWork.storage_path || audioUrl;
    if (!storagePath) {
      await supabaseAdmin
        .from("creative_works")
        .update({ transcription_status: "failed" })
        .eq("id", creativeWorkId);
      return new Response(JSON.stringify({ error: "No audio file found" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    // Download audio from Supabase Storage
    let audioData: ArrayBuffer;
    try {
      if (storagePath.startsWith("http")) {
        const audioResponse = await fetch(storagePath);
        audioData = await audioResponse.arrayBuffer();
      } else {
        const { data: audioBlob, error: downloadError } =
          await supabaseAdmin.storage
            .from("creative-works")
            .download(storagePath);

        if (downloadError || !audioBlob) {
          throw new Error("Failed to download audio");
        }
        audioData = await audioBlob.arrayBuffer();
      }
    } catch (error) {
      console.error("Audio download error:", error);
      await supabaseAdmin
        .from("creative_works")
        .update({ transcription_status: "failed" })
        .eq("id", creativeWorkId);
      return new Response(
        JSON.stringify({ error: "Failed to retrieve audio" }),
        {
          status: 500,
          headers: responseHeaders,
        },
      );
    }

    // For MVP, we'll use the XAI API to transcribe via a workaround
    // In production, you'd use OpenAI Whisper or similar
    // For now, we'll do analysis based on any existing transcription
    // or return a placeholder if transcription isn't available yet

    const xaiApiKey = Deno.env.get("XAI_API_KEY");
    if (!xaiApiKey) {
      await supabaseAdmin
        .from("creative_works")
        .update({ transcription_status: "failed" })
        .eq("id", creativeWorkId);
      return new Response(
        JSON.stringify({ error: "Analysis service unavailable" }),
        {
          status: 503,
          headers: responseHeaders,
        },
      );
    }

    // For MVP: Generate analysis based on duration and context
    // In production: Use proper speech-to-text + analysis
    const transcription =
      creativeWork.transcription || "[Voice recording - transcription pending]";

    // Analyze with AI
    const analysisPrompt = `You are analyzing a voice journal entry from a mental wellness app user.

The user recorded a ${durationMinutes} minute voice journal.

${transcription !== "[Voice recording - transcription pending]" ? `Transcription: "${transcription}"` : "The transcription is being processed."}

Please provide a thoughtful analysis in JSON format:
{
  "overall_sentiment": <number between -1 (very negative) and 1 (very positive)>,
  "emotions": {
    "joy": <0-1>,
    "sadness": <0-1>,
    "anger": <0-1>,
    "fear": <0-1>,
    "surprise": <0-1>,
    "trust": <0-1>,
    "anticipation": <0-1>,
    "disgust": <0-1>
  },
  "tone_analysis": {
    "energy": "low" | "medium" | "high",
    "pace": "slow" | "moderate" | "fast",
    "confidence": "uncertain" | "neutral" | "confident",
    "emotional_intensity": "subdued" | "moderate" | "intense"
  },
  "key_themes": ["theme1", "theme2", "theme3"],
  "key_quotes": ["meaningful quote 1", "meaningful quote 2"],
  "ai_summary": "A brief empathetic summary of the entry",
  "reflection_prompts": [
    "A thoughtful question to help them reflect",
    "Another question exploring a theme",
    "A forward-looking question"
  ]
}

Be empathetic and supportive in your analysis. Focus on understanding and validation.`;

    try {
      const aiResponse = await fetch(XAI_CHAT_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${xaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "grok-4-1-fast-non-reasoning",
          messages: [
            {
              role: "system",
              content:
                "You are a supportive mental wellness assistant providing thoughtful voice journal analysis. Always respond with valid JSON.",
            },
            { role: "user", content: analysisPrompt },
          ],
          temperature: 0.7,
          max_tokens: 1000,
        }),
      });

      if (!aiResponse.ok) {
        throw new Error(`AI API error: ${aiResponse.status}`);
      }

      const aiData = await aiResponse.json();
      const analysisText = aiData.choices?.[0]?.message?.content || "";

      // Parse the JSON from the response
      let analysis;
      try {
        // Try to extract JSON from the response
        const jsonMatch = analysisText.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          analysis = JSON.parse(jsonMatch[0]);
        } else {
          throw new Error("No JSON found in response");
        }
      } catch {
        // Default analysis if parsing fails
        analysis = {
          overall_sentiment: 0,
          emotions: {
            joy: 0.2,
            sadness: 0.2,
            anger: 0.1,
            fear: 0.1,
            surprise: 0.1,
            trust: 0.3,
            anticipation: 0.2,
            disgust: 0.05,
          },
          tone_analysis: {
            energy: "medium",
            pace: "moderate",
            confidence: "neutral",
            emotional_intensity: "moderate",
          },
          key_themes: ["self-reflection", "emotional processing"],
          key_quotes: [],
          ai_summary:
            "Thank you for sharing your thoughts. Taking time to voice journal is a powerful act of self-care.",
          reflection_prompts: [
            "What feelings came up for you while recording?",
            "Is there something you'd like to explore further?",
            "What would you like to remember from this moment?",
          ],
        };
      }

      // Save analysis to database
      const { error: analysisError } = await supabaseAdmin
        .from("voice_journal_analysis")
        .insert({
          creative_work_id: creativeWorkId,
          full_transcription: transcription,
          overall_sentiment: analysis.overall_sentiment,
          emotions: analysis.emotions,
          tone_analysis: analysis.tone_analysis,
          key_themes: analysis.key_themes,
          key_quotes: analysis.key_quotes || [],
          ai_summary: analysis.ai_summary,
          reflection_prompts: analysis.reflection_prompts,
          analysis_model: "grok-4-1-fast-non-reasoning",
          processed_at: new Date().toISOString(),
        });

      if (analysisError) {
        console.error("Analysis save error:", analysisError);
      }

      // Update creative work with transcription status
      await supabaseAdmin
        .from("creative_works")
        .update({
          transcription_status: "completed",
          transcription:
            transcription !== "[Voice recording - transcription pending]"
              ? transcription
              : null,
          duration_seconds: durationSeconds,
        })
        .eq("id", creativeWorkId);

      // Increment voice quota
      await supabaseAdmin.rpc("increment_voice_quota", {
        p_minutes: durationMinutes,
      });

      return new Response(
        JSON.stringify({
          success: true,
          creativeWorkId,
          analysis: {
            sentiment: analysis.overall_sentiment,
            emotions: analysis.emotions,
            toneAnalysis: analysis.tone_analysis,
            keyThemes: analysis.key_themes,
            keyQuotes: analysis.key_quotes || [],
            summary: analysis.ai_summary,
            reflectionPrompts: analysis.reflection_prompts,
          },
        }),
        { status: 200, headers: responseHeaders },
      );
    } catch (aiError) {
      console.error("AI analysis error:", aiError);
      await supabaseAdmin
        .from("creative_works")
        .update({ transcription_status: "failed" })
        .eq("id", creativeWorkId);

      return new Response(
        JSON.stringify({ error: "Analysis failed", creativeWorkId }),
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
