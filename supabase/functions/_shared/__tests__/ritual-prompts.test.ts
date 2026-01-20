/**
 * Unit tests for ritual-prompts.ts
 */

import {
  calculateCurrentStep,
  getRitualPrompts,
  isValidRitualType,
  RITUAL_PROMPTS,
} from "../ritual-prompts.ts";
import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

Deno.test("getRitualPrompts - returns correct prompts for gratitude", () => {
  const prompts = getRitualPrompts("gratitude");
  assertEquals(prompts.type, "gratitude");
  assertEquals(prompts.totalDuration, 180);
  assertEquals(prompts.steps.length, 3);
});

Deno.test("getRitualPrompts - returns correct prompts for grounding", () => {
  const prompts = getRitualPrompts("grounding");
  assertEquals(prompts.type, "grounding");
  assertEquals(prompts.totalDuration, 180);
  assertEquals(prompts.steps.length, 4);
});

Deno.test("getRitualPrompts - returns correct prompts for wins", () => {
  const prompts = getRitualPrompts("wins");
  assertEquals(prompts.type, "wins");
  assertEquals(prompts.totalDuration, 180);
  assertEquals(prompts.steps.length, 3);
});

Deno.test("getRitualPrompts - returns correct prompts for breathing", () => {
  const prompts = getRitualPrompts("breathing");
  assertEquals(prompts.type, "breathing");
  assertEquals(prompts.totalDuration, 180);
  assertEquals(prompts.steps.length, 5);
});

Deno.test("calculateCurrentStep - gratitude ritual step 1", () => {
  // Step 1 (0-60s)
  let result = calculateCurrentStep("gratitude", 0);
  assertEquals(result?.stepIndex, 0);
  assertEquals(result?.timeRemaining, 60);
  assertEquals(result?.completed, false);

  // Mid step 1 (30s)
  result = calculateCurrentStep("gratitude", 30);
  assertEquals(result?.stepIndex, 0);
  assertEquals(result?.timeRemaining, 30);
});

Deno.test("calculateCurrentStep - gratitude ritual step transition", () => {
  // Step boundary (60s) - transition to step 2
  let result = calculateCurrentStep("gratitude", 60);
  assertEquals(result?.stepIndex, 1);
  assertEquals(result?.timeRemaining, 60);

  // Step 2 (90s)
  result = calculateCurrentStep("gratitude", 90);
  assertEquals(result?.stepIndex, 1);
  assertEquals(result?.timeRemaining, 30);
});

Deno.test("calculateCurrentStep - gratitude ritual last step", () => {
  // Last step (150s)
  let result = calculateCurrentStep("gratitude", 150);
  assertEquals(result?.stepIndex, 2);
  assertEquals(result?.timeRemaining, 30);

  // Completed (180s)
  result = calculateCurrentStep("gratitude", 180);
  assertEquals(result?.completed, true);
  assertEquals(result?.timeRemaining, 0);
});

Deno.test("calculateCurrentStep - grounding ritual (45s steps)", () => {
  // Step 1 (0-45s)
  let result = calculateCurrentStep("grounding", 0);
  assertEquals(result?.stepIndex, 0);
  assertEquals(result?.timeRemaining, 45);

  // Step boundary (45s) - transition to step 2
  result = calculateCurrentStep("grounding", 45);
  assertEquals(result?.stepIndex, 1);
  assertEquals(result?.timeRemaining, 45);

  // Step 4 (135s)
  result = calculateCurrentStep("grounding", 135);
  assertEquals(result?.stepIndex, 3);
  assertEquals(result?.timeRemaining, 45);
});

Deno.test(
  "calculateCurrentStep - breathing ritual (36s steps, 5 cycles)",
  () => {
    // Verify 5 steps for breathing
    const prompts = getRitualPrompts("breathing");
    assertEquals(prompts.steps.length, 5);

    // Each step should be 36 seconds
    prompts.steps.forEach((step, index) => {
      assertEquals(step.duration, 36);
    });

    // Step 5 starts at 144s (4 * 36)
    let result = calculateCurrentStep("breathing", 144);
    assertEquals(result?.stepIndex, 4);

    // Last step ends at 180s
    result = calculateCurrentStep("breathing", 179);
    assertEquals(result?.stepIndex, 4);
  },
);

