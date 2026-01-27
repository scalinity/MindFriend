// supabase/functions/start-insight-experiment/index.ts
// Creates a new 7-day experiment for the authenticated user
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";

const VALID_ACTION_TYPES = [
  "morning_walk",
  "meditation_daily",
  "no_phone_before_bed",
  "gratitude_journaling",
  "cold_shower",
  "digital_detox_evening",
  "exercise_30min",
] as const;

type ActionType = (typeof VALID_ACTION_TYPES)[number];

// Input limits
const MAX_TITLE_LENGTH = 100;
const MAX_DESCRIPTION_LENGTH = 500;

interface StartExperimentRequest {
  actionType: ActionType;
  title: string;
  description: string;
}

interface ExperimentDay {
  id: string;
  experiment_id: string;
  day_index: number;
  completed: boolean;
  completed_at: string | null;
  mood_score: number | null;
  energy_score: number | null;
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

    const requestBody: StartExperimentRequest = await req.json();
    const { actionType, title, description } = requestBody;

    // Validate inputs
    if (!actionType || !title || !description) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: actionType, title, description",
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate input lengths
    if (typeof title !== "string" || title.length > MAX_TITLE_LENGTH) {
      return new Response(
        JSON.stringify({
          error: "INVALID_TITLE",
          message: `Title must be a string with max ${MAX_TITLE_LENGTH} characters`,
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (typeof description !== "string" || description.length > MAX_DESCRIPTION_LENGTH) {
      return new Response(
        JSON.stringify({
          error: "INVALID_DESCRIPTION",
          message: `Description must be a string with max ${MAX_DESCRIPTION_LENGTH} characters`,
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!VALID_ACTION_TYPES.includes(actionType)) {
      return new Response(
        JSON.stringify({
          error: "INVALID_ACTION_TYPE",
          message: `actionType must be one of: ${VALID_ACTION_TYPES.join(", ")}`,
        }),
        {
          status: 400,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check for active experiments (database unique index also enforces this)
    const { data: activeExperiment } = await supabaseAdmin
      .from("insight_experiments")
      .select("id, title")
      .eq("user_id", user.id)
      .eq("status", "active")
      .maybeSingle();

    if (activeExperiment) {
      return new Response(
        JSON.stringify({
          error: "ACTIVE_EXPERIMENT_EXISTS",
          message: `You already have an active experiment: "${activeExperiment.title}". Complete or cancel it first.`,
          existingExperimentId: activeExperiment.id,
        }),
        {
          status: 409,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get user timezone for baseline calculation
    const { data: userSettings } = await supabaseAdmin
      .from("user_settings")
      .select("timezone")
      .eq("user_id", user.id)
      .maybeSingle();

    const timezone = userSettings?.timezone || "UTC";
    const now = new Date();

    // Calculate baseline from 7 days prior using user's timezone
    // Convert current time to user's timezone for accurate day boundaries
    const userNow = new Date(now.toLocaleString("en-US", { timeZone: timezone }));
    const baselineStart = new Date(userNow);
    baselineStart.setDate(baselineStart.getDate() - 7);
    baselineStart.setHours(0, 0, 0, 0);
    const baselineEnd = new Date(userNow);
    baselineEnd.setDate(baselineEnd.getDate() - 1);
    baselineEnd.setHours(23, 59, 59, 999);

    // Query moods for baseline calculation
    const { data: baselineMoods } = await supabaseAdmin
      .from("moods")
      .select("mood_score, energy_score")
      .eq("user_id", user.id)
      .gte("created_at", baselineStart.toISOString())
      .lte("created_at", baselineEnd.toISOString());

    let baselineMoodAvg: number | null = null;
    let baselineEnergyAvg: number | null = null;

    if (baselineMoods && baselineMoods.length > 0) {
      const moodScores = baselineMoods
        .map((m) => m.mood_score)
        .filter((s): s is number => s !== null);
      const energyScores = baselineMoods
        .map((m) => m.energy_score)
        .filter((s): s is number => s !== null);

      if (moodScores.length > 0) {
        const moodSum = moodScores.reduce((sum, s) => sum + s, 0);
        baselineMoodAvg = parseFloat((moodSum / moodScores.length).toFixed(2));
      }

      if (energyScores.length > 0) {
        const energySum = energyScores.reduce((sum, s) => sum + s, 0);
        baselineEnergyAvg = parseFloat(
          (energySum / energyScores.length).toFixed(2),
        );
      }
    }

    // Create experiment and days atomically (with manual rollback on failure)
    let experiment: { id: string; title: string; description: string; action_type: string; started_at: string; status: string; baseline_mood_avg: number | null; baseline_energy_avg: number | null } | null = null;
    
    try {
      // Create experiment
      const { data: expData, error: experimentError } = await supabaseAdmin
        .from("insight_experiments")
        .insert({
          user_id: user.id,
          title: title.trim(),
          description: description.trim(),
          action_type: actionType,
          started_at: now.toISOString(),
          status: "active",
          baseline_mood_avg: baselineMoodAvg,
          baseline_energy_avg: baselineEnergyAvg,
        })
        .select()
        .single();

      if (experimentError || !expData) {
        console.error("Experiment creation failed:", experimentError);
        return new Response(
          JSON.stringify({
            error: "Failed to create experiment",
            details: experimentError?.message,
          }),
          {
            status: 500,
            headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      
      experiment = expData;

      // Create 7 days
      const days = Array.from({ length: 7 }, (_, i) => ({
        experiment_id: experiment!.id,
        day_index: i + 1,
        completed: false,
      }));

      const { error: daysError } = await supabaseAdmin
        .from("insight_experiment_days")
        .insert(days);

      if (daysError) {
        // Rollback: delete the experiment
        await supabaseAdmin
          .from("insight_experiments")
          .delete()
          .eq("id", experiment.id);
        console.error("Days creation failed, rolled back experiment:", daysError);
        return new Response(
          JSON.stringify({
            error: "Failed to create experiment days",
            details: daysError.message,
          }),
          {
            status: 500,
            headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    } catch (dbError) {
      // Rollback if experiment was created
      if (experiment) {
        await supabaseAdmin
          .from("insight_experiments")
          .delete()
          .eq("id", experiment.id);
      }
      console.error("Database operation failed:", dbError);
      return new Response(
        JSON.stringify({ error: "Database operation failed" }),
        {
          status: 500,
          headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch created days
    const { data: createdDays } = await supabaseAdmin
      .from("insight_experiment_days")
      .select("*")
      .eq("experiment_id", experiment.id)
      .order("day_index");

    return new Response(
      JSON.stringify({
        experimentId: experiment.id,
        title: experiment.title,
        description: experiment.description,
        actionType: experiment.action_type,
        startedAt: experiment.started_at,
        status: experiment.status,
        baselineMoodAvg: experiment.baseline_mood_avg,
        baselineEnergyAvg: experiment.baseline_energy_avg,
        hasBaseline: baselineMoodAvg !== null || baselineEnergyAvg !== null,
        baselineDataPoints: baselineMoods?.length || 0,
        currentDay: 1,
        totalDays: 7,
        days: (createdDays || []).map((d: ExperimentDay) => ({
          dayIndex: d.day_index,
          completed: d.completed,
          completedAt: d.completed_at,
          moodScore: d.mood_score,
          energyScore: d.energy_score,
        })),
      }),
      {
        status: 201,
        headers: { ...baseCorsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error(
      "Start experiment error:",
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
