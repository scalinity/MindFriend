// Shared notification utility functions
// Extracted for testability

// Notification types supported
export type NotificationType =
  | "circle_activity"
  | "hug"
  | "streak_risk"
  | "weekly_summary"
  | "challenge";

// Map notification types to user settings columns
export const TYPE_TO_SETTING: Record<NotificationType, string> = {
  circle_activity: "notify_circle_activity",
  hug: "notify_hugs",
  streak_risk: "notify_streak_risk",
  weekly_summary: "notify_weekly_summary",
  challenge: "notify_challenges",
};

export interface NotificationContent {
  title: string;
  body: string;
  deepLink: string;
}

export interface NotificationData {
  senderId?: string;
  senderName?: string;
  circleId?: string;
  circleName?: string;
  streak?: number;
  urgency?: number;
  checkins?: number;
  quests?: number;
  exercises?: number;
  moodMessage?: string;
  completedCount?: number;
  totalMembers?: number;
  challengeTitle?: string;
}

// Build notification content based on type
export function buildNotificationContent(
  type: NotificationType,
  data: NotificationData,
): NotificationContent {
  switch (type) {
    case "circle_activity":
      return {
        title: "Circle Update",
        body: `${data.senderName || "Someone"} shared how they're feeling`,
        deepLink: `mindfriend://circle/${data.circleId || ""}`,
      };

    case "hug":
      return {
        title: "You got a hug! 🤗",
        body: `${data.senderName || "Someone"} sent you some love`,
        deepLink: `mindfriend://circle/${data.circleId || ""}`,
      };

    case "streak_risk": {
      const urgency = data.urgency || 0;
      const streak = data.streak || 0;
      const messages = [
        `You've been consistent for ${streak} days. Tomorrow is day ${streak + 1}!`,
        `Your ${streak} day streak is at risk - check in to keep it going`,
      ];
      return {
        title: "🔥 Streak Alert",
        body: messages[urgency] || messages[0],
        deepLink: "mindfriend://quest",
      };
    }

    case "weekly_summary":
      return {
        title: "Your Week in Review 📊",
        body: `${data.checkins || 0} check-ins, ${data.quests || 0} quests. ${data.moodMessage || ""}`.trim(),
        deepLink: "mindfriend://insights",
      };

    case "challenge": {
      const completed = data.completedCount || 0;
      const total = data.totalMembers || 0;
      return {
        title: "Challenge Update 🎯",
        body: `${completed}/${total} completed today's challenge`,
        deepLink: `mindfriend://circle/${data.circleId || ""}`,
      };
    }

    default:
      return {
        title: "MindFriend",
        body: "Check in with yourself today",
        deepLink: "mindfriend://",
      };
  }
}

// Check if current hour is within quiet hours
export function isInQuietHours(
  currentHour: number,
  quietStart: string | null,
  quietEnd: string | null,
): boolean {
  if (!quietStart || !quietEnd) return false;

  const startHour = parseInt(quietStart.split(":")[0], 10);
  const endHour = parseInt(quietEnd.split(":")[0], 10);

  // Handle wrap-around (e.g., 22:00 to 08:00)
  if (startHour > endHour) {
    return currentHour >= startHour || currentHour < endHour;
  } else {
    return currentHour >= startHour && currentHour < endHour;
  }
}

// Get mood trend message for weekly summary
export function getMoodTrendMessage(
  trend: string | null,
  avgMood: number | null,
): string {
  if (!trend || avgMood === null) {
    return "Keep tracking to see your trends!";
  }

  switch (trend) {
    case "improving":
      return "Your mood is trending up! 📈";
    case "stable":
      return "Your mood has been steady.";
    case "declining":
      return "It's been a tough week. We're here for you.";
    default:
      return "";
  }
}
