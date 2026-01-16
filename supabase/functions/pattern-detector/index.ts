// MindFriend Pattern Detector
// Runs daily at 3 AM via Supabase cron to detect behavioral patterns
// See: docs/specs/01-proactive-intelligence.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";

interface DetectedPattern {
  pattern_type: string;
  pattern_key: string;
  pattern_data: Record<string, unknown>;
  confidence: number;
}

interface EligibleUser {
  user_id: string;
  mood_count: number;
  first_mood_at: string;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const headers = {
    ...corsHeaders,
    "Content-Type": "application/json",
  };

  // Require cron secret or service role key
  const expectedCronSecret = Deno.env.get("CRON_SECRET") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

  if (
    !isAuthorizedCronRequest(req.headers, expectedCronSecret, serviceRoleKey)
  ) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers,
    });
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const now = new Date();
    let usersProcessed = 0;
    let patternsDetected = 0;
    let patternsUpdated = 0;
    let engagementStatesUpdated = 0;

    // Get users with sufficient data (14+ days of moods)
    const { data: eligibleUsers, error: eligibleError } =
      await supabaseAdmin.rpc("get_pattern_eligible_users", { p_min_days: 14 });

    if (eligibleError) {
      console.error("Error fetching eligible users:", eligibleError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch eligible users" }),
        { status: 500, headers },
      );
    }

    console.log(
      `Found ${eligibleUsers?.length || 0} eligible users for pattern detection`,
    );

    for (const user of (eligibleUsers || []) as EligibleUser[]) {
      try {
        // Detect patterns using database function
        const { data: patterns, error: patternError } = await supabaseAdmin.rpc(
          "detect_mood_patterns",
          { p_user_id: user.user_id },
        );

        if (patternError) {
          console.error(
            `Error detecting patterns for ${user.user_id}:`,
            patternError,
          );
          continue;
        }

        const detectedPatterns = patterns as DetectedPattern[] | null;
        if (!detectedPatterns || detectedPatterns.length === 0) {
          // No patterns detected, still update engagement state
          await supabaseAdmin.rpc("update_engagement_state", {
            p_user_id: user.user_id,
          });
          engagementStatesUpdated++;
          continue;
        }

        for (const pattern of detectedPatterns) {
          // Upsert pattern
          const { error: upsertError, data: upsertData } = await supabaseAdmin
            .from("user_patterns")
            .upsert(
              {
                user_id: user.user_id,
                pattern_type: pattern.pattern_type,
                pattern_key: pattern.pattern_key,
                pattern_data: pattern.pattern_data,
                confidence: pattern.confidence,
                last_confirmed_at: now.toISOString(),
                is_active: true,
              },
              {
                onConflict: "user_id,pattern_type,pattern_key",
                ignoreDuplicates: false,
              },
            )
            .select();

          if (upsertError) {
            console.error(
              `Error upserting pattern for ${user.user_id}:`,
              upsertError,
            );
          } else {
            patternsDetected++;
            if (upsertData && upsertData.length > 0) {
              // Check if this is a new pattern or update
              const isNew =
                upsertData[0].first_detected_at ===
                upsertData[0].last_confirmed_at;
              if (isNew) {
                console.log(
                  `New pattern detected for ${user.user_id}: ${pattern.pattern_key}`,
                );
              } else {
                patternsUpdated++;
              }
            }
          }
        }

        // Update engagement state while we're here
        await supabaseAdmin.rpc("update_engagement_state", {
          p_user_id: user.user_id,
        });
        engagementStatesUpdated++;
        usersProcessed++;

        // Deactivate patterns that weren't confirmed this run
        // (they may have changed or no longer apply)
        const confirmedKeys = detectedPatterns.map((p) => p.pattern_key);
        await supabaseAdmin
          .from("user_patterns")
          .update({ is_active: false })
          .eq("user_id", user.user_id)
          .not(
            "pattern_key",
            "in",
            `(${confirmedKeys.map((k) => `'${k}'`).join(",")})`,
          )
          .lt(
            "last_confirmed_at",
            new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
          );
      } catch (userError) {
        console.error(`Error processing user ${user.user_id}:`, userError);
      }
    }

    // Check for newly detected patterns that should trigger insights
    await notifyNewPatterns(supabaseAdmin);

    console.log("Pattern detection complete:", {
      usersProcessed,
      patternsDetected,
      patternsUpdated,
      engagementStatesUpdated,
    });

    return new Response(
      JSON.stringify({
        success: true,
        timestamp: now.toISOString(),
        users_processed: usersProcessed,
        patterns_detected: patternsDetected,
        patterns_updated: patternsUpdated,
        engagement_states_updated: engagementStatesUpdated,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("Pattern detector error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});

async function notifyNewPatterns(
  supabase: ReturnType<typeof createClient>,
): Promise<void> {
  // Find patterns that were first detected recently and haven't been surfaced yet
  const { data: newPatterns, error } = await supabase
    .from("user_patterns")
    .select("id, user_id, pattern_type, pattern_key, pattern_data, confidence")
    .eq("is_active", true)
    .eq("times_surfaced", 0)
    .eq("user_acknowledged", false)
    .gte("confidence", 0.7) // Only high-confidence patterns
    .gte(
      "first_detected_at",
      new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
    );

  if (error) {
    console.error("Error fetching new patterns for notification:", error);
    return;
  }

  if (!newPatterns || newPatterns.length === 0) {
    console.log("No new patterns to notify about");
    return;
  }

  console.log(
    `Found ${newPatterns.length} new patterns to potentially notify about`,
  );

  for (const pattern of newPatterns) {
    try {
      // Check if user has pattern insights enabled
      const { data: settings } = await supabase
        .from("user_settings")
        .select("proactive_enabled, proactive_types_enabled")
        .eq("user_id", pattern.user_id)
        .single();

      if (!settings?.proactive_enabled) continue;
      if (!settings.proactive_types_enabled?.includes("pattern_insight"))
        continue;

      // Generate insight message
      const insightMessage = generatePatternInsight(pattern);

      // Schedule a proactive message
      await supabase.from("proactive_messages").insert({
        user_id: pattern.user_id,
        trigger_type: "pattern_insight",
        message_content: insightMessage,
        delivery_channel: "in_app", // Pattern insights are in-app first
        scheduled_for: new Date().toISOString(),
        status: "scheduled",
        metadata: {
          pattern_id: pattern.id,
          pattern_type: pattern.pattern_type,
          pattern_key: pattern.pattern_key,
        },
      });

      // Mark pattern as surfaced
      await supabase
        .from("user_patterns")
        .update({ times_surfaced: 1 })
        .eq("id", pattern.id);

      console.log(
        `Scheduled pattern insight for ${pattern.user_id}: ${pattern.pattern_key}`,
      );
    } catch (notifyError) {
      console.error(
        `Error notifying pattern for ${pattern.user_id}:`,
        notifyError,
      );
    }
  }
}

function generatePatternInsight(pattern: {
  pattern_type: string;
  pattern_key: string;
  pattern_data: Record<string, unknown>;
}): string {
  const data = pattern.pattern_data;

  switch (pattern.pattern_type) {
    case "day_of_week": {
      const dayName = pattern.pattern_key.split("_")[0];
      const trend = pattern.pattern_key.includes("dip") ? "dip" : "peak";
      const delta = Math.abs((data.delta as number) || 0);

      if (trend === "dip") {
        return `We noticed your mood tends to dip on ${dayName}s (about ${delta.toFixed(1)} points lower than average). Consider scheduling extra self-care or lighter activities on ${dayName}s.`;
      } else {
        return `Great news! Your mood tends to peak on ${dayName}s (about ${delta.toFixed(1)} points higher than average). You might want to schedule important tasks on ${dayName}s when you're feeling your best!`;
      }
    }

    case "exercise_correlation": {
      const exerciseAvg = (data.exercise_day_avg as number) || 0;
      const nonExerciseAvg = (data.non_exercise_day_avg as number) || 0;
      const delta = (exerciseAvg - nonExerciseAvg).toFixed(1);

      return `Exercise appears to boost your mood! On days you exercise, your mood averages ${exerciseAvg.toFixed(1)} compared to ${nonExerciseAvg.toFixed(1)} on rest days. That's a +${delta} improvement!`;
    }

    case "quest_preference": {
      const questType = (data.quest_type as string) || "wellness";
      const rate = ((data.completion_rate as number) || 0) * 100;

      return `You really seem to enjoy ${questType} quests! You complete them ${rate.toFixed(0)}% of the time. We'll try to offer more of these when possible.`;
    }

    default:
      return "We've noticed an interesting pattern in your wellness data. Tap to learn more!";
  }
}
