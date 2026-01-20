/**
 * Ritual Prompts - Hardcoded prompt sequences for each ritual type
 *
 * Each ritual type has a fixed set of prompts with specific durations.
 * Total duration for all types is 180 seconds (3 minutes).
 */

export type RitualType = "gratitude" | "grounding" | "wins" | "breathing";

export interface RitualStep {
  duration: number; // seconds
  prompt: string;
}

export interface RitualPromptSequence {
  type: RitualType;
  totalDuration: number;
  steps: RitualStep[];
}

/**
 * Gratitude Ritual (180s total)
 * 3 prompts × 60s each
 */
const GRATITUDE_PROMPTS: RitualPromptSequence = {
  type: "gratitude",
  totalDuration: 180,
  steps: [
    {
      duration: 60,
      prompt: "What's something small that brought you joy today?",
    },
    { duration: 60, prompt: "Who's someone you're grateful for right now?" },
    {
      duration: 60,
      prompt: "What's going well in your life, even if it's tiny?",
    },
  ],
};

/**
 * Grounding Ritual (180s total)
 * 4 prompts × 45s each (5-4-3-2-1 technique without smell)
 */
const GROUNDING_PROMPTS: RitualPromptSequence = {
  type: "grounding",
  totalDuration: 180,
  steps: [
    { duration: 45, prompt: "Name 5 things you can see around you" },
    { duration: 45, prompt: "Name 4 things you can touch right now" },
    { duration: 45, prompt: "Name 3 things you can hear" },
    { duration: 45, prompt: "Take 3 slow breaths and notice how you feel" },
  ],
};

/**
 * Wins Ritual (180s total)
 * 3 prompts × 60s each
 */
const WINS_PROMPTS: RitualPromptSequence = {
  type: "wins",
  totalDuration: 180,
  steps: [
    { duration: 60, prompt: "What's one thing you accomplished today?" },
    { duration: 60, prompt: "What challenge did you overcome this week?" },
    { duration: 60, prompt: "What progress are you proud of?" },
  ],
};

/**
 * Breathing Ritual (180s total)
 * 5 cycles × 36s each (box breathing)
 */
const BREATHING_PROMPTS: RitualPromptSequence = {
  type: "breathing",
  totalDuration: 180,
  steps: [
    {
      duration: 36,
      prompt: "Breathe in for 4... Hold for 4... Out for 4... Hold for 4",
    },
    {
      duration: 36,
      prompt: "Breathe in for 4... Hold for 4... Out for 4... Hold for 4",
    },
    {
      duration: 36,
      prompt: "Breathe in for 4... Hold for 4... Out for 4... Hold for 4",
    },
    {
      duration: 36,
      prompt: "Breathe in for 4... Hold for 4... Out for 4... Hold for 4",
    },
    {
      duration: 36,
      prompt: "Breathe in for 4... Hold for 4... Out for 4... Hold for 4",
    },
  ],
};

/**
 * Map of all ritual types to their prompt sequences
 */
export const RITUAL_PROMPTS: Record<RitualType, RitualPromptSequence> = {
  gratitude: GRATITUDE_PROMPTS,
  grounding: GROUNDING_PROMPTS,
  wins: WINS_PROMPTS,
  breathing: BREATHING_PROMPTS,
};

/**
 * Get the prompt sequence for a ritual type
 */
export function getRitualPrompts(type: RitualType): RitualPromptSequence {
  const sequence = RITUAL_PROMPTS[type];
  if (!sequence) {
    throw new Error(`Unknown ritual type: ${type}`);
  }
  return sequence;
}

/**
 * Calculate the current step based on elapsed time
 */
export function calculateCurrentStep(
  type: RitualType,
  elapsedSeconds: number,
): {
  stepIndex: number;
  prompt: string;
  timeRemaining: number;
  completed: boolean;
} | null {
  const sequence = RITUAL_PROMPTS[type];
  if (!sequence) {
    return null;
  }

  // If ritual has completed
  if (elapsedSeconds >= sequence.totalDuration) {
    const lastStep = sequence.steps[sequence.steps.length - 1];
    return {
      stepIndex: sequence.steps.length - 1,
      prompt: lastStep.prompt,
      timeRemaining: 0,
      completed: true,
    };
  }

  // Find the current step
  let accumulatedTime = 0;
  for (let i = 0; i < sequence.steps.length; i++) {
    const step = sequence.steps[i];
    const stepEndTime = accumulatedTime + step.duration;

    if (elapsedSeconds < stepEndTime) {
      return {
        stepIndex: i,
        prompt: step.prompt,
        timeRemaining: stepEndTime - elapsedSeconds,
        completed: false,
      };
    }

    accumulatedTime = stepEndTime;
  }

  // Fallback (should not reach here)
  const lastStep = sequence.steps[sequence.steps.length - 1];
  return {
    stepIndex: sequence.steps.length - 1,
    prompt: lastStep.prompt,
    timeRemaining: 0,
    completed: true,
  };
}

/**
 * Get all ritual types as an array
 */
export const RITUAL_TYPES: RitualType[] = [
  "gratitude",
  "grounding",
  "wins",
  "breathing",
];

/**
 * Check if a value is a valid ritual type
 */
export function isValidRitualType(value: string): value is RitualType {
  return RITUAL_TYPES.includes(value as RitualType);
}
