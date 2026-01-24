// MindFriend Get Micro-Suggestions Edge Function
// Returns personalized micro-moment suggestions based on context and preferences

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

// Configuration Constants
const RETRY_MAX_ATTEMPTS = 3;
const RETRY_BASE_DELAY_MS = 1000;
const MAX_DURATION_MIN = 15; // Minimum duration in seconds
const MAX_DURATION_MAX = 120; // Maximum duration in seconds
const MAX_DURATION_DEFAULT = 60; // Default duration in seconds
const LIMIT_MIN = 1;
const LIMIT_MAX = 10;
const LIMIT_DEFAULT = 3;
const RECENT_COMPLETIONS_HOURS = 24; // Exclude recently completed (24h)
const RECENT_DELIVERIES_HOURS = 6; // Stronger exclusion for recent deliveries (6h)
const RATING_HISTORY_LIMIT = 50;
const TEMPLATES_QUERY_LIMIT = 20;
const CONTEXT_MATCH_BOOST = 50;
const TRIGGER_TYPE_MATCH_BOOST = 40;
const RATING_BOOST_MULTIPLIER = 10; // (avgRating - 3) * 10
const RECENT_COMPLETION_PENALTY = 20;
const PREFERRED_TYPE_BOOST = 10;
const SHORT_DURATION_BOOST_BASE = 30;
const LOW_CONFIDENCE_PENALTY_MULTIPLIER = 10;

// Circuit Breaker Configuration
const CIRCUIT_BREAKER_FAILURE_THRESHOLD = 5;
const CIRCUIT_BREAKER_RESET_TIMEOUT_MS = 30000; // 30 seconds

// Circuit Breaker State
enum CircuitState {
  CLOSED = "CLOSED",
  OPEN = "OPEN",
  HALF_OPEN = "HALF_OPEN",
}

class CircuitBreaker {
  private state: CircuitState = CircuitState.CLOSED;
  private failureCount = 0;
  private lastFailureTime: number | null = null;
  private successCount = 0;

