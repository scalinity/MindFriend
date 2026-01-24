// N006: Wellbeing Debt Calculator - Debt Score Calculation Edge Function
// Runs daily at 2:00 AM UTC via cron (after detect-transactions)
// Calculates rolling debts, trends, threshold status, and updates user profiles

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import type {
  Transaction,
  DebtScore,
  UserProfile,
  TrendData,
  ThresholdStatus,
  CrashEvent,
  CategoryStats,
} from "../_shared/wellbeing-debt-types.ts";
import {
  getYesterdayISO,
  getDateNDaysAgo,
  calculateSlope,
  calculatePercentile10,
} from "../_shared/wellbeing-debt-utils.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Manual trigger: calculate for specific user and date
    if (req.method === "POST") {
      const { user_id, date } = await req.json();
      const score = await calculateUserDebtScore(
        supabase,
        user_id,
        date || getYesterdayISO(),
      );

      return new Response(JSON.stringify({ success: true, score }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // Cron trigger: calculate for all active users
    await calculateDebtScoresForAllUsers(supabase);

    return new Response(
      JSON.stringify({
        success: true,
        message: "Debt score calculation completed",
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error in calculate-debt-score:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

async function calculateDebtScoresForAllUsers(supabase: any) {
  const yesterday = getYesterdayISO();

  // Get all users who have transactions for yesterday
  const { data: usersWithTransactions, error } = await supabase
    .from("wellbeing_transactions")
    .select("user_id")
    .eq("date", yesterday);

  if (error) {
    console.error("Error fetching users with transactions:", error);
    return;
  }

  // Deduplicate user IDs
  const uniqueUserIds = [
    ...new Set(usersWithTransactions.map((t) => t.user_id)),
  ];

  console.log(
    `Processing debt scores for ${uniqueUserIds.length} users on ${yesterday}`,
  );

  for (const userId of uniqueUserIds) {
    try {
      const score = await calculateUserDebtScore(supabase, userId, yesterday);
      await insertDebtScore(supabase, score);
      await updateUserProfile(supabase, userId, yesterday);
      console.log(`User ${userId}: Debt score calculated and profile updated`);
    } catch (error) {
      console.error(`Error processing user ${userId}:`, error);
      // Continue with other users
    }
  }
}

async function calculateUserDebtScore(
  supabase: any,
  userId: string,
  date: string,
): Promise<DebtScore> {
  // 1. Get transactions for past 30 days (to calculate all rolling windows)
  const startDate = getDateNDaysAgo(date, 29); // 30 days including date
  const { data: transactions, error } = await supabase
    .from("wellbeing_transactions")
    .select("*")
    .eq("user_id", userId)
    .gte("date", startDate)
    .lte("date", date)
    .order("date", { ascending: true });

  if (error) {
    throw new Error(`Error fetching transactions: ${error.message}`);
  }

  // 2. Calculate daily balance for target date
  const dailyBalance = calculateDailyBalance(transactions, date);

  // 3. Calculate rolling debts (7, 14, 30 day)
  const rolling7Day = calculateRollingDebt(transactions, date, 7);
  const rolling14Day = calculateRollingDebt(transactions, date, 14);
  const rolling30Day = calculateRollingDebt(transactions, date, 30);

  // 4. Calculate trend
  const trend = calculateTrend(transactions, date);

  // 5. Get user profile for threshold
  const profile = await getUserProfile(supabase, userId);

  // 6. Calculate threshold status
  const thresholdStatus = calculateThresholdStatus(
    rolling14Day, // Use 14-day rolling debt as "current debt"
    trend,
    profile,
  );

  return {
    user_id: userId,
    date,
    daily_balance: dailyBalance,
    rolling_debt_7day: rolling7Day,
    rolling_debt_14day: rolling14Day,
    rolling_debt_30day: rolling30Day,
    trend,
    threshold_status: thresholdStatus,
  };
}

// =============================================================================
// DEBT CALCULATION
// =============================================================================

function calculateDailyBalance(
  transactions: Transaction[],
  date: string,
): number {
  const dayTransactions = transactions.filter((t) => t.date === date);

  const deposits = dayTransactions
    .filter((t) => t.type === "deposit")
    .reduce((sum, t) => sum + t.amount, 0);

  const withdrawals = dayTransactions
    .filter((t) => t.type === "withdrawal")
    .reduce((sum, t) => sum + t.amount, 0);

  // Clamp between -100 and +100 (Assumption #8)
  const balance = deposits - withdrawals;
  return Math.max(-100, Math.min(100, balance));
}

function calculateRollingDebt(
  transactions: Transaction[],
  endDate: string,
  days: number,
): number {
  const startDate = getDateNDaysAgo(endDate, days - 1);

  const relevantTransactions = transactions.filter((t) => {
    return t.date >= startDate && t.date <= endDate;
  });

  const deposits = relevantTransactions
    .filter((t) => t.type === "deposit")
    .reduce((sum, t) => sum + t.amount, 0);

  const withdrawals = relevantTransactions
    .filter((t) => t.type === "withdrawal")
    .reduce((sum, t) => sum + t.amount, 0);

  const net = deposits - withdrawals;

  // Only negative balances are "debt" (Assumption #8: zero state)
  return net < 0 ? Math.abs(net) : 0;
}

function calculateTrend(
  transactions: Transaction[],
  endDate: string,
): TrendData {
  // Get last 7 days of daily balances
  const debts: number[] = [];
  for (let i = 6; i >= 0; i--) {
    const date = getDateNDaysAgo(endDate, i);
    const balance = calculateDailyBalance(transactions, date);
    debts.push(balance);
  }

  // Linear regression for trend velocity
  const slope = calculateSlope(debts);

  // Determine direction
  let direction: "improving" | "worsening" | "stable";
  if (slope > 1) {
    direction = "improving"; // Positive velocity = more deposits
  } else if (slope < -1) {
    direction = "worsening"; // Negative velocity = more withdrawals
  } else {
    direction = "stable";
  }

  // Project 7 days forward
  const currentDebt = debts[debts.length - 1];
  const projection7Day = currentDebt + slope * 7;

  return {
    direction,
    velocity: slope,
    projection_7day: projection7Day,
  };
}

function calculateThresholdStatus(
  currentDebt: number,
  trend: TrendData,
  profile: UserProfile,
): ThresholdStatus {
  const threshold = profile.personal_threshold || -50; // Default -50

  // Calculate how close to threshold (as ratio)
  const debtRatio = currentDebt / Math.abs(threshold);

  // Determine severity
  let severity: "safe" | "warning" | "danger";
  if (debtRatio < 0.7) {
    severity = "safe";
  } else if (debtRatio < 0.9) {
    severity = "warning";
  } else {
    severity = "danger"; // ≥90% of threshold
  }

  // Project days until crash based on trend
  let daysUntilCrash: number | null = null;
  if (
    trend.direction === "worsening" &&
    trend.velocity < 0 &&
    currentDebt < Math.abs(threshold)
  ) {
    const debtRemaining = Math.abs(threshold) - currentDebt;
    daysUntilCrash = Math.ceil(debtRemaining / Math.abs(trend.velocity));
  }

  // Confidence based on crash history size (Assumption #3: min 3 crashes)
  const crashCount = profile.crash_history.crashes.length;
  const confidence = Math.min(1.0, crashCount / 10);

  return {
    current_debt: currentDebt,
    threshold,
    severity,
    days_until_crash: daysUntilCrash,
    confidence,
  };
}

// =============================================================================
// USER PROFILE MANAGEMENT
// =============================================================================

async function getUserProfile(
  supabase: any,
  userId: string,
): Promise<UserProfile> {
  const { data: profile, error } = await supabase
    .from("wellbeing_debt_profiles")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (error || !profile) {
    // Create default profile
    const defaultProfile: UserProfile = {
      user_id: userId,
      personal_threshold: -50,
      crash_history: { crashes: [], last_updated: null },
      top_drains: { categories: [], last_updated: null },
      top_deposits: { categories: [], last_updated: null },
    };

    await supabase
      .from("wellbeing_debt_profiles")
      .insert(defaultProfile)
      .single();

    return defaultProfile;
  }

  return profile;
}

async function updateUserProfile(supabase: any, userId: string, date: string) {
  // 1. Detect if today is a crash day
  const isCrash = await detectCrash(supabase, userId, date);

  if (isCrash) {
    await handleCrashDetection(supabase, userId, date);
  }

  // 2. Update top drains/deposits (monthly)
  await updateTopCategories(supabase, userId, date);
}

async function detectCrash(
  supabase: any,
  userId: string,
  date: string,
): Promise<boolean> {
  // Assumption #1: Crash = mood ≤2 within 48 hours
  const startDate = date;
  const endDate = new Date(date);
  endDate.setDate(endDate.getDate() + 2); // Check next 48 hours
  const endDateStr = endDate.toISOString().split("T")[0];

  const { data: moods, error } = await supabase
    .from("moods")
    .select("mood_score")
    .eq("user_id", userId)
    .gte("created_at", `${startDate}T00:00:00Z`)
    .lt("created_at", `${endDateStr}T23:59:59Z`);

  if (error || !moods) {
    return false;
  }

  return moods.some((m) => m.mood_score <= 2);
}

async function handleCrashDetection(
  supabase: any,
  userId: string,
  date: string,
) {
  // Get current profile
  const profile = await getUserProfile(supabase, userId);

  // Get debt at crash (7-day rolling debt from yesterday)
  const yesterday = getDateNDaysAgo(date, 1);
  const { data: scoreAtCrash, error } = await supabase
    .from("wellbeing_debt_scores")
    .select("rolling_debt_7day")
    .eq("user_id", userId)
    .eq("date", yesterday)
    .single();

  const debtAtCrash = scoreAtCrash?.rolling_debt_7day || 0;

  // Get mood score that triggered crash
  const { data: crashMood } = await supabase
    .from("moods")
    .select("mood_score")
    .eq("user_id", userId)
    .gte("created_at", `${date}T00:00:00Z`)
    .order("created_at", { ascending: true })
    .limit(1)
    .single();

  const moodScore = crashMood?.mood_score || 1;

  // Add to crash history
  const newCrash: CrashEvent = {
    date,
    debt_at_crash: debtAtCrash,
    mood_score: moodScore,
  };

  const updatedCrashes = [...profile.crash_history.crashes, newCrash];

  // Recalculate threshold if ≥3 crashes (Assumption #3)
  let newThreshold = profile.personal_threshold || -50;
  if (updatedCrashes.length >= 3) {
    const crashDebts = updatedCrashes.map((c) => c.debt_at_crash);
    newThreshold = calculatePercentile10(crashDebts);
  }

  // Update profile
  await supabase
    .from("wellbeing_debt_profiles")
    .update({
      personal_threshold: newThreshold,
      crash_history: {
        crashes: updatedCrashes,
        last_updated: new Date().toISOString(),
      },
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", userId);

  console.log(
    `Crash detected for user ${userId}: debt=${debtAtCrash}, mood=${moodScore}, new_threshold=${newThreshold}`,
  );
}

async function updateTopCategories(
  supabase: any,
  userId: string,
  date: string,
) {
  // Get transactions for last 30 days
  const startDate = getDateNDaysAgo(date, 29);
  const { data: transactions, error } = await supabase
    .from("wellbeing_transactions")
    .select("type, category, amount")
    .eq("user_id", userId)
    .gte("date", startDate)
    .lte("date", date);

  if (error || !transactions) {
    return;
  }

  // Aggregate by category and type
  const categoryMap = new Map<string, { total: number; count: number }>();

  for (const t of transactions) {
    const key = t.category;
    const existing = categoryMap.get(key) || { total: 0, count: 0 };
    categoryMap.set(key, {
      total: existing.total + t.amount,
      count: existing.count + 1,
    });
  }

  // Separate drains and deposits
  const drains: CategoryStats[] = [];
  const deposits: CategoryStats[] = [];

  for (const [category, stats] of categoryMap.entries()) {
    const stat: CategoryStats = {
      category,
      total_amount: stats.total,
      frequency: stats.count,
    };

    if (stats.total < 0) {
      drains.push(stat);
    } else if (stats.total > 0) {
      deposits.push(stat);
    }
  }

  // Sort and take top 3
  const topDrains = drains
    .sort((a, b) => a.total_amount - b.total_amount) // Most negative first
    .slice(0, 3);

  const topDeposits = deposits
    .sort((a, b) => b.total_amount - a.total_amount) // Most positive first
    .slice(0, 3);

  // Update profile
  await supabase
    .from("wellbeing_debt_profiles")
    .update({
      top_drains: {
        categories: topDrains,
        last_updated: new Date().toISOString(),
      },
      top_deposits: {
        categories: topDeposits,
        last_updated: new Date().toISOString(),
      },
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", userId);
}

// =============================================================================
// PERSISTENCE
// =============================================================================

async function insertDebtScore(supabase: any, score: DebtScore) {
  const { error } = await supabase
    .from("wellbeing_debt_scores")
    .upsert(score, { onConflict: "user_id,date" });

  if (error) {
    console.error("Error inserting debt score:", error);
    throw error;
  }
}
