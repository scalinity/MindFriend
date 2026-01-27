// Deliver Time Capsules Cron Function
// Runs hourly to deliver due capsules with AI companion letters

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  captureUserSnapshot,
  calculateHighlights,
  formatTimeAgo,
  UserSnapshot,
} from "../_shared/capsule-utils.ts";
import { logError, createErrorResponse } from "../_shared/error-logger.ts";

// TypeScript interfaces for type safety
interface TimeCapsule {
  id: string;
  user_id: string;
  title: string;
  content_encrypted: string;
  content_type: string;
  theme: string;
  created_at: string;
  deliver_at: string;
  delivered_at: string | null;
  opened_at: string | null;
  status: "sealed" | "delivered" | "opened";
  companion_letter: string | null;
  companion_letter_generated_at: string | null;
  word_count: number;
  media_count: number;
  encryption_key_id: string;
  deleted_at: string | null;
  capsule_snapshots?: UserSnapshot[];
}

serve(async (_req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Find capsules due for delivery
    const now = new Date();
    const { data: dueCapsules, error: fetchError } = await supabase
      .from("time_capsules")
      .select("*")
      .eq("status", "sealed")
      .lte("deliver_at", now.toISOString())
      .order("deliver_at", { ascending: true })
      .limit(50);

    if (fetchError) {
      logError(
        {
          function: "deliver-capsules",
          operation: "fetch_due_capsules",
        },
        fetchError,
      );
      return createErrorResponse(fetchError);
    }

    if (!dueCapsules || dueCapsules.length === 0) {
      console.log("No capsules due for delivery");
      return new Response(
        JSON.stringify({ delivered: 0, message: "No capsules due" }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    console.log(`Processing ${dueCapsules.length} capsules for delivery`);

    let successCount = 0;
    let failureCount = 0;

    for (const capsule of dueCapsules) {
      try {
        // Validate user still exists (handle deleted accounts)
        const { data: userExists, error: userCheckError } = await supabase
          .from("profiles")
          .select("id")
          .eq("id", capsule.user_id)
          .single();

        if (userCheckError || !userExists) {
          console.log(
            `Skipping capsule ${capsule.id} - user ${capsule.user_id} no longer exists`,
          );
          // Soft delete the capsule
          await supabase
            .from("time_capsules")
            .update({ deleted_at: new Date().toISOString() })
            .eq("id", capsule.id);
          failureCount++;
          continue;
        }

        // Capture current user snapshot
        const nowSnapshot = await captureUserSnapshot(
          supabase,
          capsule.user_id,
        );

        // Get creation snapshot (handle null case)
        const thenSnapshot = capsule.capsule_snapshots?.[0] || null;

        // Generate companion letter (with comprehensive error handling)
        let companionLetter: string;
        try {
          companionLetter = await generateCompanionLetter(
            supabase,
            capsule,
            thenSnapshot,
            nowSnapshot,
          );
        } catch (letterError) {
          logError(
            {
              function: "deliver-capsules",
              operation: "generate_companion_letter",
              metadata: { capsuleId: capsule.id },
            },
            letterError,
          );
          // Use minimal fallback on total failure
          companionLetter = `Dear friend,\n\nYour time capsule from the past is ready to open. We hope it brings back meaningful memories.\n\nKeep going! 🌱`;
        }

        // Update capsule status
        const { error: updateError } = await supabase
          .from("time_capsules")
          .update({
            status: "delivered",
            delivered_at: new Date().toISOString(),
            companion_letter: companionLetter,
            companion_letter_generated_at: new Date().toISOString(),
          })
          .eq("id", capsule.id);

        if (updateError) {
          logError(
            {
              function: "deliver-capsules",
              operation: "update_capsule_status",
              metadata: { capsuleId: capsule.id },
            },
            updateError,
          );
          failureCount++;
          continue;
        }

        // Send push notification (non-blocking)
        try {
          await sendDeliveryNotification(supabase, capsule);
        } catch (notifError) {
          console.error(
            `Failed to send notification for capsule ${capsule.id}:`,
            notifError,
          );
          // Don't fail delivery if notification fails
        }

        successCount++;
      } catch (error) {
        logError(
          {
            function: "deliver-capsules",
            operation: "process_capsule",
            metadata: { capsuleId: capsule.id },
          },
          error,
        );
        failureCount++;
      }
    }

    console.log(
      `Delivery complete: ${successCount} successful, ${failureCount} failed`,
    );

    return new Response(
      JSON.stringify({
        delivered: successCount,
        failed: failureCount,
        total: dueCapsules.length,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    logError(
      {
        function: "deliver-capsules",
        operation: "cron_execution",
      },
      error,
    );
    return createErrorResponse(error);
  }
});

// Generate AI companion letter with fallback template
async function generateCompanionLetter(
  supabase: SupabaseClient,
  capsule: TimeCapsule,
  thenSnapshot: UserSnapshot | null,
  nowSnapshot: UserSnapshot,
): Promise<string> {
  try {
    // Get user profile for personalization
    const { data: profile } = await supabase
      .from("profiles")
      .select("display_name")
      .eq("id", capsule.user_id)
      .single();

    const displayName = profile?.display_name || "friend";

    // Calculate time difference
    const createdAt = new Date(capsule.created_at);
    const now = new Date();
    const diffMs = now.getTime() - createdAt.getTime();
    const diffDays = Math.floor(diffMs / (24 * 60 * 60 * 1000));
    const diffMonths = Math.floor(diffDays / 30);
    const diffYears = Math.floor(diffDays / 365);

    let timeAgo: string;
    if (diffYears > 0) {
      timeAgo = `${diffYears} year${diffYears > 1 ? "s" : ""} ago`;
    } else if (diffMonths > 0) {
      timeAgo = `${diffMonths} month${diffMonths > 1 ? "s" : ""} ago`;
    } else {
      timeAgo = `${diffDays} day${diffDays > 1 ? "s" : ""} ago`;
    }

    // Calculate journey highlights
    const highlights = calculateHighlights(thenSnapshot, nowSnapshot);

    // Try AI generation
    const xaiApiKey = Deno.env.get("XAI_API_KEY");
    if (xaiApiKey) {
      try {
        const aiLetter = await callGrokAPI(
          xaiApiKey,
          displayName,
          timeAgo,
          capsule.theme,
          thenSnapshot,
          nowSnapshot,
          highlights,
        );

        if (aiLetter) {
          return aiLetter;
        }
      } catch (aiError) {
        console.error("AI letter generation failed, using fallback:", aiError);
      }
    }

    // Fallback template
    return generateFallbackLetter(
      displayName,
      timeAgo,
      thenSnapshot,
      nowSnapshot,
      highlights,
    );
  } catch (error) {
    console.error("Error generating companion letter:", error);
    // Return basic fallback
    return `Dear friend,\n\nYour time capsule from the past is ready to open. We hope it brings back meaningful memories.\n\nKeep going! 🌱`;
  }
}

// Call Grok API for AI letter generation
async function callGrokAPI(
  apiKey: string,
  displayName: string,
  timeAgo: string,
  theme: string,
  thenSnapshot: UserSnapshot | null,
  nowSnapshot: UserSnapshot,
  highlights: string[],
): Promise<string | null> {
  const prompt = `You are a warm, supportive wellness companion writing a heartfelt letter to accompany a time capsule.

Time since creation: ${timeAgo}
Theme: ${theme}
User name: ${displayName}

THEIR JOURNEY SINCE THEN:
- Streak then: ${thenSnapshot?.current_streak || 0} → Now: ${nowSnapshot?.current_streak || 0} days
- Quests completed: +${(nowSnapshot?.total_quests_completed || 0) - (thenSnapshot?.total_quests_completed || 0)}
- Exercises done: +${(nowSnapshot?.total_exercises || 0) - (thenSnapshot?.total_exercises || 0)}
- Level: ${thenSnapshot?.level || 1} → ${nowSnapshot?.level || 1}
- Badges earned: +${(nowSnapshot?.badges_earned || 0) - (thenSnapshot?.badges_earned || 0)}
${thenSnapshot?.average_mood_30d && nowSnapshot?.average_mood_30d ? `- Mood trend: ${thenSnapshot.average_mood_30d.toFixed(1)} → ${nowSnapshot.average_mood_30d.toFixed(1)}` : ""}

KEY HIGHLIGHTS:
${highlights.map((h) => `- ${h}`).join("\n")}

Write a warm, personal letter (200-300 words) that:
1. Acknowledges the journey they've been on
2. Celebrates their growth and progress
3. Reflects on how far they've come
4. Ends with encouragement for their continued journey

Tone: Warm, celebratory, genuine. Avoid being overly effusive.`;

  const response = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "grok-beta",
      messages: [{ role: "user", content: prompt }],
      max_tokens: 500,
      temperature: 0.7,
    }),
  });

  if (!response.ok) {
    throw new Error(`Grok API error: ${response.status}`);
  }

  const data = await response.json();
  return data.choices?.[0]?.message?.content || null;
}

// Generate fallback template letter
function generateFallbackLetter(
  displayName: string,
  timeAgo: string,
  thenSnapshot: UserSnapshot | null,
  nowSnapshot: UserSnapshot,
  highlights: string[],
): string {
  const streakGrowth =
    (nowSnapshot?.current_streak || 0) - (thenSnapshot?.current_streak || 0);
  const questsDiff =
    (nowSnapshot?.total_quests_completed || 0) -
    (thenSnapshot?.total_quests_completed || 0);
  const badgesDiff =
    (nowSnapshot?.badges_earned || 0) - (thenSnapshot?.badges_earned || 0);

  let letter = `Dear ${displayName},\n\n`;
  letter += `${timeAgo}, you created this time capsule for yourself. `;

  if (highlights.length > 0) {
    letter += `Since then:\n`;
    highlights.forEach((highlight) => {
      letter += `- ${highlight}\n`;
    });
  } else {
    letter += `Since then, you've been on quite a journey:\n`;
    if (streakGrowth > 0) {
      letter += `- Your streak grew from ${thenSnapshot?.current_streak || 0} to ${nowSnapshot?.current_streak || 0} days\n`;
    }
    if (questsDiff > 0) {
      letter += `- You completed ${questsDiff} more quests\n`;
    }
    if (badgesDiff > 0) {
      letter += `- You earned ${badgesDiff} new badges\n`;
    }
  }

  letter += `\nKeep going! 🌱`;

  return letter;
}

// Send delivery notification
async function sendDeliveryNotification(
  supabase: SupabaseClient,
  capsule: TimeCapsule,
): Promise<void> {
  try {
    await supabase.functions.invoke("send-notification", {
      body: {
        userId: capsule.user_id,
        title: "💌 Time Capsule Ready",
        body: capsule.title
          ? `Your capsule "${capsule.title}" is ready to open!`
          : "A message from your past self awaits...",
        data: {
          type: "capsule_ready",
          capsuleId: capsule.id,
        },
      },
    });
  } catch (error) {
    console.error(
      `Failed to send notification for capsule ${capsule.id}:`,
      error,
    );
    // Don't fail delivery if notification fails
  }
}
