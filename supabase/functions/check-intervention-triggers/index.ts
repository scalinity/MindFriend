// Contextual Micro-Interventions: Trigger Evaluation and Intervention Selection
// Evaluates trigger conditions and selects best intervention for user context

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface TriggerContext {
  biometrics?: {
    heartRate?: number; // BPM
    hrv?: number; // Milliseconds
  };
  timeOfDay?: string; // 'morning' | 'afternoon' | 'evening'
  recentMood?: number; // 1-5 scale
}

interface CheckTriggersRequest {
  context?: TriggerContext;
}

type TriggerType = "time_based" | "biometric" | "pattern" | "manual";

interface CheckTriggersResponse {
  shouldTrigger: boolean;
  triggerType?: TriggerType;
  intervention?: any; // MicroMomentTemplate
  contextMessage?: string;
  suppressionReason?:
    | "quiet_hours"
    | "daily_limit"
    | "cooldown"
    | "no_matching_templates"
    | "disabled";
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Get authenticated user
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

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

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

    const userId = user.id;

    // Parse request body
    const { context }: CheckTriggersRequest = await req.json();

    // 1. Load user preferences
    const { data: prefs, error: prefsError } = await supabase
      .from("intervention_preferences")
      .select("*")
      .eq("user_id", userId)
      .single();

    if (prefsError && prefsError.code !== "PGRST116") {
      // Error other than "no rows"
      throw prefsError;
    }

    // If no preferences exist, create defaults
    if (!prefs) {
      const { data: newPrefs, error: insertError } = await supabase
        .from("intervention_preferences")
        .insert({
          user_id: userId,
          enabled: true,
          max_daily: 5,
          quiet_hours_start: null,
          quiet_hours_end: null,
        })
        .select()
        .single();

      if (insertError) throw insertError;

      // Use new default preferences
      return evaluateTriggers(supabase, userId, newPrefs, context);
    }

