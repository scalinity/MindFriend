// Action Templates for Autonomous Wellness Agent
// Provides message templates and AI-powered personalization

import type { SignalType, SignalEvidence } from "./signal-detectors.ts";

export type ActionType =
  | "check_in"
  | "suggest_exercise"
  | "morning_briefing"
  | "encouragement"
  | "streak_reminder"
  | "mood_prompt"
  | "content_recommendation"
  | "concern_alert";

export interface ActionContent {
  title: string;
  body: string;
  quickActions: QuickAction[];
  deepLink?: string;
  metadata?: Record<string, unknown>;
}

export interface QuickAction {
  label: string;
  action: string;
  value?: string;
}

export interface MessageContext {
  userName: string;
  signalType: SignalType;
  severity: string;
  evidence: SignalEvidence;
  streak: number;
  timeOfDay: "morning" | "afternoon" | "evening" | "night";
}

interface MessageTemplate {
  titlePatterns: string[];
  bodyPatterns: string[];
  quickActions: QuickAction[];
  deepLink?: string;
}

/**
 * Get action type based on signal type
 */
export function getActionTypeForSignal(signalType: SignalType): ActionType {
  const mapping: Record<SignalType, ActionType> = {
    mood_decline: "check_in",
    mood_improvement: "encouragement",
    activity_drop: "suggest_exercise",
    streak_risk: "streak_reminder",
    inactivity: "mood_prompt",
    stress_spike: "suggest_exercise",
    positive_momentum: "encouragement",
  };
  return mapping[signalType] || "check_in";
}

/**
 * Generate personalized message content
 */
export async function generateActionContent(
  actionType: ActionType,
  context: MessageContext,
  useAI = true,
): Promise<ActionContent> {
  const template = getTemplate(actionType, context.signalType);

  if (useAI && Deno.env.get("XAI_API_KEY")) {
    try {
      return await generateAIMessage(actionType, context, template);
    } catch {
      // Fall back to template
    }
  }

  return generateTemplateMessage(template, context);
}

/**
 * Get template for action type and signal type combination
 */
