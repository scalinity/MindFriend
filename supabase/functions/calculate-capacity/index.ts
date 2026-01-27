import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2.49.1";
import { corsHeaders } from "../_shared/cors.ts";
import { toZonedTime, fromZonedTime } from "npm:date-fns-tz@3.2.0";
import { addDays, startOfDay } from "npm:date-fns@4.1.0";
import type {
  CalculateCapacityRequest,
  CalculateCapacityResponse,
  CapacityInput,
  CapacityOverrideRow,
  CapacityLevel,
  CapacityComponents,
  CapacityOverride,
  CapacityResult,
  Mood,
  MoodData,
  SleepData,
  SleepLog,
  StreakData,
  UserCapacityRow,
  CompletionData,
} from "./types.ts";
import {
  calculateSleepScore,
  calculateMoodScore,
  calculateStreakScore,
  calculateCompletionScore,
  calculateCompositeScore,
  calculateCapacity,
  smoothCapacity,
  scoreToLevel,
  WEIGHTS,
} from "./algorithms.ts";

// =====================================================
// QUERY TIMEOUT UTILITY
// =====================================================

/**
 * Wraps a database query with a timeout to prevent hanging
 * @param queryFn Async function that executes the query (can be Promise or PromiseLike)
 * @param timeoutMs Timeout in milliseconds (default: 5000ms)
 * @returns Query result
 * @throws Error if timeout exceeded
 */
async function withQueryTimeout<T>(
  queryFn: () => PromiseLike<T>,
  timeoutMs: number = 5000,
): Promise<T> {
  return Promise.race([
    Promise.resolve(queryFn()),
    new Promise<T>((_, reject) =>
      setTimeout(
        () => reject(new Error(`Database query timeout after ${timeoutMs}ms`)),
        timeoutMs,
      ),
    ),
  ]);
}

// =====================================================
// CONFIGURATION CONSTANTS
// =====================================================

// CONFIGURATION CONSTANTS
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const RATE_LIMIT_MAX_REQUESTS = 60; // requests per window (once per minute average)
const MAX_TIMEZONE_LENGTH = 50; // Maximum timezone identifier length
const MAX_REQUEST_BODY_SIZE = 1024 * 1024; // 1MB maximum request size
const SLEEP_LOOKBACK_DAYS = 7; // Days to look back for sleep data
const MOOD_LOOKBACK_DAYS = 3; // Days to look back for mood data
const COMPLETION_LOOKBACK_DAYS = 7; // Days for completion rate calculation
const COMPLETION_VOLUME_DIVISOR = 30; // Divisor for volume score calculation (total quests / 30)

// SECURITY: Origin validation
function validateOrigin(req: Request): boolean {
  const allowedOrigin = Deno.env.get("ALLOWED_ORIGIN") || "";
  const origin = req.headers.get("Origin");

  // Allow requests without Origin header (direct API calls)
  if (!origin) return true;

  // In development (localhost), allow
  if (!Deno.env.get("DENO_REGION") && origin.startsWith("http://localhost")) {
    return true;
  }

  // In production, require exact origin match
  return origin === allowedOrigin;
}

// =====================================================
// HELPER FUNCTIONS
// =====================================================

/**
 * Validate request and authenticate user
 * @returns User ID and validated request data
 * @throws Error if validation fails
 *
 * NOTE: Uses admin client to validate tokens since it has permission to validate
 * tokens from any authentication method (OAuth, email, etc.)
 */