    // Check if interventions are enabled
    if (!prefs.enabled) {
      return new Response(
        JSON.stringify({
          shouldTrigger: false,
          suppressionReason: "disabled",
        } as CheckTriggersResponse),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Evaluate triggers with user preferences
    const response = await evaluateTriggers(supabase, userId, prefs, context);

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error in check-intervention-triggers:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: error.message,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

async function evaluateTriggers(
  supabase: any,
  userId: string,
  prefs: any,
  context?: TriggerContext,
): Promise<CheckTriggersResponse> {
  // 2. Check quiet hours
  const now = new Date();
  const currentTime = now.toTimeString().slice(0, 8); // "HH:MM:SS"

  if (prefs.quiet_hours_start && prefs.quiet_hours_end) {
    const { data: isQuiet, error: quietError } = await supabase.rpc(
      "is_in_quiet_hours",
      {
        check_time: currentTime,
        quiet_start: prefs.quiet_hours_start,
        quiet_end: prefs.quiet_hours_end,
      },
    );

    if (quietError) {
      console.error("Error checking quiet hours:", quietError);
    } else if (isQuiet) {
      return {
        shouldTrigger: false,
        suppressionReason: "quiet_hours",
      };
    }
  }

  // 3. Check daily limit
  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);

  const { count: todayCount, error: countError } = await supabase
    .from("intervention_deliveries")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("delivered_at", todayStart.toISOString());

  if (countError) {
    console.error("Error checking daily limit:", countError);
  } else if ((todayCount || 0) >= prefs.max_daily) {
    return {
      shouldTrigger: false,
      suppressionReason: "daily_limit",
    };
  }

  // 4. Check cooldown (4 hours after last dismissal)
  const cooldownHours = 4;
  const cooldownCutoff = new Date(
    now.getTime() - cooldownHours * 60 * 60 * 1000,
  );

  const { data: recentDismissal, error: dismissError } = await supabase
    .from("intervention_deliveries")
    .select("dismissed_at")
    .eq("user_id", userId)
    .not("dismissed_at", "is", null)
    .gte("dismissed_at", cooldownCutoff.toISOString())
    .order("dismissed_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (dismissError) {
    console.error("Error checking cooldown:", dismissError);
  } else if (recentDismissal) {
    return {
      shouldTrigger: false,
      suppressionReason: "cooldown",
    };
  }

  // 5. Evaluate trigger conditions
  const triggerType = determineTriggerType(context);

  if (!triggerType) {
    return {
      shouldTrigger: false,
      suppressionReason: "no_matching_templates",
    };
  }

  // 6. Select best intervention for trigger type
  const { data: suggestions, error: suggestionError } =
    await supabase.functions.invoke("get-micro-suggestions", {
      body: {
        triggerType,
        triggerConfidence: calculateConfidence(context, triggerType),
        limit: 1,
      },
    });

  if (suggestionError) {
    console.error("Error getting suggestions:", suggestionError);
    return {
      shouldTrigger: false,
      suppressionReason: "no_matching_templates",
    };
  }

  if (!suggestions?.suggestions || suggestions.suggestions.length === 0) {
    return {
      shouldTrigger: false,
      suppressionReason: "no_matching_templates",
    };
  }

  const intervention = suggestions.suggestions[0];

  // Generate context message
  const contextMessage = generateContextMessage(triggerType, context);

  return {
    shouldTrigger: true,
    triggerType,
    intervention,
    contextMessage,
  };
}

function determineTriggerType(context?: TriggerContext): TriggerType | null {
  if (!context) {
    // Default to time-based if no context provided
    return "time_based";
  }

  // Priority: biometric > time_based > pattern
  if (context.biometrics) {
    const { heartRate, hrv } = context.biometrics;

    // Elevated heart rate threshold: > 100 BPM
    if (heartRate && heartRate > 100) {
      return "biometric";
    }

    // Low HRV threshold: < 30 ms
    if (hrv && hrv < 30) {
      return "biometric";
    }
  }

  // Time-based trigger
  if (context.timeOfDay) {
    return "time_based";
  }

  // Pattern-based (low recent mood)
  if (context.recentMood && context.recentMood <= 2) {
    return "pattern";
  }

  return "time_based"; // Default fallback
}

function calculateConfidence(
  context?: TriggerContext,
  triggerType?: TriggerType,
): number {
  if (!context || !triggerType) return 0.5;

  if (triggerType === "biometric" && context.biometrics) {
    const { heartRate, hrv } = context.biometrics;

    if (heartRate) {
      // Scale confidence: 100 BPM = 0.5, 130+ BPM = 1.0
      const hrConfidence = Math.min(1.0, (heartRate - 100) / 30 + 0.5);
      return hrConfidence;
    }

    if (hrv) {
      // Scale confidence: 30 ms = 0.5, 0 ms = 1.0
      const hrvConfidence = Math.min(1.0, 1.0 - hrv / 60);
      return hrvConfidence;
    }
  }

  if (triggerType === "time_based") {
    return 1.0; // Time-based triggers are always high confidence
  }

  if (triggerType === "pattern" && context.recentMood) {
    // Scale confidence: mood 2 = 0.6, mood 1 = 1.0
    return Math.min(1.0, 1.6 - context.recentMood * 0.3);
  }

  return 0.7; // Default moderate confidence
}

function generateContextMessage(
  triggerType: TriggerType,
  context?: TriggerContext,
): string {
  switch (triggerType) {
    case "biometric":
      if (
        context?.biometrics?.heartRate &&
        context.biometrics.heartRate > 100
      ) {
        return "I noticed your heart rate is elevated. A quick breathing exercise might help.";
      }
      if (context?.biometrics?.hrv && context.biometrics.hrv < 30) {
        return "Your stress levels seem high. Let's take a moment to reset.";
      }
      return "I sensed you might need a quick wellness break.";

    case "time_based":
      if (context?.timeOfDay === "morning") {
        return "Good morning! Perfect time to set a positive intention.";
      }
      if (context?.timeOfDay === "afternoon") {
        return "Afternoon slump? A quick reset can help you refocus.";
      }
      if (context?.timeOfDay === "evening") {
        return "Good time to reflect and release the day.";
      }
      return "Good time for a mindful break.";

    case "pattern":
      return "I noticed you might be experiencing a challenging moment. This could help.";

    default:
      return "A moment of wellness for you.";
  }
}
