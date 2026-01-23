// MindFriend Assign Quest Edge Function
// Handles daily quest assignment, streak milestone detection, and streak recovery
// Triggered by cron job or directly
// See: specs/03-circle-virality.md, specs/10-streak-recovery.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

// Streak milestones that trigger circle posts
const STREAK_MILESTONES = [7, 14, 30, 60, 100, 365];

// Constants for performance and reliability
const CRON_BATCH_SIZE = 50; // Process users in parallel batches
const OPERATION_TIMEOUT_MS = 25000; // 25s timeout per operation

/**
 * Creates a promise that rejects after the specified timeout
 */
function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  operation: string,
): Promise<T> {
  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      reject(
        new Error(`Operation '${operation}' timed out after ${timeoutMs}ms`),
      );
    }, timeoutMs);

    promise
      .then((result) => {
        clearTimeout(timeoutId);
        resolve(result);
      })
      .catch((error) => {
        clearTimeout(timeoutId);
        reject(error);
      });
  });
}

/**
 * Splits an array into chunks of specified size
 */
function chunkArray<T>(array: T[], chunkSize: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < array.length; i += chunkSize) {
    chunks.push(array.slice(i, i + chunkSize));
  }
  return chunks;
}

interface QuestTemplate {
  id: string;
  type: string;
  title: string;
  description: string;
  estimated_minutes: number;
  difficulty: string;
  tags: string[];
  instructions?: unknown;
}

interface UserStats {
  current_streak_days: number;
  longest_streak_days: number;
  last_quest_date: string | null;
  streak_shields_remaining?: number;
  streak_shields_max?: number;
  recovery_quest_available?: boolean;
  recovery_quest_expires_at?: string;
  streak_before_break?: number;
}

interface StreakProtectionResult {
  streak_protected: boolean;
  new_streak: number;
  shields_remaining: number;
  recovery_available: boolean;
  streak_before_break: number | null;
  recovery_expires_at: string | null;
}

interface RecoveryQuestResult {
  success: boolean;
  attempt_id: string | null;
  quest_template_id: string | null;
  quest_title: string | null;
  quest_description: string | null;
  quest_estimated_minutes: number | null;
  quest_instructions: unknown | null;
  error_message: string | null;
}

interface RecoveryCompleteResult {
  success: boolean;
  restored_streak: number;
  error_message: string | null;
}

// Get current date in user's timezone (or UTC if not set)
function getLocalDate(timezone: string = "UTC"): string {
  try {
    const formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    return formatter.format(new Date());
  } catch {
    // Fallback to UTC if timezone is invalid
    return new Date().toISOString().split("T")[0];
  }
}

// Check if streak should continue
function shouldContinueStreak(
  lastQuestDate: string | null,
  todayDate: string,
): boolean {
  if (!lastQuestDate) return false;

  const today = new Date(todayDate);
  const lastQuest = new Date(lastQuestDate);
  const diffDays = Math.floor(
    (today.getTime() - lastQuest.getTime()) / (1000 * 60 * 60 * 24),
  );

  // Streak continues if last quest was yesterday
  return diffDays === 1;
}

// Post streak milestone to all user's circles
async function postStreakMilestone(
  supabase: SupabaseClient,
  userId: string,
  streakDays: number,
  displayName: string,
): Promise<void> {
  // Get user's circles
  const { data: memberships } = await supabase
    .from("circle_members")
    .select("circle_id")
    .eq("user_id", userId);

  if (!memberships?.length) return;

  const localDate = getLocalDate();

  // Post milestone to each circle
  for (const membership of memberships) {
    await supabase.from("circle_posts").insert({
      circle_id: membership.circle_id,
      user_id: userId,
      post_type: "milestone",
      mood_emoji: "🔥",
      body_text: `${displayName} just hit ${streakDays} days! Keep it up!`,
      local_date: localDate,
    });
  }

  console.log(
    `Posted ${streakDays}-day milestone to ${memberships.length} circles for user ${userId}`,
  );
}