function getTemplate(
  actionType: ActionType,
  signalType: SignalType,
): MessageTemplate {
  const templates: Record<string, MessageTemplate> = {
    "check_in:mood_decline": {
      titlePatterns: [
        "Hey {{name}}, checking in",
        "{{name}}, thinking of you",
        "A moment for you",
      ],
      bodyPatterns: [
        "I noticed your mood has been lower lately. Want to talk about it?",
        "How are you holding up? I'm here if you need support.",
        "Just wanted to see how you're doing today.",
      ],
      quickActions: [
        { label: "I'm doing okay", action: "respond", value: "okay" },
        { label: "Could use support", action: "start_chat" },
        { label: "Not now", action: "dismiss" },
      ],
      deepLink: "mindfriend://chat",
    },
    "check_in:inactivity": {
      titlePatterns: [
        "Miss you, {{name}}",
        "{{name}}, I'm here when ready",
        "Thinking of you",
      ],
      bodyPatterns: [
        "It's been a few days. No pressure, just wanted you to know I'm here.",
        "Whenever you're ready, I'd love to hear how you're doing.",
        "Just a gentle hello. How has life been treating you?",
      ],
      quickActions: [
        { label: "Log mood", action: "mood_log" },
        { label: "Quick exercise", action: "exercise", value: "quick" },
        { label: "Just browsing", action: "open_app" },
      ],
      deepLink: "mindfriend://mood",
    },
    "encouragement:positive_momentum": {
      titlePatterns: [
        "You're on a roll, {{name}}!",
        "{{name}}, you're doing great",
        "Keep it up!",
      ],
      bodyPatterns: [
        "Your consistency this week has been amazing. Keep going!",
        "{{streak}}-day streak and counting! You should be proud.",
        "I can see the positive changes. You're building great habits!",
      ],
      quickActions: [
        { label: "Thanks!", action: "acknowledge" },
        { label: "Keep going", action: "open_app" },
      ],
      deepLink: "mindfriend://home",
    },
    "encouragement:mood_improvement": {
      titlePatterns: [
        "{{name}}, great progress!",
        "Your mood is looking up",
        "Nice trend!",
      ],
      bodyPatterns: [
        "I noticed your mood improving this week. That's wonderful!",
        "Whatever you're doing, it's working. Keep it up!",
        "The upward trend in your mood is inspiring to see.",
      ],
      quickActions: [
        { label: "Thanks!", action: "acknowledge" },
        { label: "Log today's mood", action: "mood_log" },
      ],
      deepLink: "mindfriend://mood",
    },
    "streak_reminder:streak_risk": {
      titlePatterns: [
        "{{name}}, your {{streak}}-day streak awaits",
        "Don't lose your streak!",
        "Quick reminder, {{name}}",
      ],
      bodyPatterns: [
        "Your {{streak}}-day streak is at risk! Complete today's quest to keep it alive.",
        "Just a quick task left for today. You've got this!",
        "{{streak}} days of progress - don't let it slip away. Complete your quest!",
      ],
      quickActions: [
        { label: "Complete quest", action: "quest" },
        { label: "Quick check-in", action: "mood_log" },
        { label: "Remind later", action: "snooze", value: "1h" },
      ],
      deepLink: "mindfriend://quest",
    },
    "suggest_exercise:activity_drop": {
      titlePatterns: [
        "Time for a refresh, {{name}}",
        "A little movement?",
        "{{name}}, exercise suggestion",
      ],
      bodyPatterns: [
        "I noticed you've been less active lately. How about a quick breathing exercise?",
        "Even a short exercise can help. Want to try one?",
        "A gentle movement break might feel good right now.",
      ],
      quickActions: [
        { label: "2-min breathing", action: "exercise", value: "breathing" },
        { label: "5-min meditation", action: "exercise", value: "meditation" },
        { label: "Maybe later", action: "snooze", value: "3h" },
      ],
      deepLink: "mindfriend://exercises/breathing",
    },
    "suggest_exercise:stress_spike": {
      titlePatterns: [
        "{{name}}, a calming moment",
        "Take a breath",
        "Stress relief suggestion",
      ],
      bodyPatterns: [
        "Sensing some stress? A quick breathing exercise might help.",
        "When things feel intense, a grounding exercise can help.",
        "Here's a suggestion to help you feel more centered.",
      ],
      quickActions: [
        { label: "Box breathing", action: "exercise", value: "box-breathing" },
        { label: "Grounding", action: "exercise", value: "grounding" },
        { label: "Not now", action: "dismiss" },
      ],
      deepLink: "mindfriend://exercises/breathing/box-breathing",
    },
    "mood_prompt:inactivity": {
      titlePatterns: [
        "How are you, {{name}}?",
        "Quick check-in",
        "{{name}}, share a moment",
      ],
      bodyPatterns: [
        "Haven't heard from you in a while. How are you feeling today?",
        "A quick mood log helps me support you better. How's today going?",
        "Just curious - how's your day been?",
      ],
      quickActions: [
        { label: "Log mood", action: "mood_log" },
        { label: "I'm good", action: "respond", value: "good" },
        { label: "Not great", action: "start_chat" },
      ],
      deepLink: "mindfriend://mood",
    },
  };

  const key = `${actionType}:${signalType}`;
  return templates[key] || getDefaultTemplate(actionType);
}

