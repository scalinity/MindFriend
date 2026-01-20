// Email template system with HTML escaping, validation, and rendering

interface EmailTemplate {
  subject: string;
  htmlBody: string;
  textBody: string;
  previewText: string;
}

interface WeeklySummaryPayload {
  userName: string;
  weekStartDate: string;
  quests: { name: string; completed: number; total: number }[];
  moods: { date: string; mood: string; intensity: number }[];
  totalStreakDays: number;
  exercisesCompleted: number;
}

interface StreakCelebrationPayload {
  userName: string;
  streakDays: number;
  milestone: boolean;
}

interface AchievementUnlockPayload {
  userName: string;
  badgeName: string;
  badgeDescription: string;
  badgeIcon: string;
}

interface LapsedUserNudgePayload {
  userName: string;
  daysSinceActive: number;
  lastActivityDate: string;
  topQuest: string;
  topExercise: string;
}

interface MonthlyReportPayload {
  userName: string;
  monthYear: string;
  quests: { name: string; completed: number; total: number }[];
  moodTrend: string;
  totalStreakDays: number;
  exercisesCompleted: number;
  topBadges: string[];
}

type EmailPayload =
  | WeeklySummaryPayload
  | StreakCelebrationPayload
  | AchievementUnlockPayload
  | LapsedUserNudgePayload
  | MonthlyReportPayload;

