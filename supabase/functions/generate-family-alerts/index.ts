// Spec 11: Family Wellness - Generate Family Alerts Edge Function
// Generates parental alerts based on child activity patterns and mood trends
// Can be called by cron or manually

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface GenerateAlertsResponse {
  success: boolean;
  alertsGenerated?: number;
  familiesProcessed?: number;
  error?: string;
}

serve(async (req: Request): Promise<Response> => {
  // Allow both GET (for cron) and POST (for manual triggering)
  if (req.method !== "GET" && req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // For GET requests (cron), verify cron secret if provided
  if (req.method === "GET") {
    const authHeader = req.headers.get("Authorization");
    // In production, verify cron signature here
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    let alertsGenerated = 0;
    let familiesProcessed = 0;

    // Get all active families with members
    const { data: families } = await supabase
      .from("family_groups")
      .select("*, family_members(id, user_id, role, birth_date)")
      .eq("family_members.status", "active");

    if (!families || families.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          alertsGenerated: 0,
          familiesProcessed: 0,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    for (const family of families) {
      familiesProcessed++;

      // Get parent members
      const parents = (family.family_members as any[]).filter(
        (m) => m.role === "admin" || m.role === "parent",
      );

      if (parents.length === 0) continue;

      // Get child members (under 18)
      const children = (family.family_members as any[]).filter((m) => {
        if (!m.birth_date) return false;
        const age = calculateAge(new Date(m.birth_date));
        return age < 18 && (m.role === "child" || m.role === "teen");
      });

      if (children.length === 0) continue;

      // Batch-load activity summaries for all children in this family
      const sevenDaysAgo = new Date();
      sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
      const today = new Date();
      const childIds = children.map((c) => c.id);

      const { data: allSummaries } = await supabase
        .from("family_activity_summaries")
        .select("*")
        .eq("family_id", family.id)
        .in("member_id", childIds)
        .gte("period_start", sevenDaysAgo.toISOString().split("T")[0])
        .order("period_start", { ascending: true });

      // Group summaries by member_id for O(1) lookups
      const summariesByMember = new Map<string, any[]>();
      for (const s of allSummaries || []) {
        const list = summariesByMember.get(s.member_id) || [];
        list.push(s);
        summariesByMember.set(s.member_id, list);
      }

      // Check each child for alert conditions
      for (const child of children) {
        const summaries = summariesByMember.get(child.id) || [];

        if (!summaries || summaries.length === 0) continue;

        const latestSummary = summaries[summaries.length - 1];

        // Check for inactivity (no sessions in 3+ days)
        if (latestSummary.sessions_completed === 0) {
          const { data: lastMood } = await supabase
            .from("moods")
            .select("created_at")
            .eq("user_id", child.user_id)
            .order("created_at", { ascending: false })
            .limit(1)
            .single();

          if (lastMood) {
            const daysSinceLastActivity = Math.floor(
              (Date.now() - new Date(lastMood.created_at).getTime()) /
                (1000 * 60 * 60 * 24),
            );

            if (daysSinceLastActivity >= 3) {
              // Generate inactivity alert for each parent
              for (const parent of parents) {
                await createAlert(
                  supabase,
                  family.id,
                  child.id,
                  parent.user_id,
                  "inactivity",
                  "info",
                  `${child.nickname || "Your child"} hasn't checked in for ${daysSinceLastActivity} days`,
                  `No activity from ${child.nickname || "your child"} in the last ${daysSinceLastActivity} days. Consider checking in with them about their wellness.`,
                  "check_in",
                  [
                    `Ask how they're feeling today`,
                    `Suggest a family wellness activity together`,
                  ],
                );
                alertsGenerated++;
              }
            }
          }
        }

        // Check for mood concern (declining trend)
        if (latestSummary.mood_trend === "declining" && summaries.length >= 2) {
          // Ensure we're not spamming - check if recent alert exists
          const { data: existingAlert } = await supabase
            .from("family_alerts")
            .select("id")
            .eq("family_id", family.id)
            .eq("about_member_id", child.id)
            .eq("alert_type", "mood_concern")
            .gte(
              "created_at",
              new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
            );

          if (!existingAlert || existingAlert.length === 0) {
            for (const parent of parents) {
              await createAlert(
                supabase,
                family.id,
                child.id,
                parent.user_id,
                "mood_concern",
                "attention",
                `${child.nickname || "Your child"}'s mood seems to be declining`,
                `Recent mood entries suggest that ${child.nickname || "your child"}'s wellness may need attention.`,
                "start_conversation",
                [
                  `I noticed your mood has been lower lately, everything okay?`,
                  `Want to talk about what's on your mind?`,
                  `Let's do a wellness activity together`,
                ],
              );
              alertsGenerated++;
            }
          }
        }

        // Check for achievement milestone
        if (latestSummary.badges_earned > 0) {
          const { data: existingMilestoneAlert } = await supabase
            .from("family_alerts")
            .select("id")
            .eq("family_id", family.id)
            .eq("about_member_id", child.id)
            .eq("alert_type", "milestone")
            .gte("created_at", today.toISOString().split("T")[0]);

          if (!existingMilestoneAlert || existingMilestoneAlert.length === 0) {
            for (const parent of parents) {
              await createAlert(
                supabase,
                family.id,
                child.id,
                parent.user_id,
                "milestone",
                "info",
                `🎉 ${child.nickname || "Your child"} earned ${latestSummary.badges_earned} new badge(s)!`,
                `Way to go! Celebrate this achievement with them.`,
                "celebrate",
                [],
              );
              alertsGenerated++;
            }
          }
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        alertsGenerated,
        familiesProcessed,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error generating family alerts:", error);
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Internal server error",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

// Helper function: Create an alert in the database
async function createAlert(
  supabase: any,
  familyId: string,
  aboutMemberId: string,
  forParentId: string,
  alertType: string,
  severity: string,
  title: string,
  message: string,
  actionType: string | null,
  conversationStarters: string[],
) {
  await supabase.from("family_alerts").insert({
    family_id: familyId,
    about_member_id: aboutMemberId,
    for_parent_id: forParentId,
    alert_type: alertType,
    severity,
    title,
    message,
    action_type: actionType,
    conversation_starters: conversationStarters,
    was_read: false,
    was_acted_upon: false,
    expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
  });
}

// Helper function: Calculate age from birth date
function calculateAge(birthDate: Date): number {
  const today = new Date();
  let age = today.getFullYear() - birthDate.getFullYear();
  const monthDiff = today.getMonth() - birthDate.getMonth();

  if (
    monthDiff < 0 ||
    (monthDiff === 0 && today.getDate() < birthDate.getDate())
  ) {
    age--;
  }

  return age;
}