function getDefaultTemplate(actionType: ActionType): MessageTemplate {
  const defaults: Record<ActionType, MessageTemplate> = {
    check_in: {
      titlePatterns: ["Checking in, {{name}}"],
      bodyPatterns: ["How are you doing today?"],
      quickActions: [
        { label: "I'm good", action: "respond", value: "good" },
        { label: "Could be better", action: "start_chat" },
      ],
      deepLink: "mindfriend://chat",
    },
    suggest_exercise: {
      titlePatterns: ["Exercise suggestion"],
      bodyPatterns: ["A quick exercise might help you feel better."],
      quickActions: [
        { label: "Try it", action: "exercise" },
        { label: "Later", action: "snooze", value: "1h" },
      ],
      deepLink: "mindfriend://exercises",
    },
    morning_briefing: {
      titlePatterns: ["Good morning, {{name}}"],
      bodyPatterns: ["Here's your daily wellness briefing."],
      quickActions: [{ label: "View", action: "open_app" }],
      deepLink: "mindfriend://home",
    },
    encouragement: {
      titlePatterns: ["Great job, {{name}}!"],
      bodyPatterns: ["You're making great progress. Keep it up!"],
      quickActions: [{ label: "Thanks!", action: "acknowledge" }],
      deepLink: "mindfriend://home",
    },
    streak_reminder: {
      titlePatterns: ["Streak reminder"],
      bodyPatterns: ["Complete your daily quest to keep your streak alive!"],
      quickActions: [
        { label: "Complete", action: "quest" },
        { label: "Later", action: "snooze", value: "1h" },
      ],
      deepLink: "mindfriend://quest",
    },
    mood_prompt: {
      titlePatterns: ["How are you feeling?"],
      bodyPatterns: ["Take a moment to log your mood."],
      quickActions: [{ label: "Log mood", action: "mood_log" }],
      deepLink: "mindfriend://mood",
    },
    content_recommendation: {
      titlePatterns: ["For you, {{name}}"],
      bodyPatterns: ["I found something that might help."],
      quickActions: [{ label: "View", action: "open_app" }],
      deepLink: "mindfriend://library",
    },
    concern_alert: {
      titlePatterns: ["{{name}}, I'm here for you"],
      bodyPatterns: [
        "If you're going through something difficult, please know support is available.",
      ],
      quickActions: [
        { label: "Talk to someone", action: "crisis_resources" },
        { label: "I'm okay", action: "respond", value: "okay" },
      ],
      deepLink: "mindfriend://crisis",
    },
  };

  return defaults[actionType];
}

function generateTemplateMessage(
  template: MessageTemplate,
  context: MessageContext,
): ActionContent {
  const title = interpolate(randomChoice(template.titlePatterns), context);
  const body = interpolate(randomChoice(template.bodyPatterns), context);

  return {
    title,
    body,
    quickActions: template.quickActions,
    deepLink: template.deepLink,
  };
}

async function generateAIMessage(
  actionType: ActionType,
  context: MessageContext,
  fallbackTemplate: MessageTemplate,
): Promise<ActionContent> {
  const apiKey = Deno.env.get("XAI_API_KEY");
  if (!apiKey) {
    return generateTemplateMessage(fallbackTemplate, context);
  }

  const prompt = buildAIPrompt(actionType, context);

  // Create abort controller for timeout
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 10000); // 10 second timeout

  try {
    const response = await fetch("https://api.x.ai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "grok-beta",
        messages: [{ role: "user", content: prompt }],
        max_tokens: 150,
        temperature: 0.7,
      }),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      throw new Error(`AI API error: ${response.status}`);
    }

    const result = await response.json();
    const generatedContent = result.choices[0]?.message?.content;

    if (!generatedContent) {
      throw new Error("Empty AI response");
    }

    // Parse JSON response with safe parsing
    let parsed: { title?: string; body?: string };
    try {
      parsed = JSON.parse(generatedContent);
    } catch {
      // AI returned non-JSON, try to extract from text
      const titleMatch = generatedContent.match(/"title"\s*:\s*"([^"]+)"/);
      const bodyMatch = generatedContent.match(/"body"\s*:\s*"([^"]+)"/);
      parsed = {
        title: titleMatch?.[1],
        body: bodyMatch?.[1],
      };
    }

    // Validate and sanitize
    const title =
      typeof parsed.title === "string" &&
      parsed.title.length > 0 &&
      parsed.title.length <= 100
        ? parsed.title
        : fallbackTemplate.titlePatterns[0];
    const body =
      typeof parsed.body === "string" &&
      parsed.body.length > 0 &&
      parsed.body.length <= 500
        ? parsed.body
        : fallbackTemplate.bodyPatterns[0];

    return {
      title: interpolate(title, context),
      body: interpolate(body, context),
      quickActions: fallbackTemplate.quickActions,
      deepLink: fallbackTemplate.deepLink,
    };
  } catch {
    clearTimeout(timeoutId);
    return generateTemplateMessage(fallbackTemplate, context);
  }
}

