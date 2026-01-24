// MindFriend Analyze Intervention Patterns Edge Function
// Server-side ML timing analysis: learns optimal intervention delivery times from historical data

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { logSanitized } from "../_shared/logging-sanitization.ts";

/**
 * LOGGING POLICY:
 * - NEVER log raw biometric values from intervention_deliveries.context_snapshot
 * - Use logSanitized() for all error logging
 * - Only log error.message, never full error objects
 */

// Configuration Constants
const MIN_DAYS_FOR_ANALYSIS = 14; // 2 weeks minimum
const ROLLING_WINDOW_DAYS = 90; // Analyze last 90 days
const MIN_SAMPLES_PER_HOUR = 2; // Minimum deliveries per hour for confidence
const CONFIDENCE_BOOST_MAX = 0.5; // Maximum confidence adjustment
const RETRY_MAX_ATTEMPTS = 3;
const RETRY_BASE_DELAY_MS = 1000;

// ML Formula Constants
const COMPLETION_RATE_WEIGHT = 0.6; // 60% weight for completion rate
const RATING_WEIGHT = 0.3; // 30% weight for average rating
const DISMISS_RATE_WEIGHT = 0.1; // 10% weight for dismiss rate
const NEUTRAL_COMPLETION_RATE = 0.5; // Baseline completion rate
const NEUTRAL_RATING = 3.0; // Baseline rating (out of 5)
const NEUTRAL_DISMISS_RATE = 0.5; // Baseline dismiss rate
const RATING_SCALE = 5.0; // Maximum rating value

const corsHeaders = getCorsHeaders("*");

interface HourlyMetrics {
  completionRate: number;
  avgRating: number;
  dismissRate: number;
  confidence: number;
  sampleCount: number;
}

interface TimingPreferences {
  hourlyConfidence: Record<string, HourlyMetrics>;
  sampleCount: number;
  minimumDataMet: boolean;
  windowDays: number;
}

// Singleton Supabase client
let supabaseClient: ReturnType<typeof createClient> | null = null;

function getSupabaseClient() {
  if (!supabaseClient) {
    supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
  }
  return supabaseClient;
}

