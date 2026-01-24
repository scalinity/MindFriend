// Prompt Builder Module
// Purpose: Construct context-aware AI prompts for personalized exercise generation
// Author: dev-pipeline
// Date: 2026-01-24

import { GenerationContext } from "./context-gatherer.ts";

export interface PromptSpec {
  systemPrompt: string;
  userPrompt: string;
}

/**
 * Build context-aware prompts for exercise generation
 *
 * @param exerciseType - Type of exercise to generate
 * @param context - User context (mood, history, preferences)
 * @param duration - Desired duration in seconds
 * @param theme - Optional theme override
 * @returns System and user prompts for AI generation
 */
export function buildContextualPrompt(
  exerciseType: string,
  context: GenerationContext,
  duration?: number,
  theme?: string,
): PromptSpec {
  const basePrompt = getBasePrompt(exerciseType);
  const contextualEnhancements = buildContextualEnhancements(
    context,
    exerciseType,
    duration,
  );
  const diversityRequirement = buildDiversityRequirement(
    context.recentExercises,
  );

  const systemPrompt = `You are a professional wellness content creator specializing in ${exerciseType} exercises. Create personalized, therapeutic content that adapts to the user's current state and preferences. Your content should feel genuinely crafted for this specific person, not generic or templated.`;

  const userPrompt =
    `${basePrompt}\n\n${contextualEnhancements}\n\n${diversityRequirement}`.trim();

  return { systemPrompt, userPrompt };
}

/**
 * Get base prompt template for each exercise type
 */
function getBasePrompt(exerciseType: string): string {
  const prompts: Record<string, string> = {
    breathing: `Create a personalized breathing exercise.

OUTPUT FORMAT (JSON):
{
  "title": "Creative 3-5 word title",
  "description": "One sentence describing the exercise",
  "content": {
    "pattern": {
      "inhaleSeconds": number (2-6),
      "holdInSeconds": number (0-4),
      "exhaleSeconds": number (3-8),
      "holdOutSeconds": number (0-3),
      "patternName": "e.g., Box Breathing, Extended Exhale"
    },
    "cycles": number,
    "introText": "Opening guidance (2-3 sentences)",
    "outroText": "Closing message (1-2 sentences)"
  }
}`,

    meditation: `Create a personalized meditation script.

OUTPUT FORMAT (JSON):
{
  "title": "Creative meditation title",
  "description": "Brief description of this meditation",
  "content": {
    "script": [
      {"timestamp": 0, "text": "Opening text to settle into meditation...", "type": "intro"},
      {"timestamp": 30, "text": "Gentle breathing instruction...", "type": "breathingGuide"},
      {"timestamp": 60, "text": "Body awareness section...", "type": "bodyAwareness"},
      {"timestamp": 120, "text": "Main visualization...", "type": "visualization"},
      {"timestamp": 240, "text": "Gentle return to awareness...", "type": "closing"}
    ]
  }
}`,

    grounding: `Create a personalized grounding exercise.

OUTPUT FORMAT (JSON):
{
  "title": "Creative grounding exercise title",
  "description": "Brief description",
  "content": {
    "technique": "e.g., 5-4-3-2-1, body scan, object focus",
    "prompts": [
      {"timestamp": 0, "text": "Find a comfortable position...", "sense": null},
      {"timestamp": 15, "text": "Notice 5 things you can see...", "sense": "sight"},
      {"timestamp": 45, "text": "Notice 4 things you can touch...", "sense": "touch"}
    ]
  }
}`,

    journaling: `Create personalized journaling prompts.

OUTPUT FORMAT (JSON):
{
  "title": "Creative journaling session title",
  "description": "Brief description of reflection theme",
  "content": {
    "prompts": [
      {"text": "First reflection prompt...", "category": "emotion"},
      {"text": "Second reflection prompt...", "category": "thought"},
      {"text": "Third reflection prompt...", "category": "action"}
    ],
    "reflectionQuestions": [
      "Deeper question 1...",
      "Deeper question 2..."
    ]
  }
}`,
  };

  return prompts[exerciseType] || prompts.meditation;
}

/**
 * Build contextual enhancements based on user state
 */
