// MindFriend Proactive Scheduler
// Runs every 15 minutes via Supabase cron to identify users needing proactive outreach
// See: docs/specs/01-proactive-intelligence.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";
import { isInQuietHours } from "../_shared/notification-utils.ts";

interface ProactiveCandidate {
  user_id: string;
  trigger_type: string;
  priority: number;
  context: Record<string, unknown>;
}

interface UserSettings {
  proactive_enabled: boolean;
  proactive_max_daily: number;
  proactive_types_enabled: string[];
  quiet_hours_start_local: string | null;
  quiet_hours_end_local: string | null;
  timezone: string;
}

interface EngagementState {
  proactive_ignore_count: number;
  last_proactive_at: string | null;
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
    const candidates: ProactiveCandidate[] = [];

    // 1. Find mood decline candidates (priority 1 - highest)
    const { data: moodDeclineUsers, error: moodError } =
      await supabaseAdmin.rpc("find_mood_decline_users", {
        p_threshold: 2,
        p_consecutive_days: 2,
      });

    if (moodError) {
      console.error("Error fetching mood decline users:", moodError);
    } else if (moodDeclineUsers) {
      for (const user of moodDeclineUsers) {
        candidates.push({
          user_id: user.user_id,
          trigger_type: "mood_decline",
          priority: 1,
          context: {
            avg_mood: user.avg_mood,
            consecutive_days: user.consecutive_days,
          },
        });
      }
    }

    // 2. Find streak risk candidates (priority 2)
    const { data: streakRiskUsers, error: streakError } =
      await supabaseAdmin.rpc("find_streak_risk_users", { p_min_streak: 3 });

    if (streakError) {
      console.error("Error fetching streak risk users:", streakError);
    } else if (streakRiskUsers) {
      for (const user of streakRiskUsers) {
        candidates.push({
          user_id: user.user_id,
          trigger_type: "streak_risk",
          priority: 2,
          context: {
            streak: user.current_streak_days,
            timezone: user.timezone,
          },
        });
      }
    }

    // 3. Find milestone approaching candidates (priority 3)
    const { data: milestoneUsers, error: milestoneError } =
      await supabaseAdmin.rpc("find_milestone_approaching_users");

    if (milestoneError) {
      console.error("Error fetching milestone users:", milestoneError);
    } else if (milestoneUsers) {
      for (const user of milestoneUsers) {
        candidates.push({
          user_id: user.user_id,
          trigger_type: "milestone_approach",
          priority: 3,
          context: {
            streak: user.current_streak_days,
            milestone: user.next_milestone,
          },
        });
      }
    }

    // 4. Find re-engagement candidates (priority 4)
    const { data: reengagementUsers, error: reengError } =
      await supabaseAdmin.rpc("find_reengagement_users", {
        p_days_inactive: 3,
      });

    if (reengError) {
      console.error("Error fetching reengagement users:", reengError);
    } else if (reengagementUsers) {
      for (const user of reengagementUsers) {
        candidates.push({
          user_id: user.user_id,
          trigger_type: "reengagement",
          priority: 4,
          context: { days_inactive: user.days_inactive },
        });
      }
    }

    console.log(`Found ${candidates.length} proactive candidates`);

    // Process candidates (filter, dedupe, respect limits)
    const processed = await processProactiveCandidates(
      supabaseAdmin,
      candidates,
    );

