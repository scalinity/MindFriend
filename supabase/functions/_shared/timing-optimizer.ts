// Timing Optimizer for Autonomous Wellness Agent
// Calculates optimal delivery times based on user preferences and learned patterns

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface DeliveryWindow {
  hour: number;
  score: number;
  reason: string;
}

export interface AgentSettingsRow {
  quiet_hours_start: string;
  quiet_hours_end: string;
  timezone: string;
  max_daily_outreach: number;
  autonomy_level: string;
}

export interface LearningRow {
  learned_value: {
    preferred_hours?: number[];
    [key: string]: unknown;
  };
}

/**
 * Find the optimal delivery time for an action
 */
export async function findOptimalDeliveryTime(
  supabase: SupabaseClient,
  userId: string,
  actionType: string,
): Promise<Date> {
  // Get user's learned preferences
  const { data: learning } = await supabase
    .from("agent_learnings")
    .select("learned_value")
    .eq("user_id", userId)
    .eq("learning_type", "optimal_time")
    .single();

  // Get user's settings
  const { data: settings } = await supabase
    .from("agent_settings")
    .select("quiet_hours_start, quiet_hours_end, timezone")
    .eq("user_id", userId)
    .single();

  // Get historical response patterns
  const { data: actions } = await supabase
    .from("agent_actions")
    .select("delivered_at, status, action_type")
    .eq("user_id", userId)
    .eq("action_type", actionType)
    .in("status", ["opened", "responded", "dismissed"])
    .order("created_at", { ascending: false })
    .limit(20);

  const now = new Date();
  const userTz = settings?.timezone || "UTC";
  const windows = generateDeliveryWindows(
    now,
    settings as AgentSettingsRow | null,
    learning as LearningRow | null,
    actions,
    userTz,
  );

  // Find best window outside quiet hours
  const validWindows = windows
    .filter((w) =>
      isOutsideQuietHours(w.hour, settings as AgentSettingsRow | null),
    )
    .sort((a, b) => b.score - a.score);

  const bestWindow = validWindows[0] || { hour: 10 }; // Default 10 AM

  // Calculate actual delivery time in user's timezone
  return calculateDeliveryTime(now, bestWindow.hour, userTz);
}

/**
 * Generate scoring windows for each hour of the day
 */
function generateDeliveryWindows(
  now: Date,
  settings: AgentSettingsRow | null,
  learning: LearningRow | null,
  historicalActions: Array<{ delivered_at: string; status: string }> | null,
  userTz: string,
): DeliveryWindow[] {
  const windows: DeliveryWindow[] = [];

  for (let hour = 7; hour <= 21; hour++) {
    let score = 50; // Base score
    const reasons: string[] = [];

    // Learned preference boost
    if (learning?.learned_value?.preferred_hours?.includes(hour)) {
      score += 30;
      reasons.push("learned preference");
    }

    // Historical success rate
    if (historicalActions && historicalActions.length > 0) {
      const actionsAtHour = historicalActions.filter((a) => {
        const actionHour = new Date(a.delivered_at).getHours();
        return actionHour === hour;
      });

      if (actionsAtHour.length > 0) {
        const successRate =
          actionsAtHour.filter(
            (a) => a.status === "responded" || a.status === "opened",
          ).length / actionsAtHour.length;
        score += successRate * 20;
        reasons.push(`${Math.round(successRate * 100)}% response rate`);
      }
    }

    // Time-of-day patterns (general user behavior)
    if (hour >= 8 && hour <= 10) {
      score += 15; // Morning boost
      reasons.push("morning optimal");
    } else if (hour >= 18 && hour <= 20) {
      score += 10; // Evening boost
      reasons.push("evening good");
    } else if (hour >= 12 && hour <= 14) {
      score -= 5; // Lunch dip
      reasons.push("lunch time");
    }

    // Penalize hours close to quiet hours
    const quietStart = parseInt(
      settings?.quiet_hours_start?.split(":")[0] || "22",
    );
    const quietEnd = parseInt(settings?.quiet_hours_end?.split(":")[0] || "8");

    if (Math.abs(hour - quietStart) <= 1 || Math.abs(hour - quietEnd) <= 1) {
      score -= 10;
      reasons.push("near quiet hours");
    }

    windows.push({
      hour,
      score: Math.max(0, Math.min(100, score)),
      reason: reasons.join(", ") || "default",
    });
  }

  return windows;
}