function buildContextualEnhancements(
  context: GenerationContext,
  exerciseType: string,
  duration?: number,
): string {
  const sections: string[] = [];

  // Mood and energy context
  if (context.mood) {
    const moodGuidance = getMoodSpecificGuidance(
      context.mood.label,
      exerciseType,
    );
    sections.push(`CURRENT USER STATE:
- Emotional state: ${context.mood.label}
- Energy level: ${context.mood.level}/10
- Time of day: ${context.timeOfDay}

${moodGuidance}`);
  } else {
    sections.push(`TIME OF DAY: ${context.timeOfDay}
Create a ${context.timeOfDay === "morning" ? "energizing and uplifting" : context.timeOfDay === "evening" ? "calming and reflective" : "balanced"} exercise suitable for ${context.timeOfDay}.`);
  }

  // Personalization preferences
  if (context.preferences.imagery.length > 0) {
    sections.push(`PERSONALIZATION:
- Incorporate these imagery themes naturally: ${context.preferences.imagery.join(", ")}
- Guidance level: ${context.preferences.guidanceLevel} (${getGuidanceLevelDescription(context.preferences.guidanceLevel)})
- Voice tone: ${context.preferences.voicePreference}
${context.preferences.avoidThemes.length > 0 ? `- AVOID these themes: ${context.preferences.avoidThemes.join(", ")}` : ""}`);
  }

  // Duration specification
  if (duration) {
    sections.push(
      `DURATION: Approximately ${duration} seconds (${Math.floor(duration / 60)} minutes)`,
    );
  }

  return sections.join("\n\n");
}

/**
 * Build diversity requirement to avoid repetition
 */
function buildDiversityRequirement(
  recentExercises: GenerationContext["recentExercises"],
): string {
  if (recentExercises.length === 0) {
    return "";
  }

  const recentTitles = recentExercises.slice(0, 5).map((ex) => ex.title);

  return `DIVERSITY REQUIREMENT:
The user recently completed these exercises:
${recentTitles.map((title) => `- "${title}"`).join("\n")}

You MUST create something different. Use different themes, metaphors, and imagery. DO NOT repeat recent titles or core themes. Be creative and original.`;
}

/**
 * Get mood-specific guidance for each exercise type
 */
function getMoodSpecificGuidance(mood: string, exerciseType: string): string {
  const guidanceMatrix: Record<string, Record<string, string>> = {
    anxious: {
      breathing:
        "Use extended exhale patterns (inhale 4s, exhale 6-8s). Emphasize safety, grounding, and settling. Avoid rapid breathing.",
      meditation:
        "Focus on present-moment awareness and body grounding. Avoid future-focused visualizations that may increase worry.",
      grounding:
        "Use 5-4-3-2-1 sensory technique with emphasis on tactile sensations. Slow pace, reassuring tone.",
      journaling:
        "Prompts should gently explore worries without amplifying them. Include grounding reflection questions.",
    },
    sad: {
      breathing:
        "Gentle, compassionate pacing. Avoid overly energizing patterns. Equal inhale/exhale with gentle holds.",
      meditation:
        "Self-compassion focus. Acknowledge feelings without trying to fix them. Warm, supportive tone.",
      grounding:
        "Focus on comforting sensations (soft textures, warm objects). Present-moment awareness.",
      journaling:
        "Prompts that validate emotions and gently encourage self-compassion. Avoid toxic positivity.",
    },
    tired: {
      breathing:
        "Energizing patterns: equal inhale/exhale (4-4), no long holds. Slightly faster pace.",
      meditation:
        "Short, focused practice. Body awareness without inducing sleep. Gentle energizing imagery.",
      grounding:
        "Standing exercises if possible. Cool sensations (fresh air, water). Movement-based grounding.",
      journaling:
        "Brief, simple prompts. Focus on small wins and energy sources.",
    },
    stressed: {
      breathing:
        "Progressive relaxation. Start slow (4-7-8), deepen gradually. Extended exhales to activate parasympathetic system.",
      meditation:
        "Release tension visualization. Body scan with letting-go cues. Spacious imagery.",
      grounding:
        "Environment-based grounding. Safe space awareness. Slow, deliberate sensory focus.",
      journaling:
        "Prompts for stress mapping and reframing. Action-oriented reflection questions.",
    },
    angry: {
      breathing:
        "Cooling breath patterns. Extended exhales. Avoid rapid breathing that may escalate activation.",
      meditation:
        "Release and transform anger imagery. Physical tension release cues. Grounding and cooling.",
      grounding:
        "Physical grounding (feet on floor, hands on surfaces). Cool sensations. Firm, clear guidance.",
      journaling:
        "Safe expression prompts. Exploring root causes. Action planning for resolution.",
    },
  };

  const moodKey = mood.toLowerCase();
  const guidance = guidanceMatrix[moodKey]?.[exerciseType];

  if (guidance) {
    return `MOOD-SPECIFIC GUIDANCE:\n${guidance}`;
  }

  // Default guidance
  return "Create a balanced, calming exercise suitable for general wellness and emotional regulation.";
}

/**
 * Get description for guidance level
 */
function getGuidanceLevelDescription(level: string): string {
  const descriptions: Record<string, string> = {
    minimal: "Quiet spaces for self-paced practice, minimal verbal guidance",
    moderate: "Balanced guidance with pauses, not too verbose",
    detailed: "Step-by-step instructions with clear cues and checkpoints",
  };

  return descriptions[level] || "balanced";
}
