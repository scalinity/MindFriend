// AI Insight Generation Module for Weekly Insights
// Uses xAI (Grok) to generate personalized weekly observations
// See: specs/06-weekly-insights.md

import { Pattern } from "./pattern-detection.ts";

export interface Recommendation {
  title: string;
  reason: string;
}

export interface AIInsightResult {
  insight: string;
  recommendations: Recommendation[];
}

export interface InsightContext {
  userName?: string;
  wellnessFocus?: string;
  avgMood: number | null;
  moodTrend: string | null;
  questCount: number;
  exerciseCount: number;
  exerciseMinutes: number;
  checkinCount: number;
  circleCheckinCount: number;
  patterns: Pattern[];
  streakDays: number;
}

const XAI_API_URL = "https://api.x.ai/v1/chat/completions";
const MODEL = "grok-4-1-fast-non-reasoning-fast";

// Fallback insights when AI is unavailable or data is insufficient
const FALLBACK_INSIGHTS: Record<string, AIInsightResult> = {
  improving: {
    insight:
      "You're making great progress this week! Your consistent engagement with wellness practices is paying off. Keep up the momentum.",
    recommendations: [
      {
        title: "Build on your streak",
        reason:
          "Consistency compounds - try adding one more minute to your exercises",
      },
    ],
  },
  stable: {
    insight:
      "You've maintained steady wellness habits this week. Stability is a foundation for growth. Small, consistent efforts add up over time.",
    recommendations: [
      {
        title: "Try a new exercise type",
        reason: "Variety can spark new insights about what works best for you",
      },
    ],
  },
  declining: {
    insight:
      "This week has been challenging, and that's okay. Remember that wellness isn't linear. Be gentle with yourself and focus on one small step today.",
    recommendations: [
      {
        title: "Start with a 2-minute breathing exercise",
        reason: "Short practices can help restore your sense of calm",
      },
    ],
  },
  insufficient_data: {
    insight:
      "We're still getting to know your patterns. The more you log your moods and complete exercises, the more personalized insights we can provide.",
    recommendations: [
      {
        title: "Log your mood daily",
        reason: "Even a quick check-in helps us understand your patterns",
      },
    ],
  },
};

/**
 * Generate personalized AI insight from user's weekly data
 */
export async function generateAIInsight(
  context: InsightContext,
  apiKey: string | undefined,
): Promise<AIInsightResult> {
  // Use fallback if no API key or insufficient data
  if (!apiKey) {
    console.warn("XAI_API_KEY not configured, using fallback insight");
    return getFallbackInsight(context.moodTrend);
  }

  if (
    context.checkinCount < 2 &&
    context.questCount < 1 &&
    context.exerciseCount < 1
  ) {
    return getFallbackInsight("insufficient_data");
  }

  try {
    const prompt = buildPrompt(context);
    const response = await callXAI(apiKey, prompt);
    return parseResponse(response) || getFallbackInsight(context.moodTrend);
  } catch (error) {
    console.error("AI insight generation error:", error);
    return getFallbackInsight(context.moodTrend);
  }
}

function buildPrompt(context: InsightContext): string {
  const parts: string[] = [];

  // User context
  if (context.userName) {
    parts.push(`User: ${context.userName}`);
  }
  if (context.wellnessFocus) {
    parts.push(`Wellness focus: ${context.wellnessFocus}`);
  }

  // Weekly metrics
  parts.push(`\nThis week's data:`);
  if (context.avgMood !== null) {
    parts.push(`- Average mood: ${context.avgMood.toFixed(1)} out of 5`);
  }
  if (context.moodTrend) {
    parts.push(`- Mood trend vs last week: ${context.moodTrend}`);
  }
  parts.push(`- Mood check-ins: ${context.checkinCount}`);
  parts.push(`- Quests completed: ${context.questCount}`);
  parts.push(`- Exercises completed: ${context.exerciseCount}`);
  if (context.exerciseMinutes > 0) {
    parts.push(`- Total exercise time: ${context.exerciseMinutes} minutes`);
  }
  if (context.circleCheckinCount > 0) {
    parts.push(`- Social check-ins: ${context.circleCheckinCount}`);
  }
  if (context.streakDays > 0) {
    parts.push(`- Current streak: ${context.streakDays} days`);
  }

  // Patterns
  if (context.patterns.length > 0) {
    parts.push(`\nPatterns detected:`);
    for (const pattern of context.patterns) {
      parts.push(`- ${pattern.description}`);
    }
  }

  const dataSection = parts.join("\n");

  return `You are MindFriend, a supportive mental wellness companion. Generate a brief, personalized weekly insight based on this user's data.

${dataSection}

Write:
1. A 2-3 sentence personalized observation about their week. Be warm, specific, and avoid generic platitudes. Reference their actual data.
2. One specific, actionable recommendation based on their patterns and behavior.

Guidelines:
- If mood is declining, be compassionate and gentle, not preachy
- If they have a streak, acknowledge it positively
- Connect recommendations to their observed patterns
- Keep the tone supportive and non-judgmental
- Do not use excessive exclamation marks or be overly enthusiastic

Return JSON only:
{"insight": "Your personalized observation here.", "recommendations": [{"title": "Short action title", "reason": "Why this helps based on their data"}]}`;
}

async function callXAI(apiKey: string, prompt: string): Promise<string> {
  const response = await fetch(XAI_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [{ role: "user", content: prompt }],
      max_tokens: 400,
      temperature: 0.7,
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`xAI API error: ${response.status} ${error}`);
  }

  const data = await response.json();
  return data.choices?.[0]?.message?.content || "";
}

function parseResponse(response: string): AIInsightResult | null {
  try {
    // Extract JSON from response (handle markdown code blocks)
    let jsonStr = response;
    const jsonMatch = response.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
    if (jsonMatch) {
      jsonStr = jsonMatch[1];
    }

    const parsed = JSON.parse(jsonStr.trim());

    // Validate structure
    if (
      typeof parsed.insight !== "string" ||
      !Array.isArray(parsed.recommendations)
    ) {
      return null;
    }

    // Validate recommendations
    const validRecs = parsed.recommendations.filter(
      (r: unknown): r is Recommendation =>
        typeof r === "object" &&
        r !== null &&
        typeof (r as Record<string, unknown>).title === "string" &&
        typeof (r as Record<string, unknown>).reason === "string",
    );

    return {
      insight: parsed.insight.substring(0, 500), // Limit length
      recommendations: validRecs.slice(0, 3), // Max 3 recommendations
    };
  } catch {
    return null;
  }
}

function getFallbackInsight(trend: string | null): AIInsightResult {
  const key = trend && FALLBACK_INSIGHTS[trend] ? trend : "stable";
  return FALLBACK_INSIGHTS[key];
}
