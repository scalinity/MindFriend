// Agent Monitor - Detects wellness signals for users
// Triggered by cron (every 30 minutes) or manually for testing

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  detectSignals,
  isDuplicateSignal,
  type SignalDetectionResult,
} from "../_shared/signal-detectors.ts";
import {
  getActionTypeForSignal,
  generateActionContent,
  generateReasoning,
} from "../_shared/action-templates.ts";
import {
  findOptimalDeliveryTime,
  getActionCountToday,
  getConfidenceThreshold,
  getMaxDailyActions,
} from "../_shared/timing-optimizer.ts";
import { getCorsHeaders } from "../_shared/cors.ts";


interface AgentSettings {
  user_id: string;
  autonomy_level: string;
  enabled_signals: string[];
  is_enabled: boolean;
  max_daily_outreach: number;
}

interface Profile {
  id: string;
  display_name: string;
  current_streak: number;
}

serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate request - require service role or valid cron token
    const authHeader = req.headers.get("Authorization");
    const cronSecret = Deno.env.get("CRON_SECRET");

    // Allow cron jobs with secret, or admin service calls
    const isCronRequest =
      cronSecret && req.headers.get("X-Cron-Secret") === cronSecret;
    const isServiceRequest = authHeader?.includes(
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    if (!isCronRequest && !isServiceRequest) {
      // Validate user token for manual triggers
      if (!authHeader) {
        return new Response(
          JSON.stringify({ error: "Missing authorization" }),
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

      // Check if user has admin role for manual triggering
      const { data: profile } = await supabase
        .from("profiles")
        .select("role")
        .eq("id", user.id)
        .single();

      if (profile?.role !== "admin") {
        return new Response(
          JSON.stringify({ error: "Admin access required" }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Parse request for optional user filtering with validation
    let userIds: string[] | null = null;
    const uuidRegex =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    const MAX_USER_IDS = 100; // Limit batch size to prevent DoS

    try {
      const body = await req.json();
      if (body.user_ids) {
        // Validate user_ids is an array
        if (!Array.isArray(body.user_ids)) {
          return new Response(
            JSON.stringify({ error: "user_ids must be an array" }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        // Limit array size
        if (body.user_ids.length > MAX_USER_IDS) {
          return new Response(
            JSON.stringify({
              error: `user_ids array exceeds maximum size of ${MAX_USER_IDS}`,
            }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        // Validate each UUID format
        const invalidIds = body.user_ids.filter(
          (id: unknown) => typeof id !== "string" || !uuidRegex.test(id),
        );
        if (invalidIds.length > 0) {
          return new Response(
            JSON.stringify({ error: "Invalid UUID format in user_ids array" }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        userIds = body.user_ids;
      }
    } catch {
      // No body, process all active users
    }

    // Get active users with agent enabled
    let query = supabase
      .from("agent_settings")
      .select(
        "user_id, autonomy_level, enabled_signals, is_enabled, max_daily_outreach",
      )
      .eq("is_enabled", true);

    if (userIds && userIds.length > 0) {
      query = query.in("user_id", userIds);
    }

    const { data: settings, error: settingsError } = await query;

    if (settingsError) {
      throw new Error(
        `Failed to fetch agent settings: ${settingsError.message}`,
      );
    }

    if (!settings || settings.length === 0) {
      return new Response(
        JSON.stringify({
          processed: 0,
          signals_detected: 0,
          actions_created: 0,
          errors: [],
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let processed = 0;
    let signalsDetected = 0;
    let actionsCreated = 0;
    const errors: string[] = [];

    // Process users in batches of 10
    const batchSize = 10;
    for (let i = 0; i < settings.length; i += batchSize) {
      const batch = settings.slice(i, i + batchSize);

      const results = await Promise.allSettled(
        batch.map((userSettings) =>
          processUser(supabase, userSettings as AgentSettings),
        ),
      );

      for (const result of results) {
        processed++;
        if (result.status === "fulfilled") {
          signalsDetected += result.value.signalsDetected;
          actionsCreated += result.value.actionsCreated;
        } else {
          errors.push(result.reason?.message || "Unknown error");
        }
      }
    }

    return new Response(
      JSON.stringify({
        processed,
        signals_detected: signalsDetected,
        actions_created: actionsCreated,
        errors: errors.slice(0, 10), // Limit error list
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Agent monitor error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// Cache for profiles to avoid N+1 queries
const profileCache = new Map<string, Profile | null>();

async function getProfileCached(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<Profile | null> {
  if (profileCache.has(userId)) {
    return profileCache.get(userId) || null;
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, display_name, current_streak")
    .eq("id", userId)
    .single();

  profileCache.set(userId, profile as Profile | null);
  return profile as Profile | null;
}

async function processUser(
  supabase: ReturnType<typeof createClient>,
  settings: AgentSettings,
): Promise<{ signalsDetected: number; actionsCreated: number }> {
  const userId = settings.user_id;
  let signalsDetected = 0;
  let actionsCreated = 0;

  // Detect signals for this user
  const detectedSignals = await detectSignals(
    supabase,
    userId,
    settings.enabled_signals,
  );

  // Get confidence threshold based on autonomy level
  const confidenceThreshold = getConfidenceThreshold(settings.autonomy_level);

  // Filter signals by confidence threshold
  const validSignals = detectedSignals.filter(
    (s) => s.confidence >= confidenceThreshold,
  );

  // Early exit if no valid signals (avoids profile fetch)
  if (validSignals.length === 0) {
    return { signalsDetected, actionsCreated };
  }

  // Get user profile for context (cached)
  const profile = await getProfileCached(supabase, userId);

  for (const signal of validSignals) {
    // Check for duplicate signals
    const isDuplicate = await isDuplicateSignal(
      supabase,
      userId,
      signal.type,
      24,
    );

    if (isDuplicate) {
      continue;
    }

    // Insert signal
    const { data: insertedSignal, error: signalError } = await supabase
      .from("agent_signals")
      .insert({
        user_id: userId,
        signal_type: signal.type,
        severity: signal.severity,
        confidence: signal.confidence,
        evidence: signal.evidence,
        detected_at: new Date().toISOString(),
        expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(), // 24h expiry
      })
      .select()
      .single();

    if (signalError) {
      // Log error without exposing full user ID (first 8 chars only for correlation)
      console.error(
        `Failed to insert signal for user ${userId.substring(0, 8)}...:`,
        signalError.message,
      );
      continue;
    }

    signalsDetected++;

    // Check if we can create an action
    const actionCountToday = await getActionCountToday(supabase, userId);
    const maxActions = getMaxDailyActions(settings.autonomy_level);

    if (actionCountToday >= maxActions) {
      // Log decision to skip due to quota
      await logDecision(supabase, userId, insertedSignal.id, "skip", {
        reason: "daily_quota_exceeded",
        current_count: actionCountToday,
        max_allowed: maxActions,
      });
      continue;
    }

    // Create action
    const actionType = getActionTypeForSignal(signal.type);
    const timeOfDay = getTimeOfDay();

    const content = await generateActionContent(actionType, {
      userName: profile?.display_name || "friend",
      signalType: signal.type,
      severity: signal.severity,
      evidence: signal.evidence,
      streak: profile?.current_streak || 0,
      timeOfDay,
    });

    const reasoning = generateReasoning(
      signal.type,
      signal.evidence,
      actionType,
    );

    const scheduledFor = await findOptimalDeliveryTime(
      supabase,
      userId,
      actionType,
    );

    const { data: action, error: actionError } = await supabase
      .from("agent_actions")
      .insert({
        user_id: userId,
        signal_id: insertedSignal.id,
        action_type: actionType,
        status: "scheduled",
        scheduled_for: scheduledFor.toISOString(),
        content,
        channel: "push",
        reasoning,
      })
      .select()
      .single();

    if (actionError) {
      // Log error without exposing full user ID
      console.error(
        `Failed to create action for user ${userId.substring(0, 8)}...:`,
        actionError.message,
      );
      continue;
    }

    actionsCreated++;

    // Log decision
    await logDecision(supabase, userId, insertedSignal.id, "create_action", {
      action_id: action.id,
      action_type: actionType,
      scheduled_for: scheduledFor.toISOString(),
      confidence: signal.confidence,
    });
  }

  return { signalsDetected, actionsCreated };
}

async function logDecision(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  signalId: string,
  outcome: string,
  inputs: Record<string, unknown>,
): Promise<void> {
  const reasoning =
    outcome === "skip"
      ? `Skipped action creation: ${inputs.reason}`
      : `Created ${inputs.action_type} action for signal`;

  await supabase.from("agent_decisions").insert({
    user_id: userId,
    decision_type: "action_creation",
    inputs,
    reasoning,
    outcome,
    action_taken: inputs.action_id || null,
  });
}

function getTimeOfDay(): "morning" | "afternoon" | "evening" | "night" {
  const hour = new Date().getHours();
  if (hour >= 5 && hour < 12) return "morning";
  if (hour >= 12 && hour < 17) return "afternoon";
  if (hour >= 17 && hour < 21) return "evening";
  return "night";
}
