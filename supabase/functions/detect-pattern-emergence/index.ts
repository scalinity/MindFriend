import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { checkRateLimit, createRateLimitResponse } from "../_shared/rate-limiter.ts";
import { validateUUID } from "../_shared/validation.ts";
import { getCorsHeaders } from "../_shared/cors.ts";


interface WeightedComponent {
  component_id: string;
  signal: string;
  weight: number;
  detection_threshold: number;
  last_active: string | null;
}

interface ActiveSignal {
  component_id: string;
  signal: string;
  detected_value: number;
  threshold: number;
  days_active: number;
}

interface StressSignature {
  id: string;
  user_id: string;
  crisis_type: string;
  components: WeightedComponent[];
  source: string;
  confidence: number;
  detection_sensitivity: number;
}

interface DetectPatternRequest {
  signature_id?: string;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from JWT
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
      return new Response(
        JSON.stringify({ error: "Unauthorized", code: "AUTH_ERROR" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Rate limiting: 10 requests per minute per user
    if (!checkRateLimit(user.id, 10, 60 * 1000)) {
      return createRateLimitResponse(60);
    }

    const body: DetectPatternRequest = await req.json().catch(() => ({}));

    // Input validation: signature_id must be valid UUID if provided
    if (body.signature_id && !validateUUID(body.signature_id)) {
      return new Response(
        JSON.stringify({ error: "Invalid signature_id format", code: "INVALID_INPUT" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get user's signature
    let signatureQuery = supabase
      .from("stress_signatures")
      .select("*")
      .eq("user_id", user.id);

    if (body.signature_id) {
      signatureQuery = signatureQuery.eq("id", body.signature_id);
    }

    const { data: signatures, error: sigError } = await signatureQuery;

    if (sigError) {
      console.error("Signature query error:", sigError);
      return new Response(
        JSON.stringify({
          error: "Failed to fetch signature",
          code: "QUERY_ERROR",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!signatures || signatures.length === 0) {
      return new Response(
        JSON.stringify({
          error:
            "No active signature found. Complete the warning signs setup first.",
          code: "SIGNATURE_NOT_INITIALIZED",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const signature = signatures[0] as StressSignature;
    const components = signature.components || [];

    if (components.length === 0) {
      return new Response(
        JSON.stringify({
          is_emerging: false,
          emergence_score: 0,
          active_components: [],
          message: "Signature has no components configured",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get signals from last 3 days
    const threeDaysAgo = new Date();
    threeDaysAgo.setDate(threeDaysAgo.getDate() - 3);

    const { data: recentSignals, error: signalError } = await supabase
      .from("signature_signals")
      .select("signal_type, value, date")
      .eq("user_id", user.id)
      .gte("date", threeDaysAgo.toISOString().split("T")[0])
      .order("date", { ascending: false });

    if (signalError) {
      console.error("Signal query error:", signalError);
      return new Response(
        JSON.stringify({
          error: "Failed to fetch signals",
          code: "QUERY_ERROR",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Group signals by type and find max value + days active
    const signalMap = new Map<
      string,
      { maxValue: number; dates: Set<string> }
    >();

    for (const signal of recentSignals || []) {
      const existing = signalMap.get(signal.signal_type);
      if (existing) {
        existing.maxValue = Math.max(existing.maxValue, signal.value);
        existing.dates.add(signal.date);
      } else {
        signalMap.set(signal.signal_type, {
          maxValue: signal.value,
          dates: new Set([signal.date]),
        });
      }
    }

    // Detect active components
    const activeComponents: ActiveSignal[] = [];
    let totalWeight = 0;
    let activeWeight = 0;

    for (const component of components) {
      totalWeight += component.weight;

      const signalData = signalMap.get(component.signal);
      if (!signalData) continue;

      if (signalData.maxValue >= component.detection_threshold) {
        activeWeight += component.weight;
        activeComponents.push({
          component_id: component.component_id,
          signal: component.signal,
          detected_value: signalData.maxValue,
          threshold: component.detection_threshold,
          days_active: signalData.dates.size,
        });
      }
    }

    // Calculate emergence score
    const emergenceScore = totalWeight > 0 ? activeWeight / totalWeight : 0;
    const isEmerging =
      emergenceScore >= signature.detection_sensitivity &&
      activeComponents.length >= 2;

    // Determine severity
    let severity: "mild" | "moderate" | "severe";
    if (activeComponents.length >= 5) {
      severity = "severe";
    } else if (activeComponents.length >= 3) {
      severity = "moderate";
    } else {
      severity = "mild";
    }

    // Determine intervention tier
    let interventionTier: "gentle" | "moderate" | "immediate";
    if (emergenceScore >= 0.8) {
      interventionTier = "immediate";
    } else if (emergenceScore >= 0.6) {
      interventionTier = "moderate";
    } else {
      interventionTier = "gentle";
    }

    // Calculate estimated time to event (hours)
    // Formula: (1.0 - avgSignalStrength) * 72
    let estimatedHours: number | null = null;
    if (isEmerging && activeComponents.length > 0) {
      const avgStrength =
        activeComponents.reduce((sum, c) => sum + c.detected_value, 0) /
        activeComponents.length;
      estimatedHours = Math.round((1.0 - avgStrength) * 72);
    }

    // If pattern is emerging, create an alert
    let alert = null;
    if (isEmerging) {
      // Check if there's already a recent alert (within 24h)
      const oneDayAgo = new Date();
      oneDayAgo.setDate(oneDayAgo.getDate() - 1);

      const { data: existingAlert } = await supabase
        .from("pattern_alerts")
        .select("id, emergence_score, severity")
        .eq("user_id", user.id)
        .eq("signature_id", signature.id)
        .gte("detected_at", oneDayAgo.toISOString())
        .is("dismissed_at", null)
        .maybeSingle();

      if (existingAlert) {
        // Update if severity increased
        if (emergenceScore > existingAlert.emergence_score) {
          await supabase
            .from("pattern_alerts")
            .update({
              emergence_score: emergenceScore,
              active_components: activeComponents,
              severity: severity,
              intervention_tier: interventionTier,
              predicted_time_to_event: estimatedHours
                ? estimatedHours * 3600
                : null,
            })
            .eq("id", existingAlert.id);
        }

        alert = {
          id: existingAlert.id,
          severity: severity,
          intervention_tier: interventionTier,
          message: generateAlertMessage(activeComponents, severity),
          updated: true,
        };
      } else {
        // Create new alert
        const { data: newAlert, error: alertError } = await supabase
          .from("pattern_alerts")
          .insert({
            user_id: user.id,
            signature_id: signature.id,
            detected_at: new Date().toISOString(),
            active_components: activeComponents,
            emergence_score: emergenceScore,
            severity: severity,
            intervention_tier: interventionTier,
            predicted_time_to_event: estimatedHours
              ? estimatedHours * 3600
              : null,
            intervention_delivered: false,
          })
          .select("id")
          .single();

        if (!alertError && newAlert) {
          alert = {
            id: newAlert.id,
            severity: severity,
            intervention_tier: interventionTier,
            message: generateAlertMessage(activeComponents, severity),
            updated: false,
          };
        }
      }

      // Update signature with last_active dates for active components
      const updatedComponents = components.map((comp) => {
        const active = activeComponents.find((a) => a.signal === comp.signal);
        if (active) {
          return { ...comp, last_active: new Date().toISOString() };
        }
        return comp;
      });

      await supabase
        .from("stress_signatures")
        .update({ components: updatedComponents })
        .eq("id", signature.id);
    }

    return new Response(
      JSON.stringify({
        is_emerging: isEmerging,
        emergence_score: Math.round(emergenceScore * 100) / 100,
        active_components: activeComponents,
        active_component_count: activeComponents.length,
        total_component_count: components.length,
        severity: severity,
        intervention_tier: interventionTier,
        estimated_hours: estimatedHours,
        alert: alert,
      }),
      {
        status: 200,
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

function generateAlertMessage(
  activeComponents: ActiveSignal[],
  severity: string,
): string {
  const signals = activeComponents.map((c) => c.signal);

  // Personalized messages based on active components
  if (signals.includes("isolation") && signals.includes("insomnia_wired")) {
    return "I've noticed you've been quieter lately and sleep has been tough. This is a pattern we've seen before. Want to talk about it?";
  }

  if (signals.includes("catastrophizing") || signals.includes("rumination")) {
    return "It seems like worries have been building up. Let's take a moment to get grounded.";
  }

  if (signals.includes("numbness") || signals.includes("oversleeping")) {
    return "I'm noticing some familiar patterns. How are you really doing?";
  }

  if (signals.includes("low_energy") && signals.includes("procrastination")) {
    return "Energy has felt low lately. Small steps today can help break the cycle.";
  }

  if (signals.includes("tearfulness") || signals.includes("irritability")) {
    return "Emotions have been running high. That's okay. Let's check in together.";
  }

  // Generic messages by severity
  switch (severity) {
    case "severe":
      return "I'm noticing several warning signs coming together. This is a good time to reach out for support.";
    case "moderate":
      return "Some patterns are emerging that we've tracked before. Let's check in and see how you're really doing.";
    default:
      return "I'm noticing a few familiar signs. How are you feeling today?";
  }
}
