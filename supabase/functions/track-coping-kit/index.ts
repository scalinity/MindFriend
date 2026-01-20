// Edge Function: track-coping-kit
// Handles kit tracking: start, step_complete, complete, cancel
// Integrates with XP and streak systems

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { CommonErrors } from "../_shared/errors.ts";

const XP_PER_KIT_COMPLETE = 10;

// Request/Response types
interface TrackRequest {
  kit_id: string;
  action: "start" | "step_complete" | "complete" | "cancel";
  step_index?: number;
  step_result?: Record<string, unknown>;
  feedback?: {
    helpful: boolean;
    comment?: string;
  };
}

interface StepCompleteResponse {
  success: boolean;
  next_step_index: number;
  is_complete: boolean;
  exercise_session_id?: string;
}

interface LevelUpInfo {
  old_level: number;
  new_level: number;
}

interface CompleteResponse {
  success: boolean;
  xp_awarded: number;
  level_up?: LevelUpInfo;
  streak_incremented: boolean;
}

interface TrackResponse {
  success: boolean;
  progress_id?: string;
  active_progress?: {
    current_step_index: number;
    total_steps: number;
    expires_at: string;
  };
  step?: StepCompleteResponse;
  complete?: CompleteResponse;
  error?: string;
}

// Helper to calculate level from XP
function calculateLevel(xp: number): number {
  // Simple leveling: level = floor(sqrt(xp / 100)) + 1
  return Math.floor(Math.sqrt(xp / 100)) + 1;
}

// Fallback breathing exercise for missing references
const FALLBACK_BREATHING_STEP = {
  type: "breathing",
  breathing_pattern: "box",
  duration_cycles: 2,
  instructions:
    "Inhale for 4 seconds, hold for 4, exhale for 4, hold for 4. This is a calming fallback exercise.",
};

serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Only accept POST
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // Create Supabase client with user's JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return CommonErrors.unauthorized(corsHeaders);
    }

    const token = authHeader.replace("Bearer ", "");
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );

    // Verify user authentication
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return CommonErrors.invalidToken(corsHeaders);
    }

    // Parse request body
    const body: TrackRequest = await req.json();
    const { kit_id, action, step_index, step_result, feedback } = body;

    // Validate required fields
    if (!kit_id || !action) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: kit_id, action" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch kit details
    const { data: kit, error: kitError } = await supabase
      .from("coping_kits")
      .select("id, title, steps, is_premium")
      .eq("id", kit_id)
      .single();

    if (kitError || !kit) {
      return new Response(
        JSON.stringify({ error: "Kit not found", code: "NOT_FOUND" }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get or create user_coping_kits entry
    const { data: userKit, error: userKitError } = await supabase
      .from("user_coping_kits")
      .select("*")
      .eq("user_id", user.id)
      .eq("kit_id", kit_id)
      .single();

    const upsertUserKit = async () => {
      await supabase.from("user_coping_kits").upsert(
        {
          user_id: user.id,
          kit_id: kit_id,
          total_uses: userKit ? userKit.total_uses + 1 : 1,
          completed_count: userKit ? userKit.completed_count : 0,
          last_used_at: new Date().toISOString(),
        },
        { onConflict: "user_id, kit_id" },
      );
    };

    if (userKitError && userKitError.code !== "PGRST116") {
      console.error("Error fetching user kit:", userKitError);
      return CommonErrors.internalError(corsHeaders);
    }

    // Check premium status (simplified - would check subscription table in production)
    const isPremium = kit.is_premium; // TODO: Check subscription status
    if (kit.is_premium && !isPremium) {
      return new Response(
        JSON.stringify({
          error: "Premium kit - upgrade required",
          code: "PREMIUM_REQUIRED",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get or create progress record
    const { data: progress, error: progressError } = await supabase
      .from("kit_progress")
      .select("*")
      .eq("user_id", user.id)
      .eq("kit_id", kit_id)
      .single();

    // Handle based on action
    switch (action) {
      case "start": {
        // Create or update progress
        const totalSteps = Array.isArray(kit.steps) ? kit.steps.length : 0;
        const { data: newProgress, error: createError } = await supabase
          .from("kit_progress")
          .upsert(
            {
              user_id: user.id,
              kit_id: kit_id,
              current_step_index: 0,
              step_results: [],
              started_at: new Date().toISOString(),
              expires_at: new Date(
                Date.now() + 24 * 60 * 60 * 1000,
              ).toISOString(),
            },
            { onConflict: "user_id, kit_id", returning: "*" },
          )
          .select()
          .single();

        if (createError) {
          console.error("Error creating progress:", createError);
          return CommonErrors.internalError(corsHeaders);
        }

        await upsertUserKit();

        const response: TrackResponse = {
          success: true,
          progress_id: newProgress.id,
          active_progress: {
            current_step_index: 0,
            total_steps: totalSteps,
            expires_at: newProgress.expires_at,
          },
        };

        return new Response(JSON.stringify(response), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      case "step_complete": {
        if (step_index === undefined) {
          return new Response(
            JSON.stringify({ error: "step_index required for step_complete" }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        // Get current progress
        let currentProgress = progress;
        if (!currentProgress) {
          // Auto-start if no progress exists
          const { data: newProgress } = await supabase
            .from("kit_progress")
            .upsert(
              {
                user_id: user.id,
                kit_id: kit_id,
                current_step_index: step_index,
                step_results: [step_result ?? {}],
                started_at: new Date().toISOString(),
                expires_at: new Date(
                  Date.now() + 24 * 60 * 60 * 1000,
                ).toISOString(),
              },
              { onConflict: "user_id, kit_id", returning: "*" },
            )
            .select()
            .single();
          currentProgress = newProgress;
        }

        const totalSteps = Array.isArray(kit.steps) ? kit.steps.length : 0;
        const nextStepIndex = step_index + 1;
        const isComplete = nextStepIndex >= totalSteps;

        // Update progress
        const { error: updateError } = await supabase
          .from("kit_progress")
          .update({
            current_step_index: nextStepIndex,
            step_results: [
              ...(currentProgress.step_results ?? []),
              step_result ?? {},
            ],
            expires_at: new Date(
              Date.now() + 24 * 60 * 60 * 1000,
            ).toISOString(),
          })
          .eq("id", currentProgress.id);

        if (updateError) {
          console.error("Error updating progress:", updateError);
          return CommonErrors.internalError(corsHeaders);
        }

        const stepResponse: StepCompleteResponse = {
          success: true,
          next_step_index: nextStepIndex,
          is_complete: isComplete,
        };

        const response: TrackResponse = {
          success: true,
          active_progress: {
            current_step_index: nextStepIndex,
            total_steps: totalSteps,
            expires_at: new Date(
              Date.now() + 24 * 60 * 60 * 1000,
            ).toISOString(),
          },
          step: stepResponse,
        };

        return new Response(JSON.stringify(response), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      case "complete": {
        if (!progress) {
          return new Response(
            JSON.stringify({ error: "No active progress found" }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        const totalSteps = Array.isArray(kit.steps) ? kit.steps.length : 0;

        // Award XP and update streak
        // Fetch current profile for XP/streak
        const { data: profile } = await supabase
          .from("profiles")
          .select("xp, current_streak, longest_streak, last_active_at")
          .eq("id", user.id)
          .single();

        const oldXP = profile?.xp ?? 0;
        const newXP = oldXP + XP_PER_KIT_COMPLETE;
        const oldLevel = calculateLevel(oldXP);
        const newLevel = calculateLevel(newXP);

        // Check streak logic (simplified)
        const today = new Date().toISOString().split("T")[0];
        const lastActive = profile?.last_active_at
          ? new Date(profile.last_active_at).toISOString().split("T")[0]
          : null;

        let newStreak = profile?.current_streak ?? 0;
        let streakIncremented = false;

        if (lastActive !== today) {
          if (lastActive) {
            const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000)
              .toISOString()
              .split("T")[0];
            if (lastActive === yesterday) {
              // Consecutive day - increment streak
              newStreak += 1;
              streakIncremented = true;
            } else if (lastActive < yesterday) {
              // Streak broken - reset to 1
              newStreak = 1;
              streakIncremented = true;
            }
          } else {
            // First activity
            newStreak = 1;
            streakIncremented = true;
          }
        }

        // Update profile with XP and streak
        const { error: profileUpdateError } = await supabase
          .from("profiles")
          .update({
            xp: newXP,
            current_streak: newStreak,
            longest_streak: Math.max(newStreak, profile?.longest_streak ?? 0),
            last_active_at: new Date().toISOString(),
          })
          .eq("id", user.id);

        if (profileUpdateError) {
          console.error("Error updating profile:", profileUpdateError);
        }

        // Delete progress record
        await supabase.from("kit_progress").delete().eq("id", progress.id);

        // Update user_coping_kits completed_count
        await supabase
          .from("user_coping_kits")
          .update({
            completed_count: (userKit?.completed_count ?? 0) + 1,
            last_used_at: new Date().toISOString(),
          })
          .eq("user_id", user.id)
          .eq("kit_id", kit_id);

        // Record feedback if provided
        if (feedback) {
          await supabase.from("kit_feedback").insert({
            user_id: user.id,
            kit_id: kit_id,
            helpful: feedback.helpful,
            comment: feedback.comment,
            xp_granted: XP_PER_KIT_COMPLETE,
          });
        }

        const completeResponse: CompleteResponse = {
          success: true,
          xp_awarded: XP_PER_KIT_COMPLETE,
          streak_incremented: streakIncremented,
        };

        if (newLevel > oldLevel) {
          completeResponse.level_up = {
            old_level: oldLevel,
            new_level: newLevel,
          };
        }

        const response: TrackResponse = {
          success: true,
          complete: completeResponse,
        };

        return new Response(JSON.stringify(response), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      case "cancel": {
        if (progress) {
          // Delete progress
          await supabase.from("kit_progress").delete().eq("id", progress.id);
        }

        return new Response(
          JSON.stringify({ success: true, message: "Kit cancelled" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      default:
        return new Response(JSON.stringify({ error: "Invalid action" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    }
  } catch (error) {
    console.error("Unexpected error in track-coping-kit:", error);
    return CommonErrors.internalError(corsHeaders);
  }
});
