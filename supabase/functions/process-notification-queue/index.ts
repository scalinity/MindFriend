// MindFriend Notification Queue Processor
// Processes pending notifications that were queued during quiet hours
// Run via Supabase cron every 15 minutes
// See: specs/04-smart-notifications.md

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";
import {
  buildAPNsPayload,
  getAPNsConfig,
  isAPNsConfigured,
  sendAPNs,
} from "../_shared/apns.ts";
import {
  isInQuietHours,
  type NotificationType,
  RECOVERY_MODE_BLOCKED_TYPES,
  TYPE_TO_SETTING,
} from "../_shared/notification-utils.ts";

Deno.serve(async (req) => {
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
    !(await isAuthorizedCronRequest(
      req.headers,
      expectedCronSecret,
      serviceRoleKey,
    ))
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
          profiles!inner(timezone)
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
      skipped: 0,
      uncertain: 0,
      claimFailures: 0,
    };

    const now = new Date();

    const userIds = [...new Set(pendingNotifications.map((n) => n.user_id))];
    // user_settings references auth.users, not notification_history/profiles;
    // PostgREST cannot embed it through the restored schema's relationships.
    const { data: settings, error: settingsError } = await supabaseAdmin
      .from("user_settings")
      .select(
        "user_id, quiet_hours_start_local, quiet_hours_end_local, recovery_mode_active, notify_circle_activity, notify_hugs, notify_streak_risk, notify_weekly_summary, notify_challenges, reminders_enabled, proactive_enabled",
      )
      .in("user_id", userIds);
    const settingsByUser = new Map((settings || []).map((s) => [s.user_id, s]));
    if (settingsError || userIds.some((id) => !settingsByUser.has(id))) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to fetch notification settings",
        }),
        { status: 500, headers },
      );
    }

    // Batch fetch push tokens for all users
    const { data: allPushTokens, error: tokenError } = await supabaseAdmin
      .from("push_tokens")
      .select("user_id, device_token")
      .in("user_id", userIds)
      .eq("platform", "ios");
    if (tokenError) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to fetch push tokens",
        }),
        { status: 500, headers },
      );
    }

    if (!isAPNsConfigured()) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Push notifications are not configured",
        }),
        { status: 503, headers },
      );
    }

    // Create a map of user_id -> tokens[]
    const tokensByUser = new Map<string, string[]>();
    for (const pt of allPushTokens || []) {
      const tokens = tokensByUser.get(pt.user_id) || [];
      tokens.push(pt.device_token);
      tokensByUser.set(pt.user_id, tokens);
    }

    // Process notifications in parallel (with concurrency limit)
    const CONCURRENCY = 10;
    const notificationUpdates: Array<{
      id: string;
      status: string;
      sent_at: string | null;
      metadata?: Record<string, unknown>;
      scheduled_for?: string | null;
    }> = [];
    const invalidTokens: Array<{ user_id: string; token: string }> = [];

    type NotificationWithJoins = (typeof pendingNotifications)[0] & {
      profiles: { timezone: string };
    };

    const processNotification = async (
      notification: NotificationWithJoins,
    ): Promise<{
      result: "sent" | "failed" | "queued" | "no_token" | "skipped" | "uncertain" | "claim_failed";
    }> => {
      // Use joined data directly (no extra queries!)
      const timezone = notification.profiles?.timezone || "America/Los_Angeles";
      const userSettings = settingsByUser.get(notification.user_id)!;
      const quietStart = userSettings.quiet_hours_start_local || null;
      const quietEnd = userSettings.quiet_hours_end_local || null;
      const type = notification.notification_type as NotificationType;
      const settingColumn = TYPE_TO_SETTING[type];
      const disabled = settingColumn &&
        (userSettings as Record<string, unknown>)[settingColumn] === false;
      const recoveryBlocked = userSettings.recovery_mode_active === true &&
        RECOVERY_MODE_BLOCKED_TYPES.has(type);
      if (disabled || recoveryBlocked) {
        notificationUpdates.push({
          id: notification.id,
          status: "failed",
          sent_at: null,
          metadata: {
            ...notification.metadata,
            skipped_reason: disabled
              ? "notification_type_disabled"
              : "recovery_mode_active",
          },
        });
        return { result: "skipped" };
      }

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

      // Remove retry eligibility before contacting APNs. A lost response or a
      // failed final status write must not cause another provider submission.
      const priorAttempts = Number(notification.metadata?.delivery_attempts || 0);
      const attempt = (Number.isSafeInteger(priorAttempts) && priorAttempts >= 0 ? priorAttempts : 0) + 1;
      const attemptMetadata = {
        ...notification.metadata,
        delivery_attempts: attempt,
        delivery_state: "attempting",
        last_attempt_at: now.toISOString(),
      };
      const { data: claimed, error: claimError } = await supabaseAdmin
        .from("notification_history")
        .update({ scheduled_for: null, metadata: attemptMetadata })
        .eq("id", notification.id)
        .eq("status", "pending")
        .lte("scheduled_for", now.toISOString())
        .select("id")
        .maybeSingle();
      if (claimError) return { result: "claim_failed" };
      if (!claimed) return { result: "skipped" };

      // Send notification; retry only an explicit temporary rejection.
      let sent = false;
      let transient = false;
      let uncertain = false;
      const providerResults: Array<{ apnsId?: string; statusCode?: number; success: boolean; reason?: string }> = [];

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
          providerResults.push({
            apnsId: result.apnsId,
            statusCode: result.statusCode,
            success: result.success,
            reason: result.reason,
          });

          if (result.success) {
            sent = true;
          } else if (result.statusCode === 410) {
            invalidTokens.push({ user_id: notification.user_id, token });
          } else if (result.statusCode === undefined) {
            uncertain = true;
          } else if (result.statusCode === 429 || result.statusCode >= 500) {
            transient = true;
          }
        }
      }

      const retry = !sent && !uncertain && transient && attempt < 4;
      notificationUpdates.push({
        id: notification.id,
        status: sent ? "sent" : (retry || uncertain) ? "pending" : "failed",
        sent_at: sent ? now.toISOString() : null,
        scheduled_for: retry
          ? new Date(now.getTime() + 15 * 60 * 1000 * 2 ** (attempt - 1)).toISOString()
          : null,
        metadata: {
          ...attemptMetadata,
          provider_results: providerResults,
          delivery_state: sent ? "sent" : uncertain ? "uncertain" : retry ? "retry_scheduled" : "failed",
        },
      });

      return { result: sent ? "sent" : uncertain ? "uncertain" : retry ? "queued" : "failed" };
    };

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
            case "skipped":
              results.skipped++;
              break;
            case "uncertain":
              results.uncertain++;
              break;
            case "claim_failed":
              results.claimFailures++;
              break;
          }
        } else {
          console.error("Notification processing error:", res.reason);
          results.failed++;
        }
      }
    }

    // Batch update notification statuses
    let persistenceFailures = 0;
    for (const update of notificationUpdates) {
      const { error: updateError } = await supabaseAdmin
        .from("notification_history")
        .update({
          status: update.status,
          sent_at: update.sent_at,
          ...(update.metadata ? { metadata: update.metadata } : {}),
          ...(update.scheduled_for !== undefined ? { scheduled_for: update.scheduled_for } : {}),
        })
        .eq("id", update.id)
        .select("id")
        .single();
      if (updateError) persistenceFailures++;
    }

    // Batch delete invalid tokens
    for (const { user_id, token } of invalidTokens) {
      await supabaseAdmin
        .from("push_tokens")
        .delete()
        .eq("user_id", user_id)
        .eq("device_token", token);
    }

    if (persistenceFailures || results.claimFailures || results.uncertain) {
      // Claimed rows stay unscheduled if the provider outcome or its persistence
      // is unknown. Preserve their IDs/attempt metadata for reconciliation.
      return new Response(
        JSON.stringify({
          success: false,
          ...results,
          persistenceFailures,
          error: persistenceFailures
            ? "notification_status_persistence_failed"
            : results.claimFailures
            ? "notification_claim_failed"
            : "notification_delivery_uncertain",
        }),
        { status: 500, headers },
      );
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
