// MindFriend Proactive Scheduler
// Runs every 15 minutes via Supabase cron to identify users needing proactive outreach
// See: docs/specs/01-proactive-intelligence.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";
import { isInQuietHours } from "../_shared/notification-utils.ts";
import {
  getProactiveSettingsBatch,
  getUsersProactiveCountsBatch,
  getEngagementStatesBatch,
  insertProactiveMessagesBatch,
  updateNotificationStatusesBatch,
  updateEngagementStatesBatch,
  type BatchProactiveMessage,
  type BatchNotificationStatusUpdate,
  type BatchEngagementUpdate,
} from "../_shared/batch-utils.ts";

interface ProactiveCandidate {
  user_id: string;
  trigger_type: string;
  priority: number;
  context: Record<string, unknown>;
}

// Validate UUID format to prevent injection attacks
function isValidUUID(uuid: string): boolean {
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(uuid);
}

// Validate array of UUIDs
function validateUserIds(userIds: string[]): boolean {
  return userIds.every(isValidUUID);
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
    !(await isAuthorizedCronRequest(req.headers, expectedCronSecret, serviceRoleKey))
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

  const userIds = Array.from(byUser.keys());
  console.log(
    `Processing ${userIds.length} unique users (batch pre-fetch starting)`,
  );

  // Helper to safely log user identifiers without exposing full UUIDs
  const hashUserId = (id: string) => id.substring(0, 8) + "...";

  // Validate all user IDs to prevent injection attacks
  if (!validateUserIds(userIds)) {
    console.error("Invalid user IDs detected in batch processing");
    throw new Error("Invalid user ID format");
  }

  // Pre-fetch all data in 3 batch queries instead of N sequential queries
  const settingsMap = await getProactiveSettingsBatch(supabase, userIds);
  const countsMap = await getUsersProactiveCountsBatch(supabase, userIds);
  const engagementMap = await getEngagementStatesBatch(supabase, userIds);

  // Also pre-fetch all display names in one query
  const { data: allProfiles } = await supabase
    .from("profiles")
    .select("id, display_name")
    .in("id", userIds);

  const profileMap = new Map<string, string>();
  if (allProfiles) {
    for (const p of allProfiles) {
      const firstName = (p.display_name || "there").split(" ")[0];
      profileMap.set(p.id, firstName);
    }
  }

  // Collect all messages and updates for batch operations
  const messagesToInsert: BatchProactiveMessage[] = [];
  const statusUpdates: BatchNotificationStatusUpdate[] = [];
  const engagementUpdates: BatchEngagementUpdate[] = [];

  for (const [userId, candidate] of byUser) {
    try {
      // All data now fetched - O(1) lookups instead of sequential queries
      const settings = settingsMap.get(userId);
      const count = countsMap.get(userId);
      const engagement = engagementMap.get(userId);

      if (!settings?.proactive_enabled) {
        console.log(`User ${hashUserId(userId)}: proactive disabled`);
        continue;
      }

      if (!settings.proactive_types_enabled?.includes(candidate.trigger_type)) {
        console.log(
          `User ${hashUserId(userId)}: trigger type ${candidate.trigger_type} not enabled`,
        );
        continue;
      }

      // Check quiet hours
      const currentHour = new Date().toLocaleString("en-US", {
        timeZone: settings.timezone || "UTC",
        hour: "numeric",
        hour12: false,
      });
      const hour = parseInt(currentHour, 10);

      if (
        isInQuietHours(
          hour,
          settings.quiet_hours_start_local,
          settings.quiet_hours_end_local,
        )
      ) {
        console.log(`User ${hashUserId(userId)}: in quiet hours`);
        continue;
      }

      // Check daily limit
      if ((count?.count_today || 0) >= (settings.max_daily || 2)) {
        console.log(
          `User ${hashUserId(userId)}: daily limit reached (${count?.count_today})`,
        );
        continue;
      }

      // Check engagement state backoff
      if (engagement && engagement.proactive_ignore_count >= 3) {
        console.log(
          `User ${hashUserId(userId)}: too many ignored messages (${engagement.proactive_ignore_count})`,
        );
        continue;
      }

      // Generate message
      const displayName =
        profileMap.get(userId) || (settings ? "there" : "there");
      const message = generateProactiveMessage(displayName, candidate);

      // Collect for batch insert
      messagesToInsert.push({
        user_id: userId,
        trigger_type: candidate.trigger_type,
        message_content: message,
        delivery_channel: "push",
        scheduled_for: new Date().toISOString(),
      });

      processed.push(candidate);
      console.log(`Approved ${candidate.trigger_type} for ${hashUserId(userId)}`);
    } catch (err) {
      console.error(`Error processing candidate ${hashUserId(userId)}:`, err);
    }
  }

  // Batch insert all messages at once
  if (messagesToInsert.length > 0) {
    console.log(
      `Batch inserting ${messagesToInsert.length} proactive messages...`,
    );
    const insertedMessages = await insertProactiveMessagesBatch(
      supabase,
      messagesToInsert,
    );

    // Prepare notification updates and engagement updates for all inserted messages
    const promises: Promise<void>[] = [];
    for (const message of messagesToInsert) {
      const inserted = insertedMessages.get(message.user_id);
      if (inserted) {
        const notificationType = getNotificationType(message.trigger_type);

        // Send push notification
        const response = supabase.functions.invoke("send-notification", {
          body: {
            type: notificationType,
            recipientId: message.user_id,
            data: {
              displayName: profileMap.get(message.user_id) || "there",
            },
          },
        });

        promises.push(
          (async () => {
            const result = await response;
            if (!result.error) {
              // Collect status update
              statusUpdates.push({
                message_id: inserted.id,
                status: "sent",
                sent_at: new Date().toISOString(),
              });

              // Collect engagement update
              engagementUpdates.push({
                user_id: message.user_id,
                new_state: "active", // Mark as re-engaged
              });
            } else {
              // Mark as failed
              statusUpdates.push({
                message_id: inserted.id,
                status: "expired",
              });
            }
          })(),
        );
      }
    }

    // Wait for all promises to resolve
    await Promise.allSettled(promises);
  }

  // Batch update all notification statuses
  if (statusUpdates.length > 0) {
    console.log(`Batch updating ${statusUpdates.length} notification statuses`);
    await updateNotificationStatusesBatch(supabase, statusUpdates);
  }

  // Batch update all engagement states
  if (engagementUpdates.length > 0) {
    console.log(
      `Batch updating ${engagementUpdates.length} engagement state records`,
    );
    await updateEngagementStatesBatch(supabase, engagementUpdates);
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

function generateProactiveMessage(
  displayName: string,
  candidate: ProactiveCandidate,
): string {
  const name = displayName || "there";

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
