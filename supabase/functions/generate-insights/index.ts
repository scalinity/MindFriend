// supabase/functions/generate-insights/index.ts
// Smart Personalization: Generate personalized insights from user data

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

interface Insight {
  insight_type: string;
  insight_category: string;
  title: string;
  description: string;
  data_points: Record<string, unknown>;
  confidence: number;
  action_type?: string;
  action_data?: Record<string, unknown>;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

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

  try {
    const insights: Insight[] = [];

    // Get user's recent data
    const weekAgo = new Date(
      Date.now() - 7 * 24 * 60 * 60 * 1000,
    ).toISOString();

    const { data: recentEngagements } = await supabase
      .from("content_engagements")
      .select("*")
      .eq("user_id", user.id)
      .gte("created_at", weekAgo);

    const { data: recentMoods } = await supabase
      .from("moods")
      .select("*")
      .eq("user_id", user.id)
      .gte("created_at", weekAgo);

    const { data: patterns } = await supabase
      .from("usage_patterns")
      .select("*")
      .eq("user_id", user.id);

    const { data: learnedPrefs } = await supabase
      .from("learned_preferences")
      .select("*")
      .eq("user_id", user.id)
      .gte("confidence_score", 0.5);

    // Insight 1: Best time to practice
    const timePattern = patterns?.find((p) => p.pattern_type === "daily_time");
    if (timePattern && timePattern.confidence >= 0.3) {
      const patternData = timePattern.pattern_data as {
        slots?: Array<{ hour: number; score: number }>;
      };
      const bestSlot = patternData.slots?.[0];
      if (bestSlot) {
        insights.push({
          insight_type: "pattern",
          insight_category: "habit",
          title: "Your Power Hour",
          description: `You're most likely to complete wellness activities at ${formatHour(bestSlot.hour)}. Consider scheduling your daily practice around this time.`,
          data_points: { bestHour: bestSlot.hour, score: bestSlot.score },
          confidence: timePattern.confidence,
          action_type: "adjust_schedule",
          action_data: {
            suggested_time: `${String(bestSlot.hour).padStart(2, "0")}:00`,
          },
        });
      }
    }

    // Insight 2: Content preference
    const topPrefs = learnedPrefs
      ?.filter((p) => p.preference_type === "category")
      .sort(
        (a, b) =>
          (b.preference_score as number) - (a.preference_score as number),
      )
      .slice(0, 2);

    if (topPrefs && topPrefs.length > 0) {
      const topPref = topPrefs[0];
      insights.push({
        insight_type: "pattern",
        insight_category: "activity",
        title: "What Works for You",
        description: `${formatCategory(topPref.preference_key as string)} exercises seem to resonate most with you. You complete these ${Math.round((topPref.engagement_rate as number) * 100)}% of the time.`,
        data_points: {
          topCategory: topPref.preference_key,
          completionRate: topPref.engagement_rate,
        },
        confidence: topPref.confidence_score as number,
        action_type: "try_content",
        action_data: { category: topPref.preference_key },
      });
    }

    // Insight 3: Mood trend
    if (recentMoods && recentMoods.length >= 3) {
      const avgMood =
        recentMoods.reduce((sum, m) => sum + ((m.score as number) ?? 3), 0) /
        recentMoods.length;
      const twoWeeksAgo = new Date(
        Date.now() - 14 * 24 * 60 * 60 * 1000,
      ).toISOString();

      const { data: olderMoods } = await supabase
        .from("moods")
        .select("*")
        .eq("user_id", user.id)
        .gte("created_at", twoWeeksAgo)
        .lt("created_at", weekAgo);

      if (olderMoods && olderMoods.length >= 3) {
        const prevAvgMood =
          olderMoods.reduce((sum, m) => sum + ((m.score as number) ?? 3), 0) /
          olderMoods.length;
        const change = avgMood - prevAvgMood;

        if (Math.abs(change) >= 0.3) {
          insights.push({
            insight_type: "trend",
            insight_category: "mood",
            title: change > 0 ? "Mood Uplift" : "Mood Check-in",
            description:
              change > 0
                ? `Your average mood has improved this week. Keep up the great work with your wellness routine!`
                : `Your mood has been a bit lower this week. Consider trying some mood-boosting activities.`,
            data_points: {
              currentAvg: avgMood,
              previousAvg: prevAvgMood,
              change: change,
            },
            confidence: 0.7,
            action_type: change > 0 ? "celebrate" : "try_content",
            action_data: change > 0 ? {} : { category: "mood_boost" },
          });
        }
      }
    }

    // Insight 4: Activity streak/consistency
    if (recentEngagements && recentEngagements.length > 0) {
      const activeDays = new Set(
        recentEngagements.map(
          (e) => new Date(e.created_at).toISOString().split("T")[0],
        ),
      ).size;

      if (activeDays >= 5) {
        insights.push({
          insight_type: "milestone",
          insight_category: "habit",
          title: "Consistency Star",
          description: `You've been active ${activeDays} out of the last 7 days. This consistency is building lasting wellness habits.`,
          data_points: { activeDays },
          confidence: 0.9,
          action_type: "celebrate",
          action_data: {},
        });
      } else if (activeDays <= 2) {
        insights.push({
          insight_type: "suggestion",
          insight_category: "habit",
          title: "Small Steps Count",
          description: `Life gets busy! Try a 1-minute breathing exercise to maintain your streak without the time commitment.`,
          data_points: { activeDays },
          confidence: 0.8,
          action_type: "try_content",
          action_data: { category: "micro_moment", length: "micro" },
        });
      }
    }

    // Insight 5: Completion improvement
    const lengthPrefs = learnedPrefs
      ?.filter((p) => p.preference_type === "content_length")
      .sort(
        (a, b) => (b.engagement_rate as number) - (a.engagement_rate as number),
      );

    if (lengthPrefs && lengthPrefs.length > 1) {
      const best = lengthPrefs[0];
      const worst = lengthPrefs[lengthPrefs.length - 1];

      if (
        (best.engagement_rate as number) - (worst.engagement_rate as number) >=
        0.3
      ) {
        insights.push({
          insight_type: "suggestion",
          insight_category: "activity",
          title: "Session Length Sweet Spot",
          description: `You complete ${formatLength(best.preference_key as string)} sessions much more often than ${formatLength(worst.preference_key as string)} ones. Focus on what works!`,
          data_points: {
            bestLength: best.preference_key,
            bestRate: best.engagement_rate,
            worstLength: worst.preference_key,
            worstRate: worst.engagement_rate,
          },
          confidence: Math.min(
            best.confidence_score as number,
            worst.confidence_score as number,
          ),
          action_type: "adjust_preference",
          action_data: { preferred_length: best.preference_key },
        });
      }
    }

    // Insight 6: Weekly day pattern
    const dayPattern = patterns?.find((p) => p.pattern_type === "weekly_day");
    if (dayPattern && dayPattern.confidence >= 0.3) {
      const patternData = dayPattern.pattern_data as {
        days?: Array<{ day: number; score: number; sessions?: number }>;
      };
      const sortedDays =
        patternData.days?.sort((a, b) => b.score - a.score) ?? [];
      const bestDay = sortedDays[0];
      const worstDay = sortedDays[sortedDays.length - 1];

      if (bestDay && worstDay && bestDay.score - worstDay.score >= 0.2) {
        const dayNames = [
          "Sunday",
          "Monday",
          "Tuesday",
          "Wednesday",
          "Thursday",
          "Friday",
          "Saturday",
        ];
        insights.push({
          insight_type: "pattern",
          insight_category: "habit",
          title: "Your Best Day",
          description: `${dayNames[bestDay.day]} is your most active wellness day. Maybe schedule something special for ${dayNames[worstDay.day]} to balance your week?`,
          data_points: {
            bestDay: bestDay.day,
            bestDayScore: bestDay.score,
            worstDay: worstDay.day,
            worstDayScore: worstDay.score,
          },
          confidence: dayPattern.confidence,
          action_type: "adjust_schedule",
          action_data: { suggested_days: [worstDay.day] },
        });
      }
    }

    // Save insights to database (delete old ones first)
    await supabase
      .from("personalized_insights")
      .delete()
      .eq("user_id", user.id)
      .lte("valid_until", new Date().toISOString());

    const validUntil = new Date(
      Date.now() + 7 * 24 * 60 * 60 * 1000,
    ).toISOString();

    for (const insight of insights) {
      await supabase.from("personalized_insights").insert({
        user_id: user.id,
        ...insight,
        valid_until: validUntil,
      });
    }

    // Return new insights
    return new Response(JSON.stringify({ insights }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error generating insights:", error);
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

function formatHour(hour: number): string {
  if (hour === 0) return "12 AM";
  if (hour === 12) return "12 PM";
  if (hour < 12) return `${hour} AM`;
  return `${hour - 12} PM`;
}

function formatCategory(category: string): string {
  return category
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

function formatLength(length: string): string {
  const labels: Record<string, string> = {
    micro: "very short (1-3 min)",
    short: "short (5-10 min)",
    medium: "medium (10-20 min)",
    long: "longer (20+ min)",
  };
  return labels[length] || length;
}
