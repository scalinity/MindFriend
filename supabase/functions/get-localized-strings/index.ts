// Spec 14: get-localized-strings Edge Function
// Fetches localized strings with language and region fallback

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  checkRateLimit,
  getRateLimitHeaders,
  getCorsHeaders,
} from "../_shared/cors.ts";

interface LocalizedStringsRequest {
  language: string;
  region?: string;
  keys?: string[];
  since?: string;
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // CORS headers
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Validate JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    if (!token) {
      return new Response(
        JSON.stringify({ error: "Invalid Authorization header" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    // Create authenticated Supabase client with the user's token
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        },
      },
    );

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Rate limit by user ID (60 requests per minute)
    const rateLimitResult = checkRateLimit(user.id, 60, 60 * 1000);
    if (!rateLimitResult.allowed) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded" }), {
        status: 429,
        headers: {
          "Content-Type": "application/json",
          ...getRateLimitHeaders(
            rateLimitResult.remaining,
            rateLimitResult.resetIn,
          ),
        },
      });
    }

    const { language, region, keys, since }: LocalizedStringsRequest =
      await req.json();

    // Validate language parameter (2-5 chars, lowercase letters and hyphens)
    if (
      !language ||
      typeof language !== "string" ||
      !/^[a-z]{2}(-[a-z]{2,3})?$/.test(language)
    ) {
      return new Response(
        JSON.stringify({
          error:
            "language parameter is required and must be a valid language code",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Validate region parameter if provided (2-3 uppercase letters)
    if (
      region &&
      (typeof region !== "string" || !/^[A-Z]{2,3}$/.test(region))
    ) {
      return new Response(
        JSON.stringify({
          error: "region parameter must be a valid region code",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Validate keys parameter if provided
    if (
      keys &&
      (!Array.isArray(keys) ||
        keys.some((k) => typeof k !== "string" || k.length > 100))
    ) {
      return new Response(
        JSON.stringify({
          error: "keys must be an array of strings, each <= 100 chars",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Validate since parameter if provided (ISO 8601 datetime)
    if (since && typeof since !== "string") {
      return new Response(
        JSON.stringify({
          error: "since parameter must be an ISO 8601 datetime string",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Build query: Start with exact language + region match
    let query = supabase
      .from("localized_strings")
      .select("string_key, value, plural_forms");

    // Language is required
    query = query.eq("language", language);

    // Region-specific override: fetch both region-specific and default (NULL)
    // Use separate queries to avoid PostgREST filter injection
    if (region) {
      // Get both region-specific and default (NULL region) entries
      const { data: regionSpecific, error: err1 } = await query.eq(
        "region",
        region,
      );
      const { data: defaultRegion, error: err2 } = await supabase
        .from("localized_strings")
        .select("string_key, value, plural_forms")
        .eq("language", language)
        .is("region", null);

      if (err1 || err2) {
        console.error("Localized strings query error:", err1 || err2);
        throw new Error("Failed to fetch localized strings");
      }

      // Merge results: region-specific overrides defaults
      const stringMap: Record<
        string,
        { value: string; plurals?: Record<string, string> }
      > = {};

      // First add defaults
      for (const str of defaultRegion || []) {
        stringMap[str.string_key] = {
          value: str.value,
          plurals: str.plural_forms,
        };
      }

      // Then override with region-specific
      for (const str of regionSpecific || []) {
        stringMap[str.string_key] = {
          value: str.value,
          plurals: str.plural_forms,
        };
      }

      const response = {
        language,
        region: region || null,
        strings: stringMap,
        updated_at: new Date().toISOString(),
      };

      return new Response(JSON.stringify(response), {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "public, max-age=3600",
          ...getRateLimitHeaders(
            rateLimitResult.remaining,
            rateLimitResult.resetIn,
          ),
        },
      });
    } else {
      query = query.is("region", null);
    }

    // Specific keys if provided
    if (keys && Array.isArray(keys) && keys.length > 0) {
      query = query.in("string_key", keys);
    }

    // Incremental updates: only fetch changes since this timestamp
    if (since && typeof since === "string") {
      query = query.gte("updated_at", since);
    }

    const { data: strings, error } = await query;

    if (error) {
      console.error("Supabase query error:", error);
      return new Response(
        JSON.stringify({ error: "Failed to fetch localized strings" }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Build string map (region-specific overrides default)
    // First pass: add defaults (region IS NULL)
    // Second pass: override with region-specific (region = requested region)
    const stringMap: Record<
      string,
      { value: string; plurals?: Record<string, string> }
    > = {};

    // Add all results, with region-specific overriding defaults
    for (const str of strings || []) {
      stringMap[str.string_key] = {
        value: str.value,
        plurals: str.plural_forms,
      };
    }

    const response = {
      language,
      region: region || null,
      strings: stringMap,
      updated_at: new Date().toISOString(),
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=3600", // Cache for 1 hour
        ...getRateLimitHeaders(
          rateLimitResult.remaining,
          rateLimitResult.resetIn,
        ),
      },
    });
  } catch (error) {
    console.error("Unexpected error in get-localized-strings:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