    return new Response(
      JSON.stringify({
        success: true,
        timestamp: now.toISOString(),
        candidates_found: candidates.length,
        messages_scheduled: processed.length,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("Proactive scheduler error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});

async function processProactiveCandidates(
  supabase: SupabaseClient,
  candidates: ProactiveCandidate[],
): Promise<ProactiveCandidate[]> {
  const processed: ProactiveCandidate[] = [];

  // Group by user, take highest priority
  const byUser = new Map<string, ProactiveCandidate>();
  for (const c of candidates.sort((a, b) => a.priority - b.priority)) {
    if (!byUser.has(c.user_id)) {
      byUser.set(c.user_id, c);
    }
  }

  for (const [userId, candidate] of byUser) {
    try {
      // Check user preferences
      const { data: settings } = await supabase
        .from("user_settings")
        .select(
          "proactive_enabled, proactive_max_daily, proactive_types_enabled, quiet_hours_start_local, quiet_hours_end_local, timezone",
        )
        .eq("user_id", userId)
        .single();

      const userSettings = settings as UserSettings | null;

      if (!userSettings?.proactive_enabled) {
        console.log(`User ${userId}: proactive disabled`);
        continue;
      }

      if (
        !userSettings.proactive_types_enabled?.includes(candidate.trigger_type)
      ) {
        console.log(
          `User ${userId}: trigger type ${candidate.trigger_type} not enabled`,
        );
        continue;
      }

      // Check quiet hours
      const timezone = userSettings.timezone || "UTC";
      const formatter = new Intl.DateTimeFormat("en-US", {
        timeZone: timezone,
        hour: "numeric",
        hour12: false,
      });
      const currentHour = parseInt(formatter.format(new Date()), 10);

      if (
        isInQuietHours(
          currentHour,
          userSettings.quiet_hours_start_local,
          userSettings.quiet_hours_end_local,
        )
      ) {
        console.log(`User ${userId}: in quiet hours`);
        continue;
      }

      // Check daily limit
      const { count } = await supabase
        .from("proactive_messages")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .gte(
          "sent_at",
          new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
        );

      if ((count || 0) >= (userSettings.proactive_max_daily || 2)) {
        console.log(`User ${userId}: daily limit reached (${count})`);
        continue;
      }

      // Check engagement state backoff
      const { data: engagement } = await supabase
        .from("user_engagement_states")
        .select("proactive_ignore_count, last_proactive_at")
        .eq("user_id", userId)
        .single();

      const engagementState = engagement as EngagementState | null;
      if (engagementState && engagementState.proactive_ignore_count >= 3) {
        console.log(
          `User ${userId}: too many ignored messages (${engagementState.proactive_ignore_count})`,
        );
        continue;
      }

      // Generate message and schedule
      const message = await generateProactiveMessage(
        supabase,
        userId,
        candidate,
      );

      // Insert proactive message record
      const { error: insertError } = await supabase
        .from("proactive_messages")
        .insert({
          user_id: userId,
          trigger_type: candidate.trigger_type,
          message_content: message,
          delivery_channel: "push",
          scheduled_for: new Date().toISOString(),
          status: "scheduled",
          metadata: candidate.context,
        });

      if (insertError) {
        console.error(
          `Error inserting proactive message for ${userId}:`,
          insertError,
        );
        continue;
      }

      // Send push notification via existing send-notification function
      const notificationType = getNotificationType(candidate.trigger_type);
      const response = await supabase.functions.invoke("send-notification", {
        body: {
          type: notificationType,
          recipientId: userId,
          data: {
            ...candidate.context,
            displayName: await getUserDisplayName(supabase, userId),
          },
        },
      });

      if (response.error) {
        console.error(
          `Error sending proactive notification to ${userId}:`,
          response.error,
        );
        // Update message status to failed
        await supabase
          .from("proactive_messages")
          .update({ status: "expired" })
          .eq("user_id", userId)
          .eq("status", "scheduled")
          .order("created_at", { ascending: false })
          .limit(1);
      } else {
        // Update message status to sent
        await supabase
          .from("proactive_messages")
          .update({ status: "sent", sent_at: new Date().toISOString() })
          .eq("user_id", userId)
          .eq("status", "scheduled")
          .order("created_at", { ascending: false })
          .limit(1);

        // Update last_proactive_at
        await supabase.from("user_engagement_states").upsert(
          {
            user_id: userId,
            last_proactive_at: new Date().toISOString(),
          },
          { onConflict: "user_id" },
        );

        processed.push(candidate);
        console.log(`Sent proactive ${candidate.trigger_type} to ${userId}`);
      }
    } catch (err) {
      console.error(`Error processing candidate ${userId}:`, err);
    }
  }

  return processed;
}

function getNotificationType(triggerType: string): string {
  const typeMap: Record<string, string> = {
    mood_decline: "proactive_mood_decline",
    streak_risk: "proactive_streak_risk",
    milestone_approach: "proactive_milestone",
    reengagement: "proactive_reengagement",
    pattern_insight: "proactive_pattern_insight",
  };
  return typeMap[triggerType] || "proactive_mood_decline";
}

async function getUserDisplayName(
  supabase: SupabaseClient,
  userId: string,
): Promise<string> {
  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", userId)
    .single();

  return profile?.display_name?.split(" ")[0] || "there";
}

async function generateProactiveMessage(
  supabase: SupabaseClient,
  userId: string,
  candidate: ProactiveCandidate,
): Promise<string> {
  const name = await getUserDisplayName(supabase, userId);

  // Template-based generation
  const templates: Record<string, string[]> = {
    mood_decline: [
      `Hey ${name}, I noticed things have been tough lately. No pressure—just wanted you to know I'm here. Want to do a quick reset together?`,
      `${name}, sending you a gentle check-in. How are you holding up? I'm here if you want to chat or try a calming exercise.`,
    ],
    streak_risk: [
      `You're on a ${candidate.context.streak}-day streak! That's amazing. Today's quest is ready whenever you are. 💪`,
      `Hey ${name}, just a friendly reminder—you've got a great ${candidate.context.streak}-day streak going. Keep it up!`,
    ],
    milestone_approach: [
      `${name}, you're just 1 day away from a ${candidate.context.milestone}-day streak! You've got this! 🎉`,
      `Tomorrow could be day ${candidate.context.milestone}! Your consistency is inspiring. Ready for today's quest?`,
    ],
    reengagement: [
      `Hey ${name}, it's been a few days. No judgment—life happens. I'm here when you're ready. Maybe a quick 2-minute breathing exercise?`,
      `${name}, just wanted to say hi. Your wellness journey is still here waiting. Want to ease back in with something small?`,
    ],
  };

  const options = templates[candidate.trigger_type] || [
    `Hey ${name}, hope you're doing well!`,
  ];
  return options[Math.floor(Math.random() * options.length)];
}
