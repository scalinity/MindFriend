import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";
import {
  buildFallbackItems,
  buildQuestItem,
  getLocalDate,
  isPlanInRange,
  normalizePlanSize,
  normalizeSourceType,
  type ExerciseRow,
  type QuestRow,
} from "../_shared/action-autopilot.ts";

interface GenerateActionPlanRequest {
  sourceType: string;
  planSize: string;
  timezone: string;
  regenerate?: boolean;
  moodContextId?: string;
  weeklySummaryId?: string;
}

const DEFAULT_TIMEZONE = "UTC";
const MAX_ITEMS = 4;
const RATE_LIMIT_ENDPOINT = "generate-action-plan";
const RATE_LIMIT_CONFIG = { windowMs: 60 * 1000, maxRequests: 10 };
const FREE_DAILY_LIMIT = 2;

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");

    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: { headers: { Authorization: `Bearer ${token}` } },
      },
    );

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const rateLimitResult = await checkRateLimit(
      supabaseAdmin,
      user.id,
      RATE_LIMIT_ENDPOINT,
      RATE_LIMIT_CONFIG,
    );

    if (!rateLimitResult.allowed) {
      return new Response(
        JSON.stringify({
          error: "Too many requests",
          code: "RATE_LIMITED",
          retryAfter: rateLimitResult.retryAfter,
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            ...getRateLimitHeaders(rateLimitResult),
          },
        },
      );
    }

    const responseHeaders = {
      ...corsHeaders,
      "Content-Type": "application/json",
      ...getRateLimitHeaders(rateLimitResult),
    };

    let body: GenerateActionPlanRequest;
    try {
      body = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: "Invalid request format" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    const planSize = normalizePlanSize(body.planSize);
    const sourceType = normalizeSourceType(body.sourceType);
    const timezone = body.timezone || DEFAULT_TIMEZONE;

    if (!planSize || !sourceType) {
      return new Response(JSON.stringify({ error: "Invalid request fields" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    const localDate = getLocalDate(timezone);
    const regenerate = body.regenerate === true;

    const { data: profile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .select("subscription_tier")
      .eq("id", user.id)
      .single();

    if (profileError || !profile) {
      return new Response(JSON.stringify({ error: "Unable to load profile" }), {
        status: 500,
        headers: responseHeaders,
      });
    }

    const isPremium = profile.subscription_tier === "premium";

    const { data: existingPlans, error: existingError } = await supabaseAdmin
      .from("action_plans")
      .select(
        "id, status, source_type, plan_size, local_date, timezone, scheduled_for, created_at, updated_at",
      )
      .eq("user_id", user.id)
      .eq("local_date", localDate)
      .order("created_at", { ascending: false });

    if (existingError) {
      return new Response(JSON.stringify({ error: "Unable to load plans" }), {
        status: 500,
        headers: responseHeaders,
      });
    }

    const latestPlan = existingPlans?.[0];
    const hasActiveDraft = latestPlan && ["draft", "scheduled"].includes(latestPlan.status);

    if (!regenerate && hasActiveDraft) {
      const { data: planItems } = await supabaseAdmin
        .from("action_plan_items")
        .select("id, item_type, reference_id, title, duration_minutes, sort_order, item_status")
        .eq("plan_id", latestPlan.id)
        .order("sort_order", { ascending: true });

      return new Response(
        JSON.stringify({
          planId: latestPlan.id,
          planStatus: latestPlan.status,
          items: planItems ?? [],
          usedFallback: false,
          quotaRemaining: isPremium ? -1 : Math.max(0, FREE_DAILY_LIMIT - (existingPlans?.length ?? 0)),
        }),
        { headers: responseHeaders },
      );
    }

    if (regenerate && latestPlan && ["in_progress", "completed"].includes(latestPlan.status)) {
      return new Response(
        JSON.stringify({
          error: "Plan already started",
          code: "PLAN_LOCKED",
        }),
        { status: 409, headers: responseHeaders },
      );
    }

    if (!isPremium) {
      const plansToday = existingPlans?.length ?? 0;
      if (plansToday >= FREE_DAILY_LIMIT) {
        return new Response(
          JSON.stringify({
            error: "AI_QUOTA_EXCEEDED",
            message:
              "You've reached your daily Action Plan limit. Upgrade to Premium for unlimited plans!",
            quotaUsed: plansToday,
            quotaLimit: FREE_DAILY_LIMIT,
          }),
          { status: 429, headers: responseHeaders },
        );
      }
    }

    if (regenerate && hasActiveDraft) {
      await supabaseAdmin
        .from("action_plans")
        .update({ status: "cancelled", updated_at: new Date().toISOString() })
        .eq("id", latestPlan.id);
    }

    const { data: quest } = await supabaseAdmin
      .from("quests")
      .select("id, quest_templates(title, estimated_minutes)")
      .eq("user_id", user.id)
      .eq("local_date", localDate)
      .maybeSingle();

    const questItem = buildQuestItem(quest as QuestRow | null);

    const { data: exercises } = await supabaseAdmin
      .from("exercises")
      .select("id, title, type, duration_seconds")
      .eq("premium_only", false)
      .order("title", { ascending: true });

    const fallbackItems = buildFallbackItems(
      planSize,
      questItem,
      (exercises as ExerciseRow[]) ?? [],
    );

    if (!isPlanInRange(planSize, fallbackItems)) {
      return new Response(
        JSON.stringify({ error: "Fallback plan invalid" }),
        { status: 500, headers: responseHeaders },
      );
    }

    const { data: planInsert, error: planError } = await supabaseAdmin
      .from("action_plans")
      .insert({
        user_id: user.id,
        source_type: sourceType,
        plan_size: planSize,
        local_date: localDate,
        timezone,
        status: "draft",
      })
      .select("id, status")
      .single();

    if (planError || !planInsert) {
      return new Response(JSON.stringify({ error: "Failed to create plan" }), {
        status: 500,
        headers: responseHeaders,
      });
    }

    const itemsToInsert = fallbackItems.slice(0, MAX_ITEMS).map((item, index) => ({
      plan_id: planInsert.id,
      item_type: item.itemType,
      reference_id: item.referenceId,
      title: item.title,
      duration_minutes: item.durationMinutes,
      sort_order: index,
      item_status: "pending",
    }));

    const { data: insertedItems, error: itemError } = await supabaseAdmin
      .from("action_plan_items")
      .insert(itemsToInsert)
      .select("id, item_type, reference_id, title, duration_minutes, sort_order, item_status")
      .order("sort_order", { ascending: true });

    if (itemError) {
      return new Response(JSON.stringify({ error: "Failed to save plan items" }), {
        status: 500,
        headers: responseHeaders,
      });
    }

    return new Response(
      JSON.stringify({
        planId: planInsert.id,
        planStatus: planInsert.status,
        items: insertedItems ?? [],
        usedFallback: true,
        quotaRemaining: isPremium ? -1 : Math.max(0, FREE_DAILY_LIMIT - ((existingPlans?.length ?? 0) + 1)),
      }),
      { headers: responseHeaders },
    );
  } catch (error) {
    console.error("generate-action-plan error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
