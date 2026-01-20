import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildFallbackItems,
  buildQuestItem,
  isPlanInRange,
  type ExerciseRow,
  type PlanSize,
  type QuestRow,
} from "../_shared/action-autopilot.ts";

const exercises: ExerciseRow[] = [
  { id: "1", title: "Breath", type: "breathing", duration_seconds: 180 },
  { id: "2", title: "Ground", type: "grounding", duration_seconds: 120 },
  { id: "3", title: "Journal", type: "journaling", duration_seconds: 300 },
  { id: "4", title: "Move", type: "movement", duration_seconds: 180 },
  { id: "5", title: "Meditate", type: "meditation", duration_seconds: 300 },
];

const quest: QuestRow = {
  id: "quest-1",
  quest_templates: { title: "Daily Quest", estimated_minutes: 5 },
};

function assertPlan(planSize: PlanSize, itemsCountMin: number) {
  const questItem = buildQuestItem(quest);
  const items = buildFallbackItems(planSize, questItem, exercises);
  assertEquals(items.length >= itemsCountMin, true);
  assertEquals(isPlanInRange(planSize, items), true);
}

Deno.test("fallback plan quick range", () => {
  assertPlan("quick", 2);
});

Deno.test("fallback plan standard range", () => {
  assertPlan("standard", 2);
});