  async execute<T>(operation: () => Promise<T>): Promise<T> {
    if (this.state === CircuitState.OPEN) {
      if (
        this.lastFailureTime &&
        Date.now() - this.lastFailureTime > CIRCUIT_BREAKER_RESET_TIMEOUT_MS
      ) {
        this.state = CircuitState.HALF_OPEN;
        this.successCount = 0;
      } else {
        throw new Error("Circuit breaker is OPEN");
      }
    }

    try {
      const result = await operation();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  private onSuccess() {
    this.failureCount = 0;
    
    if (this.state === CircuitState.HALF_OPEN) {
      this.successCount++;
      if (this.successCount >= 2) {
        this.state = CircuitState.CLOSED;
      }
    }
  }

  private onFailure() {
    this.failureCount++;
    this.lastFailureTime = Date.now();

    if (this.failureCount >= CIRCUIT_BREAKER_FAILURE_THRESHOLD) {
      this.state = CircuitState.OPEN;
    }
  }

  getState(): CircuitState {
    return this.state;
  }
}

const circuitBreaker = new CircuitBreaker();

interface SuggestionRequest {
  context?: string;
  maxDuration?: number;
  energyPreference?: string;
  excludeTypes?: string[];
  limit?: number;
  triggerType?: string; // NEW: 'time_based' | 'biometric' | 'pattern'
  triggerConfidence?: number; // NEW: 0-1 scale
}

interface MicroMomentTemplate {
  id: string;
  name: string;
  slug: string;
  type: string;
  title: string;
  description: string | null;
  duration_seconds: number;
  instructions: unknown;
  animation_type: string | null;
  audio_url: string | null;
  haptic_pattern: unknown;
  suggested_contexts: string[] | null;
  energy_effect: string | null;
  is_premium: boolean;
  is_active: boolean;
  sort_order: number;
}

// Singleton Supabase client to prevent connection pool exhaustion
let supabaseClient: ReturnType<typeof createClient> | null = null;

function getSupabaseClient() {
  if (!supabaseClient) {
    supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );
  }
  return supabaseClient;
}

// Retry helper with exponential backoff
async function withRetry<T>(
  operation: () => Promise<T>,
  maxRetries = RETRY_MAX_ATTEMPTS,
  baseDelay = RETRY_BASE_DELAY_MS
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
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    return await circuitBreaker.execute(async () => {
      const supabase = getSupabaseClient();

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

      // Parse request body
      let body: SuggestionRequest = {};
      try {
        body = await req.json();
      } catch {
        // Empty body is OK - use defaults
      }

      // Validate context enum
      const validContexts = [
        "morning",
        "evening",
        "pre_meeting",
        "break",
        "stress",
        "anxiety",
        "grounding",
        "energy",
        "work",
        "sleep",
        "transition",
      ];
      const context =
        body.context && validContexts.includes(body.context)
          ? body.context
          : null;

      // Validate energy preference
      const validEnergy = ["calming", "energizing", "neutral"];
      const energyPreference =
        body.energyPreference && validEnergy.includes(body.energyPreference)
          ? body.energyPreference
          : null;

      // Validate max duration (15-120 seconds)
      const maxDuration =
        typeof body.maxDuration === "number"
          ? Math.max(MAX_DURATION_MIN, Math.min(body.maxDuration, MAX_DURATION_MAX))
          : MAX_DURATION_DEFAULT;

      // Validate limit
      const limit =
        typeof body.limit === "number"
          ? Math.max(LIMIT_MIN, Math.min(body.limit, LIMIT_MAX))
          : LIMIT_DEFAULT;

      // Validate exclude types
      const validTypes = [
        "breathing",
        "check_in",
        "grounding",
        "movement",
        "transition",
        "gratitude",
      ];
      const excludeTypes = Array.isArray(body.excludeTypes)
        ? body.excludeTypes.filter((t) => validTypes.includes(t))
        : [];

      // Get user preferences
      const { data: preferences } = await withRetry(() =>
        supabase
          .from("micro_delivery_preferences")
          .select("preferred_types, preferred_durations, silent_mode_only")
          .eq("user_id", user.id)
          .maybeSingle()
      );

      // Check subscription status for premium content
      const { data: subscription } = await withRetry(() =>
        supabase
          .from("subscriptions")
          .select("status")
          .eq("user_id", user.id)
          .eq("status", "active")
          .maybeSingle()
      );

      const isPremium = subscription !== null;

      // Get recently completed templates (last 24 hours) to avoid repetition
      const twentyFourHoursAgo = new Date(
        Date.now() - RECENT_COMPLETIONS_HOURS * 60 * 60 * 1000,
      ).toISOString();
      const { data: recentCompletions } = await withRetry(() =>
        supabase
          .from("micro_moment_completions")
          .select("template_id")
          .eq("user_id", user.id)
          .gte("completed_at", twentyFourHoursAgo)
      );

      const recentTemplateIds =
        recentCompletions?.map((c) => c.template_id) || [];

      // NEW: Get recent intervention deliveries (last 6 hours) for stronger exclusion
      const sixHoursAgo = new Date(Date.now() - RECENT_DELIVERIES_HOURS * 60 * 60 * 1000).toISOString();
      const { data: recentDeliveries } = await withRetry(() =>
        supabase
          .from("intervention_deliveries")
          .select("intervention_id, rating")
          .eq("user_id", user.id)
          .gte("delivered_at", sixHoursAgo)
          .order("delivered_at", { ascending: false })
      );

      const recentDeliveryIds =
        recentDeliveries?.map((d) => d.intervention_id) || [];

      // NEW: Get user's rating history for all templates
      const { data: ratingHistory } = await withRetry(() =>
        supabase
          .from("intervention_deliveries")
          .select("intervention_id, rating")
          .eq("user_id", user.id)
          .not("rating", "is", null)
          .order("delivered_at", { ascending: false })
          .limit(RATING_HISTORY_LIMIT)
      );

      // Calculate average rating per template
      const ratingMap = new Map<string, { total: number; count: number }>();
      ratingHistory?.forEach((r) => {
        if (!r.rating) return;
        const existing = ratingMap.get(r.intervention_id) || {
          total: 0,
          count: 0,
        };
        ratingMap.set(r.intervention_id, {
          total: existing.total + r.rating,
          count: existing.count + 1,
        });
      });

      // Build and execute templates query with retry
      let query = supabase
        .from("micro_moment_templates")
        .select("*")
        .eq("is_active", true)
        .lte("duration_seconds", maxDuration);

      // Filter by premium status
      if (!isPremium) {
        query = query.eq("is_premium", false);
      }

      // Filter by energy preference
      if (energyPreference) {
        query = query.eq("energy_effect", energyPreference);
      }

      // Filter by preferred types (if user has preferences and no exclude list)
      const preferredTypes = preferences?.preferred_types as string[] | null;
      if (preferredTypes?.length && excludeTypes.length === 0) {
        query = query.in("type", preferredTypes);
      }

      // Exclude specific types
      if (excludeTypes.length > 0) {
        for (const excludeType of excludeTypes) {
          query = query.neq("type", excludeType);
        }
      }

      // Order by sort_order
      query = query.order("sort_order", { ascending: true }).limit(TEMPLATES_QUERY_LIMIT);

      const { data: templates, error: templatesError } = await withRetry(() => query);

      if (templatesError) {
        console.error("Templates query error:", templatesError);
        return new Response(
          JSON.stringify({ error: "Failed to fetch templates" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Score and sort templates
      const scoredTemplates = (templates || [])
        .filter((template: MicroMomentTemplate) => {
          // EXCLUDE templates delivered in last 6 hours
          return !recentDeliveryIds.includes(template.id);
        })
        .map((template: MicroMomentTemplate) => {
          let score = 100;

          // Boost context match
          if (context && template.suggested_contexts?.includes(context)) {
            score += CONTEXT_MATCH_BOOST;
          }

          // NEW: Boost triggerType match (if provided)
          if (body.triggerType) {
            const triggerContextMap: Record<string, string[]> = {
              time_based: ["morning", "evening", "break", "transition"],
              biometric: ["stress", "anxiety", "grounding"],
              pattern: ["grounding", "stress", "anxiety"],
            };
            const triggerContexts = triggerContextMap[body.triggerType] || [];
            const matchesTrigger = triggerContexts.some((ctx) =>
              template.suggested_contexts?.includes(ctx),
            );
            if (matchesTrigger) {
              score += TRIGGER_TYPE_MATCH_BOOST;
            }
          }

          // NEW: Weight by user's average rating for this template
          const ratingData = ratingMap.get(template.id);
          if (ratingData && ratingData.count > 0) {
            const avgRating = ratingData.total / ratingData.count;
            // Rating boost: 5-star avg = +20, 4-star = +10, 3-star = 0, 2-star = -10, 1-star = -20
            const ratingBoost = (avgRating - 3) * RATING_BOOST_MULTIPLIER;
            score += ratingBoost;
          }

          // Penalize recently completed (last 24h, weaker penalty than 6h exclusion)
          if (recentTemplateIds.includes(template.id)) {
            score -= RECENT_COMPLETION_PENALTY;
          }

          // Slight boost for preferred types
          if (preferredTypes?.includes(template.type)) {
            score += PREFERRED_TYPE_BOOST;
          }

          // Prefer shorter exercises for quick contexts
          if (context === "pre_meeting" || context === "break") {
            score += Math.max(0, SHORT_DURATION_BOOST_BASE - template.duration_seconds);
          }

          // NEW: Reduce score for low-confidence triggers
          if (body.triggerConfidence !== undefined) {
            const confidencePenalty = (1 - body.triggerConfidence) * LOW_CONFIDENCE_PENALTY_MULTIPLIER;
            score -= confidencePenalty;
          }

          return { template, score };
        });

      // Sort by score descending, then by sort_order
      scoredTemplates.sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score;
        return a.template.sort_order - b.template.sort_order;
      });

      // Return top N suggestions
      const suggestions = scoredTemplates.slice(0, limit).map((s) => s.template);

      return new Response(
        JSON.stringify({
          suggestions,
          context,
          preferences: {
            maxDuration,
            silentMode: preferences?.silent_mode_only ?? false,
            isPremium,
          },
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    });
  } catch (error) {
    if ((error as Error).message === "Circuit breaker is OPEN") {
      return new Response(
        JSON.stringify({ error: "Service temporarily unavailable" }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.error("Error in get-micro-suggestions:", {
      error: (error as Error).message,
      circuitState: circuitBreaker.getState(),
    });

    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
