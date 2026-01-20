/**
 * Values Journal Edge Function
 * GET: Retrieve user's journal entries with gap analysis
 * POST: Create new entry with automatic gap detection (30-day baseline)
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface JournalEntry {
  id: string;
  valueKey: string;
  valueName?: string;
  entryType: string;
  description: string;
  impactLevel?: number;
  createdAt: string;
}

interface GapAnalysis {
  hasGap: boolean;
  message?: string;
  baseline?: number;
  currentWeek?: number;
}

interface GetEntriesResponse {
  success: boolean;
  entries?: JournalEntry[];
  gapAnalysis?: Record<string, GapAnalysis>; // Per value
  error?: string;
}

interface CreateEntryRequest {
  valueKey: string;
  entryType: "action" | "conflict" | "alignment" | "growth";
  description: string;
  impactLevel?: number; // 1-5
}

interface CreateEntryResponse {
  success: boolean;
  entryId?: string;
  gapAnalysis?: GapAnalysis;
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

    // GET: Retrieve journal entries
    if (req.method === "GET") {
      // Fetch all journal entries for user
      const { data: entries, error: entriesError } = await supabaseClient
        .from("values_journal")
        .select(
          "id, value_key, entry_type, description, impact_level, created_at",
        )
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(100); // Last 100 entries

      if (entriesError) {
        console.error(
          "[values-journal] Failed to fetch entries:",
          entriesError,
        );
        return new Response(
          JSON.stringify({
            success: false,
            error: "Failed to load journal entries",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Fetch value card names for display
      if (entries && entries.length > 0) {
        const valueKeys = [...new Set(entries.map((e) => e.value_key))];
        const { data: valueCards } = await supabaseClient
          .from("values_cards")
          .select("value_key, display_name")
          .in("value_key", valueKeys);

        const valueNames: Record<string, string> = {};
        valueCards?.forEach((card) => {
          valueNames[card.value_key] = card.display_name;
        });

        // Format entries
        const formattedEntries: JournalEntry[] = entries.map((entry) => ({
          id: entry.id,
          valueKey: entry.value_key,
          valueName: valueNames[entry.value_key] || entry.value_key,
          entryType: entry.entry_type,
          description: entry.description,
          impactLevel: entry.impact_level,
          createdAt: entry.created_at,
        }));

        // Compute gap analysis for each value
        const gapAnalysis: Record<string, GapAnalysis> = {};

        for (const valueKey of valueKeys) {
          const thirtyDaysAgo = new Date();
          thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

          const sevenDaysAgo = new Date();
          sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

          // Count entries in last 30 days
          const { count: thirtyDayCount } = await supabaseClient
            .from("values_journal")
            .select("id", { count: "exact", head: true })
            .eq("user_id", user.id)
            .eq("value_key", valueKey)
            .gte("created_at", thirtyDaysAgo.toISOString());

          // Count entries in last 7 days
          const { count: sevenDayCount } = await supabaseClient
            .from("values_journal")
            .select("id", { count: "exact", head: true })
            .eq("user_id", user.id)
            .eq("value_key", valueKey)
            .gte("created_at", sevenDaysAgo.toISOString());

          // Compute baseline (daily average over 30 days)
          const baseline = (thirtyDayCount || 0) / 30;
          const currentWeek = sevenDayCount || 0;
          const weeklyBaseline = baseline * 7;

          // Flag gap if current week < 50% of baseline
          const hasGap =
            currentWeek < weeklyBaseline * 0.5 && weeklyBaseline > 0;

          gapAnalysis[valueKey] = {
            hasGap,
            message: hasGap
              ? `You're living ${valueNames[valueKey] || valueKey} less this week. You logged ${currentWeek} entries vs ${weeklyBaseline.toFixed(1)} weekly average.`
              : undefined,
            baseline: weeklyBaseline,
            currentWeek,
          };
        }

        const response: GetEntriesResponse = {
          success: true,
          entries: formattedEntries,
          gapAnalysis,
        };

        return new Response(JSON.stringify(response), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // No entries yet
      return new Response(
        JSON.stringify({ success: true, entries: [], gapAnalysis: {} }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // POST: Create new entry
    if (req.method === "POST") {
      const body: CreateEntryRequest = await req.json();
      const { valueKey, entryType, description, impactLevel } = body;

      // Validate input
      if (!valueKey || !entryType || !description) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Missing required fields: valueKey, entryType, description",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      if (!["action", "conflict", "alignment", "growth"].includes(entryType)) {
        return new Response(
          JSON.stringify({
            success: false,
            error:
              "Invalid entryType (must be action, conflict, alignment, or growth)",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      if (description.length > 5000) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Description too long (max 5000 characters)",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      if (impactLevel && (impactLevel < 1 || impactLevel > 5)) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Impact level must be between 1 and 5",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Insert entry
      const { data: newEntry, error: insertError } = await supabaseClient
        .from("values_journal")
        .insert({
          user_id: user.id,
          value_key: valueKey,
          entry_type: entryType,
          description,
          impact_level: impactLevel || null,
        })
        .select("id")
        .single();

      if (insertError) {
        console.error("[values-journal] Failed to create entry:", insertError);
        return new Response(
          JSON.stringify({
            success: false,
            error: "Failed to save journal entry",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Compute gap analysis for this value
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

      const sevenDaysAgo = new Date();
      sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

      const { count: thirtyDayCount } = await supabaseClient
        .from("values_journal")
        .select("id", { count: "exact", head: true })
        .eq("user_id", user.id)
        .eq("value_key", valueKey)
        .gte("created_at", thirtyDaysAgo.toISOString());

      const { count: sevenDayCount } = await supabaseClient
        .from("values_journal")
        .select("id", { count: "exact", head: true })
        .eq("user_id", user.id)
        .eq("value_key", valueKey)
        .gte("created_at", sevenDaysAgo.toISOString());

      const baseline = (thirtyDayCount || 0) / 30;
      const currentWeek = sevenDayCount || 0;
      const weeklyBaseline = baseline * 7;

      const hasGap = currentWeek < weeklyBaseline * 0.5 && weeklyBaseline > 0;

      const gapAnalysis: GapAnalysis = {
        hasGap,
        message: hasGap
          ? `You're living this value less this week. You logged ${currentWeek} entries vs ${weeklyBaseline.toFixed(1)} weekly average.`
          : undefined,
        baseline: weeklyBaseline,
        currentWeek,
      };

      const response: CreateEntryResponse = {
        success: true,
        entryId: newEntry.id,
        gapAnalysis,
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
    console.error("[values-journal] Unexpected error:", error);
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
