// Generate meditation audio using Google Cloud TTS Chirp 3 HD voices
// This function generates audio for meditation exercises and uploads to Supabase Storage
//
// Strategy: Generate each segment's speech via a separate TTS call, then
// concatenate the speech chunks with programmatically-generated silence
// to produce a full-duration MP3 matching the exercise length.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  createGoogleTTSClient,
  CHIRP3_HD_PRESETS,
} from "../_shared/google-tts.ts";
import { getCorsHeaders } from "../_shared/cors.ts";


interface MeditationSegment {
  timestamp_seconds: number;
  text: string;
  segment_type?: string;
}

interface MeditationInstructions {
  segments: MeditationSegment[];
}

// ─── Silent MP3 Frame Data ────────────────────────────────────────────
// Pre-generated 1-second silent MP3 at 24kHz, 32kbps, mono (matches TTS output format).
// Created with: ffmpeg -f lavfi -i anullsrc=r=24000:cl=mono -t 1 -b:a 32k -map_metadata -1 -write_xing 0 -id3v2_version 0 -f mp3
// Stripped of all ID3/Xing headers — pure MPEG frames only.
// Duration: ~1.056s per copy. Concatenating N copies yields N*1.056s of silence.
const SILENCE_1S_BASE64 =
  "//NExAAAAANIAAAAAExBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExFMAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKYAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMu//NExKwAAANIAAAAADEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//NExKwAAANIAAAAAFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//NExKwAAANIAAAAAFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV";

// Duration of the silence template in seconds
const SILENCE_TEMPLATE_DURATION = 1.056;

// Bytes per second for CBR MP3 at 32kbps (32000 bits/s / 8 = 4000 bytes/s)
const MP3_BYTES_PER_SECOND = 4000;

// Decode the silence template once at module load
let silenceFrames: Uint8Array | null = null;

function getSilenceFrames(): Uint8Array {
  if (!silenceFrames) {
    const binaryString = atob(SILENCE_1S_BASE64);
    silenceFrames = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      silenceFrames[i] = binaryString.charCodeAt(i);
    }
  }
  return silenceFrames;
}

// ─── MP3 Frame Utilities ──────────────────────────────────────────────

// Strip ID3v2/v1 headers and Xing/Info frames from MP3 data, returning only audio frames
function extractMP3Frames(mp3Data: Uint8Array): Uint8Array {
  let start = 0;

  // Skip ID3v2 header if present (starts with "ID3")
  if (
    mp3Data.length > 10 &&
    mp3Data[0] === 0x49 &&
    mp3Data[1] === 0x44 &&
    mp3Data[2] === 0x33
  ) {
    const size =
      ((mp3Data[6] & 0x7f) << 21) |
      ((mp3Data[7] & 0x7f) << 14) |
      ((mp3Data[8] & 0x7f) << 7) |
      (mp3Data[9] & 0x7f);
    start = 10 + size;
  }

  // Find first MPEG sync word (0xFF followed by 0xE0+)
  while (start < mp3Data.length - 1) {
    if (mp3Data[start] === 0xff && (mp3Data[start + 1] & 0xe0) === 0xe0) {
      break;
    }
    start++;
  }

  // Check for Xing/Info header in the first frame and skip it
  // Xing/Info headers contain metadata, not audio
  const xingSearchEnd = Math.min(start + 200, mp3Data.length);
  for (let i = start; i < xingSearchEnd - 4; i++) {
    if (
      (mp3Data[i] === 0x58 &&
        mp3Data[i + 1] === 0x69 &&
        mp3Data[i + 2] === 0x6e &&
        mp3Data[i + 3] === 0x67) || // "Xing"
      (mp3Data[i] === 0x49 &&
        mp3Data[i + 1] === 0x6e &&
        mp3Data[i + 2] === 0x66 &&
        mp3Data[i + 3] === 0x6f) // "Info"
    ) {
      // Skip to next sync word after this frame
      let nextFrame = start + 1;
      while (nextFrame < mp3Data.length - 1) {
        if (
          mp3Data[nextFrame] === 0xff &&
          (mp3Data[nextFrame + 1] & 0xe0) === 0xe0
        ) {
          start = nextFrame;
          break;
        }
        nextFrame++;
      }
      break;
    }
  }

  // Strip ID3v1 tag at end (128 bytes starting with "TAG")
  let end = mp3Data.length;
  if (end >= 128) {
    const tagStart = end - 128;
    if (
      mp3Data[tagStart] === 0x54 &&
      mp3Data[tagStart + 1] === 0x41 &&
      mp3Data[tagStart + 2] === 0x47
    ) {
      end = tagStart;
    }
  }

  return mp3Data.slice(start, end);
}

