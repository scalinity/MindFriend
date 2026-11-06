// MindFriend Smart Notification Edge Function
// Handles push notifications with preferences, quiet hours, and history tracking
// See: specs/04-smart-notifications.md

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";
import { isAuthorizedCronRequest } from "../_shared/auth.ts";
import {
  buildAPNsPayload,
  getAPNsConfig,
  isAPNsConfigured,
  sendAPNs,
} from "../_shared/apns.ts";
import {
  buildNotificationContent,
  isInQuietHours,
  type NotificationType,
  RECOVERY_MODE_BLOCKED_TYPES,
  TYPE_TO_SETTING,
} from "../_shared/notification-utils.ts";

// Rate limiting configuration
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const RATE_LIMIT_MAX_PER_USER = 100; // Max notifications per user per hour
const RATE_LIMIT_MAX_PER_SENDER = 50; // Max notifications a sender can trigger per hour

interface NotificationRequest {
  type: NotificationType;
  recipientId: string;
  data: {
    // Common fields
    senderId?: string;
    senderName?: string;
    circleId?: string;
    circleName?: string;
    // Streak-specific
    streak?: number;
    urgency?: number; // 0 = encouraging, 1 = warning
    // Weekly summary-specific
    checkins?: number;
    quests?: number;
    moodMessage?: string;
    // Challenge-specific
    completedCount?: number;
    totalMembers?: number;
    challengeTitle?: string;
    sessionId?: string;
  };
}

// Check rate limit for a recipient or sender
async function checkRateLimit(
  supabase: SupabaseClient,
  userId: string,
  type: "recipient" | "sender",
): Promise<{ allowed: boolean; count: number; limit: number }> {
  const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MS).toISOString();
  const limit = type === "recipient"
    ? RATE_LIMIT_MAX_PER_USER
    : RATE_LIMIT_MAX_PER_SENDER;

  // For recipients, count notifications received
  // For senders, count notifications triggered (via metadata.senderId)
  let query = supabase
    .from("notification_history")
    .select("*", { count: "exact", head: true })
    .gte("created_at", windowStart);

  if (type === "recipient") {
    query = query.eq("user_id", userId);
  } else {
    // Count notifications where this user was the sender
    query = query.filter("metadata->>senderId", "eq", userId);
  }

  const { count } = await query;
  const currentCount = count ?? 0;

  return {
    allowed: currentCount < limit,
    count: currentCount,
    limit,
  };
}

// Calculate when quiet hours end (for scheduling)
// Returns a UTC timestamp for when the user's quiet hours end in their timezone
function getQuietHoursEndTime(
  now: Date,
  timezone: string,
  quietEnd: string,
): Date {
  const endHour = parseInt(quietEnd.split(":")[0], 10);
  const endMinute = parseInt(quietEnd.split(":")[1] || "0", 10);

  // Get current time components in user's timezone
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });

  const parts = formatter.formatToParts(now);
  const getPart = (type: string) =>
    parts.find((p) => p.type === type)?.value || "0";

  const currentYear = parseInt(getPart("year"), 10);
  const currentMonth = parseInt(getPart("month"), 10);
  const currentDay = parseInt(getPart("day"), 10);
  const currentHour = parseInt(getPart("hour"), 10);

  // Determine target date - today or tomorrow based on current hour
  let targetDay = currentDay;
  let targetMonth = currentMonth;
  let targetYear = currentYear;

  if (currentHour >= endHour) {
    // Past quiet hours end time, schedule for tomorrow
    const tomorrow = new Date(currentYear, currentMonth - 1, currentDay + 1);
    targetDay = tomorrow.getDate();
    targetMonth = tomorrow.getMonth() + 1;
    targetYear = tomorrow.getFullYear();
  }

  // Create a date string in the user's timezone, then parse it
  // Format: "YYYY-MM-DDTHH:MM:SS" in the user's timezone
  const targetDateStr = `${targetYear}-${
    String(targetMonth).padStart(2, "0")
  }-${String(targetDay).padStart(2, "0")}T${String(endHour).padStart(2, "0")}:${
    String(endMinute).padStart(2, "0")
  }:00`;

  // Use Intl to get the UTC offset for this timezone at this time
  // Then calculate the UTC equivalent
  const utcFormatter = new Intl.DateTimeFormat("en-US", {
    timeZone: "UTC",
    hour: "2-digit",
    hour12: false,
  });
  const tzFormatter = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    hour: "2-digit",
    hour12: false,
  });

  // Find the offset by comparing what hour it is in UTC vs the target timezone
  // at a known time, then apply that offset
  const utcHour = parseInt(utcFormatter.format(now), 10);
  const tzHour = parseInt(tzFormatter.format(now), 10);
  let offsetHours = tzHour - utcHour;

  // Handle day boundary wrap-around
  if (offsetHours > 12) offsetHours -= 24;
  if (offsetHours < -12) offsetHours += 24;

  // Calculate the UTC time by subtracting the offset
  const utcTime = new Date(targetDateStr);
  utcTime.setHours(endHour - offsetHours, endMinute, 0, 0);

  return utcTime;
}