async function validateAndAuthenticate(
  req: Request,
  supabaseAuth: SupabaseClient,
  supabaseAdmin: SupabaseClient,
): Promise<{ userId: string; localDate: string; timezone: string }> {
  // Validate Content-Type
  const contentType = req.headers.get("Content-Type");
  if (!contentType?.includes("application/json")) {
    throw new Error("Content-Type must be application/json");
  }

  // Validate request body size
  const contentLength = req.headers.get("Content-Length");
  if (contentLength && parseInt(contentLength, 10) > MAX_REQUEST_BODY_SIZE) {
    throw new Error(
      `Request body too large (max ${MAX_REQUEST_BODY_SIZE} bytes)`,
    );
  }

  // Authenticate user
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    console.error("Missing Authorization header");
    throw new Error("Missing Authorization header");
  }

  const token = authHeader.replace("Bearer ", "");
  console.log(
    "Attempting to authenticate user with token length:",
    token.length,
  );

  const {
    data: { user },
    error: authError,
  } = await supabaseAdmin.auth.getUser(token);

  if (authError) {
    console.error("Authentication error:", authError);
    throw new Error(`Authentication failed: ${authError.message}`);
  }

  if (!user) {
    console.error("No user returned from auth.getUser");
    throw new Error("Authentication failed: No user found");
  }

  console.log("User authenticated successfully:", user.id);
  const userId = user.id;

  // Rate limiting
  await checkRateLimit(supabaseAdmin, userId);

  // Parse and validate request
  const requestData: CalculateCapacityRequest = await req.json();
  const { localDate, timezone } = requestData;

  // Validate localDate format (YYYY-MM-DD)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(localDate)) {
    throw new Error("Invalid localDate format (expected YYYY-MM-DD)");
  }

  // Validate timezone
  if (!timezone || timezone.length > MAX_TIMEZONE_LENGTH) {
    throw new Error("Invalid timezone");
  }

  // SECURITY: Validate IANA timezone format
  // Valid formats: Area/Location (e.g., America/New_York, Europe/London)
  // or Area/Location/City (e.g., America/Argentina/Buenos_Aires)
  // or special cases: UTC, GMT
  // Pattern allows: Capital letter followed by alphanumeric and underscores
  const timezoneRegex =
    /^([A-Z][a-zA-Z_]+\/[A-Z][a-zA-Z_]+(?:\/[A-Z][a-zA-Z_]+)?|UTC|GMT)$/;
  if (!timezoneRegex.test(timezone)) {
    throw new Error(
      "Invalid timezone format (expected IANA identifier like America/New_York)",
    );
  }

  return { userId, localDate, timezone };
}

/**
 * Apply manual capacity override
 * Overrides calculated capacity with user-specified level
 */
async function handleOverride(
  supabaseAdmin: SupabaseClient,
  userId: string,
  localDate: string,
  timezone: string,
  override: CapacityOverride,
  baseResponse: CalculateCapacityResponse,
): Promise<CalculateCapacityResponse> {
  // Calculate override score based on level
  const overrideScore = getOverrideScore(override.override_level);
  const level = scoreToLevel(overrideScore);

  // Use neutral component scores for overrides
  const components: CalculateCapacityResponse["components"] = {
    sleep: {
      score: 50,
      weight: WEIGHTS.sleep,
      contribution: 50 * WEIGHTS.sleep,
    },
    mood: {
      score: 50,
      weight: WEIGHTS.mood,
      contribution: 50 * WEIGHTS.mood,
    },
    streak: {
      score: 50,
      weight: WEIGHTS.streak,
      contribution: 50 * WEIGHTS.streak,
    },
    completion: {
      score: 50,
      weight: WEIGHTS.completion,
      contribution: 50 * WEIGHTS.completion,
    },
  };

  const response: CalculateCapacityResponse = {
    score: overrideScore,
    level,
    components,
    local_date: localDate,
    calculated_at: new Date().toISOString(),
    expires_at: getNextMidnight(timezone).toISOString(),
    has_override: true,
  };

  // Persist override capacity
  await persistCapacity(
    supabaseAdmin,
    userId,
    overrideScore,
    level,
    components,
    localDate,
    timezone,
    true,
  );

  return response;
}

/**
 * Check for valid cached capacity
 * @returns Cached response if valid, null if needs recalculation
 */
