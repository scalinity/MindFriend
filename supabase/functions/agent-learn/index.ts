// Agent Learn - Updates learnings based on user responses
// Called when user responds to an agent action

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface LearnRequest {
  action_id: string;
  user_response: {
    response_type: string;
    selected_action?: string;
    timestamp: string;
    sentiment?: string;
  };
}

interface AgentAction {
  id: string;
  user_id: string;
  action_type: string;
  signal_id: string | null;
  delivered_at: string;
}

serve(async (req) => {
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
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
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

    const body: LearnRequest = await req.json();
    const { action_id, user_response } = body;

    if (!action_id || !user_response) {
      return new Response(
        JSON.stringify({ error: "Missing action_id or user_response" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get the action
    const { data: action, error: actionError } = await supabase
      .from("agent_actions")
      .select("id, user_id, action_type, signal_id, delivered_at")
      .eq("id", action_id)
      .eq("user_id", user.id)
      .single();

    if (actionError || !action) {
      return new Response(JSON.stringify({ error: "Action not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Calculate effectiveness score
    const effectivenessScore = calculateEffectivenessScore(user_response);

    // Update action with response
    const newStatus = getStatusFromResponse(user_response.response_type);
    await supabase
      .from("agent_actions")
      .update({
        status: newStatus,
        user_response,
        effectiveness_score: effectivenessScore,
      })
      .eq("id", action_id);

    // Update learnings
    const learningsUpdated = await updateLearnings(
      supabase,
      user.id,
      action as AgentAction,
      user_response,
      effectivenessScore,
    );

    // Mark related signal as resolved if action was helpful
    if (action.signal_id && effectivenessScore > 0.5) {
      await supabase
        .from("agent_signals")
        .update({
          is_resolved: true,
          resolved_at: new Date().toISOString(),
          resolution_type: "action_responded",
        })
        .eq("id", action.signal_id);
    }

    return new Response(
      JSON.stringify({
        learnings_updated: learningsUpdated,
        effectiveness_score: effectivenessScore,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Agent learn error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

function calculateEffectivenessScore(userResponse: {
  response_type: string;
  sentiment?: string;
}): number {
  // Base scores by response type
  const responseScores: Record<string, number> = {
    responded: 1.0,
    action_taken: 1.5,
    opened: 0.7,
    dismissed: 0.2,
    feedback_positive: 1.5,
    feedback_negative: 0.1,
    ignored: 0.0,
  };

  let score = responseScores[userResponse.response_type] ?? 0.5;

  // Adjust for sentiment
  if (userResponse.sentiment === "positive") {
    score = Math.min(2.0, score * 1.2);
  } else if (userResponse.sentiment === "negative") {
    score = Math.max(0.0, score * 0.8);
  }

  return Math.round(score * 100) / 100;
}

function getStatusFromResponse(responseType: string): string {
  const statusMap: Record<string, string> = {
    responded: "responded",
    action_taken: "responded",
    opened: "opened",
    dismissed: "dismissed",
    feedback_positive: "responded",
    feedback_negative: "responded",
    ignored: "dismissed",
  };
  return statusMap[responseType] || "responded";
}

async function updateLearnings(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  action: AgentAction,
  userResponse: { response_type: string; timestamp: string },
  effectivenessScore: number,
): Promise<number> {
  let learningsUpdated = 0;

  // 1. Update optimal time learning
  if (action.delivered_at) {
    const deliveredHour = new Date(action.delivered_at).getHours();
    await updateLearning(supabase, userId, "optimal_time", {
      hour: deliveredHour,
      effectiveness: effectivenessScore,
      action_type: action.action_type,
    });
    learningsUpdated++;
  }

  // 2. Update response preference learning
  await updateLearning(supabase, userId, "response_preference", {
    action_type: action.action_type,
    response_type: userResponse.response_type,
    effectiveness: effectivenessScore,
  });
  learningsUpdated++;

  // 3. Update frequency tolerance if user dismissed
  if (userResponse.response_type === "dismissed") {
    await updateLearning(supabase, userId, "frequency_tolerance", {
      dismissed_count_increment: 1,
      timestamp: userResponse.timestamp,
    });
    learningsUpdated++;
  }

  return learningsUpdated;
}

async function updateLearning(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  learningType: string,
  newData: Record<string, unknown>,
): Promise<void> {
  // Get existing learning
  const { data: existing } = await supabase
    .from("agent_learnings")
    .select("id, learned_value, confidence, sample_count")
    .eq("user_id", userId)
    .eq("learning_type", learningType)
    .single();

  if (existing) {
    // Update using exponential moving average
    const sampleCount = Math.min(1000, (existing.sample_count || 0) + 1);
    const alpha = 2 / (sampleCount + 1); // EMA smoothing factor

    const updatedValue = mergeLearnedValues(
      existing.learned_value,
      newData,
      alpha,
    );
    const newConfidence = Math.min(1.0, 0.5 + sampleCount * 0.02);

    await supabase
      .from("agent_learnings")
      .update({
        learned_value: updatedValue,
        confidence: newConfidence,
        sample_count: sampleCount,
        last_updated: new Date().toISOString(),
      })
      .eq("id", existing.id);
  } else {
    // Create new learning
    await supabase.from("agent_learnings").insert({
      user_id: userId,
      learning_type: learningType,
      learned_value: newData,
      confidence: 0.5,
      sample_count: 1,
    });
  }
}

function mergeLearnedValues(
  existing: Record<string, unknown>,
  newData: Record<string, unknown>,
  alpha: number,
): Record<string, unknown> {
  const merged = { ...existing };

  for (const [key, value] of Object.entries(newData)) {
    if (typeof value === "number" && typeof existing[key] === "number") {
      // Apply EMA for numeric values
      merged[key] = alpha * value + (1 - alpha) * (existing[key] as number);
    } else if (key === "preferred_hours" && Array.isArray(existing[key])) {
      // For optimal time, track preferred hours
      const hours = existing[key] as number[];
      const newHour = newData.hour as number;
      if (newHour !== undefined && !hours.includes(newHour)) {
        merged[key] = [...hours, newHour].slice(-5); // Keep last 5 preferred hours
      }
    } else if (key === "dismissed_count_increment") {
      // Increment dismissal count
      merged.dismissed_count = ((existing.dismissed_count as number) || 0) + 1;
    } else {
      merged[key] = value;
    }
  }

  return merged;
}
