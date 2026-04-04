// MindFriend Notification Queue Processor
// Processes pending notifications that were queued during quiet hours
// Run via Supabase cron every 15 minutes
// See: specs/04-smart-notifications.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";
import {
  sendAPNs,
  buildAPNsPayload,
  isAPNsConfigured,
  getAPNsConfig,
} from "../_shared/apns.ts";
import { isInQuietHours } from "../_shared/notification-utils.ts";

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const headers = {
    ...corsHeaders,
    "Content-Type": "application/json",
  };

  // Require cron secret or service role key
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

  try {
    // Initialize Supabase client with service role
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get pending notifications with all needed data in a single query (JOIN optimization)
    const { data: pendingNotifications, error: fetchError } =
      await supabaseAdmin
        .from("notification_history")
        .select(
          `
          id,
          user_id,
          notification_type,
          title,
          body,
          deep_link,
          metadata,
          profiles!inner(timezone),
          user_settings!inner(quiet_hours_start_local, quiet_hours_end_local)
        `,
        )
        .eq("status", "pending")
        .lte("scheduled_for", new Date().toISOString())
        .limit(100);

    if (fetchError) {
      console.error("Error fetching pending notifications:", fetchError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch pending notifications" }),
        { status: 500, headers },
      );
    }

    if (!pendingNotifications || pendingNotifications.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          processed: 0,
          message: "No pending notifications",
        }),
        { status: 200, headers },
      );
    }

    console.log(
      `Processing ${pendingNotifications.length} pending notifications`,
    );

    const results = {
      processed: 0,
      sent: 0,
      stillQueued: 0,
      failed: 0,
      noToken: 0,
    };

    const now = new Date();

    // Batch fetch push tokens for all users
    const userIds = [...new Set(pendingNotifications.map((n) => n.user_id))];
    const { data: allPushTokens } = await supabaseAdmin
      .from("push_tokens")
      .select("user_id, token")
      .in("user_id", userIds)
      .eq("platform", "ios");

    // Create a map of user_id -> tokens[]
    const tokensByUser = new Map<string, string[]>();
    for (const pt of allPushTokens || []) {
      const tokens = tokensByUser.get(pt.user_id) || [];
      tokens.push(pt.token);
      tokensByUser.set(pt.user_id, tokens);
    }

    // Process notifications in parallel (with concurrency limit)
    const CONCURRENCY = 10;
    const notificationUpdates: Array<{
      id: string;
      status: string;
      sent_at: string | null;
    }> = [];
    const invalidTokens: Array<{ user_id: string; token: string }> = [];

    // deno-lint-ignore no-explicit-any
    type NotificationWithJoins = (typeof pendingNotifications)[0] & {
      profiles: { timezone: string };
      user_settings: {
        quiet_hours_start_local: string | null;
        quiet_hours_end_local: string | null;
      };
    };

    async function processNotification(
      notification: NotificationWithJoins,
    ): Promise<{
      result: "sent" | "failed" | "queued" | "no_token";
      invalidToken?: { user_id: string; token: string };
    }> {
      // Use joined data directly (no extra queries!)
      const timezone = notification.profiles?.timezone || "America/Los_Angeles";
      const quietStart =
        notification.user_settings?.quiet_hours_start_local || null;
      const quietEnd =
        notification.user_settings?.quiet_hours_end_local || null;

      // Get current hour in user's timezone
      const formatter = new Intl.DateTimeFormat("en-US", {
        timeZone: timezone,
        hour: "numeric",
        hour12: false,
      });
      const currentHour = parseInt(formatter.format(now), 10);

      // If still in quiet hours, skip
      if (isInQuietHours(currentHour, quietStart, quietEnd)) {
        return { result: "queued" };
      }

      // Get push tokens from pre-fetched map
      const tokens = tokensByUser.get(notification.user_id) || [];

      if (tokens.length === 0) {
        notificationUpdates.push({
          id: notification.id,
          status: "failed",
          sent_at: null,
        });
        return { result: "no_token" };
      }

      // Send notification
      let sent = false;

      if (isAPNsConfigured()) {
        const config = getAPNsConfig()!;
        const payload = buildAPNsPayload(
          notification.id,
          notification.notification_type,
          notification.title,
          notification.body,
          notification.deep_link || "mindfriend://",
          notification.metadata || {},
        );

        for (const token of tokens) {
          const result = await sendAPNs(token, payload, {
            bundleId: config.bundleId,
            keyId: config.keyId,
            teamId: config.teamId,
            privateKey: config.privateKey,
            production: config.production,
          });

          if (result.success) {
            sent = true;
          } else if (result.statusCode === 410) {
            invalidTokens.push({ user_id: notification.user_id, token });
          }
        }
      } else {
        // Mock mode
        console.log("[MOCK QUEUE SEND]", notification.id);
        sent = true;
      }

      notificationUpdates.push({
        id: notification.id,
        status: sent ? "sent" : "failed",
        sent_at: sent ? now.toISOString() : null,
      });

      return { result: sent ? "sent" : "failed" };
    }

    // Process in batches with concurrency limit
    for (let i = 0; i < pendingNotifications.length; i += CONCURRENCY) {
      const batch = pendingNotifications.slice(i, i + CONCURRENCY);
      const batchResults = await Promise.allSettled(
        batch.map((n) => processNotification(n as NotificationWithJoins)),
      );

      for (const res of batchResults) {
        results.processed++;
        if (res.status === "fulfilled") {
          switch (res.value.result) {
            case "sent":
              results.sent++;
              break;
            case "failed":
              results.failed++;
              break;
            case "queued":
              results.stillQueued++;
              break;
            case "no_token":
              results.noToken++;
              break;
          }
        } else {
          console.error("Notification processing error:", res.reason);
          results.failed++;
        }
      }
    }

    // Batch update notification statuses
    for (const update of notificationUpdates) {
      await supabaseAdmin
        .from("notification_history")
        .update({ status: update.status, sent_at: update.sent_at })
        .eq("id", update.id);
    }

    // Batch delete invalid tokens
    for (const { user_id, token } of invalidTokens) {
      await supabaseAdmin
        .from("push_tokens")
        .delete()
        .eq("user_id", user_id)
        .eq("token", token);
    }

    console.log("Queue processing complete:", results);

    return new Response(
      JSON.stringify({
        success: true,
        ...results,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("Queue processor error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
