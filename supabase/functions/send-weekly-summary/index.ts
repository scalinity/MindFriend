import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  getCurrentWeekStart,
  calculateScheduledTime,
} from "../_shared/email-utils.ts";
import { getMoodTrendMessage } from "../_shared/notification-utils.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const weekStart = getCurrentWeekStart();
    const weekEnd = new Date(weekStart);
    weekEnd.setDate(weekEnd.getDate() + 6);  // End on Sunday, not Monday (off-by-one fix)
    weekEnd.setHours(23, 59, 59, 999);  // Set to end of day

    console.log(
      `Starting weekly summary generation for week: ${weekStart.toISOString()} to ${weekEnd.toISOString()}`,
    );

    // Batch fetch: preferences with profiles
    const { data: prefWithProfiles, error: prefError } = await supabase
      .from("email_preferences")
      .select(
        "user_id, timezone, preferred_send_hour, profiles(id, email, full_name)",
      )
      .eq("weekly_summary", true)
      .is("unsubscribed_at", null);

    if (prefError) {
      throw prefError;
    }

    if (!prefWithProfiles || prefWithProfiles.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: "No users with weekly_summary enabled",
          queued: 0,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    const userIds = prefWithProfiles.map((p: any) => p.user_id);
    console.log(`Found ${userIds.length} users for weekly summary`);

    // Paginate to prevent memory explosion (process 1000 users at a time)
    const BATCH_SIZE = 1000;
    let totalQueued = 0;
    let totalErrors = 0;

    for (let offset = 0; offset < userIds.length; offset += BATCH_SIZE) {
      const batchUserIds = userIds.slice(offset, offset + BATCH_SIZE);
      console.log(
        `Processing batch: ${offset + 1}-${Math.min(offset + BATCH_SIZE, userIds.length)} of ${userIds.length}`
      );

      // Fetch batch data
      const [
        { data: batchQuests },
        { data: batchMoods },
        { data: batchExercises },
        { data: batchStreaks },
      ] = await Promise.all([
        supabase
          .from("quests")
          .select("user_id, template_name, completed")
          .in("user_id", batchUserIds)
          .gte("created_at", weekStart.toISOString())
          .lte("created_at", weekEnd.toISOString()),
        supabase
          .from("moods")
          .select("user_id, recorded_at, mood, intensity")
          .in("user_id", batchUserIds)
          .gte("recorded_at", weekStart.toISOString())
          .lte("recorded_at", weekEnd.toISOString()),
        supabase
          .from("exercise_sessions")
          .select("user_id, completed_at")
          .in("user_id", batchUserIds)
          .gte("completed_at", weekStart.toISOString())
          .lte("completed_at", weekEnd.toISOString()),
        supabase
          .from("user_profiles")
          .select("user_id, current_streak_days")
          .in("user_id", batchUserIds),
      ]);

      // Build Maps for O(1) lookup (fixes O(n²) performance bug)
      const userQuestsMap = new Map<string, any[]>();
      (batchQuests || []).forEach((q: any) => {
        if (!userQuestsMap.has(q.user_id)) userQuestsMap.set(q.user_id, []);
        userQuestsMap.get(q.user_id)!.push(q);
      });

      const userMoodsMap = new Map<string, any[]>();
      (batchMoods || []).forEach((m: any) => {
        if (!userMoodsMap.has(m.user_id)) userMoodsMap.set(m.user_id, []);
        userMoodsMap.get(m.user_id)!.push(m);
      });

      const userExercisesMap = new Map<string, any[]>();
      (batchExercises || []).forEach((e: any) => {
        if (!userExercisesMap.has(e.user_id)) userExercisesMap.set(e.user_id, []);
        userExercisesMap.get(e.user_id)!.push(e);
      });

      const streaksMap = new Map<string, number>();
      (batchStreaks || []).forEach((s: any) => {
        streaksMap.set(s.user_id, s.current_streak_days);
      });

      // Process batch
      const queueEntries: any[] = [];
      // CRITICAL FIX: Filter to batch subset BEFORE iterating to prevent O(n²) complexity
      const batchPreferences = prefWithProfiles.filter(p => batchUserIds.includes(p.user_id));
      
      for (const pref of batchPreferences) {
        const profile = (pref as any).profiles?.[0];
        if (!profile) continue;

        // Get data from Maps (O(1) lookup)
        const questsForUser = userQuestsMap.get(pref.user_id) || [];
        const moodsForUser = userMoodsMap.get(pref.user_id) || [];
        const exercisesForUser = userExercisesMap.get(pref.user_id) || [];

        // Aggregate quest data
        const questStats: {
          [key: string]: { completed: number; total: number };
        } = {};
        questsForUser.forEach((q: any) => {
          if (!questStats[q.template_name]) {
            questStats[q.template_name] = { completed: 0, total: 0 };
          }
          questStats[q.template_name].total++;
          if (q.completed) {
            questStats[q.template_name].completed++;
          }
        });

        const questArray = Object.entries(questStats).map(([name, stats]) => ({
          name,
          completed: stats.completed,
          total: stats.total,
        }));

        // Format mood data
        const moodData = (moodsForUser || []).map((m: any) => ({
          date: m.recorded_at.split("T")[0],
          mood: m.mood,
          intensity: m.intensity,
        }));

        const totalStreakDays = streaksMap.get(pref.user_id) || 0;
        const exercisesCompleted = exercisesForUser.length;

        // Calculate scheduled send time
        const scheduledFor = calculateScheduledTime(
          pref.timezone,
          pref.preferred_send_hour,
        );

        queueEntries.push({
          user_id: pref.user_id,
          email_type: "weekly_summary",
          template_version: "v1",
          payload: {
            weekStartDate: weekStart.toISOString().split("T")[0],
            quests: questArray,
            moods: moodData,
            totalStreakDays,
            exercisesCompleted,
          },
          status: "pending",
          scheduled_for: scheduledFor.toISOString(),
          retry_count: 0,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        });

        // Send weekly summary push notification
        const completedQuests = questsForUser.filter((q: any) => q.completed).length;
        // Calculate simple mood trend from moodData
        let moodTrend: string | null = null;
        let avgMood: number | null = null;
        if (moodData.length >= 2) {
          const intensities = moodData.map((m: any) => m.intensity);
          avgMood = intensities.reduce((a: number, b: number) => a + b, 0) / intensities.length;
          const firstHalf = intensities.slice(0, Math.floor(intensities.length / 2));
          const secondHalf = intensities.slice(Math.floor(intensities.length / 2));
          const firstAvg = firstHalf.reduce((a: number, b: number) => a + b, 0) / firstHalf.length;
          const secondAvg = secondHalf.reduce((a: number, b: number) => a + b, 0) / secondHalf.length;
          if (secondAvg - firstAvg > 0.5) moodTrend = "improving";
          else if (firstAvg - secondAvg > 0.5) moodTrend = "declining";
          else moodTrend = "stable";
        }

        // Fire push notification (non-blocking, don't fail email queue on push error)
        fetch(`${supabaseUrl}/functions/v1/send-notification`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${supabaseServiceKey}`,
          },
          body: JSON.stringify({
            type: "weekly_summary",
            recipientId: pref.user_id,
            data: {
              checkins: moodData.length,
              quests: completedQuests,
              exercises: exercisesCompleted,
              moodMessage: getMoodTrendMessage(moodTrend, avgMood),
            },
          }),
        }).catch((err) => console.error(`Weekly push notification failed for user ${pref.user_id}:`, err));
      }

      // Batch insert all queue entries for this batch
      let queuedCount = 0;
      let errorCount = 0;

      if (queueEntries.length > 0) {
        const { error: insertError } = await supabase
          .from("email_queue")
          .insert(queueEntries);

        if (insertError) {
          console.error("Batch insert error, falling back to individual inserts:", insertError);
          
          // Fall back to individual inserts to prevent losing entire batch
          for (const entry of queueEntries) {
            try {
              const { error: singleError } = await supabase
                .from("email_queue")
                .insert([entry]);
              
              if (singleError) {
                console.error(`Failed to queue email for user ${entry.user_id}:`, singleError);
                errorCount++;
              } else {
                queuedCount++;
              }
            } catch (err) {
              console.error(`Exception inserting entry for user ${entry.user_id}:`, err);
              errorCount++;
            }
          }
        } else {
          queuedCount = queueEntries.length;
        }
      }

      totalQueued += queuedCount;
      totalErrors += errorCount;
    }

    console.log(
      `Weekly summary generation complete: ${totalQueued} queued, ${totalErrors} errors`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        message: "Weekly summaries queued",
        queued: totalQueued,
        errors: totalErrors,
        totalUsers: prefWithProfiles.length,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Unexpected error in send-weekly-summary:", error);
    return new Response(
      JSON.stringify({
        error: `Unexpected error: ${String(error)}`,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