// Check if user is in vacation mode for given date
async function checkVacationMode(
  supabase: SupabaseClient,
  userId: string,
  date: string,
): Promise<boolean> {
  const { data: vacation } = await supabase
    .from("vacation_mode")
    .select("*")
    .eq("user_id", userId)
    .eq("is_active", true)
    .lte("start_date", date)
    .gte("end_date", date)
    .single();

  return !!vacation;
}

// Check and award shield at 7-day milestones
async function checkShieldEarning(
  supabase: SupabaseClient,
  userId: string,
  currentStreak: number,
): Promise<void> {
  // Only award at 7-day milestones (7, 14, 21, 28, etc.)
  if (currentStreak <= 0 || currentStreak % 7 !== 0) {
    return;
  }

  // Get current shield status
  const { data: stats } = await supabase
    .from("user_stats")
    .select("streak_shields_remaining, streak_shields_max")
    .eq("user_id", userId)
    .single();

  if (!stats) return;

  // Award shield if not at max (premium users have max=999)
  if (stats.streak_shields_remaining < stats.streak_shields_max) {
    // Update shield count
    await supabase
      .from("user_stats")
      .update({
        streak_shields_remaining: stats.streak_shields_remaining + 1,
        updated_at: new Date().toISOString(),
      })
      .eq("user_id", userId);

    // Log shield event
    await supabase.from("streak_shield_events").insert({
      user_id: userId,
      event_type: "earned",
      streak_protected: currentStreak,
      shields_remaining: stats.streak_shields_remaining + 1,
      metadata: { earned_at_streak: currentStreak },
    });

    // Send notification
    try {
      await supabase.functions.invoke("send-notification", {
        body: {
          type: "shield_earned",
          recipientId: userId,
          data: { streakDay: currentStreak },
        },
      });
    } catch (error) {
      console.error("Failed to send shield earned notification:", error);
      // Non-critical, continue
    }
  }
}

// Assign quest to a single user
// Uses preference-weighted selection if user has quest preferences data
async function assignQuestToUser(
  supabase: SupabaseClient,
  userId: string,
  localDate: string,
): Promise<{ assigned: boolean; reason?: string }> {
  // Check if user is in vacation mode
  const isOnVacation = await checkVacationMode(supabase, userId, localDate);
  if (isOnVacation) {
    console.log(
      `User ${userId} is in vacation mode - skipping quest assignment`,
    );
    return { assigned: false, reason: "vacation_mode" };
  }

  // Check if user already has a quest for today
  const { data: existingQuest } = await supabase
    .from("quests")
    .select("id")
    .eq("user_id", userId)
    .eq("local_date", localDate)
    .single();

  if (existingQuest) {
    return { assigned: false, reason: "already_assigned" };
  }

  // Get user's current stats and profile
  const [{ data: stats }, { data: profile }] = await Promise.all([
    supabase
      .from("user_stats")
      .select("current_streak_days, longest_streak_days, last_quest_date")
      .eq("user_id", userId)
      .single(),
    supabase
      .from("profiles")
      .select("display_name, wellness_focus")
      .eq("id", userId)
      .single(),
  ]);

  // Check for active arc and use arc step if available
  try {
    const { data: arcStepResult, error: arcStepError } = await supabase.rpc(
      "get_arc_step_for_user",
      {
        p_user_id: userId,
      },
    );

    // Differentiate between errors and empty results
    if (arcStepError) {
      // Log database/RPC errors but don't fail quest assignment
      console.error(
        `Arc step RPC error for user ${userId}:`,
        arcStepError.code,
        arcStepError.message,
      );
      // Fall through to normal quest selection
    } else if (arcStepResult && arcStepResult.length > 0) {
      const arcStep = arcStepResult[0];
      console.log(
        `Arc-driven quest for user ${userId}: template ${arcStep.quest_template_id} (day ${arcStep.day_number})`,
      );

      const { error: arcInsertError } = await supabase.from("quests").insert({
        user_id: userId,
        template_id: arcStep.quest_template_id,
        local_date: localDate,
        status: "assigned",
        arc_user_id: arcStep.user_arc_id,
      });

      if (!arcInsertError) {
        return { assigned: true };
      }
      console.error(
        "Failed to assign arc quest, falling back:",
        arcInsertError.code,
        arcInsertError.message,
      );
    }
    // If arcStepResult is empty array, user has no active arc - this is expected
  } catch (err) {
    // Catch unexpected errors (should not happen with proper error field checking above)
    console.error(
      `Unexpected error in arc step lookup for user ${userId}:`,
      err,
    );
  }

  // Try preference-weighted quest selection first (Quest Choice feature)
  let templateId: string | null = null;

  try {
    const { data: weightedResult } = await supabase.rpc(
      "get_weighted_quest_for_user",
      {
        p_user_id: userId,
        p_exclude_category: null,
      },
    );

    if (weightedResult) {
      templateId = weightedResult;
    }
  } catch (err) {
    console.log(
      `Weighted selection not available for user ${userId}, falling back to random`,
    );
  }

  // Fallback to random selection if weighted selection fails or returns null
  if (!templateId) {
    const { data: templates } = await supabase
      .from("quest_templates")
      .select("id")
      .eq("is_active", true)
      .limit(10);

    if (!templates?.length) {
      return { assigned: false, reason: "no_templates" };
    }

    templateId = templates[Math.floor(Math.random() * templates.length)].id;
  }

  // Assign the quest
  const { error } = await supabase.from("quests").insert({
    user_id: userId,
    template_id: templateId,
    local_date: localDate,
    status: "assigned",
  });

  if (error) {
    console.error("Failed to assign quest:", error.code);
    return { assigned: false, reason: "insert_failed" };
  }

  return { assigned: true };
}

