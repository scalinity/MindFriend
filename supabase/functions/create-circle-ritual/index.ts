/**
 * Create Circle Ritual Edge Function
 *
 * Creates a new ritual for a circle and sends notifications to all members.
 *
 * POST /functions/v1/create-circle-ritual
 * Body: { circleId, title, ritualType, startOption, scheduledFor? }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  validateCreateRitualInput,
  jsonResponse,
  errorResponse,
  isValidUUID,
  sanitizeAndTrim,
} from "../_shared/ritual-validation.ts";
import { getRitualPrompts, RitualType } from "../_shared/ritual-prompts.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

interface CreateRitualRequest {
  circleId: string;
  title: string;
  ritualType: RitualType;
  startOption: "now" | "scheduled";
  scheduledFor?: string;
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
    const body: CreateRitualRequest = await req.json();

    // Validate input
    const validation = validateCreateRitualInput({
      circleId: body.circleId,
      title: body.title,
      ritualType: body.ritualType,
      startOption: body.startOption,
      scheduledFor: body.scheduledFor,
    });

    if (!validation.valid) {
      return errorResponse(
        "VALIDATION_ERROR",
        "Invalid input",
        400,
        validation.errors,
      );
    }

    // Verify user is a circle member
    const { data: membership, error: membershipError } = await supabase
      .from("circle_members")
      .select("id, role")
      .eq("circle_id", body.circleId)
      .eq("user_id", user.id)
      .single();

    if (membershipError || !membership) {
      return errorResponse(
        "NOT_CIRCLE_MEMBER",
        "You must be a circle member to create rituals",
        403,
        corsHeaders,
      );
    }

    // Only owners and admins can create rituals
    if (membership.role !== "owner" && membership.role !== "admin") {
      return errorResponse(
        "INSUFFICIENT_PERMISSIONS",
        "Only circle owners and admins can create rituals",
        403,
        corsHeaders,
      );
    }

    // Get ritual prompts to determine duration
    const prompts = getRitualPrompts(body.ritualType);
    const durationSeconds = prompts.totalDuration;

    // Determine scheduled_for and status based on startOption
    let scheduledFor: string;
    let status: "scheduled" | "active";

    if (body.startOption === "now") {
      scheduledFor = new Date().toISOString();
      status = "active";
    } else {
      scheduledFor = body.scheduledFor!;
      status = "scheduled";
    }

    // Insert the ritual with sanitized title
    const sanitizedTitle = sanitizeAndTrim(body.title);
    const { data: ritual, error: insertError } = await supabase
      .from("circle_rituals")
      .insert({
        circle_id: body.circleId,
        created_by: user.id,
        title: sanitizedTitle,
        ritual_type: body.ritualType,
        scheduled_for: scheduledFor,
        duration_seconds: durationSeconds,
        status,
      })
      .select()
      .single();

    if (insertError) {
      console.error("Insert error:", insertError);
      return errorResponse("INSERT_ERROR", "Failed to create ritual", 500);
    }

    // Fetch all circle members (except creator) for notifications
    const { data: members, error: membersError } = await supabase
      .from("circle_members")
      .select(
        `
        user_id,
        profiles:user_id (
          id,
          display_name
        )
      `,
      )
      .eq("circle_id", body.circleId)
      .neq("user_id", user.id);

    if (!membersError && members && members.length > 0) {
      // Get circle name for notification
      const { data: circle } = await supabase
        .from("circles")
        .select("name")
        .eq("id", body.circleId)
        .single();

      // Fetch all device tokens for all members in a single query (fixes N+1 pattern)
      const memberIds = members.map((m) => m.user_id);
      const { data: allDevices } = await supabase
        .from("push_tokens")
        .select("user_id, token, platform")
        .in("user_id", memberIds);

      // Group devices by user_id for efficient lookup
      const devicesByUser = (allDevices || []).reduce(
        (acc, device) => {
          if (!acc[device.user_id]) acc[device.user_id] = [];
          acc[device.user_id].push(device);
          return acc;
        },
        {} as Record<string, typeof allDevices>,
      );

      // Format notification time
      const ritualTime = new Date(scheduledFor);
      const timeString =
        body.startOption === "now"
          ? "starting now"
          : `at ${ritualTime.toLocaleTimeString("en-US", {
              hour: "numeric",
              minute: "2-digit",
            })}`;

      // Send notifications to members
      const notificationPromises = members.map(async (member) => {
        const devices = devicesByUser[member.user_id];
        if (!devices || devices.length === 0) {
          return;
        }

        try {
          // Call send-notification function
          await supabase.functions.invoke("send-notification", {
            body: {
              userId: member.user_id,
              title: `${circle?.name || "Circle"} Ritual`,
              body: `${body.title} - ${timeString}`,
              data: {
                type: "ritual_invite",
                ritualId: ritual.id,
                circleId: body.circleId,
              },
            },
          });
        } catch (notifError) {
          console.error(
            `Failed to send notification to ${member.user_id}:`,
            notifError,
          );
        }
      });

      // Don't await all notifications - send them in background
      Promise.all(notificationPromises).catch(console.error);
    }

    // Return the created ritual
    return jsonResponse(
      {
        ritual: {
          id: ritual.id,
          circleId: ritual.circle_id,
          createdBy: ritual.created_by,
          title: ritual.title,
          ritualType: ritual.ritual_type,
          scheduledFor: ritual.scheduled_for,
          durationSeconds: ritual.duration_seconds,
          status: ritual.status,
          createdAt: ritual.created_at,
        },
      },
      201,
    );
  } catch (error) {
    console.error("Unexpected error:", error);
    return errorResponse("SERVER_ERROR", "An unexpected error occurred", 500);
  }
});
