// Shared notification utility functions
// Extracted for testability

// Notification types supported
export type NotificationType =
  | "circle_activity"
  | "hug"
  | "streak_risk"
  | "weekly_summary"
  | "challenge"
  | "shield_used"
  | "shield_reset"
  | "recovery_available"
  | "reengagement_gentle"
  | "reengagement_social"
  | "reengagement_progress"
  | "reengagement_fresh_start"
  // Proactive Intelligence types
  | "proactive_mood_decline"
  | "proactive_streak_risk"
  | "proactive_milestone"
  | "proactive_reengagement"
  | "proactive_pattern_insight"
  // Assessment reminders
  | "assessment_reminder"
  // Buddy & Couples types
  | "buddy_encouragement"
  | "couples_exercise_invite"
  // Wellness Agent
  | "agent_action";

// Map notification types to user settings columns
export const TYPE_TO_SETTING: Record<NotificationType, string> = {
  circle_activity: "notify_circle_activity",
  hug: "notify_hugs",
  streak_risk: "notify_streak_risk",
  weekly_summary: "notify_weekly_summary",
  challenge: "notify_challenges",
  shield_used: "notify_streak_risk", // Uses same setting as streak_risk
  shield_reset: "notify_streak_risk", // Uses same setting as streak_risk
  recovery_available: "notify_streak_risk", // Uses same setting as streak_risk
  reengagement_gentle: "reminders_enabled", // Uses general reminders setting
  reengagement_social: "reminders_enabled",
  reengagement_progress: "reminders_enabled",
  reengagement_fresh_start: "reminders_enabled",
  // Proactive Intelligence - uses proactive_enabled setting
  proactive_mood_decline: "proactive_enabled",
  proactive_streak_risk: "proactive_enabled",
  proactive_milestone: "proactive_enabled",
  proactive_reengagement: "proactive_enabled",
  proactive_pattern_insight: "proactive_enabled",
  // Assessment reminders - uses general reminders setting
  assessment_reminder: "reminders_enabled",
  // Buddy & Couples - uses general reminders setting
  buddy_encouragement: "reminders_enabled",
  couples_exercise_invite: "reminders_enabled",
  // Wellness Agent - uses proactive_enabled setting
  agent_action: "proactive_enabled",
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
  // Shield-related fields
  shieldsRemaining?: number;
  shieldsMax?: number;
  streakToRecover?: number;
  // Re-engagement fields
  displayName?: string;
  absenceDays?: number;
  hugsReceived?: number;
  circlePosts?: number;
  // Proactive Intelligence fields
  avgMood?: number;
  consecutiveLowDays?: number;
  milestone?: number;
  daysInactive?: number;
  patternType?: string;
  patternInsight?: string;
  // Assessment reminder fields
  assessmentCode?: string;
  assessmentName?: string;
  daysSinceLastAssessment?: number;
  // Buddy & Couples fields
  messageType?: string;
  sessionId?: string;
  exerciseName?: string;
  // Wellness Agent fields
  title?: string;
  body?: string;
  deepLink?: string;
  actionId?: string;
  actionType?: string;
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

    case "shield_used": {
      const streak = data.streak || 0;
      const remaining = data.shieldsRemaining ?? 0;
      const max = data.shieldsMax ?? 1;
      return {
        title: "🛡️ Streak Protected!",
        body: `Your ${streak}-day streak was saved! ${remaining}/${max} shields remaining`,
        deepLink: "mindfriend://home",
      };
    }

    case "shield_reset":
      return {
        title: "🛡️ Shields Refreshed!",
        body: `Your streak shields have been reset. You have ${data.shieldsMax || 1} shield${(data.shieldsMax || 1) > 1 ? "s" : ""} for this week.`,
        deepLink: "mindfriend://home",
      };

    case "recovery_available": {
      const streakToRecover = data.streakToRecover || 0;
      return {
        title: "🔄 Recover Your Streak!",
        body: `Complete a recovery quest in the next 24h to restore your ${streakToRecover}-day streak`,
        deepLink: "mindfriend://recovery",
      };
    }

    // Re-engagement notifications (tiered by absence duration)
    case "reengagement_gentle": {
      // Day 3: Gentle check-in
      const name = data.displayName || "friend";
      return {
        title: "Thinking of you 💭",
        body: `Hey ${name}, just checking in. We're here whenever you need us.`,
        deepLink: "mindfriend://home",
      };
    }

    case "reengagement_social": {
      // Day 7: Social hook
      const hugs = data.hugsReceived || 0;
      const posts = data.circlePosts || 0;
      let body = "Your friends have been active in your circles.";
      if (hugs > 0) {
        body = `You have ${hugs} hug${hugs > 1 ? "s" : ""} waiting for you!`;
      } else if (posts > 0) {
        body = `${posts} new update${posts > 1 ? "s" : ""} from your circle.`;
      }
      return {
        title: "Your circle misses you 💛",
        body,
        deepLink: "mindfriend://circles",
      };
    }

    case "reengagement_progress": {
      // Day 14: Progress preserved message
      return {
        title: "Your progress is safe 🌱",
        body: "Your journey is waiting right where you left off. Come back when you're ready.",
        deepLink: "mindfriend://home",
      };
    }

    case "reengagement_fresh_start": {
      // Day 30: Fresh start offer
      return {
        title: "A fresh start awaits ✨",
        body: "Sometimes we all need a reset. Start fresh with a Day 2 bonus when you return.",
        deepLink: "mindfriend://home",
      };
    }

    // Proactive Intelligence notifications
    case "proactive_mood_decline": {
      const name = data.displayName || "there";
      return {
        title: "Checking in 💙",
        body: `Hey ${name}, I noticed things have been tough lately. No pressure—just wanted you to know I'm here.`,
        deepLink: "mindfriend://chat",
      };
    }

    case "proactive_streak_risk": {
      const streak = data.streak || 0;
      const name = data.displayName || "there";
      return {
        title: `${streak}-day streak 🔥`,
        body: `Hey ${name}, you're on a ${streak}-day streak! Today's quest is ready whenever you are. 💪`,
        deepLink: "mindfriend://quest",
      };
    }

    case "proactive_milestone": {
      const milestone = data.milestone || 7;
      const name = data.displayName || "there";
      return {
        title: "Almost there! 🎉",
        body: `${name}, you're just 1 day away from a ${milestone}-day streak! You've got this!`,
        deepLink: "mindfriend://quest",
      };
    }

    case "proactive_reengagement": {
      const days = data.daysInactive || 3;
      const name = data.displayName || "there";
      const messages = [
        `Hey ${name}, it's been a few days. No judgment—life happens. I'm here when you're ready.`,
        `${name}, just wanted to say hi. Your wellness journey is still here waiting.`,
        `${name}, we've missed you! A quick 2-minute breathing exercise is ready when you are.`,
      ];
      return {
        title: "Welcome back 💛",
        body: messages[Math.min(Math.floor(days / 7), messages.length - 1)],
        deepLink: "mindfriend://home",
      };
    }

    case "proactive_pattern_insight": {
      const insight =
        data.patternInsight ||
        "We've noticed an interesting pattern in your data.";
      return {
        title: "New Insight 💡",
        body: insight,
        deepLink: "mindfriend://insights",
      };
    }

    case "assessment_reminder": {
      const assessmentName = data.assessmentName || "wellness check-in";
      const code = data.assessmentCode || "";
      const days = data.daysSinceLastAssessment;
      let body = `Time for your ${assessmentName} to track your progress.`;
      if (days && days > 14) {
        body = `It's been ${days} days since your last ${assessmentName}. Take a few minutes to check in.`;
      }
      return {
        title: "Wellness Check-In 📊",
        body,
        deepLink: `mindfriend://assessment/${code}`,
      };
    }

    case "buddy_encouragement": {
      const name = data.senderName || "Your buddy";
      return {
        title: "Buddy Encouragement 💪",
        body: `${name} sent you some encouragement!`,
        deepLink: "mindfriend://home",
      };
    }

    case "couples_exercise_invite": {
      const name = data.senderName || "Your partner";
      const exercise = data.exerciseName || "an exercise";
      return {
        title: "Exercise Invite 💑",
        body: `${name} invited you to do ${exercise} together`,
        deepLink: data.sessionId
          ? `mindfriend://couples/session/${data.sessionId}`
          : "mindfriend://couples",
      };
    }

    case "agent_action": {
      return {
        title: data.title || "MindFriend",
        body: data.body || "Your wellness companion has something for you",
        deepLink: data.deepLink || "mindfriend://home",
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
