import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";


interface SensoryStats {
  totalSessions: number;
  totalMinutes: number;
  currentStreak: number;
  longestStreak: number;
  favoriteModality: string | null;
  modalityBreakdown: {
    tactile: number;
    visual: number;
    audio: number;
  };
  recentSessions: Array<{
    id: string;
    modality: string;
    patternId: string;
    duration: number;
    completedAt: string;
  }>;
}

serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Validate JWT and get user
    const authHeader = req.headers.get("Authorization")!;
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

    // Query all completed sessions
    const { data: allSessions, error: sessionsError } = await supabase
      .from("sensory_sessions")
      .select("modality, duration_seconds, completed_at")
      .eq("user_id", user.id)
      .eq("status", "completed")
      .order("completed_at", { ascending: false });

    if (sessionsError) {
      console.error("Failed to query sessions:", sessionsError);
      return new Response(
        JSON.stringify({ error: "Failed to query sessions" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const sessions = allSessions || [];

    // Calculate total sessions and minutes
    const totalSessions = sessions.length;
    const totalMinutes = Math.floor(
      sessions.reduce((sum, s) => sum + (s.duration_seconds || 0), 0) / 60,
    );

    // Calculate modality breakdown
    const modalityBreakdown = sessions.reduce(
      (acc, session) => {
        acc[session.modality as keyof typeof acc] =
          (acc[session.modality as keyof typeof acc] || 0) + 1;
        return acc;
      },
      { tactile: 0, visual: 0, audio: 0 },
    );

    // Determine favorite modality (most sessions)
    let favoriteModality: string | null = null;
    if (totalSessions > 0) {
      const maxCount = Math.max(...Object.values(modalityBreakdown));
      favoriteModality =
        Object.entries(modalityBreakdown).find(
          ([_, count]) => count === maxCount,
        )?.[0] || null;
    }

    // Calculate current streak (consecutive days with sessions)
    let currentStreak = 0;
    if (sessions.length > 0) {
      const today = new Date();
      today.setHours(0, 0, 0, 0);

      // Group sessions by date
      const sessionsByDate = new Map<string, boolean>();
      sessions.forEach((session) => {
        const date = new Date(session.completed_at);
        date.setHours(0, 0, 0, 0);
        sessionsByDate.set(date.toISOString(), true);
      });

      // Count consecutive days from today backwards
      let checkDate = new Date(today);
      while (true) {
        const dateStr = checkDate.toISOString();
        if (sessionsByDate.has(dateStr)) {
          currentStreak++;
          checkDate.setDate(checkDate.getDate() - 1);
        } else {
          break;
        }
      }
    }

    // Calculate longest streak (simplified - same logic but find max)
    let longestStreak = currentStreak; // Simplified for now

    // Get recent sessions (last 10)
    const { data: recentSessionsData, error: recentError } = await supabase
      .from("sensory_sessions")
      .select("id, modality, pattern_id, duration_seconds, completed_at")
      .eq("user_id", user.id)
      .eq("status", "completed")
      .order("completed_at", { ascending: false })
      .limit(10);

    if (recentError) {
      console.error("Failed to query recent sessions:", recentError);
    }

    const recentSessions =
      recentSessionsData?.map((s) => ({
        id: s.id,
        modality: s.modality,
        patternId: s.pattern_id,
        duration: s.duration_seconds || 0,
        completedAt: s.completed_at || "",
      })) || [];

    const stats: SensoryStats = {
      totalSessions,
      totalMinutes,
      currentStreak,
      longestStreak,
      favoriteModality,
      modalityBreakdown,
      recentSessions,
    };

    return new Response(JSON.stringify(stats), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error in get-sensory-stats:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
