export type PlanSize = "quick" | "standard";
export type PlanSourceType = "mood_checkin" | "weekly_summary" | "manual";
export type PlanItemType = "quest" | "exercise" | "chat";

export interface PlanItemDraft {
  itemType: PlanItemType;
  referenceId: string | null;
  title: string;
  durationMinutes: number;
}

export interface ExerciseRow {
  id: string;
  title: string;
  type: string;
  duration_seconds: number | null;
}

export interface QuestRow {
  id: string;
  quest_templates: {
    title: string | null;
    estimated_minutes: number | null;
  } | null;
}

const EXERCISE_TYPE_ORDER = [
  "breathing",
  "grounding",
  "journaling",
  "movement",
  "meditation",
];

const PLAN_RANGES: Record<PlanSize, { min: number; max: number; targetCount: number }> = {
  quick: { min: 5, max: 8, targetCount: 2 },
  standard: { min: 10, max: 15, targetCount: 3 },
};

export function isPlanInRange(planSize: PlanSize, items: PlanItemDraft[]): boolean {
  const range = getPlanRange(planSize);
  const total = items.reduce((sum, item) => sum + item.durationMinutes, 0);
  return items.length >= 2 && items.length <= 4 && total >= range.min && total <= range.max;
}

export function normalizePlanSize(value: unknown): PlanSize | null {
  if (value === "quick" || value === "standard") {
    return value;
  }
  return null;
}

export function normalizeSourceType(value: unknown): PlanSourceType | null {
  if (value === "mood_checkin" || value === "weekly_summary" || value === "manual") {
    return value;
  }
  return null;
}

export function getPlanRange(planSize: PlanSize) {
  return PLAN_RANGES[planSize];
}

export function getLocalDate(timezone: string): string {
  try {
    const formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    return formatter.format(new Date());
  } catch {
    return new Date().toISOString().split("T")[0];
  }
}

export function minutesFromSeconds(seconds: number | null): number {
  if (!seconds || seconds <= 0) {
    return 5;
  }
  return Math.max(1, Math.ceil(seconds / 60));
}

export function buildQuestItem(quest: QuestRow | null): PlanItemDraft | null {
  if (!quest?.quest_templates?.title) {
    return null;
  }
  const minutes = quest.quest_templates.estimated_minutes ?? 5;
  return {
    itemType: "quest",
    referenceId: quest.id,
    title: quest.quest_templates.title,
    durationMinutes: Math.max(1, minutes),
  };
}

export function buildExerciseItem(exercise: ExerciseRow): PlanItemDraft {
  return {
    itemType: "exercise",
    referenceId: exercise.id,
    title: exercise.title,
    durationMinutes: minutesFromSeconds(exercise.duration_seconds),
  };
}

export function sortExercises(exercises: ExerciseRow[]): ExerciseRow[] {
  const order = new Map(EXERCISE_TYPE_ORDER.map((type, index) => [type, index]));
  return [...exercises].sort((a, b) => {
    const orderA = order.get(a.type) ?? EXERCISE_TYPE_ORDER.length;
    const orderB = order.get(b.type) ?? EXERCISE_TYPE_ORDER.length;
    if (orderA !== orderB) {
      return orderA - orderB;
    }
    return a.title.localeCompare(b.title);
  });
}

function totalMinutes(items: PlanItemDraft[]): number {
  return items.reduce((sum, item) => sum + item.durationMinutes, 0);
}

function appendExercises(
  items: PlanItemDraft[],
  exercises: ExerciseRow[],
  maxCount: number,
  maxMinutes?: number,
) {
  let total = totalMinutes(items);
  for (const exercise of exercises) {
    if (items.length >= maxCount) {
      return;
    }
    if (items.some((item) => item.referenceId === exercise.id)) {
      continue;
    }
    const nextItem = buildExerciseItem(exercise);
    if (maxMinutes !== undefined && total + nextItem.durationMinutes > maxMinutes) {
      continue;
    }
    items.push(nextItem);
    total += nextItem.durationMinutes;
  }
}

export function buildFallbackItems(
  planSize: PlanSize,
  questItem: PlanItemDraft | null,
  exercises: ExerciseRow[],
): PlanItemDraft[] {
  const range = getPlanRange(planSize);
  const ordered = sortExercises(exercises);

  const buildWithQuest = (includeQuest: boolean) => {
    let items: PlanItemDraft[] = [];
    if (includeQuest && questItem) {
      items.push(questItem);
    }

    appendExercises(items, ordered, 4, range.max);
    return items;
  };

  let items = buildWithQuest(planSize === "standard");
  let total = totalMinutes(items);

  if (items.length < 2 || total < range.min) {
    items = buildWithQuest(false);
    total = totalMinutes(items);
  }

  while (items.length < 2 && total + 2 <= range.max) {
    items.push({
      itemType: "chat",
      referenceId: null,
      title: "Check in with MindFriend",
      durationMinutes: 2,
    });
    total += 2;
  }

  if (total < range.min) {
    appendExercises(items, ordered, 4, range.max);
  }

  if (items.length > 4) {
    items = items.slice(0, 4);
  }

  return items;
}
