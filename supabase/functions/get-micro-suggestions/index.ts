// MindFriend Get Micro-Suggestions Edge Function
// Returns personalized micro-moment suggestions based on context and preferences

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

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

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

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
        ? Math.max(15, Math.min(body.maxDuration, 120))
        : 60;

    // Validate limit
    const limit =
      typeof body.limit === "number"
        ? Math.max(1, Math.min(body.limit, 10))
        : 3;

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
    const { data: preferences } = await supabase
      .from("micro_delivery_preferences")
      .select("preferred_types, preferred_durations, silent_mode_only")
      .eq("user_id", user.id)
      .single();

    // Check subscription status for premium content
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("status")
      .eq("user_id", user.id)
      .eq("status", "active")
      .single();

    const isPremium = subscription !== null;

    // Get recently completed templates (last 24 hours) to avoid repetition
    const twentyFourHoursAgo = new Date(
      Date.now() - 24 * 60 * 60 * 1000,
    ).toISOString();
    const { data: recentCompletions } = await supabase
      .from("micro_moment_completions")
      .select("template_id")
      .eq("user_id", user.id)
      .gte("created_at", twentyFourHoursAgo)
      .order("created_at", { ascending: false })
      .limit(5);

    const recentTemplateIds =
      recentCompletions?.map((c) => c.template_id) || [];

    // NEW: Get recent intervention deliveries (last 6 hours) for stronger exclusion
    const sixHoursAgo = new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString();
    const { data: recentDeliveries } = await supabase
      .from("intervention_deliveries")
      .select("intervention_id, rating")
      .eq("user_id", user.id)
      .gte("delivered_at", sixHoursAgo)
      .order("delivered_at", { ascending: false });

    const recentDeliveryIds =
      recentDeliveries?.map((d) => d.intervention_id) || [];

    // NEW: Get user's rating history for all templates
    const { data: ratingHistory } = await supabase
      .from("intervention_deliveries")
      .select("intervention_id, rating")
      .eq("user_id", user.id)
      .not("rating", "is", null)
      .order("delivered_at", { ascending: false })
      .limit(50);

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

    // Build query for templates
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
    query = query.order("sort_order", { ascending: true }).limit(20);

    const { data: templates, error: templatesError } = await query;

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
          score += 50;
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
            score += 40;
          }
        }

        // NEW: Weight by user's average rating for this template
        const ratingData = ratingMap.get(template.id);
        if (ratingData && ratingData.count > 0) {
          const avgRating = ratingData.total / ratingData.count;
          // Rating boost: 5-star avg = +20, 4-star = +10, 3-star = 0, 2-star = -10, 1-star = -20
          const ratingBoost = (avgRating - 3) * 10;
          score += ratingBoost;
        }

        // Penalize recently completed (last 24h, weaker penalty than 6h exclusion)
        if (recentTemplateIds.includes(template.id)) {
          score -= 20;
        }

        // Slight boost for preferred types
        if (preferredTypes?.includes(template.type)) {
          score += 10;
        }

        // Prefer shorter exercises for quick contexts
        if (context === "pre_meeting" || context === "break") {
          score += Math.max(0, 30 - template.duration_seconds);
        }

        // NEW: Reduce score for low-confidence triggers
        if (body.triggerConfidence !== undefined) {
          const confidencePenalty = (1 - body.triggerConfidence) * 10;
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
  } catch (error) {
    console.error("Error getting micro-suggestions:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...getCorsHeaders(null), "Content-Type": "application/json" },
    });
  }
});