/**
 * Check if hour is outside quiet hours
 */
export function isOutsideQuietHours(
  hour: number,
  settings: AgentSettingsRow | null,
): boolean {
  if (!settings) return true;

  const start = parseInt(settings.quiet_hours_start?.split(":")[0] || "22");
  const end = parseInt(settings.quiet_hours_end?.split(":")[0] || "8");

  if (start > end) {
    // Quiet hours span midnight (e.g., 22:00 - 07:00)
    return hour < start && hour >= end;
  } else {
    // Quiet hours within same day (e.g., 23:00 - 06:00)
    return hour < start || hour >= end;
  }
}

/**
 * Calculate actual delivery time based on target hour in user's timezone
 */
function calculateDeliveryTime(
  now: Date,
  targetHour: number,
  userTz: string,
): Date {
  // Get current hour in user's timezone
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: userTz,
    hour: "numeric",
    hour12: false,
  });
  const currentHourInUserTz = parseInt(formatter.format(now));

  // Create a date in user's timezone at the target hour
  const deliveryTime = new Date(now);

  // Calculate hours difference
  let hoursToAdd = targetHour - currentHourInUserTz;

  // If target hour has passed today, schedule for tomorrow
  if (hoursToAdd <= 0) {
    hoursToAdd += 24;
  }

  deliveryTime.setTime(deliveryTime.getTime() + hoursToAdd * 60 * 60 * 1000);

  // Add some randomness (0-30 minutes) to avoid clustering
  deliveryTime.setMinutes(Math.floor(Math.random() * 30));
  deliveryTime.setSeconds(0);
  deliveryTime.setMilliseconds(0);

  return deliveryTime;
}

/**
 * Check if current time is within quiet hours for user
 */
export async function isCurrentlyQuietHours(
  supabase: SupabaseClient,
  userId: string,
): Promise<boolean> {
  const { data: settings } = await supabase
    .from("agent_settings")
    .select("quiet_hours_start, quiet_hours_end, timezone")
    .eq("user_id", userId)
    .single();

  if (!settings) return false;

  const userTz = settings.timezone || "UTC";
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: userTz,
    hour: "numeric",
    hour12: false,
  });
  const currentHour = parseInt(formatter.format(new Date()));

  return !isOutsideQuietHours(currentHour, settings as AgentSettingsRow);
}

/**
 * Get count of actions sent today
 */
export async function getActionCountToday(
  supabase: SupabaseClient,
  userId: string,
): Promise<number> {
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const { data, error } = await supabase
    .from("agent_actions")
    .select("id", { count: "exact" })
    .eq("user_id", userId)
    .gte("created_at", today.toISOString())
    .in("status", ["delivered", "opened", "responded"]);

  return data?.length || 0;
}

/**
 * Get max daily actions based on autonomy level
 */
export function getMaxDailyActions(autonomyLevel: string): number {
  const limits: Record<string, number> = {
    minimal: 1,
    balanced: 3,
    proactive: 6,
    guardian: 10,
  };
  return limits[autonomyLevel] || 3;
}

/**
 * Calculate confidence threshold based on autonomy level
 */
export function getConfidenceThreshold(autonomyLevel: string): number {
  const thresholds: Record<string, number> = {
    minimal: 0.85,
    balanced: 0.7,
    proactive: 0.5,
    guardian: 0.3,
  };
  return thresholds[autonomyLevel] || 0.7;
}
