import { generateDailyActions } from "./actions.ts";
// N006: Wellbeing Debt Calculator - Recovery Program Generator Edge Function
// HTTP POST endpoint: generates personalized 7-day recovery programs
// Triggered when user's debt reaches danger level or manually requested

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";
import type {
  DebtScore,
  UserProfile,
  RecoveryProgram,
} from "../_shared/wellbeing-debt-types.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request body
    const { startDate, intensity = "moderate" } = await req.json();
    const programStartDate =
      startDate || new Date().toISOString().split("T")[0];

    // Generate recovery program
    const result = await generateRecoveryProgram(
      supabase,
      user.id,
      programStartDate,
      intensity,
    );

    // Handle case where not enough data exists
    if ("needsMoreData" in result) {
      return new Response(
        JSON.stringify({
          success: false,
          error: result.message,
          needsMoreData: true,
        }),
        {
          status: 200, // Not a server error, just missing data
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(JSON.stringify({ success: true, program: result }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error in generate-recovery-program:", error); // Log full error server-side
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: "An unexpected error occurred",
        needsMoreData: false 
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

// =============================================================================
// USER PROFILE MANAGEMENT (matches calculate-debt-score logic)
// =============================================================================

async function getOrCreateUserProfile(
  supabase: any,
  userId: string,
): Promise<UserProfile> {
  const { data: profile, error } = await supabase
    .from("wellbeing_debt_profiles")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (error || !profile) {
    // Create default profile with rebalanced threshold
    const defaultProfile: UserProfile = {
      user_id: userId,
      personal_threshold: -75,
      crash_history: { crashes: [], last_updated: null },
      top_drains: { categories: [], last_updated: null },
      top_deposits: { categories: [], last_updated: null },
    };

    await supabase
      .from("wellbeing_debt_profiles")
      .insert(defaultProfile)
      .single();

    return defaultProfile;
  }

  return profile;
}

// =============================================================================
// RECOVERY PROGRAM GENERATION
// =============================================================================

async function generateRecoveryProgram(
  supabase: any,
  userId: string,
  startDate: string,
  intensity: string,
): Promise<RecoveryProgram | { needsMoreData: true; message: string }> {
  // 1. Get current debt score
  const { data: currentScore, error: scoreError } = await supabase
    .from("wellbeing_debt_scores")
    .select("*")
    .eq("user_id", userId)
    .order("date", { ascending: false })
    .limit(1)
    .single();

  if (scoreError || !currentScore) {
    // No debt data yet - user needs to track for a few days
    return {
      needsMoreData: true,
      message:
        "Not enough wellbeing data yet. Please track your mood and activities for a few days to generate a personalized recovery program.",
    };
  }

  // 2. Get or create user profile
  const profile = await getOrCreateUserProfile(supabase, userId);

  // 3. Get available exercises
  const { data: exercises, error: exercisesError } = await supabase
    .from("exercises")
    .select("id, title, type, duration_minutes, difficulty_level");

  if (exercisesError || !exercises || exercises.length === 0) {
    return {
      needsMoreData: true,
      message: "Exercise library not available. Please try again later.",
    };
  }

  // 4. Calculate target debt reduction
  const currentDebt = currentScore.rolling_debt_14day;
  const targetReduction = Math.max(currentDebt * 0.5, 20); // 50% reduction or min 20 points
  const dailyTarget = Math.ceil(targetReduction / 7);

  // 5. Generate 7-day action plan
  const dailyActions = generateDailyActions(
    startDate,
    profile,
    exercises,
    dailyTarget,
    intensity,
  );

  return {
    user_id: userId,
    generated_at: new Date().toISOString(),
    target_debt_reduction: targetReduction,
    daily_actions: dailyActions,
  };
}
