import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.118.0";

interface SessionRequest {
  sessionId?: string;
  sessionType: "guided" | "free" | "manual";
  startedAt: string;
  durationSeconds: number;
  patternId?: string;
  baselineRate: number;
  endingRate: number;
  lowestRate: number;
  breathCount: number;
  calmingDetected: boolean;
  qualityScore: number;
  metrics: Record<string, unknown>;
  deviceInfo?: Record<string, unknown>;
}

interface SessionResponse {
  success: boolean;
  sessionId: string;
  summary: {
    startingRate: number;
    endingRate: number;
    improvementPercent: number;
    breathsTaken: number;
    calmingAchieved: boolean;
  };
  achievements?: Array<{
    id: string;
    badgeId: string;
    title: string;
    description: string;
  }>;
  streakInfo?: {
    currentStreak: number;
    streakMessage: string;
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  try {
    // Create Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Verify authorization
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

    // Client RLS owns the upsert boundary; an arbitrary session ID cannot transfer
    // another account's record through the service role.
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );

    // Parse request body
    const body: SessionRequest = await req.json();

    // Validate required fields
    if (
      !body.sessionType || !body.startedAt ||
      !Number.isFinite(body.durationSeconds) || body.durationSeconds <= 0
    ) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Insert or update session
    const { data: session, error: sessionError } = await supabaseUser
      .from("biofeedback_sessions")
      .upsert(
        {
          id: body.sessionId,
          user_id: user.id,
          session_type: body.sessionType,
          started_at: body.startedAt,
          duration_seconds: body.durationSeconds,
          pattern_id: body.patternId,
          baseline_rate: body.baselineRate,
          ending_rate: body.endingRate,
          lowest_rate: body.lowestRate,
          breath_count: body.breathCount,
          calming_detected: body.calmingDetected,
          quality_score: body.qualityScore,
          metrics: body.metrics,
          device_info: body.deviceInfo,
        },
        { onConflict: "id" },
      )
      .select()
      .single();

    if (sessionError) {
      console.error("Session save error:", sessionError);
      return new Response(JSON.stringify({ error: "Failed to save session" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Calculate improvement
    const improvementPercent = body.baselineRate > 0
      ? ((body.baselineRate - body.endingRate) / body.baselineRate) * 100
      : 0;

    // Check achievements
    const achievements = await checkAchievements(supabase, user.id);

    // Update streak
    const streakInfo = await updateStreak(supabase, user.id);

    const response: SessionResponse = {
      success: true,
      sessionId: session.id,
      summary: {
        startingRate: body.baselineRate,
        endingRate: body.endingRate,
        improvementPercent,
        breathsTaken: body.breathCount,
        calmingAchieved: body.calmingDetected,
      },
      achievements,
      streakInfo,
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Save session error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

async function checkAchievements(
  supabase: SupabaseClient,
  userId: string,
): Promise<
  Array<{ id: string; badgeId: string; title: string; description: string }>
> {
  // Get session count
  const { data: sessionData } = await supabase
    .from("biofeedback_sessions")
    .select("id, calming_detected, baseline_rate, ending_rate")
    .eq("user_id", userId);

  if (!sessionData || sessionData.length === 0) {
    return [];
  }

  const achievements: Array<{
    id: string;
    badgeId: string;
    title: string;
    description: string;
  }> = [];
  const sessionCount = sessionData.length;
  const calmingSessions = sessionData.filter((s) => s.calming_detected).length;
  const recentSessions = sessionData.slice(-3);
  const allCalming = recentSessions.every((s) => s.calming_detected);

  // First session achievement
  if (sessionCount >= 1) {
    achievements.push({
      id: crypto.randomUUID(),
      badgeId: "first_session",
      title: "First Breath",
      description: "Completed your first biofeedback session",
    });
  }

  // Calming master (3 consecutive calming sessions)
  if (allCalming && recentSessions.length >= 3) {
    achievements.push({
      id: crypto.randomUUID(),
      badgeId: "calming_master",
      title: "Calming Master",
      description: "Achieved calming state in 3 sessions",
    });
  }

  // Session milestones
  if (sessionCount >= 10) {
    achievements.push({
      id: crypto.randomUUID(),
      badgeId: "session_milestone_10",
      title: "Deca-Breather",
      description: "Completed 10 biofeedback sessions",
    });
  }

  if (sessionCount >= 50) {
    achievements.push({
      id: crypto.randomUUID(),
      badgeId: "session_milestone_50",
      title: "Breathing Regular",
      description: "Completed 50 biofeedback sessions",
    });
  }

  if (!achievements.length) return [];
  const { data: badges, error: badgeError } = await supabase.from("badges")
    .select("id,code").in("code", achievements.map((item) => item.badgeId));
  if (badgeError) return [];
  const badgeIDs = new Map(
    (badges ?? []).map((badge) => [badge.code, badge.id]),
  );
  const persisted: typeof achievements = [];
  for (const achievement of achievements) {
    const badgeID = badgeIDs.get(achievement.badgeId);
    if (!badgeID) continue;
    const { data: awarded, error } = await supabase.from("user_badges").upsert({
      user_id: userId,
      badge_id: badgeID,
      earned_at: new Date().toISOString(),
    }, { onConflict: "user_id,badge_id", ignoreDuplicates: true }).select("id")
      .maybeSingle();
    if (!error && awarded) {
      persisted.push({ ...achievement, id: awarded.id, badgeId: badgeID });
    }
  }
  return persisted;
}

async function updateStreak(
  supabase: SupabaseClient,
  userId: string,
): Promise<{ currentStreak: number; streakMessage: string }> {
  // Get all session dates for this user
  const { data: sessions } = await supabase
    .from("biofeedback_sessions")
    .select("started_at")
    .eq("user_id", userId)
    .order("started_at", { ascending: false });

  if (!sessions || sessions.length === 0) {
    return { currentStreak: 0, streakMessage: "Start your first session!" };
  }

  // Extract unique dates
  const dates = [
    ...new Set(
      sessions.map((s) => new Date(s.started_at).toISOString().split("T")[0]),
    ),
  ];

  // Calculate streak
  let streak = 1;
  const today = new Date().toISOString().split("T")[0];
  const yesterday = new Date(Date.now() - 86400000).toISOString().split("T")[0];

  // Check if user has a session today or yesterday
  if (dates[0] !== today && dates[0] !== yesterday) {
    streak = 0;
  } else {
    for (let i = 1; i < dates.length; i++) {
      const current = new Date(dates[i - 1]);
      const previous = new Date(dates[i]);
      const diffDays = Math.floor(
        (current.getTime() - previous.getTime()) / 86400000,
      );

      if (diffDays === 1) {
        streak++;
      } else {
        break;
      }
    }
  }

  let streakMessage: string;
  if (streak === 0) {
    streakMessage = "Start a session today to begin your streak!";
  } else if (streak === 1) {
    streakMessage = "1 day streak - keep going!";
  } else {
    streakMessage = `${streak} day streak - you're on fire!`;
  }

  return { currentStreak: streak, streakMessage };
}
