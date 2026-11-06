import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

interface HistoryRequest {
  limit?: number;
  offset?: number;
  startDate?: string;
  endDate?: string;
}

interface SessionResponse {
  id: string;
  sessionType: string;
  startedAt: string;
  durationSeconds: number;
  patternName: string | null;
  baselineRate: number | null;
  endingRate: number | null;
  improvementPercent: number | null;
  breathCount: number | null;
  calmingDetected: boolean | null;
  qualityScore: number | null;
}

Deno.serve(async (req: Request): Promise<Response> => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const search = new URL(req.url).searchParams;
    const limit = Number(search.get("limit") ?? 20),
      offset = Number(search.get("offset") ?? 0);
    if (
      !Number.isInteger(limit) || limit < 1 || limit > 100 ||
      !Number.isSafeInteger(offset) || offset < 0
    ) {
      return Response.json({ error: "Invalid pagination" }, { status: 400 });
    }
    const params: HistoryRequest = {
      limit,
      offset,
      startDate: search.get("startDate") ?? undefined,
      endDate: search.get("endDate") ?? undefined,
    };

    let query = supabase
      .from("biofeedback_sessions")
      .select(
        `
        id,
        session_type,
        started_at,
        duration_seconds,
        baseline_rate,
        ending_rate,
        breath_count,
        calming_detected,
        quality_score,
        pattern_id
      `,
        { count: "exact" },
      )
      .eq("user_id", user.id)
      .order("started_at", { ascending: false })
      .range(
        params.offset ?? 0,
        (params.offset ?? 0) + (params.limit ?? 20) - 1,
      );

    if (params.startDate) {
      query = query.gte("started_at", params.startDate);
    }
    if (params.endDate) {
      query = query.lte("started_at", params.endDate);
    }

    const { data: sessions, error, count } = await query;

    if (error) {
      console.error("Get history error:", error);
      return new Response(
        JSON.stringify({ error: "Failed to fetch history" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    const ids = [
      ...new Set(
        (sessions ?? []).map((session) => session.pattern_id).filter(Boolean),
      ),
    ];
    const patternNames = new Map<string, string>();
    if (ids.length) {
      const { data: patterns, error: patternError } = await supabase.from(
        "breathing_patterns",
      )
        .select("id,display_name").in("id", ids);
      if (patternError) {
        return Response.json({ error: "Failed to fetch pattern names" }, {
          status: 503,
        });
      }
      for (const pattern of patterns ?? []) {
        patternNames.set(pattern.id, pattern.display_name);
      }
    }
    const responseSessions: SessionResponse[] = (sessions ?? []).map(
      (s: Record<string, unknown>) => {
        const session = s as Record<string, unknown>;
        const baselineRate = session.baseline_rate as number | null;
        const endingRate = session.ending_rate as number | null;

        let improvementPercent: number | null = null;
        if (baselineRate !== null && endingRate !== null && baselineRate > 0) {
          improvementPercent = ((baselineRate - endingRate) / baselineRate) *
            100;
        }

        return {
          id: session.id as string,
          sessionType: session.session_type as string,
          startedAt: session.started_at as string,
          durationSeconds: session.duration_seconds as number,
          patternName: patternNames.get(session.pattern_id as string) ?? null,
          baselineRate,
          endingRate,
          improvementPercent,
          breathCount: session.breath_count as number | null,
          calmingDetected: session.calming_detected as boolean | null,
          qualityScore: session.quality_score as number | null,
        };
      },
    );

    return new Response(
      JSON.stringify({
        success: true,
        sessions: responseSessions,
        total: count ?? 0,
        limit: params.limit,
        offset: params.offset,
        hasMore: (count ?? 0) > (params.offset ?? 0) + (params.limit ?? 20),
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Get session history error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