Deno.serve(async (req) => {
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
    // Initialize Supabase client with service role
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // This function can be called by other Edge Functions (service role)
    // or by authenticated users (for certain types like circle activity)
    const authHeader = req.headers.get("Authorization");
    let callerId: string | null = null;

    if (authHeader?.startsWith("Bearer ")) {
      const token = authHeader.slice(7);
      if (
        await isAuthorizedCronRequest(
          req.headers,
          "",
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "",
        )
      ) {
        callerId = "service_role";
      } else if (token) {
        const { data: { user }, error } = await supabaseAdmin.auth.getUser(
          token,
        );
        if (!error && user) callerId = user.id;
      }
    }

    // SECURITY FIX #001: Enforce authentication - reject unauthenticated calls
    if (!callerId) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers,
      });
    }

    // Parse request body
    const body: NotificationRequest = await req.json();

    // Default data to empty object if not provided
    if (!body.data) body.data = {};
    if (typeof body.data !== "object" || Array.isArray(body.data)) {
      return new Response(
        JSON.stringify({ error: "Invalid notification data" }),
        {
          status: 400,
          headers,
        },
      );
    }

    if (
      !body.type || typeof body.recipientId !== "string" || !body.recipientId
    ) {
      return new Response(
        JSON.stringify({ error: "Missing type or recipientId" }),
        { status: 400, headers },
      );
    }

    // Swift UUID.uuidString is uppercase; PostgreSQL returns lowercase UUIDs.
    body.recipientId = body.recipientId.toLowerCase();

    // Validate notification type
    const validTypes: NotificationType[] = Object.keys(
      TYPE_TO_SETTING,
    ) as NotificationType[];
    if (!validTypes.includes(body.type)) {
      return new Response(
        JSON.stringify({ error: "Invalid notification type" }),
        { status: 400, headers },
      );
    }

    // SECURITY FIX #001: Restrict user-initiated notifications to safe types
    // Circle-scoped types require circleId and membership validation
    const CIRCLE_SCOPED_USER_TYPES: NotificationType[] = [
      "circle_activity",
      "hug",
      "challenge",
    ];
    // Direct types require their persisted buddy or couples context below.
    const DIRECT_USER_TYPES: NotificationType[] = [
      "buddy_encouragement",
      "couples_exercise_invite",
    ];
    const USER_ALLOWED_TYPES: NotificationType[] = [
      ...CIRCLE_SCOPED_USER_TYPES,
      ...DIRECT_USER_TYPES,
    ];
    if (
      callerId !== "service_role" &&
      !USER_ALLOWED_TYPES.includes(body.type)
    ) {
      return new Response(
        JSON.stringify({ error: "Forbidden notification type" }),
        { status: 403, headers },
      );
    }

    // SECURITY FIX #001: Force senderId to authenticated caller (prevent spoofing)
    if (callerId !== "service_role") {
      body.data.senderId = callerId;
    }

    // SECURITY FIX #001: Validate circle membership for circle-scoped notifications
    if (
      callerId !== "service_role" &&
      CIRCLE_SCOPED_USER_TYPES.includes(body.type)
    ) {
      const circleId = body.data.circleId;
      if (!circleId) {
        return new Response(
          JSON.stringify({ error: "Missing circleId for circle notification" }),
          { status: 400, headers },
        );
      }

      // Verify BOTH sender and recipient are members of the circle
      const { data: members, error: membersError } = await supabaseAdmin
        .from("circle_members")
        .select("user_id")
        .eq("circle_id", circleId)
        .in("user_id", [callerId, body.recipientId]);

      const memberSet = new Set((members || []).map((m) => m.user_id));
      if (
        membersError || !memberSet.has(callerId) ||
        !memberSet.has(body.recipientId)
      ) {
        return new Response(
          JSON.stringify({ error: "Not authorized for this circle" }),
          { status: 403, headers },
        );
      }
    }

    if (callerId !== "service_role" && body.type === "buddy_encouragement") {
      // iOS persists encouragement before requesting a push. Require both the
      // accepted relationship and the message addressed to this exact recipient.
      const { data: relationships, error: relationshipError } =
        await supabaseAdmin
          .from("buddy_relationships")
          .select("id")
          .eq("status", "accepted")
          .in("inviter_id", [callerId, body.recipientId])
          .in("invitee_id", [callerId, body.recipientId]);
      const relationshipIds = (relationships || []).map((row) => row.id);
      let authorized = false;
      if (
        !relationshipError && callerId !== body.recipientId &&
        relationshipIds.length
      ) {
        const { data: messages, error: messageError } = await supabaseAdmin
          .from("buddy_encouragements")
          .select("id")
          .eq("sender_id", callerId)
          .eq("recipient_id", body.recipientId)
          .in("buddy_relationship_id", relationshipIds)
          .limit(1);
        authorized = !messageError && !!messages?.length;
      }
      if (!authorized) {
        return new Response(
          JSON.stringify({ error: "Not authorized for this buddy" }),
          {
            status: 403,
            headers,
          },
        );
      }
    }

    if (
      callerId !== "service_role" && body.type === "couples_exercise_invite"
    ) {
      const { data: session, error: sessionError } = await supabaseAdmin
        .from("couples_exercise_sessions")
        .select("partner_link_id, user_id_1, user_id_2")
        .eq("id", body.data.sessionId || "")
        .eq("status", "pending")
        .maybeSingle();
      const isPair = (row: { user_id_1: string; user_id_2: string | null }) =>
        callerId !== body.recipientId && (
          (row.user_id_1 === callerId && row.user_id_2 === body.recipientId) ||
          (row.user_id_2 === callerId && row.user_id_1 === body.recipientId)
        );
      let authorized = false;
      if (!sessionError && session && isPair(session)) {
        const { data: link, error: linkError } = await supabaseAdmin
          .from("partner_links")
          .select("user_id_1, user_id_2")
          .eq("id", session.partner_link_id)
          .eq("status", "active")
          .maybeSingle();
        authorized = !linkError && !!link && isPair(link);
      }
      if (!authorized) {
        return new Response(
          JSON.stringify({
            error: "Not authorized for this exercise invitation",
          }),
          {
            status: 403,
            headers,
          },
        );
      }
    }

    // Check rate limit for recipient (skip for service role calls like cron jobs)
    if (callerId !== "service_role") {
      const recipientRateLimit = await checkRateLimit(
        supabaseAdmin,
        body.recipientId,
        "recipient",
      );
      if (!recipientRateLimit.allowed) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "rate_limit_exceeded",
            reason: "recipient_limit",
            count: recipientRateLimit.count,
            limit: recipientRateLimit.limit,
          }),
          { status: 429, headers },
        );
      }

      // Check rate limit for sender if provided
      if (body.data.senderId) {
        const senderRateLimit = await checkRateLimit(
          supabaseAdmin,
          body.data.senderId,
          "sender",
        );
        if (!senderRateLimit.allowed) {
          return new Response(
            JSON.stringify({
              success: false,
              error: "rate_limit_exceeded",
              reason: "sender_limit",
              count: senderRateLimit.count,
              limit: senderRateLimit.limit,
            }),
            { status: 429, headers },
          );
        }
      }
    }

    // Get user's notification preferences and profile
    const { data: settings, error: settingsError } = await supabaseAdmin
      .from("user_settings")
      .select("*")
      .eq("user_id", body.recipientId)
      .single();

    if (settingsError || !settings) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "notification_settings_unavailable",
        }),
        { status: 503, headers },
      );
    }

    const { data: profile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .select("timezone, display_name")
      .eq("id", body.recipientId)
      .single();

    if (profileError || !profile) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "notification_profile_unavailable",
        }),
        { status: 503, headers },
      );
    }

    // Check if this notification type is enabled
    const settingColumn = TYPE_TO_SETTING[body.type];
    if (settings && settings[settingColumn] === false) {
      return new Response(
        JSON.stringify({
          success: true,
          skipped: true,
          reason: "notification_type_disabled",
        }),
        { status: 200, headers },
      );
    }

    // Apply the current recovery preference before delivery.
    if (
      settings?.recovery_mode_active === true &&
      RECOVERY_MODE_BLOCKED_TYPES.has(body.type)
    ) {
      console.log(
        `[Recovery Mode] Blocking ${body.type} notification for user ${body.recipientId}`,
      );
      return new Response(
        JSON.stringify({
          success: true,
          skipped: true,
          reason: "recovery_mode_active",
          blockedType: body.type,
        }),
        { status: 200, headers },
      );
    }

    // Check quiet hours
    const timezone = profile?.timezone || "America/Los_Angeles";
    const now = new Date();

    // Get current hour in user's timezone
    const formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      hour: "numeric",
      hour12: false,
    });
    const currentHour = parseInt(formatter.format(now), 10);

    const quietStart = settings?.quiet_hours_start_local || null;
    const quietEnd = settings?.quiet_hours_end_local || null;

    if (isInQuietHours(currentHour, quietStart, quietEnd)) {
      // Queue the notification for later
      const scheduledFor = getQuietHoursEndTime(now, timezone, quietEnd!);
      const content = buildNotificationContent(body.type, body.data);
      const notificationId = crypto.randomUUID();

      // Insert as pending notification
      const { error: historyError } = await supabaseAdmin.from(
        "notification_history",
      ).insert({
        id: notificationId,
        user_id: body.recipientId,
        notification_type: body.type,
        title: content.title,
        body: content.body,
        deep_link: content.deepLink,
        metadata: body.data,
        status: "pending",
        scheduled_for: scheduledFor.toISOString(),
      });

      if (historyError) {
        return new Response(
          JSON.stringify({
            success: false,
            queued: false,
            error: "notification_history_persistence_failed",
          }),
          { status: 500, headers },
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          queued: true,
          reason: "quiet_hours",
          scheduledFor: scheduledFor.toISOString(),
          id: notificationId,
        }),
        { status: 200, headers },
      );
    }

    // Get push token
    const { data: pushTokens, error: tokenError } = await supabaseAdmin
      .from("push_tokens")
      .select("device_token")
      .eq("user_id", body.recipientId)
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

    if (!pushTokens || pushTokens.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          skipped: true,
          reason: "no_push_token",
        }),
        { status: 200, headers },
      );
    }

    // Build notification content
    const content = buildNotificationContent(body.type, body.data);
    const notificationId = crypto.randomUUID();

    if (!isAPNsConfigured()) {
      return new Response(
        JSON.stringify({
          success: false,
          sent: false,
          error: "Push notifications are not configured",
        }),
        { status: 503, headers },
      );
    }

    // Persist before sending: a rejected history row must never produce a push.
    // No scheduled_for means this immediate attempt is not picked up by the queue.
    const { error: historyError } = await supabaseAdmin.from(
      "notification_history",
    ).insert({
      id: notificationId,
      user_id: body.recipientId,
      notification_type: body.type,
      title: content.title,
      body: content.body,
      deep_link: content.deepLink,
      metadata: body.data,
      status: "pending",
    });
    if (historyError) {
      return new Response(
        JSON.stringify({
          success: false,
          sent: false,
          error: "notification_history_persistence_failed",
        }),
        { status: 500, headers },
      );
    }

    // Try to send via APNs
    let sent = false;
    let apnsResult: Awaited<ReturnType<typeof sendAPNs>> | null = null;

    if (isAPNsConfigured()) {
      const config = getAPNsConfig()!;
      const payload = buildAPNsPayload(
        notificationId,
        body.type,
        content.title,
        content.body,
        content.deepLink,
        body.data,
      );

      // Send to all registered tokens
      for (const { device_token } of pushTokens) {
        apnsResult = await sendAPNs(device_token, payload, {
          bundleId: config.bundleId,
          keyId: config.keyId,
          teamId: config.teamId,
          privateKey: config.privateKey,
          production: config.production,
        });

        if (apnsResult.success) {
          sent = true;
        } else if (apnsResult.statusCode === 410) {
          // Token is invalid - remove it
          await supabaseAdmin
            .from("push_tokens")
            .delete()
            .eq("user_id", body.recipientId)
            .eq("device_token", device_token);
          console.log("Removed invalid push token for user:", body.recipientId);
        }
      }
    }

    const { error: statusError } = await supabaseAdmin.from(
      "notification_history",
    )
      .update({
        status: sent ? "sent" : "failed",
        sent_at: sent ? now.toISOString() : null,
      })
      .eq("id", notificationId)
      .select("id")
      .single();
    if (statusError) {
      // APNs may already have accepted this push. Retrying can send a duplicate;
      // this request has no caller-provided durable idempotency key.
      return new Response(
        JSON.stringify({
          success: false,
          sent,
          id: notificationId,
          error: "notification_status_persistence_failed",
        }),
        { status: 500, headers },
      );
    }

    return new Response(
      JSON.stringify({
        success: sent,
        sent,
        id: notificationId,
        apnsId: apnsResult?.apnsId,
      }),
      { status: sent ? 200 : 502, headers },
    );
  } catch (error) {
    console.error("Send notification error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
