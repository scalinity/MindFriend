// MindFriend Check Lapsed Users Edge Function
// Daily cron job to send re-engagement notifications to lapsed users
// See: specs/11-reengagement-flows.md
//
// Schedule: Daily at 6 PM local time (handled by cron config)
// Notification tiers:
// - Day 3: Gentle check-in
// - Day 7: Social hook (shows activity they've missed)
// - Day 14: Progress preserved message
// - Day 30: Fresh start offer

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import type { NotificationType } from "../_shared/notification-utils.ts";

interface LapsedUser {
  user_id: string;
  display_name: string | null;
  last_session_at: string | null;
  days_absent: number;
  notification_type: string | null;
}

// Map days absent to notification type
function getNotificationType(daysAbsent: number): NotificationType | null {
  switch (daysAbsent) {
    case 3:
      return "reengagement_gentle";
    case 7:
      return "reengagement_social";
    case 14:
      return "reengagement_progress";
    case 30:
      return "reengagement_fresh_start";
    default:
      return null;
  }
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const headers = {
    ...getCorsHeaders(origin),
    "Content-Type": "application/json",
  };

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders(origin) });
  }

  try {
    // Verify this is a cron job call (Authorization header with service role key)
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers,
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

    // Constant-time comparison to prevent timing attacks
    const tokenBytes = new TextEncoder().encode(token);
    const keyBytes = new TextEncoder().encode(serviceRoleKey);

    let isServiceRole = tokenBytes.length === keyBytes.length;
    if (isServiceRole) {
      let diff = 0;
      for (let i = 0; i < tokenBytes.length; i++) {
        diff |= tokenBytes[i] ^ keyBytes[i];
      }
      isServiceRole = diff === 0;
    }

    if (!isServiceRole) {
      return new Response(
        JSON.stringify({ error: "This endpoint requires service role access" }),
        { status: 403, headers },
      );
    }

    // Initialize Supabase admin client
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get lapsed users from the database function
    const { data: lapsedUsers, error: queryError } = await supabaseAdmin.rpc(
      "get_lapsed_users_for_notification",
    );

    if (queryError) {
      console.error("Error fetching lapsed users:", queryError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch lapsed users" }),
        { status: 500, headers },
      );
    }

    const users = (lapsedUsers || []) as LapsedUser[];
    console.log(`Found ${users.length} lapsed users to notify`);

    // Track results
    const results = {
      total: users.length,
      sent: 0,
      skipped: 0,
      failed: 0,
      details: [] as Array<{
        userId: string;
        daysAbsent: number;
        notificationType: string | null;
        status: string;
        reason?: string;
      }>,
    };

    // Process each lapsed user
    for (const user of users) {
      const notificationType = getNotificationType(user.days_absent);

      if (!notificationType) {
        results.skipped++;
        results.details.push({
          userId: user.user_id,
          daysAbsent: user.days_absent,
          notificationType: null,
          status: "skipped",
          reason: "no_matching_notification_type",
        });
        continue;
      }

      // Get additional data for social hook notification
      let hugsReceived = 0;
      let circlePosts = 0;

      if (notificationType === "reengagement_social") {
        // Fetch hugs and circle posts count for this user
        const { data: absenceData } = await supabaseAdmin.rpc(
          "calculate_user_absence",
          { p_user_id: user.user_id },
        );

        if (absenceData && absenceData.length > 0) {
          hugsReceived = absenceData[0].hugs_received || 0;
          circlePosts = absenceData[0].circle_posts || 0;
        }
      }

      // Check if we've already sent this type of notification recently
      const { data: recentNotification } = await supabaseAdmin
        .from("notification_history")
        .select("id")
        .eq("user_id", user.user_id)
        .eq("notification_type", notificationType)
        .gte(
          "created_at",
          new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
        )
        .single();

      if (recentNotification) {
        results.skipped++;
        results.details.push({
          userId: user.user_id,
          daysAbsent: user.days_absent,
          notificationType,
          status: "skipped",
          reason: "already_notified_today",
        });
        continue;
      }

      // Send the notification via send-notification function
      const notificationPayload = {
        type: notificationType,
        recipientId: user.user_id,
        data: {
          displayName: user.display_name || "friend",
          absenceDays: user.days_absent,
          hugsReceived,
          circlePosts,
        },
      };

      try {
        const notificationResponse = await fetch(
          `${Deno.env.get("SUPABASE_URL")}/functions/v1/send-notification`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
            },
            body: JSON.stringify(notificationPayload),
          },
        );

        const notificationResult = await notificationResponse.json();

        if (notificationResult.success && !notificationResult.skipped) {
          results.sent++;
          results.details.push({
            userId: user.user_id,
            daysAbsent: user.days_absent,
            notificationType,
            status: "sent",
          });

          // Log re-engagement event
          await supabaseAdmin.from("reengagement_events").insert({
            user_id: user.user_id,
            event_type: "notification_sent",
            absence_days: user.days_absent,
            metadata: { notification_type: notificationType },
          });
        } else if (notificationResult.skipped) {
          results.skipped++;
          results.details.push({
            userId: user.user_id,
            daysAbsent: user.days_absent,
            notificationType,
            status: "skipped",
            reason: notificationResult.reason,
          });
        } else {
          results.failed++;
          results.details.push({
            userId: user.user_id,
            daysAbsent: user.days_absent,
            notificationType,
            status: "failed",
            reason: notificationResult.error,
          });
        }
      } catch (sendError) {
        console.error(
          `Failed to send notification to user ${user.user_id}:`,
          sendError,
        );
        results.failed++;
        results.details.push({
          userId: user.user_id,
          daysAbsent: user.days_absent,
          notificationType,
          status: "failed",
          reason: String(sendError),
        });
      }
    }

    console.log(
      `Re-engagement notifications complete: ${results.sent} sent, ${results.skipped} skipped, ${results.failed} failed`,
    );

    return new Response(JSON.stringify({ success: true, results }), {
      status: 200,
      headers,
    });
  } catch (error) {
    console.error("Check lapsed users error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
