// N006: Wellbeing Debt Calculator - Transaction Detection Edge Function
// Runs daily at 1:00 AM UTC via cron
// Detects deposits (positive activities) and withdrawals (stressors) from all data sources

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import type {
  Transaction,
  HealthKitSleepData,
  MoodEntry,
  ExerciseSession,
  CirclePost,
  Quest,
  CircadianData,
} from "../_shared/wellbeing-debt-types.ts";
import {
  getYesterdayISO,
  calculateSleepQuality,
  calculateSleepDeposit,
  calculatePoorSleepWithdrawal,
} from "../_shared/wellbeing-debt-utils.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // CRON requests: verify secret token
    if (req.method === "GET" || !req.headers.get("Authorization")) {
      const cronSecret = req.headers.get("X-Cron-Secret");
      const expectedSecret = Deno.env.get("CRON_SECRET");
      
      if (!expectedSecret || cronSecret !== expectedSecret) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        });
      }
      
      await detectTransactionsForAllUsers(supabase);
      return new Response(
        JSON.stringify({
          success: true,
          message: "Transaction detection completed",
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // MANUAL requests: verify JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Manual trigger: detect for specific user and date
    const { user_id, date } = await req.json();
    
    // Authorization check: user can only trigger for themselves
    if (user_id && user_id !== user.id) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }

    const transactions = await detectUserTransactions(
      supabase,
      user_id || user.id,
      date || getYesterdayISO(),
    );
    await upsertTransactions(supabase, transactions);

    return new Response(
      JSON.stringify({
        success: true,
        transactions_count: transactions.length,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error in detect-transactions:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

async function detectTransactionsForAllUsers(supabase: any) {
  const yesterday = getYesterdayISO();

  // Get all active users (logged in within last 30 days)
  const { data: activeUsers, error: usersError } = await supabase
    .from("profiles")
    .select("id")
    .gte(
      "last_login_at",
      new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(),
    );

  if (usersError) {
    console.error("Error fetching active users:", usersError);
    return;
  }

  console.log(`Processing ${activeUsers.length} active users for ${yesterday}`);

  for (const user of activeUsers) {
    try {
      const transactions = await detectUserTransactions(
        supabase,
        user.id,
        yesterday,
      );
      await upsertTransactions(supabase, transactions);
      console.log(
        `User ${user.id}: ${transactions.length} transactions detected`,
      );
    } catch (error) {
      console.error(`Error processing user ${user.id}:`, error);
      // Continue with other users
    }
  }
}

async function detectUserTransactions(
  supabase: any,
  userId: string,
  date: string,
): Promise<Transaction[]> {
  const transactions: Transaction[] = [];

  // DEPOSITS
  transactions.push(...(await detectSleepDeposits(supabase, userId, date)));
  transactions.push(...(await detectExerciseDeposits(supabase, userId, date)));
  transactions.push(...(await detectSocialDeposits(supabase, userId, date)));
  transactions.push(...(await detectQuestDeposits(supabase, userId, date)));

  // WITHDRAWALS
  transactions.push(...(await detectSleepWithdrawals(supabase, userId, date)));
  transactions.push(...(await detectMoodWithdrawals(supabase, userId, date)));
  transactions.push(...(await detectSocialWithdrawals(supabase, userId, date)));
  transactions.push(
    ...(await detectCircadianWithdrawals(supabase, userId, date)),
  );

  return transactions;
}

// =============================================================================
// DEPOSIT DETECTION
// =============================================================================

async function detectSleepDeposits(
  supabase: any,
  userId: string,
  date: string,
): Promise<Transaction[]> {
  try {
    // Query HealthKit sleep data for the date
    const { data: sleepData, error } = await supabase
      .from("healthkit_sleep_data")
      .select("*")
      .eq("user_id", userId)
      .eq("date", date)
      .single();

    if (error || !sleepData) {
      return []; // No sleep data available
    }

    // Assumption #2: Calculate sleep quality
    const quality = calculateSleepQuality(
      sleepData.total_sleep_seconds,
      sleepData.deep_sleep_seconds,
      sleepData.rem_sleep_seconds,
    );

    const amount = calculateSleepDeposit(quality);

    // Only create deposit if quality is good (>0)
    if (amount > 0) {
      return [
        {
          user_id: userId,
          date,
          type: "deposit",
          category: "sleep_quality",
          amount,
          source: "healthkit",
          description: `Sleep quality: ${(quality * 10).toFixed(1)}/10`,
          metadata: {
            duration_hours: (sleepData.total_sleep_seconds / 3600).toFixed(1),
            quality_score: quality.toFixed(2),
            has_sleep_stages: sleepData.deep_sleep_seconds !== null,
          },
        },
      ];
    }

    return [];
  } catch (error) {
    console.error(`Error detecting sleep deposits for user ${userId}:`, error);
    return [];
  }
}

async function detectExerciseDeposits(
  supabase: any,
  userId: string,
  date: string,
): Promise<Transaction[]> {
  try {
    const { data: sessions, error } = await supabase
      .from("exercise_sessions")
      .select("id, exercise_id")
      .eq("user_id", userId)
      .gte("completed_at", `${date}T00:00:00Z`)
      .lt("completed_at", `${date}T23:59:59Z`);

    if (error || !sessions || sessions.length === 0) {
      return [];
    }

    const sessionCount = sessions.length;
    const amount = sessionCount * 5; // +5 per exercise

    return [
      {
        user_id: userId,
        date,
        type: "deposit",
        category: "exercise_completion",
        amount,
        source: "exercise_sessions",
        description: `${sessionCount} exercise session${sessionCount > 1 ? "s" : ""} completed`,
        metadata: { session_count: sessionCount },
      },
    ];
  } catch (error) {
    console.error(
      `Error detecting exercise deposits for user ${userId}:`,
      error,
    );
    return [];
  }
}

async function detectSocialDeposits(
  supabase: any,
  userId: string,
  date: string,
): Promise<Transaction[]> {
  try {
    // Assumption #6: Use circle_posts table only
    const { data: posts, error } = await supabase
      .from("circle_posts")
      .select("id")
      .eq("user_id", userId)
      .gte("created_at", `${date}T00:00:00Z`)
      .lt("created_at", `${date}T23:59:59Z`);

    if (error || !posts || posts.length === 0) {
      return [];
    }

    const postCount = posts.length;
    const amount = Math.min(10, postCount * 2); // +2 per post, max +10

    return [
      {
        user_id: userId,
        date,
        type: "deposit",
        category: "social_connection",
        amount,
        source: "circle_posts",
        description: `${postCount} circle post${postCount > 1 ? "s" : ""}`,
        metadata: { post_count: postCount },
      },
    ];
  } catch (error) {
    console.error(`Error detecting social deposits for user ${userId}:`, error);
    return [];
  }
}

async function detectQuestDeposits(
  supabase: any,
  userId: string,
  date: string,
): Promise<Transaction[]> {
  try {
    const { data: quests, error } = await supabase
      .from("quests")
      .select("id")
      .eq("user_id", userId)
      .eq("date", date)
      .eq("status", "completed");

    if (error || !quests || quests.length === 0) {
      return [];
    }

    const questCount = quests.length;
    const amount = questCount * 5; // +5 per quest

    return [
      {
        user_id: userId,
        date,
        type: "deposit",
        category: "quest_completion",
        amount,
        source: "quests",
        description: `${questCount} quest${questCount > 1 ? "s" : ""} completed`,
        metadata: { quest_count: questCount },
      },
    ];
  } catch (error) {
    console.error(`Error detecting quest deposits for user ${userId}:`, error);
    return [];
  }
}

// =============================================================================
// WITHDRAWAL DETECTION
// =============================================================================

async function detectSleepWithdrawals(
  supabase: any,
  userId: string,
  date: string,
): Promise<Transaction[]> {
  try {
    const { data: sleepData, error } = await supabase
      .from("healthkit_sleep_data")
      .select("*")
      .eq("user_id", userId)
      .eq("date", date)
      .single();

    if (error || !sleepData) {
      return [];
    }

    const hoursSlept = sleepData.total_sleep_seconds / 3600;
    const amount = calculatePoorSleepWithdrawal(hoursSlept);

    if (amount > 0) {
      return [
        {
          user_id: userId,
          date,
          type: "withdrawal",
          category: "poor_sleep",
          amount,
          source: "healthkit",
          description: `Slept ${hoursSlept.toFixed(1)}h (threshold: 6h)`,
          metadata: { hours_slept: hoursSlept.toFixed(1) },
        },
      ];
    }

    return [];
  } catch (error) {
    console.error(
      `Error detecting sleep withdrawals for user ${userId}:`,
      error,
    );
    return [];
  }
}

async function detectMoodWithdrawals(
  supabase: any,
  userId: string,
  date: string,
): Promise<Transaction[]> {
  try {
    const { data: moods, error } = await supabase
      .from("moods")
      .select("mood_score, created_at")
      .eq("user_id", userId)
      .gte("created_at", `${date}T00:00:00Z`)
      .lt("created_at", `${date}T23:59:59Z`);

    if (error || !moods || moods.length === 0) {
      return [];
    }

    // Assumption #8: Create separate withdrawal for each mood <4
    const negativeMoods = moods.filter((m) => m.mood_score < 4);

    return negativeMoods.map((mood, idx) => ({
      user_id: userId,
      date,
      type: "withdrawal",
      category: "negative_mood",
      amount: 3, // Fixed -3 per negative mood
      source: "mood_log",
      description: `Mood score: ${mood.mood_score}/10`,
      metadata: { mood_score: mood.mood_score, entry_index: idx },
    }));
  } catch (error) {
    console.error(
      `Error detecting mood withdrawals for user ${userId}:`,
      error,
    );
    return [];
  }
}

async function detectSocialWithdrawals(
  supabase: any,
  userId: string,
  date: string,
): Promise<Transaction[]> {
  try {
    // Assumption #7: Isolation = 3+ consecutive days of zero circle activity
    const threeDaysAgo = new Date(date);
    threeDaysAgo.setDate(threeDaysAgo.getDate() - 3);
    const startDate = threeDaysAgo.toISOString().split("T")[0];

    const { data: recentPosts, error } = await supabase
      .from("circle_posts")
      .select("id")
      .eq("user_id", userId)
      .gte("created_at", `${startDate}T00:00:00Z`)
      .lt("created_at", `${date}T23:59:59Z`);

    if (error) {
      console.error(
        `Error checking social activity for user ${userId}:`,
        error,
      );
      return [];
    }

    // If no posts in last 3 days, create isolation withdrawal
    if (!recentPosts || recentPosts.length === 0) {
      return [
        {
          user_id: userId,
          date,
          type: "withdrawal",
          category: "social_isolation",
          amount: 5,
          source: "inferred",
          description: "3+ days without circle activity",
          metadata: { days_isolated: 3 },
        },
      ];
    }

    return [];
  } catch (error) {
    console.error(
      `Error detecting social withdrawals for user ${userId}:`,
      error,
    );
    return [];
  }
}

async function detectCircadianWithdrawals(
  supabase: any,
  userId: string,
  date: string,
): Promise<Transaction[]> {
  try {
    // Query N002 circadian_rhythm_data for social jetlag
    const { data: circadianData, error } = await supabase
      .from("circadian_rhythm_data")
      .select("social_jetlag_minutes")
      .eq("user_id", userId)
      .eq("date", date)
      .single();

    if (error || !circadianData) {
      return []; // N002 not deployed or no data
    }

    const socialJetlagHours = circadianData.social_jetlag_minutes / 60;

    // Threshold: >1.5 hours of social jetlag
    if (socialJetlagHours > 1.5) {
      return [
        {
          user_id: userId,
          date,
          type: "withdrawal",
          category: "circadian_disruption",
          amount: 5,
          source: "circadian_shield",
          description: `Social jetlag: ${socialJetlagHours.toFixed(1)}h`,
          metadata: { social_jetlag_hours: socialJetlagHours.toFixed(1) },
        },
      ];
    }

    return [];
  } catch (error) {
    console.error(
      `Error detecting circadian withdrawals for user ${userId}:`,
      error,
    );
    return [];
  }
}

// =============================================================================
// TRANSACTION PERSISTENCE
// =============================================================================

async function upsertTransactions(supabase: any, transactions: Transaction[]) {
  if (transactions.length === 0) return;

  const { error } = await supabase
    .from("wellbeing_transactions")
    .upsert(transactions, {
      onConflict: "user_id,date,source,category",
      ignoreDuplicates: false,
    });

  if (error) {
    console.error("Error upserting transactions:", error);
    throw error;
  }
}
