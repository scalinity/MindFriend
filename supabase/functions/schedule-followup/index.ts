// Boundary & Needs Planner: Schedule Follow-Up
// Endpoint: POST /functions/v1/schedule-followup
// Schedules a follow-up check-in for a boundary

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders } from "../_shared/cors.ts";

// Types
interface ScheduleFollowUpRequest {
  boundaryId: string;
  checkInAt?: string; // ISO8601 date, defaults to +24 hours
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from JWT
    const authHeader = req.headers.get("Authorization")!;
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request body
    const body: ScheduleFollowUpRequest = await req.json();

    // Validate boundary ID
    if (!body.boundaryId) {
      return new Response(JSON.stringify({ error: "Missing boundaryId" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Verify boundary exists and belongs to user
    const { data: boundary, error: boundaryError } = await supabase
      .from("defined_boundaries")
      .select("id")
      .eq("id", body.boundaryId)
      .eq("user_id", user.id)
      .single();

    if (boundaryError || !boundary) {
      return new Response(JSON.stringify({ error: "Boundary not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Calculate check-in time (default: +24 hours from now)
    let checkInAt: Date;
    if (body.checkInAt) {
      checkInAt = new Date(body.checkInAt);

      // Validate that checkInAt is in the future
      if (checkInAt <= new Date()) {
        return new Response(
          JSON.stringify({ error: "Check-in time must be in the future" }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    } else {
      // Default: 24 hours from now
      checkInAt = new Date();
      checkInAt.setHours(checkInAt.getHours() + 24);
    }

    // Insert follow-up record
    const { data: followUp, error: insertError } = await supabase
      .from("boundary_follow_ups")
      .insert({
        boundary_id: body.boundaryId,
        check_in_at: checkInAt.toISOString(),
      })
      .select()
      .single();

    if (insertError) {
      console.error("Database insert error:", insertError);
      return new Response(JSON.stringify({ error: "Database error" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // TODO: Schedule local notification on iOS
    // This will be handled by the iOS app reading the follow-up record
    // and scheduling a local notification with UNUserNotificationCenter
    const reminderSet = true; // Placeholder - actual notification scheduling happens on iOS

    // Return success response
    return new Response(
      JSON.stringify({
        success: true,
        followUpId: followUp.id,
        reminderSet,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error scheduling follow-up:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