function buildAIPrompt(
  actionType: ActionType,
  context: MessageContext,
): string {
  const guidance: Record<ActionType, string> = {
    check_in: "Express gentle concern without being alarming. Offer support.",
    suggest_exercise: "Suggest a calming activity in a non-pushy way.",
    morning_briefing: "Greet warmly and set a positive tone for the day.",
    encouragement: "Celebrate their progress with specific acknowledgment.",
    streak_reminder: "Friendly reminder about their streak without pressure.",
    mood_prompt: "Gently ask about their mood in a caring way.",
    content_recommendation: "Suggest helpful content based on their patterns.",
    concern_alert: "Express care and concern, mention support resources.",
  };

  return `You are a caring wellness companion. Generate a personalized notification message.

USER CONTEXT:
- Name: ${context.userName}
- Signal: ${context.signalType}
- Severity: ${context.severity}
- Current streak: ${context.streak} days
- Time of day: ${context.timeOfDay}

MESSAGE GUIDANCE:
${guidance[actionType]}

CONSTRAINTS:
- Be warm but not overly cheerful if mood is low
- Title: max 40 characters
- Body: max 100 characters
- Sound natural, not robotic
- Don't be preachy or lecturing

Generate a JSON response with:
{
  "title": "short title",
  "body": "message body"
}`;
}

function interpolate(text: string, context: MessageContext): string {
  return text
    .replace(/\{\{name\}\}/g, context.userName)
    .replace(/\{\{streak\}\}/g, String(context.streak));
}

function randomChoice<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

/**
 * Generate reasoning explanation for an action
 */
export function generateReasoning(
  signalType: SignalType,
  evidence: SignalEvidence,
  actionType: ActionType,
): string {
  const signalDescriptions: Record<SignalType, string> = {
    mood_decline: "declining mood pattern",
    mood_improvement: "improving mood trend",
    activity_drop: "reduced activity level",
    streak_risk: "streak at risk",
    inactivity: "extended period of inactivity",
    stress_spike: "signs of increased stress",
    positive_momentum: "positive wellness momentum",
  };

  const actionDescriptions: Record<ActionType, string> = {
    check_in: "reached out to check in with you",
    suggest_exercise: "suggested an exercise",
    morning_briefing: "sent your morning briefing",
    encouragement: "sent encouragement",
    streak_reminder: "reminded you about your streak",
    mood_prompt: "asked about your mood",
    content_recommendation: "recommended some content",
    concern_alert: "expressed concern and shared resources",
  };

  let reasoning = `I noticed a ${signalDescriptions[signalType]}`;

  if (evidence.trend) {
    const direction =
      evidence.trend.direction === "up" ? "improving" : "declining";
    reasoning += ` (${direction} over ${evidence.trend.durationDays} days)`;
  }

  if (evidence.comparison) {
    const change = Math.abs(Math.round(evidence.comparison.percentChange));
    const direction = evidence.comparison.percentChange > 0 ? "up" : "down";
    reasoning += `, with a ${change}% change ${direction}`;
  }

  reasoning += `, so I ${actionDescriptions[actionType]}.`;

  return reasoning;
}
