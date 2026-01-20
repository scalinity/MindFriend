/**
 * Join Circle Ritual Edge Function
 *
 * Allows a circle member to join an active or starting ritual.
 * Handles grace period logic, calculates current step for late joiners,
 * and broadcasts join event via Realtime.
 *
 * POST /functions/v1/join-circle-ritual
 * Body: { ritualId }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  isWithinGracePeriod,
  hasRitualStarted,
  hasRitualElapsed,
  calculateElapsedSeconds,
  jsonResponse,
  errorResponse,
  isValidUUID,
} from "../_shared/ritual-validation.ts";
import { calculateCurrentStep, RitualType } from "../_shared/ritual-prompts.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

interface JoinRitualRequest {
  ritualId: string;
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
    const body: JoinRitualRequest = await req.json();

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

    // Verify user is a circle member
    const { data: membership, error: membershipError } = await supabase
      .from("circle_members")
      .select("id")
      .eq("circle_id", ritual.circle_id)
      .eq("user_id", user.id)
      .single();

    if (membershipError || !membership) {
      return errorResponse(
        "NOT_CIRCLE_MEMBER",
        "You must be a circle member to join this ritual",
        403,
      );
    }

    // Check ritual status
    if (ritual.status === "completed") {
      return errorResponse(
        "RITUAL_ENDED",
        "This ritual has already ended",
        410,
      );
    }

    if (ritual.status === "cancelled") {
      return errorResponse(
        "RITUAL_CANCELLED",
        "This ritual has been cancelled",
        410,
      );
    }

    const now = new Date();
    const scheduledFor = new Date(ritual.scheduled_for);

    // Check if ritual time has fully elapsed
    if (hasRitualElapsed(scheduledFor, ritual.duration_seconds, now)) {
      return errorResponse(
        "RITUAL_ENDED",
        "This ritual has already ended",
        410,
      );
    }

    // Check grace period for scheduled rituals
    if (ritual.status === "scheduled") {
      if (!isWithinGracePeriod(scheduledFor, now)) {
        return errorResponse(
          "GRACE_PERIOD_EXPIRED",
          "This ritual started more than 2 minutes ago and can no longer be joined",
          410,
        );
      }

      // Transition to active if ritual has started
      if (hasRitualStarted(scheduledFor, now)) {
        const { error: updateError } = await supabase
          .from("circle_rituals")
          .update({ status: "active" })
          .eq("id", body.ritualId);

        if (updateError) {
          console.error("Failed to update ritual status:", updateError);
        }
      }
    }

    // For active rituals, check if still within grace period
    if (ritual.status === "active" && !isWithinGracePeriod(scheduledFor, now)) {
      return errorResponse(
        "GRACE_PERIOD_EXPIRED",
        "This ritual started more than 2 minutes ago and can no longer be joined",
        410,
      );
    }

    // Check if user already has an active attendance record
    const { data: existingAttendance } = await supabase
      .from("circle_ritual_attendees")
      .select("id")
      .eq("ritual_id", body.ritualId)
      .eq("user_id", user.id)
      .is("left_at", null)
      .single();

    if (existingAttendance) {
      // User already joined - just return current state
      const elapsedSeconds = calculateElapsedSeconds(scheduledFor, now);
      const currentStep = calculateCurrentStep(
        ritual.ritual_type as RitualType,
        elapsedSeconds,
      );

      // Fetch attendees
      const { data: attendees } = await supabase
        .from("circle_ritual_attendees")
        .select(
          `
          id,
          user_id,
          joined_at,
          profiles:user_id (
            display_name
          )
        `,
        )
        .eq("ritual_id", body.ritualId)
        .is("left_at", null);

      return jsonResponse({
        attendance: {
          id: existingAttendance.id,
          ritualId: body.ritualId,
          userId: user.id,
          joinedAt: now.toISOString(),
        },
        ritual: {
          id: ritual.id,
          title: ritual.title,
          ritualType: ritual.ritual_type,
          status: "active",
          scheduledFor: ritual.scheduled_for,
          durationSeconds: ritual.duration_seconds,
        },
        currentStep,
        attendees: (attendees || []).map((a: any) => ({
          userId: a.user_id,
          displayName: a.profiles?.display_name || "Unknown",
          joinedAt: a.joined_at,
        })),
      });
    }

    // Insert attendance record
    const { data: attendance, error: attendanceError } = await supabase
      .from("circle_ritual_attendees")
      .insert({
        ritual_id: body.ritualId,
        user_id: user.id,
        joined_at: now.toISOString(),
      })
      .select()
      .single();

    if (attendanceError) {
      console.error("Attendance insert error:", attendanceError);
      return errorResponse("ATTENDANCE_ERROR", "Failed to join ritual", 500);
    }

    // Calculate current step for late joiners
    const elapsedSeconds = calculateElapsedSeconds(scheduledFor, now);
    const currentStep = calculateCurrentStep(
      ritual.ritual_type as RitualType,
      elapsedSeconds,
    );

    // Fetch user profile for broadcast
    const { data: profile } = await supabase
      .from("profiles")
      .select("display_name")
      .eq("id", user.id)
      .single();

    // Broadcast join event via Realtime
    // Note: Clients subscribe to `circle_ritual:{ritual_id}` channel
    try {
      const channel = supabase.channel(`circle_ritual:${body.ritualId}`);
      await channel.send({
        type: "broadcast",
        event: "user_joined",
        payload: {
          userId: user.id,
          displayName: profile?.display_name || "Unknown",
          currentStepIndex: currentStep?.stepIndex || 0,
          joinedAt: now.toISOString(),
        },
      });
    } catch (realtimeError) {
      console.error("Realtime broadcast error:", realtimeError);
      // Don't fail the request if broadcast fails
    }

    // Fetch all current attendees
    const { data: attendees } = await supabase
      .from("circle_ritual_attendees")
      .select(
        `
        id,
        user_id,
        joined_at,
        profiles:user_id (
          display_name
        )
      `,
      )
      .eq("ritual_id", body.ritualId)
      .is("left_at", null);

    return jsonResponse({
      attendance: {
        id: attendance.id,
        ritualId: body.ritualId,
        userId: user.id,
        joinedAt: attendance.joined_at,
      },
      ritual: {
        id: ritual.id,
        title: ritual.title,
        ritualType: ritual.ritual_type,
        status: "active",
        scheduledFor: ritual.scheduled_for,
        durationSeconds: ritual.duration_seconds,
      },
      currentStep,
      attendees: (attendees || []).map((a: any) => ({
        userId: a.user_id,
        displayName: a.profiles?.display_name || "Unknown",
        joinedAt: a.joined_at,
      })),
    });
  } catch (error) {
    console.error("Unexpected error:", error);
    return errorResponse("SERVER_ERROR", "An unexpected error occurred", 500);
  }
});
