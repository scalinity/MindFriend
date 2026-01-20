// supabase/functions/record-experiment-day/index.ts
// Records a completed day for an active experiment
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

interface RecordDayRequest {
  experimentId: string;
  dayIndex: number;
  moodScore?: number;
  energyScore?: number;
}

// UUID v4 format validation
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isValidUUID(value: string): boolean {
  return UUID_REGEX.test(value);
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const baseCorsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: baseCorsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${token}` } } },
    );

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    const requestBody: RecordDayRequest = await req.json();
    const { experimentId, dayIndex, moodScore, energyScore } = requestBody;

    // Validate required inputs
    if (!experimentId || dayIndex === undefined) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: experimentId, dayIndex",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate UUID format
    if (!isValidUUID(experimentId)) {
      return new Response(
        JSON.stringify({
          error: "INVALID_EXPERIMENT_ID",
          message: "experimentId must be a valid UUID",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate day index
    if (dayIndex < 1 || dayIndex > 7 || !Number.isInteger(dayIndex)) {
      return new Response(
        JSON.stringify({
          error: "INVALID_DAY_INDEX",
          message: "dayIndex must be an integer between 1 and 7",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate scores if provided
    if (
      moodScore !== undefined &&
      (moodScore < 1 || moodScore > 5 || !Number.isInteger(moodScore))
    ) {
      return new Response(
        JSON.stringify({
          error: "INVALID_MOOD_SCORE",
          message: "moodScore must be an integer between 1 and 5",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (
      energyScore !== undefined &&
      (energyScore < 1 || energyScore > 5 || !Number.isInteger(energyScore))
    ) {
      return new Response(
        JSON.stringify({
          error: "INVALID_ENERGY_SCORE",
          message: "energyScore must be an integer between 1 and 5",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify experiment ownership and status
    const { data: experiment, error: expError } = await supabaseAdmin
      .from("insight_experiments")
      .select("id, user_id, status, title, started_at")
      .eq("id", experimentId)
      .single();

    if (expError || !experiment) {
      return new Response(
        JSON.stringify({
          error: "EXPERIMENT_NOT_FOUND",
          message: "Experiment not found or you don't have access to it",
        }),
        {
          status: 404,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (experiment.user_id !== user.id) {
      return new Response(JSON.stringify({ error: "Access denied" }), {
        status: 403,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      });
    }

    if (experiment.status !== "active") {
      return new Response(
        JSON.stringify({
          error: "EXPERIMENT_NOT_ACTIVE",
          message: `This experiment is ${experiment.status}. Cannot record days for ${experiment.status} experiments.`,
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get the day record
    const { data: day, error: dayError } = await supabaseAdmin
      .from("insight_experiment_days")
      .select("id, completed, completed_at")
      .eq("experiment_id", experimentId)
      .eq("day_index", dayIndex)
      .single();

    if (dayError || !day) {
      return new Response(
        JSON.stringify({
          error: "DAY_NOT_FOUND",
          message: `Day ${dayIndex} not found for this experiment`,
        }),
        {
          status: 404,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Handle idempotent completion (already completed is OK)
    if (day.completed) {
      // Return success but indicate it was already complete
      const { data: allDays } = await supabaseAdmin
        .from("insight_experiment_days")
        .select("day_index, completed")
        .eq("experiment_id", experimentId)
        .order("day_index");

      const completedDays = (allDays || []).filter((d) => d.completed).length;

      return new Response(
        JSON.stringify({
          success: true,
          alreadyCompleted: true,
          dayIndex,
          completedAt: day.completed_at,
          experimentStatus: experiment.status,
          completedDays,
          daysRemaining: 7 - completedDays,
          reportReady: false,
        }),
        {
          status: 200,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get ALL days BEFORE updating to ensure consistent count
    const { data: allDaysBeforeUpdate } = await supabaseAdmin
      .from("insight_experiment_days")
      .select("day_index, completed")
      .eq("experiment_id", experimentId)
      .order("day_index");

    // Calculate how many are already completed (excluding current day)
    const alreadyCompletedCount = (allDaysBeforeUpdate || []).filter(
      (d) => d.completed && d.day_index !== dayIndex,
    ).length;

    const now = new Date();

    // Update day with completion
    const updateData: Record<string, unknown> = {
      completed: true,
      completed_at: now.toISOString(),
    };

    if (moodScore !== undefined) {
      updateData.mood_score = moodScore;
    }
    if (energyScore !== undefined) {
      updateData.energy_score = energyScore;
    }

    const { error: updateError } = await supabaseAdmin
      .from("insight_experiment_days")
      .update(updateData)
      .eq("id", day.id);

    if (updateError) {
      console.error("Day update failed:", updateError);
      return new Response(
        JSON.stringify({
          error: "Failed to record day",
          details: updateError.message,
        }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Now we know the current day is completed, so total is previous + 1
    const completedDays = alreadyCompletedCount + 1;
    let reportReady = false;
    let experimentStatus = experiment.status;

    // If ALL 7 days are now completed, mark experiment as completed
    if (completedDays === 7) {
      const { error: completeError } = await supabaseAdmin
        .from("insight_experiments")
        .update({
          status: "completed",
          ended_at: now.toISOString(),
        })
        .eq("id", experimentId);

      if (completeError) {
        console.error("Experiment completion failed:", completeError);
        // Don't fail the request - day was recorded successfully
      } else {
        reportReady = true;
        experimentStatus = "completed";
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        alreadyCompleted: false,
        dayIndex,
        completedAt: now.toISOString(),
        moodScore: moodScore || null,
        energyScore: energyScore || null,
        experimentStatus,
        completedDays,
        daysRemaining: 7 - completedDays,
        reportReady,
      }),
      {
        status: 200,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error(
      "Record day error:",
      error instanceof Error ? error.message : "Unknown error",
    );
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      {
        status: 500,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
