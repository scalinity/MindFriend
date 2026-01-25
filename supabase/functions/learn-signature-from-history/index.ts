import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, createRateLimitResponse } from "../_shared/rate-limiter.ts";
import { validateUUID } from "../_shared/validation.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface WeightedComponent {
  component_id: string;
  signal: string;
  weight: number;
  detection_threshold: number;
  last_active: string | null;
}

interface LearnSignatureRequest {
  crisis_event_ids?: string[];
  lookback_days?: number;
}

interface SignatureSignal {
  signal_type: string;
  value: number;
  date: string;
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

    // Rate limiting: 5 requests per hour per user (learning is expensive)
    if (!checkRateLimit(`learn:${user.id}`, 5, 60 * 60 * 1000)) {
      return createRateLimitResponse(3600);
    }

    const body: LearnSignatureRequest = await req.json();
    
    // Input validation: lookback_days must be reasonable
    const lookbackDays = body.lookback_days ?? 7;
    if (typeof lookbackDays !== "number" || lookbackDays < 1 || lookbackDays > 30) {
      return new Response(
        JSON.stringify({ error: "lookback_days must be between 1 and 30", code: "INVALID_INPUT" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Input validation: crisis_event_ids must be valid UUIDs if provided
    if (body.crisis_event_ids && Array.isArray(body.crisis_event_ids)) {
      for (const id of body.crisis_event_ids) {
        if (!validateUUID(id)) {
          return new Response(
            JSON.stringify({ error: "Invalid crisis_event_id format", code: "INVALID_INPUT" }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
      }
      // Limit array size to prevent abuse
      if (body.crisis_event_ids.length > 50) {
        return new Response(
          JSON.stringify({ error: "Too many crisis_event_ids (max 50)", code: "INVALID_INPUT" }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Get crisis events for this user
    let crisisQuery = supabase
      .from("crisis_events")
      .select("id, occurred_at, detected_at, crisis_type, severity")
      .eq("user_id", user.id)
      .order("occurred_at", { ascending: false });

    if (body.crisis_event_ids && body.crisis_event_ids.length > 0) {
      crisisQuery = crisisQuery.in("id", body.crisis_event_ids);
    }

    const { data: crisisEvents, error: crisisError } = await crisisQuery;

    if (crisisError) {
      console.error("Crisis query error:", crisisError);
      return new Response(
        JSON.stringify({
          error: "Failed to fetch crisis events",
          code: "QUERY_ERROR",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!crisisEvents || crisisEvents.length === 0) {
      return new Response(
        JSON.stringify({
          error:
            "No crisis events found. Add at least 1 past crisis to learn patterns.",
          code: "INSUFFICIENT_DATA",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // For each crisis, analyze signals from lookback period
    const signalScores: Map<string, number[]> = new Map();
    let dataPointsAnalyzed = 0;

    for (const crisis of crisisEvents) {
      const crisisDate = crisis.occurred_at || crisis.detected_at;
      if (!crisisDate) continue;

      const crisisDateObj = new Date(crisisDate);
      const lookbackStart = new Date(crisisDateObj);
      lookbackStart.setDate(lookbackStart.getDate() - lookbackDays);

      // Get signals from the lookback period
      const { data: signals, error: signalError } = await supabase
        .from("signature_signals")
        .select("signal_type, value, date")
        .eq("user_id", user.id)
        .gte("date", lookbackStart.toISOString().split("T")[0])
        .lt("date", crisisDateObj.toISOString().split("T")[0]);

      if (signalError) {
        console.error("Signal query error:", signalError);
        continue;
      }

      if (signals) {
        dataPointsAnalyzed += signals.length;
        for (const signal of signals as SignatureSignal[]) {
          if (!signalScores.has(signal.signal_type)) {
            signalScores.set(signal.signal_type, []);
          }
          signalScores.get(signal.signal_type)!.push(signal.value);
        }
      }
    }

    // Also check mood data for patterns (moods table)
    for (const crisis of crisisEvents) {
      const crisisDate = crisis.occurred_at || crisis.detected_at;
      if (!crisisDate) continue;

      const crisisDateObj = new Date(crisisDate);
      const lookbackStart = new Date(crisisDateObj);
      lookbackStart.setDate(lookbackStart.getDate() - lookbackDays);

      const { data: moods } = await supabase
        .from("moods")
        .select("score, created_at")
        .eq("user_id", user.id)
        .gte("created_at", lookbackStart.toISOString())
        .lt("created_at", crisisDateObj.toISOString());

      if (moods) {
        dataPointsAnalyzed += moods.length;
        // Low mood scores indicate potential emotional signals
        for (const mood of moods) {
          if (mood.score <= 2) {
            // Score 1-2 indicates numbness/low mood
            if (!signalScores.has("numbness")) {
              signalScores.set("numbness", []);
            }
            signalScores.get("numbness")!.push(1.0 - mood.score / 5);
          }
          if (mood.score === 3) {
            // Neutral mood might indicate emotional flatness
            if (!signalScores.has("numbness")) {
              signalScores.set("numbness", []);
            }
            signalScores.get("numbness")!.push(0.4);
          }
        }
      }
    }

    // Calculate which signals were consistently elevated before crises
    const consistentSignals: WeightedComponent[] = [];
    const totalCrises = crisisEvents.length;

    for (const [signalType, values] of signalScores) {
      if (values.length === 0) continue;

      // Calculate average value
      const avgValue = values.reduce((a, b) => a + b, 0) / values.length;

      // Calculate consistency (how often was it above threshold)
      const elevatedCount = values.filter((v) => v >= 0.5).length;
      const consistency = elevatedCount / values.length;

      // Signal is consistent if:
      // - Average value > 0.5 (elevated)
      // - Consistency > 0.5 (present in at least half the measurements)
      if (avgValue >= 0.5 && consistency >= 0.5) {
        consistentSignals.push({
          component_id: crypto.randomUUID(),
          signal: signalType,
          weight: Math.min(avgValue, 0.9), // Cap at 0.9
          detection_threshold: 0.6,
          last_active: null,
        });
      }
    }

    // If no signals found, return a message but not an error
    if (consistentSignals.length === 0) {
      return new Response(
        JSON.stringify({
          signature: null,
          patterns_found: 0,
          data_points_analyzed: dataPointsAnalyzed,
          message:
            "No consistent patterns found before crisis events. Try adding more data or reporting more crisis events.",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Calculate confidence based on amount of data
    // More crises + more data points = higher confidence
    const confidence = Math.min(
      totalCrises * 0.15 +
        (dataPointsAnalyzed > 20 ? 0.2 : dataPointsAnalyzed * 0.01) +
        0.3,
      0.9,
    );

    // Determine primary crisis type from events
    const typeCounts: Record<string, number> = {};
    for (const crisis of crisisEvents) {
      const type = crisis.crisis_type || "general";
      typeCounts[type] = (typeCounts[type] || 0) + 1;
    }
    const primaryType =
      Object.entries(typeCounts).sort((a, b) => b[1] - a[1])[0]?.[0] ||
      "general";

    // Check if user already has a signature
    const { data: existingSignature } = await supabase
      .from("stress_signatures")
      .select("id, components, source, confidence")
      .eq("user_id", user.id)
      .eq("crisis_type", primaryType)
      .maybeSingle();

    let signatureId: string;
    let finalComponents = consistentSignals;
    let finalSource = "historical_learned";

    if (existingSignature) {
      // Merge with existing signature (hybrid_refined)
      const existingComponents =
        existingSignature.components as WeightedComponent[];
      const mergedComponents = new Map<string, WeightedComponent>();

      // Add existing components
      for (const comp of existingComponents) {
        mergedComponents.set(comp.signal, comp);
      }

      // Merge/update with learned components (take max weight)
      for (const learned of consistentSignals) {
        const existing = mergedComponents.get(learned.signal);
        if (existing) {
          mergedComponents.set(learned.signal, {
            ...existing,
            weight: Math.max(existing.weight, learned.weight),
          });
        } else {
          mergedComponents.set(learned.signal, learned);
        }
      }

      finalComponents = Array.from(mergedComponents.values());
      finalSource = "hybrid_refined";

      // Update existing signature
      const { error: updateError } = await supabase
        .from("stress_signatures")
        .update({
          components: finalComponents,
          source: finalSource,
          confidence: Math.max(existingSignature.confidence, confidence),
          last_learned_at: new Date().toISOString(),
        })
        .eq("id", existingSignature.id);

      if (updateError) {
        console.error("Update error:", updateError);
        return new Response(
          JSON.stringify({
            error: "Failed to update signature",
            code: "UPDATE_ERROR",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      signatureId = existingSignature.id;
    } else {
      // Create new signature
      const { data: newSignature, error: insertError } = await supabase
        .from("stress_signatures")
        .insert({
          user_id: user.id,
          crisis_type: primaryType,
          components: consistentSignals,
          source: "historical_learned",
          confidence: confidence,
          detection_sensitivity: 0.5,
          last_learned_at: new Date().toISOString(),
        })
        .select("id")
        .single();

      if (insertError) {
        console.error("Insert error:", insertError);
        return new Response(
          JSON.stringify({
            error: "Failed to create signature",
            code: "INSERT_ERROR",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      signatureId = newSignature.id;
    }

    // Mark analyzed crises
    await supabase
      .from("crisis_events")
      .update({ analyzed: true })
      .eq("user_id", user.id)
      .in(
        "id",
        crisisEvents.map((c) => c.id),
      );

    return new Response(
      JSON.stringify({
        signature: {
          id: signatureId,
          user_id: user.id,
          crisis_type: primaryType,
          components: finalComponents,
          source: finalSource,
          confidence: confidence,
          detection_sensitivity: 0.5,
          last_learned_at: new Date().toISOString(),
        },
        patterns_found: consistentSignals.length,
        data_points_analyzed: dataPointsAnalyzed,
        crises_analyzed: crisisEvents.length,
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