// HTML escape utility
function escapeHtml(text: string): string {
  const map: Record<string, string> = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#039;",
  };
  return text.replace(/[&<>"']/g, (m) => map[m]);
}

// Email header escape utility (prevent CRLF injection and header breaking)
function escapeEmailHeader(text: string): string {
  // Remove CR and LF characters to prevent header injection
  // Also remove null bytes
  return text.replace(/[\r\n\0]/g, "").substring(0, 998);
}

// Template validation
function validatePayload(type: string, payload: unknown): boolean {
  if (!payload || typeof payload !== "object") return false;

  const p = payload as Record<string, unknown>;

  switch (type) {
    case "weekly_summary":
      return (
        typeof p.userName === "string" &&
        typeof p.weekStartDate === "string" &&
        Array.isArray(p.quests) &&
        Array.isArray(p.moods) &&
        typeof p.totalStreakDays === "number" &&
        typeof p.exercisesCompleted === "number"
      );

    case "streak_celebration":
      return (
        typeof p.userName === "string" &&
        typeof p.streakDays === "number" &&
        typeof p.milestone === "boolean"
      );

    case "achievement_unlock":
      return (
        typeof p.userName === "string" &&
        typeof p.badgeName === "string" &&
        typeof p.badgeDescription === "string" &&
        typeof p.badgeIcon === "string"
      );

    case "lapsed_nudge":
      return (
        typeof p.userName === "string" &&
        typeof p.daysSinceActive === "number" &&
        typeof p.lastActivityDate === "string" &&
        typeof p.topQuest === "string" &&
        typeof p.topExercise === "string"
      );

    case "monthly_report":
      return (
        typeof p.userName === "string" &&
        typeof p.monthYear === "string" &&
        Array.isArray(p.quests) &&
        typeof p.moodTrend === "string" &&
        typeof p.totalStreakDays === "number" &&
        typeof p.exercisesCompleted === "number" &&
        Array.isArray(p.topBadges)
      );

    default:
      return false;
  }
}

// Email template rendering
function renderTemplate(type: string, payload: EmailPayload): EmailTemplate {
  switch (type) {
    case "weekly_summary":
      return renderWeeklySummary(payload as WeeklySummaryPayload);

    case "streak_celebration":
      return renderStreakCelebration(payload as StreakCelebrationPayload);

    case "achievement_unlock":
      return renderAchievementUnlock(payload as AchievementUnlockPayload);

    case "lapsed_nudge":
      return renderLapsedNudge(payload as LapsedUserNudgePayload);

    case "monthly_report":
      return renderMonthlyReport(payload as MonthlyReportPayload);

    default:
      throw new Error(`Unknown email type: ${type}`);
  }
}

// Weekly summary template
function renderWeeklySummary(p: WeeklySummaryPayload): EmailTemplate {
  const questStats = p.quests
    .map((q) => `<tr><td>${escapeHtml(q.name)}</td><td>${q.completed}/${q.total}</td></tr>`)
    .join("");

  const moodTrend = p.moods
    .slice(-7)
    .map((m) => `<span style="margin: 0 4px; font-size: 18px;">${escapeHtml(m.mood)}</span>`)
    .join("");

  const htmlBody = `
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.6; color: #333; }
      .container { max-width: 600px; margin: 0 auto; padding: 20px; }
      .header { text-align: center; margin-bottom: 30px; }
      .stat-box { background: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 8px; }
      .cta { display: inline-block; background: #7C3AED; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin-top: 20px; }
      table { width: 100%; border-collapse: collapse; margin: 15px 0; }
      table td { padding: 8px; border-bottom: 1px solid #ddd; }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="header">
        <h1>Your Weekly Summary</h1>
        <p>Hi ${escapeHtml(p.userName)}, here's your week at a glance.</p>
      </div>
      
      <div class="stat-box">
        <strong>Quests Completed:</strong>
        <table>${questStats}</table>
      </div>
      
      <div class="stat-box">
        <strong>Your Mood Trend:</strong>
        <p>${moodTrend}</p>
      </div>
      
      <div class="stat-box">
        <strong>Current Stats:</strong>
        <p>🔥 Streak: <strong>${p.totalStreakDays}</strong> days</p>
        <p>💪 Exercises: <strong>${p.exercisesCompleted}</strong> completed</p>
      </div>
      
      <a href="mindfriend://home" class="cta">View Full Details in App</a>
    </div>
  </body>
</html>
  `;

  const textBody = `
Your Weekly Summary
Hi ${p.userName}, here's your week at a glance.

Quests Completed:
${p.quests.map((q) => `  ${q.name}: ${q.completed}/${q.total}`).join("\n")}

Current Stats:
  Streak: ${p.totalStreakDays} days
  Exercises: ${p.exercisesCompleted} completed

View Full Details: mindfriend://home
  `;

  return {
    subject: `Your Weekly Summary - ${p.totalStreakDays} Day Streak! 🔥`,
    htmlBody,
    textBody,
    previewText: `${p.totalStreakDays} day streak! Your weekly summary is ready.`,
  };
}

// Streak celebration template
function renderStreakCelebration(p: StreakCelebrationPayload): EmailTemplate {
  const milestoneText = p.milestone
    ? `🎉 You've reached a major milestone: ${p.streakDays} days! This is incredible!`
    : `Keep it going! You're on a ${p.streakDays} day streak.`;

  const htmlBody = `
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; text-align: center; color: #333; }
      .container { max-width: 600px; margin: 0 auto; padding: 40px 20px; }
      .celebration { font-size: 48px; margin: 20px 0; }
      .cta { display: inline-block; background: #7C3AED; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin-top: 20px; }
    </style>
  </head>
  <body>
    <div class="container">
      <h1>Amazing Work, ${escapeHtml(p.userName)}!</h1>
      <div class="celebration">🔥</div>
      <p>${milestoneText}</p>
      <a href="mindfriend://quests" class="cta">View Your Streak</a>
    </div>
  </body>
</html>
  `;

  const textBody = `
Amazing Work, ${p.userName}!
${milestoneText}

View Your Streak: mindfriend://quests
  `;

  return {
    subject: escapeEmailHeader(`🔥 ${p.streakDays} Day Streak! You're On Fire!`),
    htmlBody,
    textBody,
    previewText: `${p.streakDays} day streak! Keep it up!`,
  };
}

// Achievement unlock template
function renderAchievementUnlock(p: AchievementUnlockPayload): EmailTemplate {
  const htmlBody = `
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; text-align: center; color: #333; }
      .container { max-width: 600px; margin: 0 auto; padding: 40px 20px; }
      .badge-icon { font-size: 64px; margin: 20px 0; }
      .cta { display: inline-block; background: #7C3AED; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin-top: 20px; }
    </style>
  </head>
  <body>
    <div class="container">
      <h1>Badge Unlocked!</h1>
      <div class="badge-icon">${escapeHtml(p.badgeIcon)}</div>
      <h2>${escapeHtml(p.badgeName)}</h2>
      <p>${escapeHtml(p.badgeDescription)}</p>
      <p>Great work, ${escapeHtml(p.userName)}!</p>
      <a href="mindfriend://achievements" class="cta">View All Badges</a>
    </div>
  </body>
</html>
  `;

  const textBody = `
Badge Unlocked!
${p.badgeName}
${p.badgeDescription}

Great work, ${p.userName}!

View All Badges: mindfriend://achievements
  `;

  return {
    subject: escapeEmailHeader(`🏆 Badge Unlocked: ${p.badgeName}!`),
    htmlBody,
    textBody,
    previewText: `You unlocked: ${p.badgeName}`,
  };
}

// Lapsed user nudge template
function renderLapsedNudge(p: LapsedUserNudgePayload): EmailTemplate {
  const daysText =
    p.daysSinceActive === 3 ? "a few days" : p.daysSinceActive === 7 ? "a week" : "a while";

  const htmlBody = `
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #333; }
      .container { max-width: 600px; margin: 0 auto; padding: 20px; }
      .message-box { background: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0; }
      .cta { display: inline-block; background: #7C3AED; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin-top: 20px; }
    </style>
  </head>
  <body>
    <div class="container">
      <h1>We Miss You, ${escapeHtml(p.userName)}!</h1>
      <div class="message-box">
        <p>It's been ${daysText} since we last saw you. We'd love to have you back!</p>
        <p><strong>Try:</strong></p>
        <ul>
          <li>📋 Complete today's quest: <em>${escapeHtml(p.topQuest)}</em></li>
          <li>💪 Try an exercise: <em>${escapeHtml(p.topExercise)}</em></li>
          <li>📝 Log your mood and reflect</li>
        </ul>
      </div>
      <a href="mindfriend://home" class="cta">Open MindFriend</a>
    </div>
  </body>
</html>
  `;

  const textBody = `
We Miss You, ${p.userName}!

It's been ${daysText} since we last saw you. We'd love to have you back!

Try:
  📋 Complete today's quest: ${p.topQuest}
  💪 Try an exercise: ${p.topExercise}
  📝 Log your mood and reflect

Open MindFriend: mindfriend://home
  `;

  return {
    subject: `We miss you! Come back to MindFriend 💙`,
    htmlBody,
    textBody,
    previewText: `We miss you! Your friends are waiting.`,
  };
}

// Monthly report template
function renderMonthlyReport(p: MonthlyReportPayload): EmailTemplate {
  const questStats = p.quests
    .map((q) => `<tr><td>${escapeHtml(q.name)}</td><td>${q.completed}/${q.total}</td></tr>`)
    .join("");

  const badgesList = p.topBadges.slice(0, 5).map((b) => `<li>${escapeHtml(b)}</li>`).join("");

  const htmlBody = `
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.6; color: #333; }
      .container { max-width: 600px; margin: 0 auto; padding: 20px; }
      .header { text-align: center; margin-bottom: 30px; }
      .stat-box { background: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 8px; }
      .cta { display: inline-block; background: #7C3AED; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin-top: 20px; }
      table { width: 100%; border-collapse: collapse; margin: 15px 0; }
      table td { padding: 8px; border-bottom: 1px solid #ddd; }
      ul { margin: 10px 0; padding-left: 20px; }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="header">
        <h1>${p.monthYear} Recap</h1>
        <p>Hi ${escapeHtml(p.userName)}, here's how you did this month!</p>
      </div>
      
      <div class="stat-box">
        <strong>Quests Completed:</strong>
        <table>${questStats}</table>
      </div>
      
      <div class="stat-box">
        <strong>Monthly Stats:</strong>
        <p>🔥 Streak: <strong>${p.totalStreakDays}</strong> days</p>
        <p>💪 Exercises: <strong>${p.exercisesCompleted}</strong> completed</p>
        <p>📊 Mood Trend: <strong>${escapeHtml(p.moodTrend)}</strong></p>
      </div>
      
      <div class="stat-box">
        <strong>Top Badges Earned:</strong>
        <ul>${badgesList}</ul>
      </div>
      
      <a href="mindfriend://profile" class="cta">View Full Report</a>
    </div>
  </body>
</html>
  `;

  const textBody = `
${p.monthYear} Recap
Hi ${p.userName}, here's how you did this month!

Quests Completed:
${p.quests.map((q) => `  ${q.name}: ${q.completed}/${q.total}`).join("\n")}

Monthly Stats:
  Streak: ${p.totalStreakDays} days
  Exercises: ${p.exercisesCompleted} completed
  Mood Trend: ${p.moodTrend}

Top Badges Earned:
${p.topBadges.slice(0, 5).map((b) => `  • ${b}`).join("\n")}

View Full Report: mindfriend://profile
  `;

  return {
    subject: `Your ${p.monthYear} Recap - Keep up the great work! 📊`,
    htmlBody,
    textBody,
    previewText: `${p.monthYear} recap: ${p.totalStreakDays} day streak, ${p.exercisesCompleted} exercises`,
  };
}

export {
  renderTemplate,
  validatePayload,
  escapeHtml,
  EmailTemplate,
  WeeklySummaryPayload,
  StreakCelebrationPayload,
  AchievementUnlockPayload,
  LapsedUserNudgePayload,
  MonthlyReportPayload,
  EmailPayload,
};
