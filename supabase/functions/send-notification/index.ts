// MindFriend Smart Notification Edge Function
// Handles push notifications with preferences, quiet hours, and history tracking
// See: specs/04-smart-notifications.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders, corsHeaders } from "../_shared/cors.ts";
import {
  sendAPNs,
  buildAPNsPayload,
  isAPNsConfigured,
  getAPNsConfig,
} from "../_shared/apns.ts";
import {
  type NotificationType,
  TYPE_TO_SETTING,
  buildNotificationContent,
  isInQuietHours,
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
  };
}

// Check rate limit for a recipient or sender
async function checkRateLimit(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  type: "recipient" | "sender",
): Promise<{ allowed: boolean; count: number; limit: number }> {
  const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MS).toISOString();
  const limit =
    type === "recipient" ? RATE_LIMIT_MAX_PER_USER : RATE_LIMIT_MAX_PER_SENDER;

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
  const targetDateStr = `${targetYear}-${String(targetMonth).padStart(2, "0")}-${String(targetDay).padStart(2, "0")}T${String(endHour).padStart(2, "0")}:${String(endMinute).padStart(2, "0")}:00`;

  // Use Intl to get the UTC offset for this timezone at this time
  // Then calculate the UTC equivalent
  const tempDate = new Date(targetDateStr + "Z"); // Parse as UTC first
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

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const origin = req.headers.get("Origin");
  const headers = {
    ...getCorsHeaders(origin),
    "Content-Type": "application/json",
  };

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

    if (authHeader) {
      const token = authHeader.replace("Bearer ", "");

      // Check if this is a service role call (Fix 3: use constant-time comparison)
      const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

      // Constant-time comparison to prevent timing attacks
      const tokenBytes = new TextEncoder().encode(token);
      const keyBytes = new TextEncoder().encode(serviceRoleKey);

      let isServiceRole = tokenBytes.length === keyBytes.length;
      if (isServiceRole) {
        // XOR comparison - constant time regardless of where mismatch occurs
        let diff = 0;
        for (let i = 0; i < tokenBytes.length; i++) {
          diff |= tokenBytes[i] ^ keyBytes[i];
        }
        isServiceRole = diff === 0;
      }

      if (isServiceRole) {
        callerId = "service_role";
      } else {
        // Validate user token
        const {
          data: { user },
        } = await supabaseAdmin.auth.getUser(token);
        if (user) {
          callerId = user.id;
        }
      }
    }

    // Parse request body
    const body: NotificationRequest = await req.json();

    if (!body.type || !body.recipientId) {
      return new Response(
        JSON.stringify({ error: "Missing type or recipientId" }),
        { status: 400, headers },
      );
    }

    // Validate notification type
    const validTypes: NotificationType[] = [
      "circle_activity",
      "hug",
      "streak_risk",
      "weekly_summary",
      "challenge",
    ];
    if (!validTypes.includes(body.type)) {
      return new Response(
        JSON.stringify({ error: "Invalid notification type" }),
        { status: 400, headers },
      );
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
    const { data: settings } = await supabaseAdmin
      .from("user_settings")
      .select("*")
      .eq("user_id", body.recipientId)
      .single();

    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("timezone, display_name")
      .eq("id", body.recipientId)
      .single();

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
      await supabaseAdmin.from("notification_history").insert({
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
    const { data: pushTokens } = await supabaseAdmin
      .from("push_tokens")
      .select("token")
      .eq("user_id", body.recipientId)
      .eq("platform", "ios");

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
      for (const { token } of pushTokens) {
        apnsResult = await sendAPNs(token, payload, {
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
            .eq("token", token);
          console.log("Removed invalid push token for user:", body.recipientId);
        }
      }
    } else {
      // Mock mode - log notification
      console.log("[MOCK NOTIFICATION]", {
        recipientId: body.recipientId,
        type: body.type,
        content,
      });
      sent = true; // Pretend it was sent for testing
    }

    // Log to notification history
    await supabaseAdmin.from("notification_history").insert({
      id: notificationId,
      user_id: body.recipientId,
      notification_type: body.type,
      title: content.title,
      body: content.body,
      deep_link: content.deepLink,
      metadata: body.data,
      status: sent ? "sent" : "failed",
      sent_at: sent ? now.toISOString() : null,
    });

    return new Response(
      JSON.stringify({
        success: true,
        sent,
        id: notificationId,
        apnsId: apnsResult?.apnsId,
      }),
      { status: 200, headers },
    );
  } catch (error) {
    console.error("Send notification error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers,
    });
  }
});
