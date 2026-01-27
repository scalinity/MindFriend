/**
 * contribute-wisdom Edge Function
 * Accepts anonymized user contributions for community wisdom aggregation
 *
 * Security:
 * - User ID is HMAC-SHA256 hashed (irreversible, no PII)
 * - Rate limited: 10 contributions per hour per user
 * - Consent verified before any contribution
 * - Data validated for PII patterns
 * - Context tags sanitized
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { hashUserId, validateEnvironment } from "../_shared/wisdom-hash.ts";
import {
  validateContributionSchema,
  ContributionType,
} from "../_shared/pii-detector.ts";

// Validate environment at startup (fail fast)
validateEnvironment();

// Rate limiting configuration
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const RATE_LIMIT_MAX_REQUESTS = 10;
const rateLimitCache = new Map<string, { count: number; resetAt: number }>();

const corsHeaders = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") || "app.mindfriend.com",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Allowed context tag prefixes (whitelist)
const ALLOWED_TAG_PREFIXES = [
  "mood:", "time:", "day:", "emotion:", "exercise:",
  "pathway:", "phase:", "category:", "type:", "effectiveness:",
  "goal:", "challenge:"
];

interface ContributeRequest {
  contributionType: ContributionType;
  contextTags?: string[];
  data: Record<string, unknown>;
}

/**
 * Checks rate limit for a user
 * @returns true if allowed, false if rate limited
 */
function checkRateLimit(userId: string): { allowed: boolean; remaining: number; resetAt: number } {
  const now = Date.now();
  const key = `wisdom:${userId}`;
  
  let entry = rateLimitCache.get(key);
  
  // Reset if window expired
  if (!entry || now > entry.resetAt) {
    entry = { count: 0, resetAt: now + RATE_LIMIT_WINDOW_MS };
    rateLimitCache.set(key, entry);
  }
  
  // Check limit
  if (entry.count >= RATE_LIMIT_MAX_REQUESTS) {
    return { allowed: false, remaining: 0, resetAt: entry.resetAt };
  }
  
  // Increment and allow
  entry.count++;
  return { allowed: true, remaining: RATE_LIMIT_MAX_REQUESTS - entry.count, resetAt: entry.resetAt };
}

/**
 * Sanitizes context tags to prevent injection
 */
function sanitizeContextTags(tags: string[]): string[] {
  return tags
    .filter(tag => {
      // Must be a string
      if (typeof tag !== "string") return false;
      // Must not be empty or too long
      if (tag.length === 0 || tag.length > 50) return false;
      // Must match allowed prefix pattern
      if (!ALLOWED_TAG_PREFIXES.some(prefix => tag.startsWith(prefix))) return false;
      // Must not contain dangerous characters
      if (/[<>"'\\;]/.test(tag)) return false;
      // Value after prefix must be alphanumeric/underscore only
      const value = tag.split(":")[1] || "";
      if (!/^[a-z0-9_]+$/.test(value)) return false;
      return true;
    })
    .slice(0, 20); // Max 20 tags
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client with service role for insert
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          error: "UNAUTHORIZED",
          message: "Missing authorization header",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "UNAUTHORIZED", message: "Invalid token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check rate limit
    const rateLimit = checkRateLimit(user.id);
    if (!rateLimit.allowed) {
      return new Response(
        JSON.stringify({
          error: "RATE_LIMITED",
          message: "Too many contributions. Please try again later.",
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            "X-RateLimit-Remaining": "0",
            "X-RateLimit-Reset": String(Math.ceil(rateLimit.resetAt / 1000)),
          },
        },
      );
    }

    // Parse request body
    const body: ContributeRequest = await req.json();
    const { contributionType, contextTags = [], data } = body;

    // Validate contribution type and data schema
    const schemaValidation = validateContributionSchema(contributionType, data);
    if (!schemaValidation.valid) {
      return new Response(
        JSON.stringify({
          error: schemaValidation.hasPII
            ? "PII_DETECTED"
            : "INVALID_DATA_SCHEMA",
          message: schemaValidation.hasPII 
            ? "Please remove personal information before submitting"
            : "Invalid data format",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check user consent
    const { data: consent } = await supabase
      .from("wisdom_consent")
      .select("contribute_anonymous_data")
      .eq("user_id", user.id)
      .single();

    if (!consent || !consent.contribute_anonymous_data) {
      return new Response(
        JSON.stringify({
          error: "CONSENT_REQUIRED",
          message:
            "Enable anonymous contributions in Settings > Community Wisdom Privacy",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Hash user ID for anonymization (HMAC-SHA256)
    const userHash = await hashUserId(user.id);

    // Build and sanitize context tags from contribution data
    const enrichedTags = buildContextTags(contributionType, data, sanitizeContextTags(contextTags));

    // Insert contribution
    const { data: contribution, error: insertError } = await supabase
      .from("wisdom_contributions")
      .insert({
        user_hash: userHash,
        contribution_type: contributionType,
        context_tags: enrichedTags,
        data_json: data,
      })
      .select("id")
      .single();

    if (insertError) {
      // Log internally but don't expose details
      console.error("Insert error:", insertError.code);
      return new Response(
        JSON.stringify({
          error: "INSERT_FAILED",
          message: "Failed to save contribution",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Return success WITHOUT exposing any hash information
    return new Response(
      JSON.stringify({
        success: true,
        contributionId: contribution.id,
      }),
      {
        status: 201,
        headers: { 
          ...corsHeaders, 
          "Content-Type": "application/json",
          "X-RateLimit-Remaining": String(rateLimit.remaining),
        },
      },
    );
  } catch (error) {
    // Log internally but don't expose details
    console.error("Contribute wisdom error:", (error as Error).message);
    return new Response(
      JSON.stringify({
        error: "INTERNAL_ERROR",
        message: "An unexpected error occurred",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

/**
 * Builds context tags from contribution data for aggregation
 */
function buildContextTags(
  type: string,
  data: Record<string, unknown>,
  userTags: string[],
): string[] {
  const tags = new Set<string>(userTags);

  // Add type-specific tags
  tags.add(`type:${type}`);

  // Add time-based tags
  const hour = new Date().getUTCHours();
  if (hour >= 5 && hour < 12) {
    tags.add("time:morning");
  } else if (hour >= 12 && hour < 17) {
    tags.add("time:afternoon");
  } else if (hour >= 17 && hour < 21) {
    tags.add("time:evening");
  } else {
    tags.add("time:night");
  }

  // Add day-of-week tag
  const days = [
    "sunday",
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
  ];
  tags.add(`day:${days[new Date().getUTCDay()]}`);

  // Add data-specific tags
  if (type === "mood_pattern") {
    const moodScore = (data as any).moodScore as number;
    if (moodScore <= 2) {
      tags.add("mood:low");
    } else if (moodScore === 3) {
      tags.add("mood:medium");
    } else {
      tags.add("mood:high");
    }

    if ((data as any).emotion) {
      tags.add(`emotion:${(data as any).emotion}`);
    }
  }

  if (type === "exercise_effectiveness") {
    tags.add(`exercise:${(data as any).exerciseType}`);
    const rating = (data as any).effectivenessRating as number;
    if (rating >= 4) {
      tags.add("effectiveness:high");
    } else if (rating >= 3) {
      tags.add("effectiveness:medium");
    } else {
      tags.add("effectiveness:low");
    }
  }

  if (type === "pathway_progress") {
    tags.add(`pathway:${(data as any).pathwayType}`);
    tags.add(`phase:${(data as any).phaseNumber}`);
  }

  if (type === "strategy_success") {
    tags.add(`category:${(data as any).category}`);
  }

  return Array.from(tags);
}
