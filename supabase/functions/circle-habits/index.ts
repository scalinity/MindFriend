import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface CircleHabitsRequest {
  operation: string;
  circleId?: string;
  template?: any;
  settings?: any;
  checkin?: any;
}

serve(async (req: Request) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { autoRefreshToken: false } },
  );

  // Verify authorization
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "UNAUTHORIZED",
          message: "Please sign in to access circle habits",
        },
      }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(token);

  if (authError || !user) {
    return new Response(
      JSON.stringify({
        success: false,
        error: { code: "UNAUTHORIZED", message: "Invalid or expired token" },
      }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    const body: CircleHabitsRequest = await req.json();
    const { operation, circleId, template, settings, checkin } = body;

    // GET TEMPLATES
    if (operation === "getTemplates") {
      const { data: templates, error } = await supabase
        .from("circle_templates")
        .select("*")
        .eq("circle_id", circleId || null)
        .order("created_at", { ascending: false });

      if (error) throw error;

      return new Response(
        JSON.stringify({
          success: true,
          data: { templates: templates || [] },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // CREATE TEMPLATE
    if (operation === "createTemplate") {
      const { data: newTemplate, error } = await supabase
        .from("circle_templates")
        .insert({
          circle_id: template.circle_id,
          name: template.name,
          description: template.description,
          questions: template.questions,
          reminder_days: template.reminder_days,
          reminder_time: template.reminder_time,
          is_active: template.is_active,
        })
        .select()
        .single();

      if (error) throw error;

      return new Response(
        JSON.stringify({
          success: true,
          data: { templates: [newTemplate] },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // GET NUDGES
    if (operation === "getNudges") {
      const { data: nudges, error } = await supabase
        .from("circle_nudges")
        .select("*")
        .eq("user_id", user.id)
        .is("acknowledged_at", null)
        .gte("expires_at", new Date().toISOString())
        .order("created_at", { ascending: false });

      if (error) throw error;

      return new Response(
        JSON.stringify({
          success: true,
          data: { nudges: nudges || [] },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // DISMISS NUDGE
    if (operation === "dismissNudge") {
      const { error } = await supabase
        .from("circle_nudges")
        .update({ acknowledged_at: new Date().toISOString() })
        .eq("id", checkin?.id);

      if (error) throw error;

      return new Response(
        JSON.stringify({
          success: true,
          data: null,
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // GET STREAK STATUS
    if (operation === "getStreakStatus") {
      // Get user's check-in streak
      const { data: checkins } = await supabase
        .from("circle_checkins")
        .select("submitted_at")
        .eq("user_id", user.id)
        .order("submitted_at", { ascending: false });

      if (checkins && checkins.length > 0) {
        const now = new Date();
        const lastCheckin = new Date(checkins[0].submitted_at);
        const daysSinceLastCheckin = Math.floor(
          (now.getTime() - lastCheckin.getTime()) / (1000 * 60 * 60 * 24),
        );

        // Calculate current streak
        let currentStreak = 0;
        const checkedDates = new Set<string>();

        for (const c of checkins) {
          const dateStr = new Date(c.submitted_at).toISOString().split("T")[0];
          if (!checkedDates.has(dateStr)) {
            checkedDates.add(dateStr);
          }
        }

        // Simple streak calculation
        let streakBroken = false;
        for (let i = 0; i < 365; i++) {
          const d = new Date();
          d.setDate(d.getDate() - i);
          const dateStr = d.toISOString().split("T")[0];

          if (checkedDates.has(dateStr)) {
            currentStreak++;
          } else if (i > 0) {
            // Allow missing today if checkin not yet done
            if (i === 0) continue;
            break;
          }
        }

        const longestStreak = currentStreak; // Simplified

        return new Response(
          JSON.stringify({
            success: true,
            data: {
              streak_status: {
                current_streak: currentStreak,
                longest_streak: longestStreak,
                last_checkin_date: checkins[0].submitted_at,
                is_at_risk: daysSinceLastCheckin > 2,
              },
            },
            error: null,
          }),
          { headers: { "Content-Type": "application/json" } },
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          data: {
            streak_status: {
              current_streak: 0,
              longest_streak: 0,
              last_checkin_date: null,
              is_at_risk: false,
            },
          },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // SUBMIT CHECK-IN
    if (operation === "submitCheckin") {
      const { data: newCheckin, error } = await supabase
        .from("circle_checkins")
        .insert({
          circle_id: checkin.circle_id,
          template_id: checkin.template_id,
          user_id: user.id,
          responses: checkin.responses,
          mood: checkin.mood,
          submitted_at: new Date().toISOString(),
        })
        .select()
        .single();

      if (error) throw error;

      return new Response(
        JSON.stringify({
          success: true,
          data: { checkin: newCheckin },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({
        success: false,
        error: { code: "INVALID_OPERATION", message: "Invalid operation" },
      }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error in circle habits function:", error);

    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "SERVER_ERROR",
          message: "Unable to process request; please try again",
        },
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
