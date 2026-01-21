import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface RewriteHistoryRequest {
  limit?: number;
  offset?: number;
  rewriteType?: string;
  wasApplied?: boolean;
  startDate?: string;
  endDate?: string;
}

serve(async (req: Request): Promise<Response> => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization" }), {
      status: 401,
    });
  }

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
    });
  }

  try {
    const url = new URL(req.url);
    const params = url.searchParams;
    const limit = parseInt(params.get("limit") || "20");
    const offset = parseInt(params.get("offset") || "0");
    const rewriteType = params.get("rewriteType") || undefined;
    const wasApplied =
      params.get("wasApplied") === "true"
        ? true
        : params.get("wasApplied") === "false"
          ? false
          : undefined;
    const startDate = params.get("startDate") || undefined;
    const endDate = params.get("endDate") || undefined;

    let query = supabase
      .from("rewrite_history")
      .select(
        "id, created_at, original_message, rewrite_type, rewritten_message, was_applied, feedback_rating",
        { count: "exact" },
      )
      .eq("user_id", user.id);

    if (rewriteType) {
      query = query.eq("rewrite_type", rewriteType);
    }
    if (wasApplied !== undefined) {
      query = query.eq("was_applied", wasApplied);
    }
    if (startDate) {
      query = query.gte("created_at", startDate);
    }
    if (endDate) {
      query = query.lte("created_at", endDate);
    }

    const {
      data: entries,
      error,
      count,
    } = await query
      .order("created_at", { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) {
      return new Response(
        JSON.stringify({ error: "Failed to fetch history" }),
        { status: 500 },
      );
    }

    // Calculate stats
    const totalRewrites = count || 0;
    const appliedCount = entries?.filter((e) => e.was_applied).length || 0;
    const avgRating =
      entries
        ?.filter((e) => e.feedback_rating)
        .reduce((sum, e) => sum + (e.feedback_rating || 0), 0) /
      (entries?.filter((e) => e.feedback_rating).length || 1);

    // Find favorite type
    const typeCounts: Record<string, number> = {};
    entries?.forEach((e) => {
      typeCounts[e.rewrite_type] = (typeCounts[e.rewrite_type] || 0) + 1;
    });
    const favoriteType =
      Object.entries(typeCounts).sort((a, b) => b[1] - a[1])[0]?.[0] || null;

    return new Response(
      JSON.stringify({
        entries: entries || [],
        total: totalRewrites,
        hasMore: totalRewrites > offset + limit,
        stats: {
          totalRewrites,
          appliedCount,
          averageRating: Math.round(avgRating * 10) / 10 || null,
          favoriteType,
        },
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error fetching rewrite history:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
    });
  }
});