// Retry helper
async function withRetry<T>(
  operation: () => Promise<T>,
  maxRetries = RETRY_MAX_ATTEMPTS,
  baseDelay = RETRY_BASE_DELAY_MS,
): Promise<T> {
  let lastError: Error | null = null;
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error as Error;
      if (attempt < maxRetries - 1) {
        const delay = baseDelay * Math.pow(2, attempt);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }
  throw lastError;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabase = getSupabaseClient();

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

    const userId = user.id;

    // Get user timezone (for hour grouping)
    const { data: settings } = await withRetry(() =>
      supabase
        .from("user_settings")
        .select("timezone")
        .eq("user_id", userId)
        .maybeSingle(),
    );

    const userTimezone = settings?.timezone || "UTC";

    // Calculate date range (last 90 days)
    const now = new Date();
    const windowStart = new Date(now);
    windowStart.setDate(windowStart.getDate() - ROLLING_WINDOW_DAYS);

    // Fetch intervention deliveries within window
    const { data: deliveries, error: deliveriesError } = await withRetry(() =>
      supabase
        .from("intervention_deliveries")
        .select("delivered_at, completed, rating, dismissed_at")
        .eq("user_id", userId)
        .gte("delivered_at", windowStart.toISOString())
        .order("delivered_at", { ascending: false }),
    );

    if (deliveriesError) {
      throw deliveriesError;
    }

    if (!deliveries || deliveries.length === 0) {
      return new Response(
        JSON.stringify({
          error: "insufficient_data",
          message: "No intervention delivery history found",
          sampleCount: 0,
          minimumRequired: MIN_DAYS_FOR_ANALYSIS,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if minimum time window met
    const oldestDelivery = new Date(
      deliveries[deliveries.length - 1].delivered_at,
    );
    const daysSinceFirst =
      (now.getTime() - oldestDelivery.getTime()) / (1000 * 60 * 60 * 24);

    if (daysSinceFirst < MIN_DAYS_FOR_ANALYSIS) {
      return new Response(
        JSON.stringify({
          error: "insufficient_data",
          message: `Need at least ${MIN_DAYS_FOR_ANALYSIS} days of data. Current: ${Math.floor(daysSinceFirst)} days`,
          sampleCount: deliveries.length,
          minimumRequired: MIN_DAYS_FOR_ANALYSIS,
          daysSinceFirst: Math.floor(daysSinceFirst),
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Group deliveries by hour (using user timezone)
    const hourlyData: Record<
      number,
      {
        total: number;
        completed: number;
        dismissed: number;
        ratings: number[];
      }
    > = {};

    for (let hour = 0; hour < 24; hour++) {
      hourlyData[hour] = {
        total: 0,
        completed: 0,
        dismissed: 0,
        ratings: [],
      };
    }

    // Use Intl.DateTimeFormat for timezone-aware hour extraction
    const formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: userTimezone,
      hour: "2-digit",
      hour12: false,
    });

    deliveries.forEach((delivery) => {
      const deliveryDate = new Date(delivery.delivered_at);
      const hourString =
        formatter.formatToParts(deliveryDate).find((p) => p.type === "hour")
          ?.value || "0";
      const hour = parseInt(hourString, 10);

      hourlyData[hour].total++;

      if (delivery.completed) {
        hourlyData[hour].completed++;
      }

      if (delivery.dismissed_at) {
        hourlyData[hour].dismissed++;
      }

      if (delivery.rating !== null && delivery.rating !== undefined) {
        hourlyData[hour].ratings.push(delivery.rating);
      }
    });

    // Calculate metrics and confidence for each hour
    const hourlyConfidence: Record<string, HourlyMetrics> = {};

    for (let hour = 0; hour < 24; hour++) {
      const data = hourlyData[hour];

      // Skip hours with insufficient samples
      if (data.total < MIN_SAMPLES_PER_HOUR) {
        continue;
      }

      const completionRate = data.total > 0 ? data.completed / data.total : 0;
      const dismissRate = data.total > 0 ? data.dismissed / data.total : 0;
      const avgRating =
        data.ratings.length > 0
          ? data.ratings.reduce((sum, r) => sum + r, 0) / data.ratings.length
          : 3.0; // Neutral default

      // Calculate confidence boost/suppression (-0.5 to +0.5)
      let confidence = 0.0;

      // Factor 1: Completion rate (60% weight)
      // High completion = positive boost, low = negative
      confidence += (completionRate - NEUTRAL_COMPLETION_RATE) * COMPLETION_RATE_WEIGHT;

      // Factor 2: Average rating (30% weight)
      // Normalized to -0.5 to +0.5 range (rating 1 = -0.3, rating 5 = +0.3)
      confidence += ((avgRating - NEUTRAL_RATING) / RATING_SCALE) * RATING_WEIGHT;

      // Factor 3: Dismiss rate (10% weight, inverted)
      // High dismiss rate = negative, low = positive
      confidence -= (dismissRate - NEUTRAL_DISMISS_RATE) * DISMISS_RATE_WEIGHT;

      // Clamp to max range
      confidence = Math.max(
        -CONFIDENCE_BOOST_MAX,
        Math.min(CONFIDENCE_BOOST_MAX, confidence),
      );

      hourlyConfidence[hour.toString()] = {
        completionRate,
        avgRating,
        dismissRate,
        confidence,
        sampleCount: data.total,
      };
    }

    const response: TimingPreferences = {
      hourlyConfidence,
      sampleCount: deliveries.length,
      minimumDataMet: true,
      windowDays: ROLLING_WINDOW_DAYS,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error in analyze-intervention-patterns:", {
      error: (error as Error).message,
    });

    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
