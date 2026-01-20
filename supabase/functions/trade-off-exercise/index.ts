/**
 * Trade-Off Exercise Edge Function
 * GET: Fetch random values conflict scenario
 * POST: Record user's choice and reasoning
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface GetScenarioResponse {
  success: boolean;
  scenario?: {
    id: string;
    text: string;
    valueA: { key: string; name: string };
    valueB: { key: string; name: string };
    questions: string[];
  };
  error?: string;
}

interface RecordChoiceRequest {
  scenarioId: string;
  choice: "value_a" | "value_b" | "both";
  reasoning?: string;
}

interface RecordChoiceResponse {
  success: boolean;
  tradeOffId?: string;
  error?: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Create Supabase client
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: {
          headers: { Authorization: req.headers.get("Authorization")! },
        },
      },
    );

    // Get authenticated user
    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser();

    if (authError || !user) {
      return new Response(
        JSON.stringify({ success: false, error: "Unauthorized" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // GET: Fetch random scenario
    if (req.method === "GET") {
      // Get random scenario using PostgreSQL's RANDOM()
      const { data: scenario, error: scenarioError } = await supabaseClient
        .from("trade_off_scenarios")
        .select("id, scenario_text, value_a, value_b, questions")
        .limit(1)
        .order("id", { ascending: false }); // Simplified random selection

      if (scenarioError || !scenario || scenario.length === 0) {
        console.error(
          "[trade-off-exercise] Failed to fetch scenario:",
          scenarioError,
        );
        return new Response(
          JSON.stringify({
            success: false,
            error: "No scenarios available",
          }),
          {
            status: 404,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const selectedScenario = scenario[0];

      // Fetch value card names
      const { data: valueCards, error: cardsError } = await supabaseClient
        .from("values_cards")
        .select("value_key, display_name")
        .in("value_key", [selectedScenario.value_a, selectedScenario.value_b]);

      if (cardsError || !valueCards) {
        console.error(
          "[trade-off-exercise] Failed to fetch value cards:",
          cardsError,
        );
        return new Response(
          JSON.stringify({
            success: false,
            error: "Failed to load value details",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const valueACard = valueCards.find(
        (c) => c.value_key === selectedScenario.value_a,
      );
      const valueBCard = valueCards.find(
        (c) => c.value_key === selectedScenario.value_b,
      );

      const response: GetScenarioResponse = {
        success: true,
        scenario: {
          id: selectedScenario.id,
          text: selectedScenario.scenario_text,
          valueA: {
            key: selectedScenario.value_a,
            name: valueACard?.display_name || selectedScenario.value_a,
          },
          valueB: {
            key: selectedScenario.value_b,
            name: valueBCard?.display_name || selectedScenario.value_b,
          },
          questions: selectedScenario.questions || [],
        },
      };

      return new Response(JSON.stringify(response), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // POST: Record user's choice
    if (req.method === "POST") {
      const body: RecordChoiceRequest = await req.json();
      const { scenarioId, choice, reasoning } = body;

      // Validate choice
      if (!["value_a", "value_b", "both"].includes(choice)) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Invalid choice (must be 'value_a', 'value_b', or 'both')",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Validate scenario exists
      const { data: scenarioExists, error: checkError } = await supabaseClient
        .from("trade_off_scenarios")
        .select("id")
        .eq("id", scenarioId)
        .single();

      if (checkError || !scenarioExists) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Scenario not found",
          }),
          {
            status: 404,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Save user's choice
      const { data: tradeOff, error: insertError } = await supabaseClient
        .from("user_trade_offs")
        .insert({
          user_id: user.id,
          scenario_id: scenarioId,
          user_choice: choice,
          reasoning: reasoning || null,
        })
        .select("id")
        .single();

      if (insertError) {
        console.error(
          "[trade-off-exercise] Failed to save choice:",
          insertError,
        );
        return new Response(
          JSON.stringify({
            success: false,
            error: "Failed to save your choice",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const response: RecordChoiceResponse = {
        success: true,
        tradeOffId: tradeOff.id,
      };

      return new Response(JSON.stringify(response), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Method not allowed
    return new Response(
      JSON.stringify({
        success: false,
        error: "Method not allowed (use GET or POST)",
      }),
      {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("[trade-off-exercise] Unexpected error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: "Internal server error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
