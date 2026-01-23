// Toggle Vacation Mode Edge Function
// Enables or disables vacation mode (streak freeze) for users

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

interface ToggleVacationRequest {
  action: "activate" | "deactivate";
  startDate?: string; // ISO date string (YYYY-MM-DD), required for activate
  endDate?: string; // ISO date string (YYYY-MM-DD), required for activate
  reason?: string; // Optional reason
}

interface VacationModeResponse {
  id: string;
  isActive: boolean;
  startDate: string;
  endDate: string;
  daysCount: number;
}

serve(async (req) => {
  const headers = getCorsHeaders(req.headers.get("Origin"));

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers });
  }

  try {
    // Validate authorization
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...headers, "Content-Type": "application/json" },
      });
    }

    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get authenticated user
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { ...headers, "Content-Type": "application/json" },
      });
    }

    // Parse request body
    const body: ToggleVacationRequest = await req.json();
    const { action, startDate, endDate, reason } = body;

    // Validate action
    if (!action || (action !== "activate" && action !== "deactivate")) {
      return new Response(
        JSON.stringify({
          error: "Invalid action. Must be 'activate' or 'deactivate'",
        }),
        {
          status: 400,
          headers: { ...headers, "Content-Type": "application/json" },
        },
      );
    }

    if (action === "activate") {
      return await activateVacation(
        supabase,
        user.id,
        startDate!,
        endDate!,
        reason,
        headers,
      );
    } else {
      return await deactivateVacation(supabase, user.id, headers);
    }
  } catch (error) {
    console.error("Toggle vacation error:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: error.message,
      }),
      {
        status: 500,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }
});

async function activateVacation(
  supabase: any,
  userId: string,
  startDate: string,
  endDate: string,
  reason: string | undefined,
  headers: Record<string, string>,
): Promise<Response> {
  // Validate required fields
  if (!startDate || !endDate) {
    return new Response(
      JSON.stringify({ error: "startDate and endDate are required" }),
      {
        status: 400,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  // Parse dates
  const start = new Date(startDate);
  const end = new Date(endDate);

  // Validate date range
  if (isNaN(start.getTime()) || isNaN(end.getTime())) {
    return new Response(
      JSON.stringify({ error: "Invalid date format. Use YYYY-MM-DD" }),
      {
        status: 400,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  const daysDiff = Math.ceil(
    (end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24),
  );

  if (daysDiff < 0) {
    return new Response(
      JSON.stringify({ error: "End date must be after start date" }),
      {
        status: 400,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  if (daysDiff > 14) {
    return new Response(
      JSON.stringify({ error: "Maximum vacation duration is 14 days" }),
      {
        status: 400,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  // Check for overlapping active vacations
  const { data: existing } = await supabase
    .from("vacation_mode")
    .select("*")
    .eq("user_id", userId)
    .eq("is_active", true)
    .single();

  if (existing) {
    return new Response(
      JSON.stringify({
        error: "overlapping_vacation",
        message: "You already have an active vacation mode",
      }),
      {
        status: 409,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  // Get current streak value
  const { data: stats } = await supabase
    .from("user_stats")
    .select("current_streak_days")
    .eq("user_id", userId)
    .single();

  // Create vacation mode entry
  const { data: vacation, error: insertError } = await supabase
    .from("vacation_mode")
    .insert({
      user_id: userId,
      start_date: startDate,
      end_date: endDate,
      reason: reason || null,
      streak_at_start: stats?.current_streak_days || 0,
      is_active: true,
    })
    .select()
    .single();

  if (insertError) {
    console.error("Insert error:", insertError);
    return new Response(
      JSON.stringify({
        error: "Failed to create vacation mode",
        details: insertError.message,
      }),
      {
        status: 500,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  // Return success response
  const response: VacationModeResponse = {
    id: vacation.id,
    isActive: vacation.is_active,
    startDate: vacation.start_date,
    endDate: vacation.end_date,
    daysCount: daysDiff + 1,
  };

  return new Response(JSON.stringify({ success: true, vacation: response }), {
    status: 200,
    headers: { ...headers, "Content-Type": "application/json" },
  });
}

async function deactivateVacation(
  supabase: any,
  userId: string,
  headers: Record<string, string>,
): Promise<Response> {
  // Deactivate all active vacations for user
  const { error: updateError } = await supabase
    .from("vacation_mode")
    .update({
      is_active: false,
      deactivated_at: new Date().toISOString(),
    })
    .eq("user_id", userId)
    .eq("is_active", true);

  if (updateError) {
    console.error("Update error:", updateError);
    return new Response(
      JSON.stringify({
        error: "Failed to deactivate vacation mode",
        details: updateError.message,
      }),
      {
        status: 500,
        headers: { ...headers, "Content-Type": "application/json" },
      },
    );
  }

  return new Response(
    JSON.stringify({
      success: true,
      message: "Vacation mode deactivated",
    }),
    {
      status: 200,
      headers: { ...headers, "Content-Type": "application/json" },
    },
  );
}
