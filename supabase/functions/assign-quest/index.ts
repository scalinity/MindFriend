// MindFriend Assign Quest Edge Function
// Handles daily quest assignment and streak milestone detection
// Triggered by cron job or directly
// See: specs/03-circle-virality.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders, corsHeaders } from "../_shared/cors.ts";

// Streak milestones that trigger circle posts
const STREAK_MILESTONES = [7, 14, 30, 60, 100, 365];

interface QuestTemplate {
  id: string;
  type: string;
  title: string;
  description: string;
  estimated_minutes: number;
  difficulty: string;
  tags: string[];
}

interface UserStats {
  current_streak_days: number;
  longest_streak_days: number;
  last_quest_date: string | null;
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

// Assign quest to a single user
async function assignQuestToUser(
  supabase: SupabaseClient,
  userId: string,
  localDate: string,
): Promise<{ assigned: boolean; reason?: string }> {
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

  // Get a random quest template (can be enhanced to consider wellness_focus)
  const { data: templates } = await supabase
    .from("quest_templates")
    .select("*")
    .limit(10);

  if (!templates?.length) {
    return { assigned: false, reason: "no_templates" };
  }

  // Random selection (could be weighted by user preferences later)
  const template = templates[Math.floor(Math.random() * templates.length)];

  // Assign the quest
  const { error } = await supabase.from("quests").insert({
    user_id: userId,
    template_id: template.id,
    local_date: localDate,
    status: "assigned",
  });

  if (error) {
    console.error("Failed to assign quest:", error.code);
    return { assigned: false, reason: "insert_failed" };
  }

  return { assigned: true };
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
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const origin = req.headers.get("Origin");
  const headers = {
    ...getCorsHeaders(origin),
    "Content-Type": "application/json",
  };

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

      // Get all users with their timezones
      const { data: users } = await supabaseAdmin
        .from("profiles")
        .select("id, timezone");

      if (!users?.length) {
        return new Response(JSON.stringify({ success: true, processed: 0 }), {
          status: 200,
          headers,
        });
      }

      let assigned = 0;
      let skipped = 0;

      for (const user of users) {
        const localDate = getLocalDate(user.timezone || "UTC");
        const result = await assignQuestToUser(
          supabaseAdmin,
          user.id,
          localDate,
        );
        if (result.assigned) {
          assigned++;
        } else {
          skipped++;
        }
      }

      return new Response(
        JSON.stringify({ success: true, assigned, skipped }),
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
