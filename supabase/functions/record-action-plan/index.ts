import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";

interface ActionPlanItemUpdate {
  id: string;
  itemType?: string;
  referenceId?: string | null;
  title?: string;
  durationMinutes?: number;
  sortOrder?: number;
}

interface ActionPlanFeedbackInput {
  rating?: number;
  notes?: string;
}

interface RecordActionPlanRequest {
  planId: string;
  status?: string;
  scheduledFor?: string;
  itemsCompleted?: string[];
  itemsSkipped?: string[];
  items?: ActionPlanItemUpdate[];
  removeItemIds?: string[];
  feedback?: ActionPlanFeedbackInput;
}

export const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const RATE_LIMIT_ENDPOINT = "record-action-plan";
const RATE_LIMIT_CONFIG = { windowMs: 60 * 1000, maxRequests: 30 };
export const VALID_STATUSES = [
  "draft",
  "scheduled",
  "in_progress",
  "completed",
  "cancelled",
];
export const VALID_ITEM_TYPES = ["quest", "exercise", "chat"];

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

    let body: RecordActionPlanRequest;
    try {
      body = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: "Invalid request format" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    const planId = body.planId;
    if (!planId || !UUID_REGEX.test(planId)) {
      return new Response(JSON.stringify({ error: "Invalid plan identifier" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    const { data: plan, error: planError } = await supabaseAdmin
      .from("action_plans")
      .select("id, user_id, status")
      .eq("id", planId)
      .single();

    if (planError || !plan) {
      return new Response(JSON.stringify({ error: "Plan not found" }), {
        status: 404,
        headers: responseHeaders,
      });
    }

    if (plan.user_id !== user.id) {
      return new Response(JSON.stringify({ error: "Access denied" }), {
        status: 403,
        headers: responseHeaders,
      });
    }

    const now = new Date().toISOString();
    const updates: Record<string, unknown> = {};

    const hasItemUpdates = (body.items?.length ?? 0) > 0 ||
      (body.removeItemIds?.length ?? 0) > 0;
    const hasCompletionUpdates = (body.itemsCompleted?.length ?? 0) > 0 ||
      (body.itemsSkipped?.length ?? 0) > 0;

    if (plan.status === "cancelled") {
      return new Response(JSON.stringify({ error: "Plan already cancelled" }), {
        status: 409,
        headers: responseHeaders,
      });
    }

    if (plan.status === "completed" && (hasItemUpdates || hasCompletionUpdates)) {
      return new Response(JSON.stringify({ error: "Plan already completed" }), {
        status: 409,
        headers: responseHeaders,
      });
    }

    if (hasItemUpdates && plan.status !== "draft") {
      return new Response(
        JSON.stringify({ error: "Items can only be edited in draft" }),
        { status: 409, headers: responseHeaders },
      );
    }

    let statusToApply = body.status;
    if (statusToApply && !VALID_STATUSES.includes(statusToApply)) {
      return new Response(JSON.stringify({ error: "Invalid status" }), {
        status: 400,
        headers: responseHeaders,
      });
    }

    if (!statusToApply && hasCompletionUpdates && plan.status === "draft") {
      statusToApply = "in_progress";
    }

    if (statusToApply) {
      updates.status = statusToApply;
      updates.updated_at = now;
    }

    if (body.scheduledFor) {
      const scheduledDate = new Date(body.scheduledFor);
      if (Number.isNaN(scheduledDate.getTime())) {
        return new Response(JSON.stringify({ error: "Invalid scheduled time" }), {
          status: 400,
          headers: responseHeaders,
        });
      }
      updates.scheduled_for = scheduledDate.toISOString();
      if (!updates.updated_at) {
        updates.updated_at = now;
      }
    }

    if (body.removeItemIds?.length) {
      await supabaseAdmin
        .from("action_plan_items")
        .delete()
        .in("id", body.removeItemIds)
        .eq("plan_id", planId);
    }

    if (body.items?.length) {
      for (const item of body.items) {
      if (!item.id || !UUID_REGEX.test(item.id)) {
        return new Response(
          JSON.stringify({ error: "Invalid item identifier" }),
          { status: 400, headers: responseHeaders },
        );
      }

      if (item.itemType && !VALID_ITEM_TYPES.includes(item.itemType)) {
        return new Response(
          JSON.stringify({ error: "Invalid item type" }),
          { status: 400, headers: responseHeaders },
        );
      }

      if (item.durationMinutes !== undefined && item.durationMinutes <= 0) {
        return new Response(
          JSON.stringify({ error: "Invalid duration" }),
          { status: 400, headers: responseHeaders },
        );
      }

      const itemUpdate: Record<string, unknown> = {};
      if (item.itemType) itemUpdate.item_type = item.itemType;
      if (item.referenceId !== undefined) itemUpdate.reference_id = item.referenceId;
      if (item.title) itemUpdate.title = item.title;
      if (item.durationMinutes !== undefined) itemUpdate.duration_minutes = item.durationMinutes;
      if (item.sortOrder !== undefined) itemUpdate.sort_order = item.sortOrder;


        if (Object.keys(itemUpdate).length > 0) {
          await supabaseAdmin
            .from("action_plan_items")
            .update(itemUpdate)
            .eq("id", item.id)
            .eq("plan_id", planId);
        }
      }
    }

    if (body.itemsCompleted?.length) {
      await supabaseAdmin
        .from("action_plan_items")
        .update({ item_status: "completed", completed_at: now })
        .in("id", body.itemsCompleted)
        .eq("plan_id", planId);
    }

    if (body.itemsSkipped?.length) {
      await supabaseAdmin
        .from("action_plan_items")
        .update({ item_status: "skipped", skipped_at: now })
        .in("id", body.itemsSkipped)
        .eq("plan_id", planId);
    }

    if (hasCompletionUpdates) {
      const { data: statuses } = await supabaseAdmin
        .from("action_plan_items")
        .select("item_status")
        .eq("plan_id", planId);

      const allDone = statuses
        ? statuses.every((item) => item.item_status !== "pending")
        : false;
      if (allDone) {
        updates.status = "completed";
        updates.updated_at = now;
      }
    }

    if (Object.keys(updates).length > 0) {
      await supabaseAdmin.from("action_plans").update(updates).eq("id", planId);
    }

    if (body.feedback) {
      await supabaseAdmin.from("action_plan_feedback").insert({
        plan_id: planId,
        rating: body.feedback.rating ?? null,
        notes: body.feedback.notes ?? null,
      });
    }

    const { data: updatedPlan } = await supabaseAdmin
      .from("action_plans")
      .select("id, status, source_type, plan_size, local_date, timezone, scheduled_for")
      .eq("id", planId)
      .single();

    const { data: updatedItems } = await supabaseAdmin
      .from("action_plan_items")
      .select("id, item_type, reference_id, title, duration_minutes, sort_order, item_status, completed_at, skipped_at")
      .eq("plan_id", planId)
      .order("sort_order", { ascending: true });

    return new Response(
      JSON.stringify({
        plan: updatedPlan,
        items: updatedItems ?? [],
      }),
      { headers: responseHeaders },
    );
  } catch (error) {
    console.error("record-action-plan error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
