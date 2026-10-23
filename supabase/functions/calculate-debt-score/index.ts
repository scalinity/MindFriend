// N006: Wellbeing Debt Calculator - Debt Score Calculation Edge Function
// Runs daily at 2:00 AM UTC via cron (after detect-transactions)
// Calculates rolling debts, trends, threshold status, and updates user profiles

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  currentSourceTransactions,
  ledgerDate,
} from "./source-transactions.ts";
import type {
  CategoryStats,
  CrashEvent,
  DebtScore,
  ThresholdStatus,
  Transaction,
  TrendData,
  UserProfile,
} from "../_shared/wellbeing-debt-types.ts";
import {
  calculatePercentile10,
  getYesterdayISO,
} from "../_shared/wellbeing-debt-utils.ts";

type CurrentTrend = TrendData & {
  available: boolean;
  observed_days: number;
  accounting_version: number;
  calculated_at: string;
};
type CurrentDebtScore = DebtScore & {
  trend: CurrentTrend;
  source_transactions: Transaction[];
};

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

      await calculateDebtScoresForAllUsers(supabase);
      return new Response(
        JSON.stringify({
          success: true,
          message: "Debt score calculation completed",
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

    // Manual trigger: calculate for specific user and date
    const { user_id, date } = await req.json();
    const targetDate = date ??
      ledgerDate(new Date().toISOString().slice(0, 10), -1);

    // Authorization check: user can only trigger for themselves
    if (user_id && user_id !== user.id) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }

    const score = await calculateUserDebtScore(
      supabase,
      user_id || user.id,
      targetDate,
    );
    if (score) {
      await updateUserProfile(
        supabase,
        user.id,
        score.date,
        score.source_transactions,
      );
      score.threshold_status = calculateThresholdStatus(
        score.rolling_debt_14day,
        score.trend,
        await getUserProfile(supabase, user.id),
      );
      await insertDebtScore(supabase, score);
    } else {
      // Preserve the old derived amount as history, but never serve it as a current calculation.
      const { error } = await supabase.from("wellbeing_debt_scores").update({
        trend: {
          direction: "stable",
          velocity: 0,
          projection_7day: 0,
          available: false,
          observed_days: 0,
          accounting_version: 0,
          calculated_at: new Date().toISOString(),
          source_transactions: [],
        },
      }).eq("user_id", user.id).eq("date", targetDate);
      if (error) throw new Error("Empty calculation could not be saved");
      await updateUserProfile(supabase, user.id, targetDate, []);
    }

    return new Response(
      JSON.stringify({
        success: true,
        score,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error in calculate-debt-score:", error); // Log full error server-side
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
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
    ...new Set<string>(
      usersWithTransactions.map((t: { user_id: string }) => t.user_id),
    ),
  ];

  console.log(
    `Processing debt scores for ${uniqueUserIds.length} users on ${yesterday}`,
  );

  for (const userId of uniqueUserIds) {
    try {
      // Retain the existing scheduled ledger workload; fresh source scans are owner-requested only.
      const score = await calculateUserDebtScore(
        supabase,
        userId,
        yesterday,
        false,
      );
      if (score && await insertDebtScore(supabase, score)) {
        await updateUserProfile(
          supabase,
          userId,
          yesterday,
          score.source_transactions,
        );
      }
      console.log(`User ${userId}: Debt score processing completed`);
    } catch (error) {
      console.error(`Error processing user ${userId}:`, error);
      // Continue with other users
    }
  }
}

export async function calculateUserDebtScore(
  supabase: any,
  userId: string,
  date: string,
  currentSources = true,
): Promise<CurrentDebtScore | null> {
  ledgerDate(date); // Reject invalid date labels before queries or writes.
  let transactions: Transaction[];
  if (currentSources) {
    transactions = await currentSourceTransactions(supabase, userId, date);
  } else {
    const { data, error } = await supabase.from("wellbeing_transactions")
      .select("*").eq("user_id", userId)
      .gte("date", ledgerDate(date, -29)).lte("date", date).order("date", {
        ascending: true,
      });
    if (error || !data) throw new Error("Ledger unavailable");
    transactions = data;
  }
  transactions = transactions.filter((t) =>
    t.user_id === userId &&
    !(t.category === "social_isolation" && t.source === "inferred")
  );
  if (transactions.length === 0) return null;

  // 2. Calculate daily balance for target date
  const dailyBalance = calculateDailyBalance(transactions, date);

  // 3. Calculate rolling debts (7, 14, 30 day)
  const rolling7Day = calculateRollingDebt(transactions, date, 7);
  const rolling14Day = calculateRollingDebt(transactions, date, 14);
  const rolling30Day = calculateRollingDebt(transactions, date, 30);

  // 4. Calculate trend
  const trend = calculateTrend(transactions, date, currentSources ? 2 : 1);

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
    source_transactions: transactions,
  };
}

// =============================================================================
// DEBT CALCULATION
// =============================================================================

export function calculateDailyBalance(
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
  return Math.round(Math.max(-100, Math.min(100, balance)) * 100) / 100;
}

export function calculateRollingDebt(
  transactions: Transaction[],
  endDate: string,
  days: number,
): number {
  const startDate = ledgerDate(endDate, -(days - 1));

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
  return net < 0 ? Math.round(Math.abs(net) * 100) / 100 : 0;
}

export function calculateTrend(
  transactions: Transaction[],
  endDate: string,
  version = 2,
): CurrentTrend {
  const firstDate = ledgerDate(endDate, -6);
  const dates = [
    ...new Set(
      transactions.filter((t) => t.date >= firstDate && t.date <= endDate).map(
        (t) => t.date,
      ),
    ),
  ].sort();
  const currentDebt = calculateRollingDebt(transactions, endDate, 14);
  const base = {
    available: dates.length >= 2,
    observed_days: dates.length,
    accounting_version: version,
    calculated_at: new Date().toISOString(),
  };
  if (dates.length < 2) {
    return {
      direction: "stable",
      velocity: 0,
      projection_7day: currentDebt,
      ...base,
    };
  }
  const xs = dates.map((date) =>
    (Date.parse(date) - Date.parse(dates[0])) / 86_400_000
  );
  const ys = dates.map((date) => calculateRollingDebt(transactions, date, 14));
  const meanX = xs.reduce((a, b) => a + b, 0) / xs.length;
  const meanY = ys.reduce((a, b) => a + b, 0) / ys.length;
  const numerator = xs.reduce(
    (sum, x, i) => sum + (x - meanX) * (ys[i] - meanY),
    0,
  );
  const denominator = xs.reduce((sum, x) => sum + (x - meanX) ** 2, 0);
  const velocity = numerator / denominator;
  if (!Number.isFinite(velocity)) throw new Error("Invalid trend inputs");
  // Rolling debt is the non-negative unpaid deficit; a falling estimate reaches zero.
  return {
    direction: velocity > 1
      ? "worsening"
      : velocity < -1
      ? "improving"
      : "stable",
    velocity,
    projection_7day: Math.max(0, currentDebt + velocity * 7),
    ...base,
  };
}

export function calculateThresholdStatus(
  currentDebt: number,
  trend: CurrentTrend,
  profile: UserProfile,
): ThresholdStatus {
  const threshold = profile.personal_threshold ?? -75; // Default -75 (increased from -50 for more forgiving economy)

  const absThreshold = Math.abs(threshold);
  if (!Number.isFinite(absThreshold) || absThreshold === 0) {
    return {
      current_debt: currentDebt,
      threshold: null,
      severity: "safe",
      days_until_crash: null,
      confidence: 0,
    };
  }

  // Calculate how close to threshold (as ratio)
  const debtRatio = currentDebt / absThreshold;

  // Determine severity (adjusted zones for rebalanced economy)
  let severity: "safe" | "warning" | "danger";
  if (debtRatio < 0.6) {
    severity = "safe"; // <60% of threshold (was 70%)
  } else if (debtRatio < 0.85) {
    severity = "warning"; // 60-85% of threshold (was 70-90%)
  } else {
    severity = "danger"; // ≥85% of threshold (was 90%)
  }

  // Project days until crash based on trend
  let daysUntilCrash: number | null = null;
  if (
    trend.direction === "worsening" &&
    trend.available && trend.velocity > 0 &&
    currentDebt < absThreshold
  ) {
    const debtRemaining = absThreshold - currentDebt;
    daysUntilCrash = Math.ceil(debtRemaining / Math.abs(trend.velocity));
  }

  // Confidence: 0 if <3 crashes, scale to 1.0 at 10+ crashes (Assumption #3: min 3 crashes)
  const crashCount =
    new Set(profile.crash_history.crashes.map((crash) => crash.date)).size;
  const confidence = crashCount < 3 ? 0 : Math.min(1.0, crashCount / 10);

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
  canRetryCreation = true,
): Promise<UserProfile> {
  const { data: stored, error } = await supabase.from("wellbeing_debt_profiles")
    .select("*").eq("user_id", userId).maybeSingle();
  if (error) throw new Error("Debt profile unavailable");
  if (!stored) {
    const profile = {
      user_id: userId,
      learned_threshold: null,
      crash_history: { crashes: [], last_updated: null },
      top_drains: { categories: [] },
      top_deposits: { categories: [] },
    };
    const { error: insertError } = await supabase.from(
      "wellbeing_debt_profiles",
    ).insert(profile);
    if (insertError) {
      if (insertError.code === "23505" && canRetryCreation) {
        return await getUserProfile(supabase, userId, false);
      }
      throw new Error("Debt profile could not be saved");
    }
    return {
      user_id: userId,
      personal_threshold: null,
      crash_history: { crashes: [], last_updated: null },
      top_drains: { categories: [], last_updated: null },
      top_deposits: { categories: [], last_updated: null },
    };
  }
  const history = stored.crash_history;
  const crashes = Array.isArray(history) ? history : history?.crashes ?? [];
  if (!Array.isArray(crashes)) throw new Error("Invalid debt history");
  // Normalize the canonical database contract while reading existing wrapped histories too.
  return {
    ...stored,
    personal_threshold: Object.hasOwn(stored, "learned_threshold")
      ? stored.learned_threshold
      : stored.personal_threshold ?? null,
    crash_history: {
      crashes,
      last_updated: Array.isArray(history)
        ? null
        : history?.last_updated ?? null,
    },
  };
}

async function updateUserProfile(
  supabase: any,
  userId: string,
  date: string,
  transactions: Transaction[],
) {
  await reconcileCrashDetection(supabase, userId, date, transactions);
  await updateTopCategories(supabase, userId, date, transactions);
}

async function reconcileCrashDetection(
  supabase: any,
  userId: string,
  date: string,
  transactions: Transaction[],
) {
  const profile = await getUserProfile(supabase, userId);
  const { data: moods, error: moodError } = await supabase.from("moods")
    .select("mood_score").eq("user_id", userId)
    .gte("created_at", `${date}T00:00:00Z`)
    .lt("created_at", `${ledgerDate(date, 2)}T00:00:00Z`);
  if (moodError || !moods) throw new Error("Threshold source unavailable");
  const lowMoods = moods.filter((m: { mood_score: number }) =>
    Number.isFinite(m.mood_score) && m.mood_score >= 1 && m.mood_score <= 2
  );
  // Replace the recalculated day's derived entry; a corrected/deleted trigger removes it.
  const crashes: CrashEvent[] = profile.crash_history.crashes.filter((crash) =>
    crash.date !== date
  );
  if (lowMoods.length > 0 && transactions.length > 0) {
    crashes.push({
      date,
      debt_at_crash: calculateRollingDebt(
        transactions,
        ledgerDate(date, -1),
        7,
      ),
      mood_score: Math.min(
        ...lowMoods.map((m: { mood_score: number }) => m.mood_score),
      ),
    });
  }
  const unique = [
    ...new Map(crashes.map((crash) => [crash.date, crash])).values(),
  ];
  const learned = unique.length >= 3
    ? calculatePercentile10(unique.map((crash) => crash.debt_at_crash))
    : 0;
  const { error } = await supabase.from("wellbeing_debt_profiles").update({
    learned_threshold: learned > 0 ? learned : null,
    last_crash_date: unique.map((crash) => crash.date).sort().at(-1) ?? null,
    // Released iOS clients decode this wrapped shape; reads also accept database-default arrays.
    crash_history: { crashes: unique, last_updated: new Date().toISOString() },
    updated_at: new Date().toISOString(),
  }).eq("user_id", userId);
  if (error) throw new Error("Debt profile could not be saved");
}

async function updateTopCategories(
  supabase: any,
  userId: string,
  date: string,
  transactions: Transaction[],
) {
  // Aggregate by category and type
  const categoryMap = new Map<string, { total: number; count: number }>();

  for (const t of transactions) {
    const key = t.category;
    const existing = categoryMap.get(key) || { total: 0, count: 0 };
    categoryMap.set(key, {
      total: existing.total + (t.type === "withdrawal" ? -t.amount : t.amount),
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
  const { error: updateError } = await supabase
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
  if (updateError) throw new Error("Debt categories could not be saved");
}

// =============================================================================
// PERSISTENCE
// =============================================================================

async function insertDebtScore(supabase: any, score: CurrentDebtScore) {
  const { source_transactions: _snapshot, ...storedScore } = score;
  const { data, error } = await supabase
    .from("wellbeing_debt_scores")
    .upsert({
      ...storedScore,
      trend: {
        ...storedScore.trend,
        // Retain only the amounts/provenance needed to reload this calculation. No private source notes.
        source_transactions: _snapshot.map((
          { id, user_id, date, type, category, amount, source, metadata },
        ) => ({
          id,
          user_id,
          date,
          type,
          category,
          amount,
          source,
          metadata: {
            source_ids: metadata?.source_ids ?? [],
            accounting: "current_source_records",
          },
        })),
      },
    }, {
      onConflict: "user_id,date",
      // A scheduled legacy-ledger result must not replace a current-source calculation.
      ignoreDuplicates: score.trend.accounting_version !== 2,
    }).select("id");

  if (error) {
    console.error("Error inserting debt score:", error);
    throw error;
  }
  return Array.isArray(data) && data.length > 0;
}