// Generate N seconds of silence by repeating the 1-second silence template
function generateSilenceData(durationSeconds: number): Uint8Array {
  if (durationSeconds <= 0) return new Uint8Array(0);

  const template = getSilenceFrames();
  const copies = Math.round(durationSeconds / SILENCE_TEMPLATE_DURATION);

  if (copies <= 0) return new Uint8Array(0);

  const totalLength = template.length * copies;
  const result = new Uint8Array(totalLength);

  for (let i = 0; i < copies; i++) {
    result.set(template, i * template.length);
  }

  return result;
}

// Concatenate multiple Uint8Array chunks into one
function concatenateChunks(chunks: Uint8Array[]): Uint8Array {
  const totalLength = chunks.reduce((sum, c) => sum + c.length, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}

// ─── Timestamp Scaling ────────────────────────────────────────────────

// Estimate speech duration from text (used only for pre-TTS timestamp planning).
// Calibrated against Chirp 3 HD at 0.85 speaking rate.
const CHARS_PER_SECOND = ((150 * 5) / 60) * 0.85 * 1.12;

function estimateSpeechDuration(text: string): number {
  return text.length / CHARS_PER_SECOND;
}

// Scale segment timestamps to span the full exercise duration
function scaleTimestamps(
  segments: MeditationSegment[],
  exerciseDuration: number,
): number[] {
  if (segments.length === 0) return [];
  if (segments.length === 1) return [5]; // Start 5s in

  const firstTimestamp = segments[0].timestamp_seconds;
  const lastTimestamp = segments[segments.length - 1].timestamp_seconds;
  const timestampSpan = lastTimestamp - firstTimestamp;

  if (timestampSpan <= 0) {
    // All at same timestamp — distribute evenly
    return segments.map(
      (_, i) => 5 + (i * (exerciseDuration - 10)) / (segments.length - 1),
    );
  }

  // Reserve time for the last segment's speech + closing buffer
  const lastSpeechDuration = estimateSpeechDuration(
    segments[segments.length - 1].text,
  );
  const usableDuration = exerciseDuration - lastSpeechDuration - 5;
  const scaleFactor = usableDuration / timestampSpan;

  return segments.map((seg) => {
    const offset = seg.timestamp_seconds - firstTimestamp;
    return 5 + offset * scaleFactor; // Start 5s in
  });
}

// ─── Main Handler ─────────────────────────────────────────────────────

serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);

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

    // Parse request
    const body = await req.json().catch(() => ({}));
    const exerciseIds: string[] | undefined = body.exerciseIds;
    const dryRun: boolean = body.dryRun ?? false;

    // Fetch meditation exercises
    let query = supabase
      .from("exercises")
      .select(
        "id, title, type, duration_seconds, duration_minutes, instructions",
      )
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
        JSON.stringify({
          message: "No meditation exercises found",
          count: 0,
        }),
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
      segmentCount?: number;
      estimatedDuration?: number;
      actualDuration?: number;
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

        // Use duration_seconds, falling back to duration_minutes * 60
        const exerciseDuration =
          exercise.duration_seconds > 0
            ? exercise.duration_seconds
            : (exercise.duration_minutes ?? 0) * 60;

        if (exerciseDuration <= 0) {
          results.push({
            id: exercise.id,
            title: exercise.title,
            status: "skipped",
            error: "Exercise has no duration",
          });
          continue;
        }

        const scaledTimestamps = scaleTimestamps(segments, exerciseDuration);

        console.log(
          `  ${segments.length} segments, duration: ${exerciseDuration}s, ` +
            `scaled range: ${scaledTimestamps[0]?.toFixed(0)}-${scaledTimestamps[scaledTimestamps.length - 1]?.toFixed(0)}s`,
        );

        if (dryRun) {
          // Calculate estimated total duration
          let totalDuration = 0;
          for (let i = 0; i < segments.length; i++) {
            const speechDuration = estimateSpeechDuration(segments[i].text);
            totalDuration += speechDuration;
            if (i < segments.length - 1) {
              const gap =
                scaledTimestamps[i + 1] - scaledTimestamps[i] - speechDuration;
              totalDuration += Math.max(2, gap);
            }
          }
          // Add trailing silence
          const lastSpeech = estimateSpeechDuration(
            segments[segments.length - 1].text,
          );
          const trailing =
            exerciseDuration -
            scaledTimestamps[scaledTimestamps.length - 1] -
            lastSpeech;
          totalDuration += Math.max(0, trailing);

          results.push({
            id: exercise.id,
            title: exercise.title,
            status: "dry_run",
            segmentCount: segments.length,
            estimatedDuration: Math.round(totalDuration),
          });
          continue;
        }

        // Generate audio: per-segment TTS + silence concatenation
        const audioChunks: Uint8Array[] = [];
        let accumulatedTime = 0;

        // Leading silence (before first segment)
        if (scaledTimestamps[0] > 0) {
          const leadingSilence = generateSilenceData(scaledTimestamps[0]);
          audioChunks.push(leadingSilence);
          accumulatedTime += leadingSilence.length / MP3_BYTES_PER_SECOND;
        }

        for (let i = 0; i < segments.length; i++) {
          const segment = segments[i];

          // Generate speech for this segment
          console.log(
            `  Segment ${i + 1}/${segments.length}: "${segment.text.substring(0, 40)}..." (${segment.text.length} chars)`,
          );

          const ttsResponse = await ttsClient.textToSpeech({
            text: segment.text,
            voiceId: "meditation",
            useChirp3HD: true,
          });

          // Extract raw MP3 frames (strip headers)
          const speechFrames = extractMP3Frames(ttsResponse.audioData);
          audioChunks.push(speechFrames);

          // Calculate actual speech duration from MP3 byte count (CBR 32kbps)
          const actualSpeechDuration = speechFrames.length / MP3_BYTES_PER_SECOND;
          accumulatedTime += actualSpeechDuration;

          // Calculate silence gap using actual speech duration
          let silenceDuration: number;
          if (i < segments.length - 1) {
            // Gap until next segment's target timestamp
            silenceDuration =
              scaledTimestamps[i + 1] - scaledTimestamps[i] - actualSpeechDuration;
          } else {
            // Trailing silence after last segment
            silenceDuration =
              exerciseDuration - scaledTimestamps[i] - actualSpeechDuration;
          }

          silenceDuration = Math.max(2, silenceDuration); // At least 2s gap

          console.log(
            `    Speech: ${actualSpeechDuration.toFixed(1)}s (${speechFrames.length} bytes), Silence: ${silenceDuration.toFixed(1)}s`,
          );

          const silenceData = generateSilenceData(silenceDuration);
          audioChunks.push(silenceData);
          accumulatedTime += silenceData.length / MP3_BYTES_PER_SECOND;
        }

        // Concatenate all chunks into final MP3
        const finalAudio = concatenateChunks(audioChunks);
        const actualDuration = finalAudio.length / MP3_BYTES_PER_SECOND;

        console.log(
          `  Final audio: ${finalAudio.length} bytes (${(finalAudio.length / 1024).toFixed(0)} KB), ` +
            `duration: ${actualDuration.toFixed(1)}s / ${exerciseDuration}s target (${((actualDuration / exerciseDuration) * 100).toFixed(0)}%)`,
        );

        // Upload to Supabase Storage
        const fileName = `meditation-${exercise.id}.mp3`;
        const storagePath = `exercises/audio/${fileName}`;

        const { error: uploadError } = await supabase.storage
          .from("audio")
          .upload(storagePath, finalAudio, {
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
          segmentCount: segments.length,
          estimatedDuration: exerciseDuration,
          actualDuration: Math.round(actualDuration),
        });

        console.log(`  Success: ${exercise.title} -> ${audioUrl}`);
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
