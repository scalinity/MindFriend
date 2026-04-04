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
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";
import {
  calculateUserAbsenceBatch,
  checkRecentNotificationsBatch,
  type BatchRecentNotificationCheck,
} from "../_shared/batch-utils.ts";
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

// Validate UUID format to prevent injection attacks
function isValidUUID(uuid: string): boolean {
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(uuid);
}

// Validate array of UUIDs
function validateUserIds(userIds: string[]): boolean {
  return userIds.every(isValidUUID);
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
    // Verify this is a cron job call (require cron secret or service role key)
    const expectedCronSecret = Deno.env.get("CRON_SECRET") || "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

    if (
      !(await isAuthorizedCronRequest(req.headers, expectedCronSecret, serviceRoleKey))
    ) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers,
      });
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

    // Helper to safely log user identifiers without exposing full UUIDs
    const sanitizeUserId = (id: string) => id.substring(0, 8) + "...";

    // Pre-fetch all data in batch queries
    const userIds = users.map((u) => u.user_id);

    // Validate all user IDs to prevent injection attacks
    if (!validateUserIds(userIds)) {
      console.error("Invalid user IDs detected in batch processing");
      return new Response(
        JSON.stringify({ error: "Invalid user ID format detected" }),
        { status: 400, headers },
      );
    }

    // Batch 1: Get absence metrics for all users
    const absenceMetricsMap = await calculateUserAbsenceBatch(
      supabaseAdmin,
      userIds,
    );

    // Batch 2: Check recent notifications for all users
    const recentNotificationChecks: BatchRecentNotificationCheck[] = users
      .map((u) => {
        const notifType = getNotificationType(u.days_absent);
        return {
          user_id: u.user_id,
          notification_type: notifType || "unknown",
        };
      })
      .filter((c) => c.notification_type !== "unknown");

    const recentNotificationsMap =
      recentNotificationChecks.length > 0
        ? await checkRecentNotificationsBatch(
            supabaseAdmin,
            recentNotificationChecks,
          )
        : new Map();

    // Track results
    const results = {
      total: users.length,
      sent: 0,
      skipped: 0,
      failed: 0,
      details: [] as Array<{
        userIdHash: string;
        daysAbsent: number;
        notificationType: string | null;
        status: string;
        reason?: string;
      }>,
    };

    // Collect reengagement events for batch insert
    const reengagementEvents: Array<{
      user_id: string;
      event_type: string;
      absence_days: number;
      metadata: Record<string, unknown>;
    }> = [];

    // Process each lapsed user (all data now pre-fetched)
    const sendPromises: Promise<void>[] = [];
    for (const user of users) {
      const notificationType = getNotificationType(user.days_absent);

      if (!notificationType) {
        results.skipped++;
        results.details.push({
          userIdHash: sanitizeUserId(user.user_id),
          daysAbsent: user.days_absent,
          notificationType: null,
          status: "skipped",
          reason: "no_matching_notification_type",
        });
        continue;
      }

      // Check if we've already sent this type of notification recently
      const recentKey = `${user.user_id}:${notificationType}`;
      const wasRecentlySent = recentNotificationsMap.get(recentKey);

      if (wasRecentlySent?.recently_sent) {
        results.skipped++;
        results.details.push({
          userIdHash: sanitizeUserId(user.user_id),
          daysAbsent: user.days_absent,
          notificationType,
          status: "skipped",
          reason: "already_notified_today",
        });
        continue;
      }

      // Get absence metrics (already pre-fetched)
      const absenceData = absenceMetricsMap.get(user.user_id);
      const hugsReceived = absenceData?.hugs_received || 0;
      const circlePosts = absenceData?.circle_posts || 0;

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

      const sendPromise = fetch(
        `${Deno.env.get("SUPABASE_URL")}/functions/v1/send-notification`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
          },
          body: JSON.stringify(notificationPayload),
        },
      )
        .then((response) => response.json())
        .then((notificationResult) => {
          if (notificationResult.success && !notificationResult.skipped) {
            results.sent++;
            results.details.push({
              userIdHash: sanitizeUserId(user.user_id),
              daysAbsent: user.days_absent,
              notificationType,
              status: "sent",
            });

            // Collect reengagement event for batch insert
            reengagementEvents.push({
              user_id: user.user_id,
              event_type: "notification_sent",
              absence_days: user.days_absent,
              metadata: { notification_type: notificationType },
            });
          } else if (notificationResult.skipped) {
            results.skipped++;
            results.details.push({
              userIdHash: sanitizeUserId(user.user_id),
              daysAbsent: user.days_absent,
              notificationType,
              status: "skipped",
              reason: notificationResult.reason,
            });
          } else {
            results.failed++;
            results.details.push({
              userIdHash: sanitizeUserId(user.user_id),
              daysAbsent: user.days_absent,
              notificationType,
              status: "failed",
              reason: notificationResult.error,
            });
          }
        })
        .catch((sendError) => {
          console.error(
            `Failed to send notification to user ${sanitizeUserId(user.user_id)}:`,
            sendError,
          );
          results.failed++;
          results.details.push({
            userIdHash: sanitizeUserId(user.user_id),
            daysAbsent: user.days_absent,
            notificationType,
            status: "failed",
            reason: String(sendError),
          });
        });

      sendPromises.push(sendPromise);
    }

    // Wait for all send promises to resolve
    await Promise.allSettled(sendPromises);

    // Batch insert all reengagement events
    if (reengagementEvents.length > 0) {
      console.log(
        `Batch inserting ${reengagementEvents.length} reengagement events`,
      );
      const { error: insertError } = await supabaseAdmin
        .from("reengagement_events")
        .insert(reengagementEvents);

      if (insertError) {
        console.error(
          "Error batch inserting reengagement events:",
          insertError,
        );
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