async function checkCachedCapacity(
  supabaseAuth: SupabaseClient,
  userId: string,
  localDate: string,
): Promise<CalculateCapacityResponse | null> {
  const { data: cachedCapacity, error: cacheError } = await withQueryTimeout(
    async () =>
      await supabaseAuth
        .from("user_capacity")
        .select(
          "score, level, components, local_date, calculated_at, expires_at, has_override",
        )
        .eq("user_id", userId)
        .eq("local_date", localDate)
        .maybeSingle(),
  );

  if (cacheError) {
    console.error("Cache lookup failed", { code: cacheError.code });
    return null;
  }

  // Return cached if valid and not stale
  if (cachedCapacity && new Date(cachedCapacity.expires_at) > new Date()) {
    return {
      score: cachedCapacity.score,
      level: cachedCapacity.level,
      components: cachedCapacity.components,
      local_date: cachedCapacity.local_date,
      calculated_at: cachedCapacity.calculated_at,
      expires_at: cachedCapacity.expires_at,
      has_override: cachedCapacity.has_override,
    };
  }

  return null;
}

/**
 * Transform CapacityResult to API response format
 */
function buildCapacityResponse(
  result: CapacityResult,
  localDate: string,
  timezone: string,
): CalculateCapacityResponse {
  const components: CalculateCapacityResponse["components"] = {
    sleep: {
      score: result.components.sleep,
      weight: WEIGHTS.sleep,
      contribution: result.components.sleep * WEIGHTS.sleep,
    },
    mood: {
      score: result.components.mood,
      weight: WEIGHTS.mood,
      contribution: result.components.mood * WEIGHTS.mood,
    },
    streak: {
      score: result.components.streak,
      weight: WEIGHTS.streak,
      contribution: result.components.streak * WEIGHTS.streak,
    },
    completion: {
      score: result.components.completion,
      weight: WEIGHTS.completion,
      contribution: result.components.completion * WEIGHTS.completion,
    },
  };

  const calculatedAt = new Date().toISOString();
  const expiresAt = getNextMidnight(timezone).toISOString();

  return {
    score: result.score,
    level: result.level,
    components,
    local_date: localDate,
    calculated_at: calculatedAt,
    expires_at: expiresAt,
    has_override: false,
  };
}

/**
 * Get or calculate capacity score
 * Checks cache first, calculates if needed
 */
async function getOrCalculateCapacity(
  supabaseAuth: SupabaseClient,
  supabaseAdmin: SupabaseClient,
  userId: string,
  localDate: string,
  timezone: string,
): Promise<CalculateCapacityResponse> {
  // Check cache first
  const cached = await checkCachedCapacity(supabaseAuth, userId, localDate);
  if (cached) {
    return cached;
  }

  // Calculate new capacity
  const { start: sleepStart, end: sleepEnd } = getDateRangeInUTC(
    localDate,
    timezone,
    SLEEP_LOOKBACK_DAYS,
  );
  const { start: moodStart, end: moodEnd } = getDateRangeInUTC(
    localDate,
    timezone,
    MOOD_LOOKBACK_DAYS,
  );

  // OPTIMIZATION: Fetch completion data first to get today's completion status
  // This avoids duplicate quest query in fetchStreakData
  const completionData = await fetchCompletionData(
    supabaseAdmin,
    userId,
    localDate,
    timezone,
  );

  // Fetch remaining data in parallel
  const [sleepData, moodData, streakData, previousCapacity] = await Promise.all(
    [
      fetchSleepData(supabaseAdmin, userId, sleepStart, sleepEnd),
      fetchMoodData(supabaseAdmin, userId, moodStart, moodEnd, timezone),
      fetchStreakData(supabaseAdmin, userId, completionData.completedToday),
      fetchPreviousCapacity(supabaseAdmin, userId, localDate),
    ],
  );

  // Calculate capacity
  const result = calculateCapacity({
    sleep: sleepData,
    mood: moodData,
    streak: streakData,
    completion: completionData,
    previous: previousCapacity,
  });

  // Transform to response format
  const response = buildCapacityResponse(result, localDate, timezone);

  // Persist to cache (non-blocking)
  // Store the full ComponentScore objects (with score, weight, contribution)
  await persistCapacity(
    supabaseAdmin,
    userId,
    result.score,
    result.level,
    response.components, // This is the correct format for the database JSONB
    localDate,
    timezone,
    false,
  );

  return response;
}

