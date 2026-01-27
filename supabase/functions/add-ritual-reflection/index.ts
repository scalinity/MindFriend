/**
 * Add Ritual Reflection Edge Function
 *
 * Allows a ritual attendee to add a reflection after the ritual completes.
 *
 * POST /functions/v1/add-ritual-reflection
 * Body: { ritualId, content }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  validateReflectionContent,
  jsonResponse,
  errorResponse,
  isValidUUID,
  sanitizeAndTrim,
} from "../_shared/ritual-validation.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

interface AddReflectionRequest {
  ritualId: string;
  content: string;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return errorResponse("UNAUTHORIZED", "Authorization required", 401);
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return errorResponse("UNAUTHORIZED", "Invalid authorization", 401);
    }

    // Parse request body
    const body: AddReflectionRequest = await req.json();

    // Validate ritualId
    if (!body.ritualId || !isValidUUID(body.ritualId)) {
      return errorResponse("VALIDATION_ERROR", "Invalid ritualId", 400);
    }

    // Validate content
    const validation = validateReflectionContent(body.content);
    if (!validation.valid) {
      return errorResponse(
        "VALIDATION_ERROR",
        "Invalid reflection content",
        400,
        validation.errors,
      );
    }

    // Fetch the ritual
    const { data: ritual, error: ritualError } = await supabase
      .from("circle_rituals")
      .select("id, status, circle_id")
      .eq("id", body.ritualId)
      .single();

    if (ritualError || !ritual) {
      return errorResponse("RITUAL_NOT_FOUND", "Ritual not found", 404);
    }

    // Check ritual status - can only add reflection to completed rituals
    if (ritual.status !== "completed") {
      return errorResponse(
        "RITUAL_NOT_COMPLETED",
        "You can only add reflections after the ritual is completed",
        400,
      );
    }

    // Verify user was an attendee
    const { data: attendance, error: attendanceError } = await supabase
      .from("circle_ritual_attendees")
      .select("id")
      .eq("ritual_id", body.ritualId)
      .eq("user_id", user.id)
      .single();

    if (attendanceError || !attendance) {
      return errorResponse(
        "NOT_ATTENDEE",
        "You must have attended the ritual to add a reflection",
        403,
      );
    }

    // Check if user already has a reflection
    const { data: existingReflection } = await supabase
      .from("circle_ritual_reflections")
      .select("id")
      .eq("ritual_id", body.ritualId)
      .eq("user_id", user.id)
      .single();

    // Sanitize content before storage
    const sanitizedContent = sanitizeAndTrim(body.content);

    if (existingReflection) {
      // Update existing reflection
      const { data: updatedReflection, error: updateError } = await supabase
        .from("circle_ritual_reflections")
        .update({ body_text: sanitizedContent })
        .eq("id", existingReflection.id)
        .select()
        .single();

      if (updateError) {
        console.error("Failed to update reflection:", updateError);
        return errorResponse(
          "UPDATE_ERROR",
          "Failed to update reflection",
          500,
        );
      }

      return jsonResponse({
        reflection: {
          id: updatedReflection.id,
          ritualId: updatedReflection.ritual_id,
          userId: updatedReflection.user_id,
          content: updatedReflection.body_text,
          createdAt: updatedReflection.created_at,
        },
        updated: true,
      });
    }

    // Insert new reflection
    const { data: reflection, error: insertError } = await supabase
      .from("circle_ritual_reflections")
      .insert({
        ritual_id: body.ritualId,
        user_id: user.id,
        body_text: sanitizedContent,
      })
      .select()
      .single();

    if (insertError) {
      console.error("Failed to insert reflection:", insertError);
      return errorResponse("INSERT_ERROR", "Failed to add reflection", 500);
    }

    // Broadcast new reflection via Realtime
    try {
      const { data: profile } = await supabase
        .from("profiles")
        .select("display_name")
        .eq("id", user.id)
        .single();

      const channel = supabase.channel(`circle_ritual:${body.ritualId}`);
      await channel.send({
        type: "broadcast",
        event: "reflection_added",
        payload: {
          reflectionId: reflection.id,
          userId: user.id,
          displayName: profile?.display_name || "Unknown",
          content: reflection.body_text,
          createdAt: reflection.created_at,
        },
      });
    } catch (realtimeError) {
      console.error("Realtime broadcast error:", realtimeError);
    }

    return jsonResponse(
      {
        reflection: {
          id: reflection.id,
          ritualId: reflection.ritual_id,
          userId: reflection.user_id,
          content: reflection.body_text,
          createdAt: reflection.created_at,
        },
        updated: false,
      },
      201,
    );
  } catch (error) {
    console.error("Unexpected error:", error);
    return errorResponse("SERVER_ERROR", "An unexpected error occurred", 500);
  }
});
