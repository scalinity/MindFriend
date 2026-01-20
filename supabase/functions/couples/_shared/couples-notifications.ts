// Couples Mode Notifications
// Send notifications to partner via existing send-notification Edge Function

// ============================================================================
// NOTIFICATION TYPES
// ============================================================================

export type NotificationType =
  | "partner_invite_accepted"
  | "exercise_session_invited"
  | "exercise_session_started"
  | "exercise_session_completed"
  | "appreciation_received";

export interface PartnerNotification {
  type: NotificationType;
  recipientUserId: string;
  senderUserId?: string;
  data: Record<string, any>;
}

interface NotificationPayload {
  type: NotificationType;
  title: string;
  body: string;
  data: Record<string, any>;
  deeplink?: string;
}

// ============================================================================
// NOTIFICATION TEMPLATES
// ============================================================================

function buildNotificationPayload(
  notification: PartnerNotification,
): NotificationPayload | null {
  switch (notification.type) {
    case "partner_invite_accepted":
      return {
        type: "partner_invite_accepted",
        title: "Partnership Activated",
        body: "Your partner accepted your invitation! You can now do couples exercises together.",
        data: {
          type: "partner_invite_accepted",
          partnerId: notification.senderUserId,
        },
        deeplink: "mindfriend://partners",
      };

    case "exercise_session_invited":
      return {
        type: "exercise_session_invited",
        title: "Exercise Invitation",
        body: `Your partner invited you to a couples exercise session: ${notification.data.exerciseName || "Exercise"}`,
        data: {
          type: "exercise_session_invited",
          sessionId: notification.data.sessionId,
          exerciseId: notification.data.exerciseId,
          exerciseName: notification.data.exerciseName,
        },
        deeplink: `mindfriend://couples-exercise/${notification.data.sessionId}`,
      };

    case "exercise_session_started":
      return {
        type: "exercise_session_started",
        title: "Session Started",
        body: `Your partner started the couples exercise: ${notification.data.exerciseName || "Exercise"}`,
        data: {
          type: "exercise_session_started",
          sessionId: notification.data.sessionId,
          exerciseId: notification.data.exerciseId,
        },
        deeplink: `mindfriend://couples-exercise/${notification.data.sessionId}`,
      };

    case "exercise_session_completed":
      return {
        type: "exercise_session_completed",
        title: "Session Completed",
        body: `Your partner completed the couples exercise. Share your thoughts!`,
        data: {
          type: "exercise_session_completed",
          sessionId: notification.data.sessionId,
          exerciseId: notification.data.exerciseId,
        },
        deeplink: `mindfriend://couples-exercise/${notification.data.sessionId}`,
      };

    case "appreciation_received":
      return {
        type: "appreciation_received",
        title: "You Received an Appreciation",
        body:
          notification.data.message ||
          "Your partner sent you an appreciation message",
        data: {
          type: "appreciation_received",
          appreciationId: notification.data.appreciationId,
          message: notification.data.message,
        },
        deeplink: "mindfriend://appreciation",
      };

    default:
      console.warn(`Unknown notification type: ${notification.type}`);
      return null;
  }
}

// ============================================================================
// NOTIFICATION SENDER
// ============================================================================

/**
 * Send a notification to partner
 * Uses existing send-notification Edge Function
 *
 * Handles offline resilience - if notification fails, logs but doesn't throw
 */
export async function sendPartnerNotification(
  supabase: any,
  notification: PartnerNotification,
): Promise<boolean> {
  try {
    const payload = buildNotificationPayload(notification);
    if (!payload) {
      console.warn(
        `Failed to build notification payload for type: ${notification.type}`,
      );
      return false;
    }

    // Get authorization token for service role
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      console.error("Missing Supabase environment variables");
      return false;
    }

    // Call send-notification Edge Function
    const response = await fetch(
      `${supabaseUrl}/functions/v1/send-notification`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${supabaseServiceKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          userId: notification.recipientUserId,
          title: payload.title,
          body: payload.body,
          data: payload.data,
          deeplink: payload.deeplink,
        }),
      },
    );

    if (!response.ok) {
      const error = await response.text();
      console.error(`Notification send failed (${response.status}):`, error);
      // Don't throw - notifications are best-effort
      return false;
    }

    console.log(
      `Notification sent: ${notification.type} to ${notification.recipientUserId}`,
    );
    return true;
  } catch (error) {
    console.error("Notification send exception:", error);
    // Don't throw - notifications are best-effort
    // Partner might be offline and will see updates when they reconnect
    return false;
  }
}

// ============================================================================
// BATCH NOTIFICATION HELPERS
// ============================================================================

/**
 * Send notifications to both users in a partnership
 * Used when both should be notified of an event
 */
export async function notifyPartnershipBoth(
  supabase: any,
  partnerId1: string,
  partnerId2: string,
  type: NotificationType,
  data: Record<string, any>,
): Promise<void> {
  // Notify user 1
  await sendPartnerNotification(supabase, {
    type,
    recipientUserId: partnerId1,
    senderUserId: partnerId2,
    data,
  });

  // Notify user 2
  await sendPartnerNotification(supabase, {
    type,
    recipientUserId: partnerId2,
    senderUserId: partnerId1,
    data,
  });
}

/**
 * Send optional notification - doesn't fail if notification send fails
 * Use when notification is nice-to-have but not critical to operation
 */
export async function sendOptionalNotification(
  supabase: any,
  notification: PartnerNotification,
): Promise<void> {
  try {
    await sendPartnerNotification(supabase, notification);
  } catch (error) {
    console.warn("Optional notification failed (expected):", error);
    // Expected to fail sometimes, don't log as error
  }
}