// =====================================================
// MAIN HANDLER
// =====================================================

serve(async (req) => {
  console.log("[calculate-capacity] Request received");

  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // SECURITY: Validate origin
  if (!validateOrigin(req)) {
    return new Response(JSON.stringify({ error: "Forbidden origin" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  console.log("[calculate-capacity] Origin validated, starting main flow");

  try {
    // Initialize Supabase clients
    console.log("[calculate-capacity] Creating Supabase clients");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
      console.error("[calculate-capacity] Missing env vars:", {
        hasUrl: !!supabaseUrl,
        hasAnonKey: !!supabaseAnonKey,
        hasServiceKey: !!supabaseServiceRoleKey,
      });
      throw new Error("Server configuration error");
    }

    const supabaseAuth = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: false },
    });

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
      auth: { persistSession: false },
    });

    console.log("[calculate-capacity] Supabase clients created");

    // Validate and authenticate
    console.log("[calculate-capacity] Starting authentication");
    const { userId, localDate, timezone } = await validateAndAuthenticate(
      req,
      supabaseAuth,
      supabaseAdmin,
    );

    // Get or calculate capacity
    let response = await getOrCalculateCapacity(
      supabaseAuth,
      supabaseAdmin,
      userId,
      localDate,
      timezone,
    );

    // Check for manual override
    const override = await fetchOverride(supabaseAdmin, userId);
    if (override) {
      response = await handleOverride(
        supabaseAdmin,
        userId,
        localDate,
        timezone,
        override,
        response,
      );
    }

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    // SECURITY FIX: Don't leak sensitive data in error logs
    console.error("Error calculating capacity:", {
      message: (error as any).message,
      name: (error as any).name,
      // Omit stack trace and full error object to prevent PII leakage
    });

    // Determine appropriate status code
    const statusCode = (error as any).message?.includes("Authentication")
      ? 401
      : (error as any).message?.includes("Rate limit")
        ? 429
        : 500;

    return new Response(
      JSON.stringify({
        error: (error as any).message || "Internal server error",
      }),
      {
        status: statusCode,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

// Helper functions

/**
 * Get date range boundaries in UTC for a given local date and timezone
 * BUG FIX: Timezone-aware date queries
 */
function getDateRangeInUTC(
  localDate: string,
  timezone: string,
  daysBack: number,
): { start: string; end: string } {
  try {
    // Create date string with time at start of day in the target timezone
    const localDateAtMidnight = `${localDate}T00:00:00`;

    // Parse the date as if it's in the target timezone, then convert to UTC
    const endUtc = fromZonedTime(localDateAtMidnight, timezone);

    // Calculate start date (go back N days)
    const startUtc = addDays(endUtc, -daysBack);

    // Add 1 day to end to include full day
    const endUtcPlusOne = addDays(endUtc, 1);

    return {
      start: startUtc.toISOString(),
      end: endUtcPlusOne.toISOString(),
    };
  } catch (error) {
    console.error("Date range calculation failed, using UTC fallback", {
      error: (error as any).message,
    });

    // Fallback: use UTC dates
    const now = new Date();
    const endUtc = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate() + 1,
    );
    const startUtc = new Date(endUtc);
    startUtc.setDate(startUtc.getDate() - daysBack);

    return {
      start: startUtc.toISOString(),
      end: endUtc.toISOString(),
    };
  }
}

/**
 * Convert local date string to UTC using proper timezone library
 * FIXED: Replaced broken manual conversion with date-fns-tz
 * @param localDateString Date string in format "YYYY-MM-DDTHH:mm:ss"
 * @param timezone IANA timezone identifier (e.g., "America/New_York")
 * @returns UTC Date object
 */
function localDateToUTC(localDateString: string, timezone: string): Date {
  try {
    // Use date-fns-tz for proper timezone conversion
    return fromZonedTime(localDateString, timezone);
  } catch (error) {
    // SECURITY: Don't log timezone (PII - reveals location)
    console.warn("Timezone conversion failed, using UTC fallback");
    return new Date(localDateString + "Z");
  }
}

async function fetchSleepData(
  supabase: SupabaseClient,
  userId: string,
  startDate: string,
  endDate: string,
): Promise<SleepData | null> {
  try {
    const { data, error } = await withQueryTimeout(() =>
      supabase
        .from("sleep_logs")
        .select("logged_at, fell_asleep_at, woke_up_at, quality")
        .eq("user_id", userId)
        .gte("logged_at", startDate)
        .lte("logged_at", endDate)
        .order("logged_at", { ascending: false }),
    );

    if (error) {
      console.error("Error fetching sleep data", {
        code: error.code,
      });
      return null;
    }

    // Calculate metrics
    // BUG FIX: Handle midnight crossing and invalid data
    const sleepHours = (data as any[]).map((log: any) => {
      const asleep = new Date(log.fell_asleep_at);
      const awake = new Date(log.woke_up_at);
      let hours = (awake.getTime() - asleep.getTime()) / (1000 * 60 * 60);

      // If negative (bad data or timezone issue), assume midnight crossing
      if (hours < 0) {
        hours += 24;
      }

      // Validate: sleep hours should be reasonable (0-24 hours)
      // Re-validate after midnight correction to catch still-negative values
      if (hours < 0 || hours > 24) {
        console.warn("Invalid sleep hours detected, clamping", {
          original: hours,
        });
        hours = Math.max(0, Math.min(hours, 24));
      }

      return hours;
    });

    // FIXED: Add division by zero protection
    const averageHours =
      sleepHours.length > 0
        ? sleepHours.reduce((a, b) => a + b, 0) / sleepHours.length
        : 0;
    const lastNightHours = (data as any[])[0]?.hours ?? null;
    const quality = (data as any[])[0]?.quality ?? null;

    // Calculate sleep deficit (cumulative hours below 7)
    const deficit7d = sleepHours.reduce((deficit, hours) => {
      return deficit + Math.max(0, 7 - hours);
    }, 0);

    return {
      averageHours,
      lastNightHours,
      quality,
      deficit7d,
    };
  } catch (error) {
    console.error("Sleep data query failed", {
      error: (error as any).message,
    });
    return null;
  }
}

async function fetchMoodData(
  supabase: SupabaseClient,
  userId: string,
  startDate: string,
  endDate: string,
  timezone: string,
): Promise<MoodData | null> {
  // Use the passed date range directly (already calculated with proper timezone handling)
  const start = startDate;
  const end = endDate;

  try {
    const { data, error } = await withQueryTimeout(() =>
      supabase
        .from("moods")
        .select("logged_at, mood_score")
        .eq("user_id", userId)
        .gte("logged_at", start)
        .lte("logged_at", end)
        .order("logged_at", { ascending: false }),
    );

    if (error) {
      console.error("Error fetching mood data", {
        code: error.code,
      });
      return null;
    }

    if (!data || data.length === 0) {
      return null;
    }

    const moodScores = (data as any[]).map((m: any) => m.mood_score);

    // FIX: Prevent division by zero
    const averageMood3d =
      moodScores.length > 0
        ? moodScores.reduce((a, b) => a + b, 0) / moodScores.length
        : 0;

    const todayMood = (data as any[])[0]?.mood_score ?? null;

    // Calculate trend (simple delta)
    let trend3d = 0;
    if (moodScores.length >= 3) {
      const latest = moodScores[0];
      const oldest = moodScores[moodScores.length - 1];
      trend3d = (latest - oldest) / 2;
    }

    return {
      todayMood,
      averageMood3d,
      trend3d,
    };
  } catch (error) {
    console.error("Mood data query failed", {
      error: (error as any).message,
    });
    return null;
  }
}

async function fetchStreakData(
  supabase: SupabaseClient,
  userId: string,
  completedToday: boolean,
): Promise<StreakData> {
  try {
    // Query: Get current/longest streaks
    const { data: streakData, error: streakError } = await withQueryTimeout(
      () =>
        supabase
          .from("profiles")
          .select("current_streak, longest_streak")
          .eq("id", userId)
          .single(),
    );

    if (streakError) {
      console.error("Error fetching streak data", {
        code: streakError.code,
      });
    }

    // Build and return streak data (no quest query needed - use passed value)
    const currentStreak = streakData?.current_streak ?? 0;
    const longestStreak = streakData?.longest_streak ?? 0;

    return {
      streakDays: currentStreak,
      completedToday,
      current_streak: currentStreak,
      longest_streak: longestStreak,
    };
  } catch (error) {
    console.error("Streak data query failed", {
      error: (error as any).message,
    });
    return {
      streakDays: 0,
      completedToday: false,
      current_streak: 0,
      longest_streak: 0,
    };
  }
}

async function fetchCompletionData(
  supabase: SupabaseClient,
  userId: string,
  localDate: string,
  timezone: string,
): Promise<{
  recentCompletionRate: number;
  questsCompleted: number;
  completedToday: boolean;
}> {
  try {
    // Query 1: Get recent quest completion rate (last 7 days)
    const recentDate = new Date();
    recentDate.setDate(recentDate.getDate() - COMPLETION_LOOKBACK_DAYS);

    const { data: recentQuests, error: recentError } = await withQueryTimeout(
      () =>
        supabase
          .from("quests")
          .select("completed, assigned_date")
          .eq("user_id", userId)
          .gte("assigned_date", recentDate.toISOString().split("T")[0])
          .order("assigned_date", { ascending: false }),
    );

    if (recentError) {
      console.error("Error fetching recent quests", {
        code: recentError.code,
      });
    }

    // Query 2: Get total completed quests
    const { count: totalCompleted, error: countError } = await withQueryTimeout(
      () =>
        supabase
          .from("quests")
          .select("*", { count: "exact", head: true })
          .eq("user_id", userId)
          .eq("completed", true),
    );

    if (countError) {
      console.error("Error fetching total completed count", {
        code: countError.code,
      });
    }

    // Calculate completion metrics
    const completedCount =
      recentQuests?.filter((q: any) => q.completed).length ?? 0;
    const totalCount = recentQuests?.length ?? 1; // Avoid division by zero
    const recentCompletionRate =
      totalCount > 0 ? completedCount / totalCount : 0;
    const questsCompleted = totalCompleted ?? 0;

    // OPTIMIZATION: Extract today's completion from recentQuests (avoids duplicate query)
    const todayQuest = recentQuests?.find(
      (q: any) => q.assigned_date === localDate,
    );
    const completedToday = todayQuest?.completed ?? false;

    return {
      recentCompletionRate,
      questsCompleted,
      completedToday,
    };
  } catch (error) {
    console.error("Completion data query failed", {
      error: (error as any).message,
    });
    return {
      recentCompletionRate: 0,
      questsCompleted: 0,
      completedToday: false,
    };
  }
}

async function fetchPreviousCapacity(
  supabase: SupabaseClient,
  userId: string,
  localDate: string,
): Promise<number | null> {
  try {
    const yesterday = new Date(localDate);
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayDate = yesterday.toISOString().split("T")[0];

    const { data, error } = await withQueryTimeout(() =>
      supabase
        .from("user_capacity")
        .select("score")
        .eq("user_id", userId)
        .eq("local_date", yesterdayDate)
        .maybeSingle(),
    );

    if (error) {
      console.error("Error fetching previous capacity", {
        code: error.code,
      });
      return null;
    }

    return data?.score ?? null;
  } catch (error) {
    console.error("Previous capacity query failed", {
      error: (error as any).message,
    });
    return null;
  }
}

async function fetchOverride(
  supabase: SupabaseClient,
  userId: string,
): Promise<CapacityOverride | null> {
  try {
    const now = new Date().toISOString();

    const { data, error } = await withQueryTimeout(() =>
      supabase
        .from("capacity_overrides")
        .select("*")
        .eq("user_id", userId)
        .eq("is_active", true)
        .gt("expires_at", now)
        .maybeSingle(),
    );

    if (error) {
      console.error("Error fetching override", {
        code: error.code,
      });
      return null;
    }

    return data;
  } catch (error) {
    console.error("Override query failed", {
      error: (error as any).message,
    });
    return null;
  }
}

async function persistCapacity(
  supabase: SupabaseClient,
  userId: string,
  score: number,
  level: CapacityLevel,
  components: CapacityComponents,
  localDate: string,
  timezone: string,
  hasOverride: boolean,
): Promise<void> {
  try {
    const calculatedAt = new Date().toISOString();
    const expiresAt = getNextMidnight(timezone).toISOString();

    const { error } = await withQueryTimeout(() =>
      supabase.from("user_capacity").upsert({
        user_id: userId,
        score,
        level,
        components,
        local_date: localDate,
        calculated_at: calculatedAt,
        expires_at: expiresAt,
        has_override: hasOverride,
      }),
    );

    if (error) {
      console.error("Error persisting capacity", {
        code: error.code,
      });
      // Continue without throwing - cache write failure is non-fatal
    }
  } catch (error) {
    console.error("Persist capacity query failed", {
      error: (error as any).message,
    });
    // Continue without throwing
  }
}

function getOverrideScore(overrideLevel: string): number {
  switch (overrideLevel) {
    case "rest":
      return 25;
    case "normal":
      return 50;
    case "challenge":
      return 75;
    default:
      return 50;
  }
}

function getNextMidnight(timezone: string): Date {
  try {
    const now = new Date();
    const zonedNow = toZonedTime(now, timezone);
    const zonedTomorrow = startOfDay(addDays(zonedNow, 1));
    return fromZonedTime(zonedTomorrow, timezone);
  } catch (error) {
    console.error("Timezone calculation failed, using UTC fallback", {
      error: (error as any).message,
    });
    const tomorrow = new Date();
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    tomorrow.setUTCHours(0, 0, 0, 0);
    return tomorrow;
  }
}

async function checkRateLimit(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MS);

  try {
    // RACE CONDITION FIX: Use atomic RPC for rate limit check
    const { data: result, error } = await withQueryTimeout(() =>
      supabase.rpc("check_capacity_rate_limit", {
        p_user_id: userId,
        p_window_ms: RATE_LIMIT_WINDOW_MS,
        p_max_requests: RATE_LIMIT_MAX_REQUESTS,
      }),
    );

    if (error) {
      console.error("RPC error in rate limit check", {
        code: error.code,
        message: error.message,
      });
      throw new Error("Database error during rate limit check");
    }

    // RPC returns {allowed: boolean, resetAt: timestamp, remaining: int}
    // Add defensive null check
    if (!result) {
      console.error("Rate limit RPC returned null result");
      // Fail open - allow request if rate limit check fails
      return;
    }

    console.log("Rate limit check result:", {
      allowed: result.allowed,
      remaining: result.remaining,
    });

    if (!result.allowed) {
      throw new Error(
        `Rate limit exceeded: ${RATE_LIMIT_MAX_REQUESTS} requests per hour`,
      );
    }
  } catch (error) {
    if ((error as any).message?.includes("Rate limit exceeded")) {
      throw error;
    }
    console.error("Rate limit query failed", {
      error: (error as any).message,
    });
    throw new Error("Database error during rate limit check");
  }
}
