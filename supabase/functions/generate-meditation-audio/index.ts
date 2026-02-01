// Generate meditation audio using Google Cloud TTS Chirp 3 HD voices
// This function generates audio for meditation exercises and uploads to Supabase Storage

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  createGoogleTTSClient,
  CHIRP3_HD_PRESETS,
} from "../_shared/google-tts.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface MeditationSegment {
  timestamp_seconds: number;
  text: string;
  segment_type?: string;
}

interface MeditationInstructions {
  segments: MeditationSegment[];
}

interface Exercise {
  id: string;
  title: string;
  type: string;
  duration_seconds: number;
  instructions: {
    type: string;
    data: MeditationInstructions;
  } | null;
}

// Calculate pause duration based on segment type and next segment timestamp
function calculatePauseDuration(
  currentSegment: MeditationSegment,
  nextSegment: MeditationSegment | null,
  exerciseDuration: number,
): number {
  if (!nextSegment) {
    // Last segment - add a closing pause
    return 5;
  }

  // Calculate pause based on timestamp difference
  const timeDiff =
    nextSegment.timestamp_seconds - currentSegment.timestamp_seconds;

  // Estimate speech duration (~150 words per minute, ~5 chars per word at 0.85 rate)
  const charsPerSecond = ((150 * 5) / 60) * 0.85;
  const estimatedSpeechDuration = currentSegment.text.length / charsPerSecond;

  // Pause is the remaining time after speech
  const pause = Math.max(2, timeDiff - estimatedSpeechDuration);

  return Math.min(pause, 15); // Cap at 15 seconds
}

// Build SSML script from meditation segments
function buildSSMLScript(
  segments: MeditationSegment[],
  exerciseDuration: number,
): string {
  let ssml = "<speak>";

  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i];
    const nextSegment = segments[i + 1] || null;

    // Add the segment text
    ssml += `<p>${escapeSSML(segment.text)}</p>`;

    // Calculate and add pause
    const pauseDuration = calculatePauseDuration(
      segment,
      nextSegment,
      exerciseDuration,
    );
    if (pauseDuration > 0) {
      ssml += `<break time="${Math.round(pauseDuration)}s"/>`;
    }
  }

  ssml += "</speak>";
  return ssml;
}

function escapeSSML(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

serve(async (req) => {
  // Handle CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize clients
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const ttsClient = createGoogleTTSClient();

    // Parse request - can specify exercise IDs or generate for all
    const body = await req.json().catch(() => ({}));
    const exerciseIds: string[] | undefined = body.exerciseIds;
    const dryRun: boolean = body.dryRun ?? false;

    // Fetch meditation exercises
    let query = supabase
      .from("exercises")
      .select("id, title, type, duration_seconds, instructions")
      .eq("type", "meditation")
      .not("instructions", "is", null);

    if (exerciseIds && exerciseIds.length > 0) {
      query = query.in("id", exerciseIds);
    }

    const { data: exercises, error: fetchError } = await query;

    if (fetchError) {
      throw new Error(`Failed to fetch exercises: ${fetchError.message}`);
    }

    if (!exercises || exercises.length === 0) {
      return new Response(
        JSON.stringify({ message: "No meditation exercises found", count: 0 }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    console.log(`Found ${exercises.length} meditation exercises to process`);

    const results: Array<{
      id: string;
      title: string;
      status: string;
      audioUrl?: string;
      error?: string;
      characterCount?: number;
    }> = [];

    for (const exercise of exercises) {
      try {
        console.log(`Processing: ${exercise.title}`);

        // Extract meditation instructions
        const instructions = exercise.instructions as {
          type: string;
          data: MeditationInstructions;
        } | null;

        if (
          !instructions ||
          instructions.type !== "meditation" ||
          !instructions.data?.segments
        ) {
          results.push({
            id: exercise.id,
            title: exercise.title,
            status: "skipped",
            error: "Invalid or missing meditation instructions",
          });
          continue;
        }

        const segments = instructions.data.segments;

        // Build plain text script (SSML for pauses handled differently)
        // For Chirp 3 HD, we'll use plain text with ellipses for pauses
        let script = "";
        for (let i = 0; i < segments.length; i++) {
          const segment = segments[i];
          const nextSegment = segments[i + 1] || null;

          script += segment.text;

          // Add pause indicator
          const pauseDuration = calculatePauseDuration(
            segment,
            nextSegment,
            exercise.duration_seconds,
          );
          if (pauseDuration > 3) {
            script += "\n\n... ... ...\n\n";
          } else if (pauseDuration > 0) {
            script += "\n\n";
          }
        }

        console.log(`Script length: ${script.length} characters`);

        if (dryRun) {
          results.push({
            id: exercise.id,
            title: exercise.title,
            status: "dry_run",
            characterCount: script.length,
          });
          continue;
        }

        // Generate audio with Chirp 3 HD
        const ttsResponse = await ttsClient.textToSpeech({
          text: script,
          voiceId: "meditation",
          useChirp3HD: true,
        });

        console.log(`Generated audio: ${ttsResponse.audioData.length} bytes`);

        // Upload to Supabase Storage
        const fileName = `meditation-${exercise.id}.mp3`;
        const storagePath = `exercises/audio/${fileName}`;

        const { error: uploadError } = await supabase.storage
          .from("audio")
          .upload(storagePath, ttsResponse.audioData, {
            contentType: "audio/mpeg",
            upsert: true,
          });

        if (uploadError) {
          throw new Error(`Upload failed: ${uploadError.message}`);
        }

        // Get public URL
        const { data: urlData } = supabase.storage
          .from("audio")
          .getPublicUrl(storagePath);

        const audioUrl = urlData.publicUrl;

        // Update exercise with audio URL
        const { error: updateError } = await supabase
          .from("exercises")
          .update({ audio_url: audioUrl })
          .eq("id", exercise.id);

        if (updateError) {
          throw new Error(`Update failed: ${updateError.message}`);
        }

        results.push({
          id: exercise.id,
          title: exercise.title,
          status: "success",
          audioUrl,
          characterCount: script.length,
        });

        console.log(`Success: ${exercise.title} -> ${audioUrl}`);
      } catch (err) {
        const errorMessage = err instanceof Error ? err.message : String(err);
        console.error(`Error processing ${exercise.title}:`, errorMessage);

        results.push({
          id: exercise.id,
          title: exercise.title,
          status: "error",
          error: errorMessage,
        });
      }
    }

    // Summary
    const summary = {
      total: results.length,
      success: results.filter((r) => r.status === "success").length,
      skipped: results.filter((r) => r.status === "skipped").length,
      errors: results.filter((r) => r.status === "error").length,
      dryRun: results.filter((r) => r.status === "dry_run").length,
    };

    return new Response(JSON.stringify({ summary, results }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error("Function error:", errorMessage);

    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