// Check and apply streak protection (shields or recovery)
async function checkStreakProtection(
  supabase: SupabaseClient,
  userId: string,
): Promise<{
  result: StreakProtectionResult | null;
  notificationType: "shield_used" | "recovery_available" | null;
}> {
  try {
    const rpcPromise = supabase.rpc("check_streak_protection", {
      p_user_id: userId,
    }) as Promise<{
      data: StreakProtectionResult[] | null;
      error: Error | null;
    }>;

    const { data, error } = await withTimeout(
      rpcPromise,
      OPERATION_TIMEOUT_MS,
      "check_streak_protection",
    );

    if (error || !data?.length) {
      console.error("Error checking streak protection:", error);
      return { result: null, notificationType: null };
    }

    const result = data[0];
    let notificationType: "shield_used" | "recovery_available" | null = null;

    if (result.streak_protected) {
      notificationType = "shield_used";
    } else if (result.recovery_available) {
      notificationType = "recovery_available";
    }

    return { result, notificationType };
  } catch (error) {
    console.error("Streak protection check failed:", error);
    return { result: null, notificationType: null };
  }
}

// Send streak protection notification
async function sendStreakNotification(
  supabase: SupabaseClient,
  userId: string,
  type: "shield_used" | "recovery_available",
  data: {
    streak?: number;
    shieldsRemaining?: number;
    shieldsMax?: number;
    streakToRecover?: number;
  },
): Promise<void> {
  try {
    await supabase.functions.invoke("send-notification", {
      body: {
        type,
        recipientId: userId,
        data,
      },
    });
    console.log(`Sent ${type} notification to user ${userId}`);
  } catch (error) {
    console.error(`Failed to send ${type} notification:`, error);
  }
}

// Start a recovery quest
async function startRecoveryQuest(
  supabase: SupabaseClient,
  userId: string,
): Promise<RecoveryQuestResult> {
  const { data, error } = (await supabase.rpc("start_recovery_quest", {
    p_user_id: userId,
  })) as { data: RecoveryQuestResult[] | null; error: Error | null };

  if (error || !data?.length) {
    console.error("Error starting recovery quest:", error);
    return {
      success: false,
      attempt_id: null,
      quest_template_id: null,
      quest_title: null,
      quest_description: null,
      quest_estimated_minutes: null,
      quest_instructions: null,
      error_message: error?.message || "Failed to start recovery quest",
    };
  }

  return data[0];
}

