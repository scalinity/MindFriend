import { assertEquals } from "jsr:@std/assert@1.0.19";
import { generateDailyActions } from "./actions.ts";
import { currentSourceTransactions } from "../calculate-debt-score/source-transactions.ts";
import type { UserProfile } from "../_shared/wellbeing-debt-types.ts";

const owner = "11111111-1111-4111-8111-111111111111";
const profile = {
  top_drains: { categories: [{ category: "poor_sleep" }, { category: "social_isolation" }] },
  top_deposits: { categories: [] },
} as unknown as UserProfile;
const exercises = [{ id: "exercise", title: "Breathing", type: "breathing", duration_minutes: 5, difficulty_level: "beginner" }];

// Read-only synthetic source records; no service or account is contacted.
function fixture(tables: Record<string, Record<string, any>[]>) {
  return { from(table: string) {
    let rows = tables[table] ?? [];
    let single = false;
    const query: any = {
      select: () => query, order: () => query,
      eq: (key: string, value: any) => { rows = rows.filter(r => r[key] === value); return query; },
      gte: (key: string, value: any) => { rows = rows.filter(r => r[key] >= value); return query; },
      lte: (key: string, value: any) => { rows = rows.filter(r => r[key] <= value); return query; },
      lt: (key: string, value: any) => { rows = rows.filter(r => r[key] < value); return query; },
      range: (start: number, end: number) => { rows = rows.slice(start, end + 1); return query; },
      single: () => { single = true; return query; },
      then: (resolve: any) => Promise.resolve({ data: single ? rows[0] : rows, error: null }).then(resolve),
    };
    return query;
  }};
}

Deno.test("generated supported plan points equal recalculated source deposits", async () => {
  const plans = generateDailyActions("2026-11-01", profile, exercises, 30, "moderate");
  assertEquals(plans.length, 7);
  for (const plan of plans) {
    const tables: Record<string, Record<string, any>[]> = {
      profiles: [{ id: owner, created_at: "2025-01-01T00:00:00Z" }],
      moods: [{ id: "mood", user_id: owner, local_date: plan.date, mood_score: 9 }],
    };
    for (const [index, action] of plan.actions.entries()) {
      if (action.source === "healthkit" || action.source === "mood_log") {
        assertEquals(action.target_points, 0, "Guidance without a supported deposit must not promise points");
        continue;
      }
      const row = { id: `${index}`, user_id: owner, completed_at: `${plan.date}T12:00:00.000Z`, created_at: `${plan.date}T12:00:00.000Z`, local_date: plan.date, status: "completed" };
      (tables[action.source] ??= []).push(row);
    }
    const transactions = await currentSourceTransactions(fixture(tables), owner, plan.date, "UTC");
    const promised = plan.actions.reduce((sum, a) => sum + a.target_points, 0);
    assertEquals(transactions.filter(t => t.type === "deposit").reduce((sum, t) => sum + t.amount, 0), promised);
    assertEquals(transactions.some(t => t.source === "mood_log"), false);
    for (const action of plan.actions.filter(a => a.source === "exercise_sessions")) {
      assertEquals(action.category, "exercise_completion");
      assertEquals(action.target_points, 8);
    }
  }
});

Deno.test("social point promise states the existing daily cap", () => {
  const actions = generateDailyActions("2026-11-01", profile, exercises, 0, "gentle")[0].actions;
  const social = actions.find(a => a.source === "circle_posts")!;
  assertEquals(social.target_points, 3);
  assertEquals(social.action.includes("up to 12 points per day"), true);
  assertEquals(actions.find(a => a.source === "quests")?.target_points, 8);
});
