// Find Mentor Matches - Intelligent matching algorithm for mentorship
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  getCorsHeaders,
  validateContentType,
  parseJsonBody,
} from "../_shared/cors.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";

interface MatchRequest {
  seekingAreas: string[];
  limit?: number;
}

interface MentorMatch {
  mentorUserId: string;
  profileId: string;
  bio: string | null;
  expertiseAreas: string[];
  languages: string[];
  mentorshipStyle: string;
  availabilityHoursWeek: number;
  avgRating: number | null;
  totalMentorships: number;
  compatibilityScore: number;
  expertiseMatchScore: number;
  languageMatchScore: number;
  timezoneMatchScore: number;
  availabilityMatchScore: number;
  matchReason: string;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Validate content type
  const contentTypeError = validateContentType(req, corsHeaders);
  if (contentTypeError) return contentTypeError;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Auth
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Unauthorized", code: "NO_AUTH" }),
      {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (authError || !user) {
    return new Response(
      JSON.stringify({ error: "Unauthorized", code: "INVALID_TOKEN" }),
      {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // Rate limiting - 20 match requests per minute
  const rateLimit = await checkRateLimit(
    supabase,
    user.id,
    "find-mentor-matches",
    {
      windowMs: 60000,
      maxRequests: 20,
    },
  );

  if (!rateLimit.allowed) {
    return new Response(
      JSON.stringify({
        error: "Too many requests. Please wait before searching again.",
        code: "RATE_LIMITED",
        retryAfter: rateLimit.retryAfter,
      }),
      {
        status: 429,
        headers: {
          ...corsHeaders,
          ...getRateLimitHeaders(rateLimit),
          "Content-Type": "application/json",
        },
      },
    );
  }

  // Parse request body
  const body = await parseJsonBody<MatchRequest>(req);
  if (!body) {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body", code: "PARSE_ERROR" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // Validate seeking areas
  if (
    !body.seekingAreas ||
    !Array.isArray(body.seekingAreas) ||
    body.seekingAreas.length === 0
  ) {
    return new Response(
      JSON.stringify({
        error: "seekingAreas is required and must be a non-empty array",
        code: "INVALID_SEEKING_AREAS",
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const limit = Math.min(body.limit || 5, 10); // Max 10 results

  try {
    // Call the matching function with timeout
    const timeoutPromise = new Promise((_resolve, reject) =>
      setTimeout(
        () => reject(new Error("Mentor matching timeout")),
        5000, // 5 second timeout
      ),
    );

    const matchPromise = supabase.rpc("find_mentor_matches", {
      p_user_id: user.id,
      p_seeking_areas: body.seekingAreas,
      p_limit: Math.min(body.limit || 5, 10),
    }).execute();

    const response = await Promise.race([matchPromise, timeoutPromise]);

    const { data: matches, error: matchError } = response;

    if (matchError) {
      console.error("Error finding matches:", matchError);
      return new Response(
        JSON.stringify({ error: "Failed to find matches", code: "DB_ERROR" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Transform to camelCase for API response
    const transformedMatches: MentorMatch[] = (matches || []).map(
      (m: Record<string, unknown>) => ({
        mentorUserId: m.mentor_user_id,
        profileId: m.profile_id,
        bio: m.bio,
        expertiseAreas: m.expertise_areas,
        languages: m.languages,
        mentorshipStyle: m.mentorship_style,
        availabilityHoursWeek: m.availability_hours_week,
        avgRating: m.avg_rating,
        totalMentorships: m.total_mentorships,
        compatibilityScore: m.compatibility_score,
        expertiseMatchScore: m.expertise_match_score,
        languageMatchScore: m.language_match_score,
        timezoneMatchScore: m.timezone_match_score,
        availabilityMatchScore: m.availability_match_score,
        matchReason: m.match_reason,
      }),
    );

    return new Response(
      JSON.stringify({
        success: true,
        matches: transformedMatches,
        count: transformedMatches.length,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        code: "INTERNAL_ERROR",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