// Complete a recovery quest
async function completeRecoveryQuest(
  supabase: SupabaseClient,
  userId: string,
  attemptId: string,
): Promise<RecoveryCompleteResult> {
  const { data, error } = (await supabase.rpc("complete_recovery_quest", {
    p_user_id: userId,
    p_attempt_id: attemptId,
  })) as { data: RecoveryCompleteResult[] | null; error: Error | null };

  if (error || !data?.length) {
    console.error("Error completing recovery quest:", error);
    return {
      success: false,
      restored_streak: 0,
      error_message: error?.message || "Failed to complete recovery quest",
    };
  }

  return data[0];
}

// Update user stats after quest completion
async function updateStreakAndCheckMilestone(
  supabase: SupabaseClient,
  userId: string,
  localDate: string,
): Promise<void> {
  // Get user's current stats and profile
  const [{ data: stats }, { data: profile }] = await Promise.all([
    supabase
      .from("user_stats")
      .select("current_streak_days, longest_streak_days, last_quest_date")
      .eq("user_id", userId)
      .single(),
    supabase.from("profiles").select("display_name").eq("id", userId).single(),
  ]);

  if (!stats) return;

  // Calculate new streak
  let newStreak = 1;
  if (shouldContinueStreak(stats.last_quest_date, localDate)) {
    newStreak = stats.current_streak_days + 1;
  }

  const newLongest = Math.max(stats.longest_streak_days, newStreak);

  // Update stats
  await supabase
    .from("user_stats")
    .update({
      current_streak_days: newStreak,
      longest_streak_days: newLongest,
      last_quest_date: localDate,
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", userId);

  // Check for milestone
  if (STREAK_MILESTONES.includes(newStreak)) {
    const displayName = profile?.display_name || "Someone";
    await postStreakMilestone(supabase, userId, newStreak, displayName);
  }

  // Check and award shield at 7-day milestones
  await checkShieldEarning(supabase, userId, newStreak);
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const headers = {
    ...getCorsHeaders(origin),
    "Content-Type": "application/json",
  };

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders(origin) });
  }

  try {
    // Initialize Supabase client with service role
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Check for cron secret (for scheduled runs)
    const cronSecret = req.headers.get("X-Cron-Secret");
    const expectedSecret = Deno.env.get("CRON_SECRET");

    // If cron request, process all users
    if (cronSecret && cronSecret === expectedSecret) {
      console.log("Processing daily quest assignment (cron)");

      // Get all users with their timezones - with timeout
      const fetchUsersPromise = supabaseAdmin
        .from("profiles")
        .select("id, timezone");

      const { data: users, error: fetchError } = await withTimeout(
        fetchUsersPromise,
        OPERATION_TIMEOUT_MS,
        "fetch_users",
      );

      if (fetchError) {
        console.error("Error fetching users:", fetchError);
        return new Response(
          JSON.stringify({ success: false, error: fetchError.message }),
          { status: 500, headers },
        );
      }

      if (!users?.length) {
        return new Response(JSON.stringify({ success: true, processed: 0 }), {
          status: 200,
          headers,
        });
      }

      let assigned = 0;
      let skipped = 0;
      let errors = 0;

      // Process users in parallel batches for better performance
      const userBatches = chunkArray(users, CRON_BATCH_SIZE);

      for (const batch of userBatches) {
        const batchPromises = batch.map(async (user) => {
          try {
            const localDate = getLocalDate(user.timezone || "UTC");
            return await assignQuestToUser(supabaseAdmin, user.id, localDate);
          } catch (error) {
            console.error(`Error assigning quest to user ${user.id}:`, error);
            return { assigned: false, reason: "error" };
          }
        });

        const batchResults = await Promise.allSettled(batchPromises);

        for (const result of batchResults) {
          if (result.status === "fulfilled") {
            if (result.value.assigned) {
              assigned++;
            } else if (result.value.reason === "error") {
              errors++;
            } else {
              skipped++;
            }
          } else {
            errors++;
            console.error("Quest assignment failed:", result.reason);
          }
        }
      }

      console.log(
        `Cron complete: ${assigned} assigned, ${skipped} skipped, ${errors} errors`,
      );

      return new Response(
        JSON.stringify({ success: true, assigned, skipped, errors }),
        { status: 200, headers },
      );
    }

    // For authenticated user requests (quest completion with streak update)
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers,
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers,
      });
    }

    // Parse request body
    const body = await req.json().catch(() => ({}));
    const action = body.action || "assign";

    // Get user's timezone
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("timezone")
      .eq("id", user.id)
      .single();

    const localDate = getLocalDate(profile?.timezone || "UTC");

    if (action === "assign") {
      // Assign quest to current user
      const result = await assignQuestToUser(supabaseAdmin, user.id, localDate);
      return new Response(JSON.stringify(result), { status: 200, headers });
    }

    if (action === "check_protection") {
      // Check streak protection status and apply shield/recovery if needed
      const { result: protectionResult, notificationType } =
        await checkStreakProtection(supabaseAdmin, user.id);

      if (!protectionResult) {
        return new Response(
          JSON.stringify({ error: "Failed to check streak protection" }),
          { status: 500, headers },
        );
      }

      // Send notification if streak was protected or recovery is available
      if (notificationType) {
        // Get user stats for notification data
        const { data: stats } = await supabaseAdmin
          .from("user_stats")
          .select("streak_shields_remaining, streak_shields_max")
          .eq("user_id", user.id)
          .single();

        if (notificationType === "shield_used") {
          await sendStreakNotification(supabaseAdmin, user.id, "shield_used", {
            streak: protectionResult.new_streak,
            shieldsRemaining: stats?.streak_shields_remaining ?? 0,
            shieldsMax: stats?.streak_shields_max ?? 1,
          });
        } else if (notificationType === "recovery_available") {
          await sendStreakNotification(
            supabaseAdmin,
            user.id,
            "recovery_available",
            {
              streakToRecover: protectionResult.streak_before_break ?? 0,
            },
          );
        }
      }

      return new Response(
        JSON.stringify({
          success: true,
          ...protectionResult,
        }),
        { status: 200, headers },
      );
    }

    if (action === "start_recovery") {
      // Start a recovery quest
      const result = await startRecoveryQuest(supabaseAdmin, user.id);

      if (!result.success) {
        return new Response(
          JSON.stringify({
            success: false,
            error: result.error_message,
          }),
          { status: 400, headers },
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          attemptId: result.attempt_id,
          quest: {
            id: result.quest_template_id,
            title: result.quest_title,
            description: result.quest_description,
            estimatedMinutes: result.quest_estimated_minutes,
            instructions: result.quest_instructions,
          },
        }),
        { status: 200, headers },
      );
    }

    if (action === "complete_recovery") {
      // Complete a recovery quest and restore streak
      const attemptId = body.attemptId;
      if (!attemptId) {
        return new Response(JSON.stringify({ error: "Missing attemptId" }), {
          status: 400,
          headers,
        });
      }

      const result = await completeRecoveryQuest(
        supabaseAdmin,
        user.id,
        attemptId,
      );

      if (!result.success) {
        return new Response(
          JSON.stringify({
            success: false,
            error: result.error_message,
          }),
          { status: 400, headers },
        );
      }

      // Check for streak milestone after recovery
      if (STREAK_MILESTONES.includes(result.restored_streak)) {
        const { data: userProfile } = await supabaseAdmin
          .from("profiles")
          .select("display_name")
          .eq("id", user.id)
          .single();

        const displayName = userProfile?.display_name || "Someone";
        await postStreakMilestone(
          supabaseAdmin,
          user.id,
          result.restored_streak,
          displayName,
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          restoredStreak: result.restored_streak,
        }),
        { status: 200, headers },
      );
    }

    if (action === "complete") {
      // Mark quest complete and update streak
      const questId = body.questId;
      if (!questId) {
        return new Response(JSON.stringify({ error: "Missing questId" }), {
          status: 400,
          headers,
        });
      }

      // Verify user owns this quest
      const { data: quest, error: questError } = await supabaseAdmin
        .from("quests")
        .select("*")
        .eq("id", questId)
        .eq("user_id", user.id)
        .single();

      if (questError || !quest) {
        return new Response(JSON.stringify({ error: "Quest not found" }), {
          status: 404,
          headers,
        });
      }

      if (quest.status === "completed") {
        return new Response(
          JSON.stringify({ success: true, alreadyCompleted: true }),
          { status: 200, headers },
        );
      }

      // Mark quest as completed
      await supabaseAdmin
        .from("quests")
        .update({
          status: "completed",
          completed_at: new Date().toISOString(),
        })
        .eq("id", questId);

      // Update streak and check for milestone
      await updateStreakAndCheckMilestone(
        supabaseAdmin,
        user.id,
        quest.local_date,
      );

      // Check if quest was part of an arc and handle milestone/completion
      if (quest.arc_user_id) {
        try {
          // Increment arc day (current_day is now N+1)
          await supabaseAdmin.rpc("increment_arc_day", {
            p_user_arc_id: quest.arc_user_id,
          });

          // Get updated arc progress (current_day has been incremented by increment_arc_day)
          const { data: arcProgress } = await supabaseAdmin
            .from("user_quest_arcs")
            .select(
              "current_day, snapshot_milestone_days, snapshot_duration_days, arc:quest_arcs(title)",
            )
            .eq("id", quest.arc_user_id)
            .single();

          if (arcProgress) {
            // Check if the UPDATED current_day is a milestone
            const isMilestone = arcProgress.snapshot_milestone_days?.includes(
              arcProgress.current_day,
            );

            if (isMilestone) {
              console.log(
                `Arc milestone reached: day ${arcProgress.current_day} for user ${user.id}`,
              );

              // Post milestone to user's circles
              const { data: memberships } = await supabaseAdmin
                .from("circle_members")
                .select("circle_id")
                .eq("user_id", user.id);

              const { data: userProfile } = await supabaseAdmin
                .from("profiles")
                .select("display_name, share_mood_in_circles")
                .eq("id", user.id)
                .single();

              // Respect privacy setting - only post if sharing is enabled
              if (
                userProfile?.share_mood_in_circles !== false &&
                memberships?.length
              ) {
                const displayName = userProfile?.display_name || "Someone";
                const arcTitle =
                  (arcProgress.arc as { title?: string })?.title || "their arc";

                for (const membership of memberships) {
                  await supabaseAdmin.from("circle_posts").insert({
                    circle_id: membership.circle_id,
                    user_id: user.id,
                    kind: "checkin",
                    mood_emoji: "🎯",
                    body_text: `${displayName} reached day ${arcProgress.current_day} of ${arcTitle}!`,
                    local_date: quest.local_date,
                  });
                }
              }
            }

            // Check for arc completion (note: increment_arc_day RPC already handles
            // marking arc as completed, but we log it here for observability)
            if (arcProgress.current_day >= arcProgress.snapshot_duration_days) {
              console.log(
                `Arc completed for user ${user.id}: ${(arcProgress.arc as { title?: string })?.title}`,
              );
            }
          }
        } catch (arcErr) {
          console.error("Arc completion handling error:", arcErr);
        }
      }

      return new Response(JSON.stringify({ success: true, completed: true }), {
        status: 200,
        headers,
      });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), {
      status: 400,
      headers,
    });
  } catch (error) {
    console.error("Assign quest error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
