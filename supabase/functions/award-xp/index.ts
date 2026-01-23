// MindFriend Award XP Edge Function
// Awards XP to users and handles level-ups, multipliers, and season progress

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

interface AwardXPRequest {
  source: string; // 'quest', 'exercise', 'mood', 'badge', 'streak', 'bonus', 'checkin'
  sourceId?: string;
  baseAmount: number;
  description?: string;
  skillTreeId?: string; // Optional: award to specific skill tree
}

interface UserExperience {
  id: string;
  user_id: string;
  total_xp: number;
  current_level: number;
  xp_to_next_level: number;
  daily_xp: number;
  daily_xp_date: string;
  weekly_xp: number;
  week_start_date: string | null;
  prestige_level: number;
  xp_multiplier: number;
  multiplier_expires_at: string | null;
}

interface LevelUpInfo {
  oldLevel: number;
  newLevel: number;
  unlockedContent?: string[];
}

// Calculate level from total XP (matches database function)
function calculateLevel(totalXp: number): number {
  return Math.max(1, Math.floor(Math.sqrt(totalXp / 50)) + 1);
}

// Calculate XP needed to reach a level
function totalXpForLevel(level: number): number {
  return 50 * (level - 1) * (level - 1);
}

// Get the start of the current week (Monday)
function getWeekStart(): string {
  const now = new Date();
  const day = now.getDay();
  const diff = now.getDate() - day + (day === 0 ? -6 : 1);
  const weekStart = new Date(now.setDate(diff));
  return weekStart.toISOString().split("T")[0];
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
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

    // Parse and validate request
    const body: AwardXPRequest = await req.json();

    if (!body.source || typeof body.baseAmount !== "number") {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: source, baseAmount",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate source enum
    const validSources = [
      "quest",
      "exercise",
      "mood",
      "badge",
      "streak",
      "bonus",
      "checkin",
      "meditation",
    ];
    if (!validSources.includes(body.source)) {
      return new Response(
        JSON.stringify({
          error: `Invalid source. Must be one of: ${validSources.join(", ")}`,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Sanitize baseAmount
    const baseAmount = Math.max(0, Math.min(body.baseAmount, 10000));

    // Get or create user experience record
    let { data: experience, error: expError } = await supabase
      .from("user_experience")
      .select("*")
      .eq("user_id", user.id)
      .single();

    const today = new Date().toISOString().split("T")[0];
    const weekStart = getWeekStart();

    if (expError || !experience) {
      // Create new experience record
      const { data: newExp, error: createError } = await supabase
        .from("user_experience")
        .insert({
          user_id: user.id,
          total_xp: 0,
          current_level: 1,
          xp_to_next_level: 100,
          daily_xp: 0,
          daily_xp_date: today,
          weekly_xp: 0,
          week_start_date: weekStart,
          prestige_level: 0,
          xp_multiplier: 1.0,
        })
        .select()
        .single();

      if (createError || !newExp) {
        console.error("Error creating experience record:", createError);
        return new Response(
          JSON.stringify({ error: "Failed to initialize experience" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      experience = newExp;
    }

    // Check if multiplier is expired
    let currentMultiplier = experience.xp_multiplier || 1.0;
    if (
      experience.multiplier_expires_at &&
      new Date(experience.multiplier_expires_at) < new Date()
    ) {
      currentMultiplier = 1.0;
    }

    // Calculate final XP amount with multiplier
    const finalAmount = Math.round(baseAmount * currentMultiplier);

    // Reset daily XP if it's a new day
    let newDailyXp = experience.daily_xp || 0;
    if (experience.daily_xp_date !== today) {
      newDailyXp = 0;
    }
    newDailyXp += finalAmount;

    // Reset weekly XP if it's a new week
    let newWeeklyXp = experience.weekly_xp || 0;
    if (experience.week_start_date !== weekStart) {
      newWeeklyXp = 0;
    }
    newWeeklyXp += finalAmount;

    // Calculate new totals and level
    const newTotalXp = (experience.total_xp || 0) + finalAmount;
    const oldLevel = experience.current_level || 1;
    const newLevel = calculateLevel(newTotalXp);
    const xpToNextLevel = totalXpForLevel(newLevel + 1) - newTotalXp;

    // Update experience record
    const { error: updateError } = await supabase
      .from("user_experience")
      .update({
        total_xp: newTotalXp,
        current_level: newLevel,
        xp_to_next_level: xpToNextLevel,
        daily_xp: newDailyXp,
        daily_xp_date: today,
        weekly_xp: newWeeklyXp,
        week_start_date: weekStart,
        xp_multiplier: currentMultiplier,
        updated_at: new Date().toISOString(),
      })
      .eq("user_id", user.id);

    if (updateError) {
      console.error("Error updating experience:", updateError);
      return new Response(
        JSON.stringify({ error: "Failed to update experience" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Log the transaction
    await supabase.from("xp_transactions").insert({
      user_id: user.id,
      amount: finalAmount,
      source: body.source,
      source_id: body.sourceId || null,
      description: body.description || null,
      multiplier_applied: currentMultiplier,
      base_amount: baseAmount,
    });

    // Award XP to skill tree if specified
    if (body.skillTreeId) {
      await supabase.rpc("increment_skill_xp", {
        p_user_id: user.id,
        p_tree_id: body.skillTreeId,
        p_xp_amount: finalAmount,
      });
    }

    // Award XP to current season if active
    const { data: activeSeason } = await supabase
      .from("seasons")
      .select("id")
      .eq("is_active", true)
      .lte("starts_at", new Date().toISOString())
      .gte("ends_at", new Date().toISOString())
      .single();

    if (activeSeason) {
      await supabase.rpc("increment_season_xp", {
        p_user_id: user.id,
        p_season_id: activeSeason.id,
        p_xp_amount: finalAmount,
      });
    }

    // Build response
    const levelUp: LevelUpInfo | null =
      newLevel > oldLevel
        ? {
            oldLevel,
            newLevel,
            unlockedContent: [], // Could populate with unlocked items
          }
        : null;
    
    // Trigger milestone narrative generation for milestone levels (NEW)
    if (levelUp) {
      const milestones = [5, 10, 25, 50, 100];
      if (milestones.includes(newLevel)) {
        // Call in background (don't await - non-blocking)
        fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/generate-milestone-narrative`, {
          method: "POST",
          headers: {
            "Authorization": req.headers.get("Authorization")!,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ level: newLevel }),
        }).catch((error) => {
          console.error("Failed to trigger milestone narrative:", error);
          // Don't fail the XP award if narrative generation fails
        });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        xpAwarded: finalAmount,
        multiplierApplied: currentMultiplier,
        experience: {
          totalXp: newTotalXp,
          currentLevel: newLevel,
          xpToNextLevel: xpToNextLevel,
          dailyXp: newDailyXp,
          weeklyXp: newWeeklyXp,
        },
        levelUp,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error awarding XP:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...getCorsHeaders(null), "Content-Type": "application/json" },
    });
  }
});
