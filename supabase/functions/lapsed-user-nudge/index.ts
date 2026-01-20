import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { daysSinceDate, calculateScheduledTime } from "../_shared/email-utils.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const inactivityThresholds = [3, 7, 14];
    let totalQueued = 0;

    for (const days of inactivityThresholds) {
      try {
        const thresholdDate = new Date();
        thresholdDate.setDate(thresholdDate.getDate() - days);

        // Find users inactive for exactly this threshold (with 1-day buffer)
        const { data: inactiveUsers } = await supabase
          .from("profiles")
          .select("id, email, full_name, last_active_at")
          .lte("last_active_at", thresholdDate.toISOString())
          .gte("last_active_at", new Date(thresholdDate.getTime() - 86400000).toISOString());

        if (!inactiveUsers || inactiveUsers.length === 0) continue;

        console.log(`Found ${inactiveUsers.length} users inactive for ${days} days`);

        const userIds = inactiveUsers.map((u: any) => u.id);

        // Batch fetch all preferences, quests, and exercises
        const [
          { data: allPrefs },
          { data: allQuests },
          { data: allExercises },
        ] = await Promise.all([
          supabase
            .from("email_preferences")
            .select("user_id, lapsed_nudge, timezone, preferred_send_hour, unsubscribed_at")
            .in("user_id", userIds),
          supabase
            .from("quests")
            .select("user_id, template_name")
            .in("user_id", userIds)
            .eq("completed", true)
            .order("completed_at", { ascending: false })
            .limit(1),
          supabase
            .from("exercise_sessions")
            .select("user_id, exercises(name)")
            .in("user_id", userIds)
            .order("completed_at", { ascending: false })
            .limit(1),
        ]);

        // Index data by user_id
        const prefsByUser = new Map<string, any>();
        const questsByUser = new Map<string, any>();
        const exercisesByUser = new Map<string, any>();

        (allPrefs || []).forEach((p: any) => {
          prefsByUser.set(p.user_id, p);
        });

        (allQuests || []).forEach((q: any) => {
          if (!questsByUser.has(q.user_id)) {
            questsByUser.set(q.user_id, q);
          }
        });

        (allExercises || []).forEach((e: any) => {
          if (!exercisesByUser.has(e.user_id)) {
            exercisesByUser.set(e.user_id, e);
          }
        });

        // Build queue entries
        const queueEntries = [];
        for (const user of inactiveUsers) {
          try {
            const prefs = prefsByUser.get(user.id);
            if (!prefs || !prefs.lapsed_nudge || prefs.unsubscribed_at) continue;

            const topQuestData = questsByUser.get(user.id);
            const topExerciseData = exercisesByUser.get(user.id);

            const topQuest = topQuestData?.template_name || "Complete a daily quest";
            const topExercise = topExerciseData?.exercises?.name || "Try a breathing exercise";

            const scheduledFor = calculateScheduledTime(
              prefs.timezone,
              prefs.preferred_send_hour,
            );

            queueEntries.push({
              user_id: user.id,
              email_type: "lapsed_nudge",
              template_version: "v1",
              payload: {
                daysSinceActive: days,
                lastActivityDate: user.last_active_at,
                topQuest,
                topExercise,
              },
              status: "pending",
              scheduled_for: scheduledFor.toISOString(),
            });

            totalQueued++;
          } catch (error) {
            console.error(`Error processing user ${user.id}:`, error);
          }
        }

        // Batch insert all queue entries
        if (queueEntries.length > 0) {
          await supabase.from("email_queue").insert(queueEntries);
        }
      } catch (error) {
        console.error(`Error processing ${days}-day threshold:`, error);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        queued: totalQueued,
        thresholds: inactivityThresholds,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
