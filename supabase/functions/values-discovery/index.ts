/**
 * Values Discovery Edge Function
 * Handles 3-phase values assessment:
 * Phase 1: Select 8-12 values from 32 cards
 * Phase 2: Rank top 5 from Phase 1 selections
 * Phase 3: Confirm final 5, compute confidence score
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface DiscoveryRequest {
  phase: 1 | 2 | 3;
  selectedCardIds?: string[]; // Phase 1: 8-12 cards
  rankedCardIds?: string[]; // Phase 2: Exactly 5 in ranked order
  confirmedCardIds?: string[]; // Phase 3: Exactly 5 (final confirmation)
}

interface DiscoveryResponse {
  success: boolean;
  nextPhase?: 2 | 3 | "complete";
  confidenceScore?: number; // Only in Phase 3
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

    // Parse request body
    const body: DiscoveryRequest = await req.json();
    const { phase, selectedCardIds, rankedCardIds, confirmedCardIds } = body;

    // Validate phase
    if (![1, 2, 3].includes(phase)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Invalid phase (must be 1, 2, or 3)",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Handle Phase 1: Select 8-12 values
    if (phase === 1) {
      if (
        !selectedCardIds ||
        selectedCardIds.length < 8 ||
        selectedCardIds.length > 12
      ) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Phase 1 requires selecting 8-12 values",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Store Phase 1 selections
      const valuesData = {
        phase1_selections: selectedCardIds,
        phase2_rankings: [],
        phase3_confirmed: [],
        scores: {},
        custom_definitions: {},
      };

      const { error: upsertError } = await supabaseClient
        .from("user_values")
        .upsert(
          {
            user_id: user.id,
            values_data: valuesData,
            top_values: [],
            custom_values: [],
            values_categories: {},
            updated_at: new Date().toISOString(),
          },
          {
            onConflict: "user_id",
          },
        );

      if (upsertError) {
        console.error("[values-discovery] Phase 1 upsert error:", upsertError);
        return new Response(
          JSON.stringify({
            success: false,
            error: "Failed to save selections",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const response: DiscoveryResponse = {
        success: true,
        nextPhase: 2,
      };

      return new Response(JSON.stringify(response), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Handle Phase 2: Rank top 5 from Phase 1 selections
    if (phase === 2) {
      if (!rankedCardIds || rankedCardIds.length !== 5) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Phase 2 requires exactly 5 ranked values",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Fetch existing values_data
      const { data: existingData, error: fetchError } = await supabaseClient
        .from("user_values")
        .select("values_data")
        .eq("user_id", user.id)
        .single();

      if (fetchError || !existingData) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Phase 1 must be completed first",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Update with Phase 2 rankings
      const valuesData = {
        ...existingData.values_data,
        phase2_rankings: rankedCardIds,
      };

      const { error: updateError } = await supabaseClient
        .from("user_values")
        .update({
          values_data: valuesData,
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", user.id);

      if (updateError) {
        console.error("[values-discovery] Phase 2 update error:", updateError);
        return new Response(
          JSON.stringify({ success: false, error: "Failed to save rankings" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const response: DiscoveryResponse = {
        success: true,
        nextPhase: 3,
      };

      return new Response(JSON.stringify(response), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Handle Phase 3: Confirm final 5 and compute confidence
    if (phase === 3) {
      if (!confirmedCardIds || confirmedCardIds.length !== 5) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Phase 3 requires exactly 5 confirmed values",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Fetch existing values_data and card details
      const { data: existingData, error: fetchError } = await supabaseClient
        .from("user_values")
        .select("values_data")
        .eq("user_id", user.id)
        .single();

      if (fetchError || !existingData) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Phase 2 must be completed first",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Fetch value card details for categorization
      const { data: cards, error: cardsError } = await supabaseClient
        .from("values_cards")
        .select("value_key, category")
        .in("value_key", confirmedCardIds);

      if (cardsError || !cards) {
        console.error(
          "[values-discovery] Failed to fetch card details:",
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

      // Compute scores (inversely weighted by rank: 1st=5pts, 2nd=4pts, ..., 5th=1pt)
      const scores: Record<string, number> = {};
      confirmedCardIds.forEach((valueKey, index) => {
        scores[valueKey] = 5 - index; // Rank 1=5 points, Rank 5=1 point
      });

      // Build category mapping
      const categoriesMap: Record<string, string[]> = {
        personal: [],
        relationships: [],
        work: [],
        growth: [],
      };

      cards.forEach((card) => {
        if (categoriesMap[card.category]) {
          categoriesMap[card.category].push(card.value_key);
        }
      });

      // Compute simple confidence score (0.0-1.0 based on consistency)
      // Higher scores indicate user was confident in rankings (no ambiguity)
      const confidenceScore = 0.8; // Simplified for MVP (see decisions.md)

      // Update with final Phase 3 data
      const valuesData = {
        ...existingData.values_data,
        phase3_confirmed: confirmedCardIds,
        scores,
      };

      const { error: finalUpdateError } = await supabaseClient
        .from("user_values")
        .update({
          values_data: valuesData,
          top_values: confirmedCardIds,
          values_categories: categoriesMap,
          completed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", user.id);

      if (finalUpdateError) {
        console.error(
          "[values-discovery] Phase 3 final update error:",
          finalUpdateError,
        );
        return new Response(
          JSON.stringify({
            success: false,
            error: "Failed to complete assessment",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const response: DiscoveryResponse = {
        success: true,
        nextPhase: "complete",
        confidenceScore,
      };

      return new Response(JSON.stringify(response), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Should never reach here
    return new Response(
      JSON.stringify({ success: false, error: "Invalid request" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("[values-discovery] Unexpected error:", error);
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
