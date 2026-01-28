import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { sanitizeErrorMessage, timingSafeEqual } from "../_shared/security.ts";

interface RateLimitConfig {
  free: { requestsPerDay: number; burst: number };
  developer: { requestsPerDay: number00; burst: number };
  enterprise: { requestsPerDay: number; burst: number };
}

const RATE_LIMITS: RateLimitConfig = {
  free: { requestsPerDay: 100, burst: 10 },
  developer: { requestsPerDay: 10000, burst: 100 },
  enterprise: { requestsPerDay: 100000, burst: 1000 },
};

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Extract API key from header
  const apiKey = req.headers.get("X-API-Key");
  if (!apiKey) {
    return new Response(JSON.stringify({ error: "API key required" }), {
      status: 401,
      headers: {
        "Content-Type": "application/json",
        "X-RateLimit-Limit": String(RATE_LIMITS.free.requestsPerDay),
        "X-RateLimit-Remaining": "0",
      },
    });
  }

  // Validate API key and get user/tier
  const { data: apiKeyData, error: keyError } = await supabase
    .from("api_keys")
    .select("user_id, tier, is_active, rate_limit_remaining, last_request_at")
    .eq("key", apiKey)
    .single();

  if (keyError || !apiKeyData || !apiKeyData.is_active) {
    return new Response(
      JSON.stringify({ error: "Invalid or inactive API key" }),
      {
        status: 401,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  const tier = apiKeyData.tier as keyof RateLimitConfig;
  const rateLimit = RATE_LIMITS[tier];

  // Check rate limit
  const now = new Date();
  const periodStart = new Date(
    now.getFullYear(),
    now.getMonth(),
    now.getDate(),
  );

  if (
    apiKeyData.rate_limit_remaining !== null &&
    apiKeyData.rate_limit_remaining <= 0
  ) {
    const resetTime = new Date(periodStart.getTime() + 24 * 60 * 60 * 1000);

    return new Response(
      JSON.stringify({
        error: "Rate limit exceeded",
        reset_at: resetTime.toISOString(),
      }),
      {
        status: 429,
        headers: {
          "Content-Type": "application/json",
          "X-RateLimit-Limit": String(rateLimit.requestsPerDay),
          "X-RateLimit-Remaining": "0",
          "X-RateLimit-Reset": String(resetTime.getTime() / 1000),
          "Retry-After": String(
            Math.ceil((resetTime.getTime() - now.getTime()) / 1000),
          ),
        },
      },
    );
  }

  // Decrement rate limit
  const newRemaining =
    (apiKeyData.rate_limit_remaining ?? rateLimit.requestsPerDay) - 1;
  await supabase
    .from("api_keys")
    .update({
      rate_limit_remaining: newRemaining,
      last_request_at: now.toISOString(),
    })
    .eq("key", apiKey);

  // Parse request path
  const url = new URL(req.url);
  const pathParts = url.pathname.split("/").filter(Boolean);
  const resource = pathParts[pathParts.length - 1];

  // Handle different endpoints
  try {
    let response: Response;

    switch (resource) {
      case "moods": {
        if (req.method === "GET") {
          response = await handleMoodsGet(
            supabase,
            apiKeyData.user_id,
            url.searchParams,
          );
        } else if (req.method === "POST") {
          response = await handleMoodsPost(
            supabase,
            apiKeyData.user_id,
            await req.json(),
          );
        } else {
          response = new Response(
            JSON.stringify({ error: "Method not allowed" }),
            {
              status: 405,
              headers: { "Content-Type": "application/json" },
            },
          );
        }
        break;
      }

      case "journal": {
        if (req.method === "GET") {
          response = await handleJournalGet(
            supabase,
            apiKeyData.user_id,
            url.searchParams,
          );
        } else if (req.method === "POST") {
          response = await handleJournalPost(
            supabase,
            apiKeyData.user_id,
            await req.json(),
          );
        } else {
          response = new Response(
            JSON.stringify({ error: "Method not allowed" }),
            {
              status: 405,
              headers: { "Content-Type": "application/json" },
            },
          );
        }
        break;
      }

      case "exercises": {
        if (req.method === "GET") {
          response = await handleExercisesGet(supabase, url.searchParams);
        } else {
          response = new Response(
            JSON.stringify({ error: "Method not allowed" }),
            {
              status: 405,
              headers: { "Content-Type": "application/json" },
            },
          );
        }
        break;
      }

      case "stats": {
        if (req.method === "GET") {
          response = await handleStatsGet(
            supabase,
            apiKeyData.user_id,
            url.searchParams,
          );
        } else {
          response = new Response(
            JSON.stringify({ error: "Method not allowed" }),
            {
              status: 405,
              headers: { "Content-Type": "application/json" },
            },
          );
        }
        break;
      }

      default:
        response = new Response(JSON.stringify({ error: "Unknown endpoint" }), {
          status: 404,
          headers: { "Content-Type": "application/json" },
        });
    }

    // Add rate limit headers to response
    response.headers.set("X-RateLimit-Limit", String(rateLimit.requestsPerDay));
    response.headers.set("X-RateLimit-Remaining", String(newRemaining));

    return response;
  } catch (error) {
    // SEC-CRIT-006: Sanitize error messages to prevent information disclosure
    console.error("Public API error:", error); // Log full error server-side only
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        // Don't expose internal error details to clients
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});

// ============================================
// Endpoint Handlers
// ============================================

async function handleMoodsGet(
  supabase: any,
  userId: string,
  params: URLSearchParams,
) {
  const limit = Math.min(parseInt(params.get("limit") || "50"), 100);
  const offset = parseInt(params.get("offset") || "0");
  const startDate = params.get("start_date");
  const endDate = params.get("end_date");

  let query = supabase
    .from("moods")
    .select("id, mood_score, note, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (startDate) query = query.gte("created_at", startDate);
  if (endDate) query = query.lte("created_at", endDate);

  const { data, error } = await query;

  if (error) {
    console.error("Public API error:", error); // Log full error server-side
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  return new Response(JSON.stringify({ moods: data, limit, offset }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

async function handleMoodsPost(supabase: any, userId: string, body: any) {
  if (!body.mood_score || body.mood_score < 1 || body.mood_score > 10) {
    return new Response(
      JSON.stringify({ error: "Invalid mood_score (1-10 required)" }),
      {
        status: 400,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  const { data, error } = await supabase
    .from("moods")
    .insert({
      user_id: userId,
      mood_score: body.mood_score,
      note: body.note,
      created_at: body.created_at || new Date().toISOString(),
    })
    .select()
    .single();

  if (error) {
    console.error("Public API error:", error); // Log full error server-side
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  return new Response(JSON.stringify({ mood: data }), {
    status: 201,
    headers: { "Content-Type": "application/json" },
  });
}

async function handleJournalGet(
  supabase: any,
  userId: string,
  params: URLSearchParams,
) {
  const limit = Math.min(parseInt(params.get("limit") || "50"), 100);
  const offset = parseInt(params.get("offset") || "0");

  const { data, error } = await supabase
    .from("journal_entries")
    .select("id, content, mood_score, tags, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (error) {
    console.error("Public API error:", error); // Log full error server-side
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  return new Response(JSON.stringify({ entries: data, limit, offset }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

async function handleJournalPost(supabase: any, userId: string, body: any) {
  if (!body.content) {
    return new Response(JSON.stringify({ error: "Content is required" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data, error } = await supabase
    .from("journal_entries")
    .insert({
      user_id: userId,
      content: body.content,
      mood_score: body.mood_score,
      tags: body.tags || [],
      created_at: body.created_at || new Date().toISOString(),
    })
    .select()
    .single();

  if (error) {
    console.error("Public API error:", error); // Log full error server-side
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  return new Response(JSON.stringify({ entry: data }), {
    status: 201,
    headers: { "Content-Type": "application/json" },
  });
}

async function handleExercisesGet(supabase: any, params: URLSearchParams) {
  const category = params.get("category");
  const limit = Math.min(parseInt(params.get("limit") || "50"), 100);

  let query = supabase
    .from("exercises")
    .select("id, title, category, duration, is_premium")
    .eq("is_active", true);

  if (category) query = query.eq("category", category);
  query = query.limit(limit);

  const { data, error } = await query;

  if (error) {
    console.error("Public API error:", error); // Log full error server-side
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  return new Response(JSON.stringify({ exercises: data }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

async function handleStatsGet(
  supabase: any,
  userId: string,
  params: URLSearchParams,
) {
  const period = params.get("period") || "7d"; // 7d, 30d, 90d

  let days = 7;
  if (period === "30d") days = 30;
  else if (period === "90d") days = 90;

  const startDate = new Date();
  startDate.setDate(startDate.getDate() - days);

  // Get mood stats
  const { data: moodData } = await supabase
    .from("moods")
    .select("mood_score, created_at")
    .eq("user_id", userId)
    .gte("created_at", startDate.toISOString());

  // Get journal stats
  const { data: journalData } = await supabase
    .from("journal_entries")
    .select("id, created_at")
    .eq("user_id", userId)
    .gte("created_at", startDate.toISOString());

  // Get exercise stats
  const { data: exerciseData } = await supabase
    .from("exercise_sessions")
    .select("id, created_at")
    .eq("user_id", userId)
    .gte("created_at", startDate.toISOString());

  const avgMood = moodData?.length
    ? moodData.reduce((sum: number, m: any) => sum + m.mood_score, 0) /
      moodData.length
    : null;

  return new Response(
    JSON.stringify({
      period,
      stats: {
        total_moods: moodData?.length || 0,
        average_mood: avgMood,
        total_journal_entries: journalData?.length || 0,
        total_exercises: exerciseData?.length || 0,
      },
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    },
  );
}
