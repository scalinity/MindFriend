import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface DistortionStat {
  code: string;
  name: string;
  count: number;
  trend: "increasing" | "decreasing" | "stable";
  helpfulRate: number;
}

interface PatternAnalytics {
  totalEncounters: number;
  last7Days: number;
  last30Days: number;
  mostCommon: DistortionStat[];
  byDistortionType: DistortionStat[];
}

serve(async (req) => {
  try {
    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Fetch all encounters for this user
    const { data: encounters, error: encountersError } = await supabase
      .from("distortion_encounters")
      .select("distortion_code, occurred_at, confidence")
      .eq("user_id", user.id)
      .order("occurred_at", { ascending: false });

    if (encountersError) {
      throw encountersError;
    }

    // Calculate date boundaries
    const now = new Date();
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const sixtyDaysAgo = new Date(now.getTime() - 60 * 24 * 60 * 60 * 1000);

    // Calculate totals
    const totalEncounters = encounters?.length || 0;
    const last7Days = encounters?.filter((e) =>
      new Date(e.occurred_at) >= sevenDaysAgo
    ).length || 0;
    const last30Days = encounters?.filter((e) =>
      new Date(e.occurred_at) >= thirtyDaysAgo
    ).length || 0;

    // Group by distortion type and calculate stats
    const distortionMap = new Map<string, {
      code: string;
      count: number;
      recentCount: number;  // Last 30 days
      olderCount: number;   // 30-60 days ago
      helpfulCount: number;
      totalInteractions: number;
    }>();

    for (const encounter of encounters || []) {
      const existing = distortionMap.get(encounter.distortion_code) || {
        code: encounter.distortion_code,
        count: 0,
        recentCount: 0,
        olderCount: 0,
        helpfulCount: 0,
        totalInteractions: 0,
      };

      existing.count++;

      const occurredAt = new Date(encounter.occurred_at);
      if (occurredAt >= thirtyDaysAgo) {
        existing.recentCount++;
      } else if (occurredAt >= sixtyDaysAgo) {
        existing.olderCount++;
      }

      distortionMap.set(encounter.distortion_code, existing);
    }

    // Fetch interaction data for helpful rate
    const { data: interactions, error: interactionsError } = await supabase
      .from("coach_interactions")
      .select("distortion_code, action")
      .eq("user_id", user.id);

    if (!interactionsError && interactions) {
      for (const interaction of interactions) {
        const stats = distortionMap.get(interaction.distortion_code);
        if (stats) {
          stats.totalInteractions++;
          if (interaction.action === "helpful") {
            stats.helpfulCount++;
          }
        }
      }
    }

    // Fetch distortion names from database
    const distortionCodes = Array.from(distortionMap.keys());
    const { data: distortions, error: distortionsError } = await supabase
      .from("cognitive_distortions")
      .select("code, name")
      .in("code", distortionCodes);

    if (distortionsError) {
      throw distortionsError;
    }

    // Build distortion stats array
    const distortionStats: DistortionStat[] = [];
    for (const [code, stats] of distortionMap.entries()) {
      const distortion = distortions?.find((d) => d.code === code);
      if (!distortion) continue;

      // Calculate trend
      let trend: "increasing" | "decreasing" | "stable" = "stable";
      if (stats.recentCount > 0 && stats.olderCount > 0) {
        const recentRate = stats.recentCount / 30; // Per day in recent period
        const olderRate = stats.olderCount / 30;    // Per day in older period
        const changePct = ((recentRate - olderRate) / olderRate) * 100;

        if (changePct > 20) trend = "increasing";
        else if (changePct < -20) trend = "decreasing";
        else trend = "stable";
      } else if (stats.recentCount > stats.olderCount) {
        trend = "increasing";
      } else if (stats.recentCount < stats.olderCount) {
        trend = "decreasing";
      }

      // Calculate helpful rate
      const helpfulRate = stats.totalInteractions > 0
        ? stats.helpfulCount / stats.totalInteractions
        : 0;

      distortionStats.push({
        code,
        name: distortion.name,
        count: stats.count,
        trend,
        helpfulRate,
      });
    }

    // Sort by count descending
    distortionStats.sort((a, b) => b.count - a.count);

    const analytics: PatternAnalytics = {
      totalEncounters,
      last7Days,
      last30Days,
      mostCommon: distortionStats.slice(0, 5), // Top 5
      byDistortionType: distortionStats,
    };

    return new Response(JSON.stringify(analytics), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("my-patterns error:", error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Unknown error" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