Deno.test("calculateCurrentStep - edge cases", () => {
  // Before ritual starts (0s)
  let result = calculateCurrentStep("gratitude", 0);
  assertEquals(result?.stepIndex, 0);

  // After total duration
  result = calculateCurrentStep("gratitude", 200);
  assertEquals(result?.completed, true);

  // Exactly at duration
  result = calculateCurrentStep("gratitude", 180);
  assertEquals(result?.completed, true);
});

Deno.test("calculateCurrentStep - invalid ritual type returns null", () => {
  const result = calculateCurrentStep("invalid" as "gratitude", 0);
  assertEquals(result, null);
});

Deno.test("isValidRitualType - validates correctly", () => {
  assertEquals(isValidRitualType("gratitude"), true);
  assertEquals(isValidRitualType("grounding"), true);
  assertEquals(isValidRitualType("wins"), true);
  assertEquals(isValidRitualType("breathing"), true);
  assertEquals(isValidRitualType("invalid"), false);
  assertEquals(isValidRitualType(""), false);
});

Deno.test("RITUAL_PROMPTS - all types have correct structure", () => {
  const types = ["gratitude", "grounding", "wins", "breathing"] as const;

  for (const type of types) {
    const prompts = RITUAL_PROMPTS[type];
    assertExists(prompts);
    assertEquals(prompts.type, type);
    assertEquals(typeof prompts.totalDuration, "number");
    assertEquals(Array.isArray(prompts.steps), true);
    assertEquals(prompts.steps.length > 0, true);

    // Each step should have duration and prompt
    for (const step of prompts.steps) {
      assertEquals(typeof step.duration, "number");
      assertEquals(typeof step.prompt, "string");
      assertEquals(step.prompt.length > 0, true);
    }
  }
});

Deno.test("All rituals have total duration of 180 seconds", () => {
  const types = ["gratitude", "grounding", "wins", "breathing"] as const;

  for (const type of types) {
    const prompts = getRitualPrompts(type);
    assertEquals(
      prompts.totalDuration,
      180,
      `Ritual ${type} should have total duration of 180 seconds`,
    );
  }
});

Deno.test("Step durations sum to total duration", () => {
  const types = ["gratitude", "grounding", "wins", "breathing"] as const;

  for (const type of types) {
    const prompts = getRitualPrompts(type);
    const sumDurations = prompts.steps.reduce(
      (sum, step) => sum + step.duration,
      0,
    );
    assertEquals(
      sumDurations,
      prompts.totalDuration,
      `Ritual ${type} step durations should sum to ${prompts.totalDuration}`,
    );
  }
});

Deno.test("Gratitude ritual has expected prompts", () => {
  const prompts = getRitualPrompts("gratitude");
  assertEquals(
    prompts.steps[0].prompt,
    "What's something small that brought you joy today?",
  );
  assertEquals(
    prompts.steps[1].prompt,
    "Who's someone you're grateful for right now?",
  );
  assertEquals(
    prompts.steps[2].prompt,
    "What's going well in your life, even if it's tiny?",
  );
});

Deno.test("Grounding ritual has expected prompts", () => {
  const prompts = getRitualPrompts("grounding");
  assertEquals(prompts.steps[0].prompt, "Name 5 things you can see around you");
  assertEquals(
    prompts.steps[1].prompt,
    "Name 4 things you can touch right now",
  );
  assertEquals(prompts.steps[2].prompt, "Name 3 things you can hear");
  assertEquals(
    prompts.steps[3].prompt,
    "Take 3 slow breaths and notice how you feel",
  );
});

Deno.test("Wins ritual has expected prompts", () => {
  const prompts = getRitualPrompts("wins");
  assertEquals(
    prompts.steps[0].prompt,
    "What's one thing you accomplished today?",
  );
  assertEquals(
    prompts.steps[1].prompt,
    "What challenge did you overcome this week?",
  );
  assertEquals(prompts.steps[2].prompt, "What progress are you proud of?");
});

Deno.test("Breathing ritual has expected prompts", () => {
  const prompts = getRitualPrompts("breathing");
  assertEquals(
    prompts.steps[0].prompt,
    "Breathe in for 4... Hold for 4... Out for 4... Hold for 4",
  );
  // All 5 steps should have the same breathing instruction
  prompts.steps.forEach((step, index) => {
    assertEquals(
      step.prompt,
      "Breathe in for 4... Hold for 4... Out for 4... Hold for 4",
    );
  });
});
