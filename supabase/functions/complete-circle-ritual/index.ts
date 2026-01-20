/**
 * Complete Circle Ritual Edge Function
 *
 * Marks a ritual as completed, closes all attendance records,
 * and creates a recap post if there were attendees.
 *
 * POST /functions/v1/complete-circle-ritual
 * Body: { ritualId }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  jsonResponse,
  errorResponse,
  isValidUUID,
} from "../_shared/ritual-validation.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface CompleteRitualRequest {
  ritualId: string;
}

// Ritual type display names
const RITUAL_TYPE_NAMES: Record<string, string> = {
  gratitude: "Gratitude",
  grounding: "Grounding",
  wins: "Wins",
  breathing: "Breathing",
};

serve(async (req) => {
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
    const body: CompleteRitualRequest = await req.json();

    // Validate ritualId
    if (!body.ritualId || !isValidUUID(body.ritualId)) {
      return errorResponse("VALIDATION_ERROR", "Invalid ritualId", 400);
    }

    // Fetch the ritual
    const { data: ritual, error: ritualError } = await supabase
      .from("circle_rituals")
      .select("*")
      .eq("id", body.ritualId)
      .single();

    if (ritualError || !ritual) {
      return errorResponse("RITUAL_NOT_FOUND", "Ritual not found", 404);
    }

    // Check if user is the creator (only creator can manually complete)
    if (ritual.created_by !== user.id) {
      // Check if user is circle owner/admin
      const { data: membership } = await supabase
        .from("circle_members")
        .select("role")
        .eq("circle_id", ritual.circle_id)
        .eq("user_id", user.id)
        .single();

      if (!membership || membership.role !== "owner") {
        return errorResponse(
          "UNAUTHORIZED",
          "Only the ritual creator or circle owner can complete this ritual",
          403,
        );
      }
    }

    // Check ritual status
    if (ritual.status === "completed") {
      return errorResponse(
        "ALREADY_COMPLETED",
        "This ritual has already been completed",
        400,
      );
    }

    if (ritual.status === "cancelled") {
      return errorResponse(
        "RITUAL_CANCELLED",
        "This ritual has been cancelled",
        400,
      );
    }

    const now = new Date();

    // Update ritual status to completed
    const { error: updateError } = await supabase
      .from("circle_rituals")
      .update({
        status: "completed",
        completed_at: now.toISOString(),
      })
      .eq("id", body.ritualId);

    if (updateError) {
      console.error("Failed to update ritual status:", updateError);
      return errorResponse("UPDATE_ERROR", "Failed to complete ritual", 500);
    }

    // Close all active attendance records
    const { error: attendanceUpdateError } = await supabase
      .from("circle_ritual_attendees")
      .update({ left_at: now.toISOString() })
      .eq("ritual_id", body.ritualId)
      .is("left_at", null);

    if (attendanceUpdateError) {
      console.error(
        "Failed to update attendance records:",
        attendanceUpdateError,
      );
    }

    // Count attendees
    const { data: attendees, error: countError } = await supabase
      .from("circle_ritual_attendees")
      .select("user_id")
      .eq("ritual_id", body.ritualId);

    const attendeeCount = attendees?.length || 0;
    const uniqueAttendees = new Set(attendees?.map((a) => a.user_id) || []);
    const uniqueAttendeeCount = uniqueAttendees.size;

    let recapPostId: string | null = null;

    // Create recap post if there were attendees
    if (uniqueAttendeeCount >= 1) {
      const ritualTypeName =
        RITUAL_TYPE_NAMES[ritual.ritual_type] || ritual.ritual_type;
      const bodyText =
        uniqueAttendeeCount === 1
          ? `1 member completed the ${ritualTypeName} ritual: "${ritual.title}"`
          : `${uniqueAttendeeCount} members completed the ${ritualTypeName} ritual: "${ritual.title}"`;

      // Get today's date in local format
      const localDate = now.toISOString().split("T")[0];

      const { data: recapPost, error: postError } = await supabase
        .from("circle_posts")
        .insert({
          circle_id: ritual.circle_id,
          user_id: ritual.created_by,
          kind: "ritual_recap",
          body_text: bodyText,
          local_date: localDate,
          ritual_id: body.ritualId,
        })
        .select()
        .single();

      if (postError) {
        console.error("Failed to create recap post:", postError);
        // Don't fail the request if recap post fails
      } else {
        recapPostId = recapPost.id;
      }
    }

    // Broadcast completion event via Realtime
    try {
      const channel = supabase.channel(`circle_ritual:${body.ritualId}`);
      await channel.send({
        type: "broadcast",
        event: "completed",
        payload: {
          completedAt: now.toISOString(),
          attendeeCount: uniqueAttendeeCount,
          recapPostId,
        },
      });
    } catch (realtimeError) {
      console.error("Realtime broadcast error:", realtimeError);
    }

    return jsonResponse({
      ritual: {
        id: ritual.id,
        status: "completed",
        completedAt: now.toISOString(),
        attendeeCount: uniqueAttendeeCount,
      },
      recapPostId,
    });
  } catch (error) {
    console.error("Unexpected error:", error);
    return errorResponse("SERVER_ERROR", "An unexpected error occurred", 500);
  }
});
