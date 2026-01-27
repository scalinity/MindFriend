import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getMonthYear, calculateScheduledTime } from "../_shared/email-utils.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const now = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0);
    monthEnd.setHours(23, 59, 59, 999);  // Set to end of day to include all data from last day of month
    const monthYear = getMonthYear(monthStart);

    console.log(`Generating monthly reports for ${monthYear}`);

    // Fetch all users with monthly_report enabled
    const { data: preferences } = await supabase
      .from("email_preferences")
      .select("user_id, timezone, preferred_send_hour")
      .eq("monthly_report", true)
      .is("unsubscribed_at", null);

    if (!preferences || preferences.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: "No users with monthly_report enabled",
          queued: 0,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    const userIds = preferences.map((p: any) => p.user_id);
    console.log(`Found ${userIds.length} users for monthly report`);

    // Paginate to prevent memory explosion (process 1000 users at a time)
    const BATCH_SIZE = 1000;
    let totalQueued = 0;
    let totalErrors = 0;

    for (let offset = 0; offset < userIds.length; offset += BATCH_SIZE) {
      const batchUserIds = userIds.slice(offset, offset + BATCH_SIZE);
      console.log(
        `Processing batch: ${offset + 1}-${Math.min(offset + BATCH_SIZE, userIds.length)} of ${userIds.length}`
      );

      // Batch fetch all user data at once
      const [
        { data: batchQuests },
        { data: batchMoods },
        { data: batchUserProfiles },
        { data: batchBadges },
        { data: batchExercises },
      ] = await Promise.all([
        supabase
          .from("quests")
          .select("user_id, template_name, completed")
          .in("user_id", batchUserIds)
          .gte("created_at", monthStart.toISOString())
          .lte("created_at", monthEnd.toISOString()),
        supabase
          .from("moods")
          .select("user_id, mood, intensity")
          .in("user_id", batchUserIds)
          .gte("recorded_at", monthStart.toISOString())
          .lte("recorded_at", monthEnd.toISOString()),
        supabase
          .from("user_profiles")
          .select("user_id, current_streak_days")
          .in("user_id", batchUserIds),
        supabase
          .from("user_badges")
          .select("user_id, badges(name)")
          .in("user_id", batchUserIds)
          .limit(5),
        supabase
          .from("exercise_sessions")
          .select("user_id, id")
          .in("user_id", batchUserIds)
          .gte("completed_at", monthStart.toISOString())
          .lte("completed_at", monthEnd.toISOString()),
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

      const userProfilesMap = new Map<string, any>();
      (batchUserProfiles || []).forEach((p: any) => {
        userProfilesMap.set(p.user_id, p);
      });

      const userBadgesMap = new Map<string, any[]>();
      (batchBadges || []).forEach((b: any) => {
        if (!userBadgesMap.has(b.user_id)) userBadgesMap.set(b.user_id, []);
        userBadgesMap.get(b.user_id)!.push(b);
      });

      const userExercisesMap = new Map<string, any[]>();
      (batchExercises || []).forEach((e: any) => {
        if (!userExercisesMap.has(e.user_id)) userExercisesMap.set(e.user_id, []);
        userExercisesMap.get(e.user_id)!.push(e);
      });

      // Process batch - CRITICAL: filter to batch subset to prevent O(n²) iteration
      const batchPreferences = preferences.filter(p => batchUserIds.includes(p.user_id));
      const queueEntries: any[] = [];
      let queuedCount = 0;

      for (const pref of batchPreferences) {
        try {
          // Get cached quest data using O(1) lookup
          const quests = userQuestsMap.get(pref.user_id) || [];
          const questStats: { [key: string]: { completed: number; total: number } } = {};
          quests.forEach((q: any) => {
            if (!questStats[q.template_name]) {
              questStats[q.template_name] = { completed: 0, total: 0 };
            }
            questStats[q.template_name].total++;
            if (q.completed) questStats[q.template_name].completed++;
          });

          // Get cached mood data
          const moods = userMoodsMap.get(pref.user_id) || [];
          let moodTrend = "Stable";
          if (moods.length > 0) {
            const avgIntensity =
              moods.reduce((sum: number, m: any) => sum + m.intensity, 0) / moods.length;
            moodTrend =
              avgIntensity > 7
                ? "Positive"
                : avgIntensity > 4
                  ? "Neutral"
                  : "Challenging";
          }

          const userProfile = userProfilesMap.get(pref.user_id);
          const badges = userBadgesMap.get(pref.user_id) || [];
          const exercises = userExercisesMap.get(pref.user_id) || [];

          const scheduledFor = calculateScheduledTime(
            pref.timezone,
            pref.preferred_send_hour,
          );

          queueEntries.push({
            user_id: pref.user_id,
            email_type: "monthly_report",
            template_version: "v1",
            payload: {
              monthYear,
              quests: Object.entries(questStats).map(([name, stats]) => ({
                name,
                completed: stats.completed,
                total: stats.total,
              })),
              moodTrend,
              totalStreakDays: userProfile?.current_streak_days || 0,
              exercisesCompleted: exercises.length,
              topBadges: (badges || []).map((b: any) => b.badges?.name || ""),
            },
            status: "pending",
            scheduled_for: scheduledFor.toISOString(),
          });

          queuedCount++;
        } catch (error) {
          console.error(`Error processing user: ${error}`);
          totalErrors++;
        }
      }

      // Batch insert all queue entries
      if (queueEntries.length > 0) {
        const { error: insertError } = await supabase
          .from("email_queue")
          .insert(queueEntries);

        if (insertError) {
          console.error("Batch insert error:", insertError);
          return new Response(
            JSON.stringify({
              error: `Failed to queue emails: ${insertError.message}`,
            }),
            { status: 500, headers: { "Content-Type": "application/json" } },
          );
        }
      }

      totalQueued += queuedCount;
    }

    return new Response(
      JSON.stringify({
        success: true,
        queued: totalQueued,
        total: preferences.length,
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
