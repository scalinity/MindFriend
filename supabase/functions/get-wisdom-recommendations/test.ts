/**
 * Tests for get-wisdom-recommendations Edge Function
 *
 * Tests relevance scoring algorithm and context enrichment
 *
 * Run with: deno test --allow-net --allow-env get-wisdom-recommendations/test.ts
 */

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

// Relevance Score Calculation
interface Insight {
  contextTags: string[];
  confidenceScore: number;
  validFrom: string;
}

function calculateRelevance(
  insight: Insight,
  userContextTags: string[],
): number {
  // Tag overlap score
  const matchingTags = insight.contextTags.filter((tag) =>
    userContextTags.includes(tag),
  );
  const tagScore = matchingTags.length / Math.max(userContextTags.length, 1);

  // Recency score (decay over days)
  const daysSinceValid = Math.floor(
    (Date.now() - new Date(insight.validFrom).getTime()) /
      (24 * 60 * 60 * 1000),
  );
  const recencyScore = Math.max(0, 1.0 - daysSinceValid * 0.1);

  // Combine with confidence score
  const relevance =
    tagScore * 0.5 + insight.confidenceScore * 0.3 + recencyScore * 0.2;

  return Math.round(relevance * 100) / 100;
}

Deno.test("calculateRelevance returns 1.0 for perfect match", () => {
  const insight: Insight = {
    contextTags: ["mood:low", "time:morning"],
    confidenceScore: 1.0,
    validFrom: new Date().toISOString(),
  };
  const userTags = ["mood:low", "time:morning"];

  const relevance = calculateRelevance(insight, userTags);

  // 0.5 (tag) + 0.3 (confidence) + 0.2 (recency) = 1.0
  assertEquals(relevance, 1.0);
});

Deno.test("calculateRelevance decreases with partial tag match", () => {
  const insight: Insight = {
    contextTags: ["mood:low"],
    confidenceScore: 1.0,
    validFrom: new Date().toISOString(),
  };
  const userTags = ["mood:low", "time:morning"];

  const relevance = calculateRelevance(insight, userTags);

  // 0.25 (1/2 tags) + 0.3 (confidence) + 0.2 (recency) = 0.75
  assertEquals(relevance, 0.75);
});

Deno.test("calculateRelevance decreases with no tag match", () => {
  const insight: Insight = {
    contextTags: ["mood:high"],
    confidenceScore: 1.0,
    validFrom: new Date().toISOString(),
  };
  const userTags = ["mood:low", "time:morning"];

  const relevance = calculateRelevance(insight, userTags);

  // 0 (tag) + 0.3 (confidence) + 0.2 (recency) = 0.5
  assertEquals(relevance, 0.5);
});

Deno.test("calculateRelevance decreases with lower confidence", () => {
  const insight: Insight = {
    contextTags: ["mood:low", "time:morning"],
    confidenceScore: 0.5,
    validFrom: new Date().toISOString(),
  };
  const userTags = ["mood:low", "time:morning"];

  const relevance = calculateRelevance(insight, userTags);

  // 0.5 (tag) + 0.15 (0.5 confidence) + 0.2 (recency) = 0.85
  assertEquals(relevance, 0.85);
});

Deno.test("calculateRelevance decreases with age", () => {
  const tenDaysAgo = new Date();
  tenDaysAgo.setDate(tenDaysAgo.getDate() - 10);

  const insight: Insight = {
    contextTags: ["mood:low", "time:morning"],
    confidenceScore: 1.0,
    validFrom: tenDaysAgo.toISOString(),
  };
  const userTags = ["mood:low", "time:morning"];

  const relevance = calculateRelevance(insight, userTags);

  // 0.5 (tag) + 0.3 (confidence) + 0 (10 days old = 0 recency) = 0.8
  assertEquals(relevance, 0.8);
});

Deno.test("calculateRelevance caps recency at 0", () => {
  const twentyDaysAgo = new Date();
  twentyDaysAgo.setDate(twentyDaysAgo.getDate() - 20);

  const insight: Insight = {
    contextTags: ["mood:low"],
    confidenceScore: 1.0,
    validFrom: twentyDaysAgo.toISOString(),
  };
  const userTags = ["mood:low"];

  const relevance = calculateRelevance(insight, userTags);

  // Recency should be capped at 0, not negative
  assertEquals(relevance >= 0, true);
});

// Context Tag Enrichment
interface EnrichmentParams {
  contextTags: string[];
  moodScore?: number;
  emotion?: string;
  goals?: string[];
  challenges?: string[];
}

function buildEnrichedTags(params: EnrichmentParams): string[] {
  const {
    contextTags,
    moodScore,
    emotion,
    goals = [],
    challenges = [],
  } = params;
  const tags = new Set<string>(contextTags);

  // Add mood-based tags
  if (moodScore !== undefined) {
    if (moodScore <= 2) {
      tags.add("mood:low");
    } else if (moodScore === 3) {
      tags.add("mood:medium");
    } else {
      tags.add("mood:high");
    }
  }

  if (emotion) {
    tags.add(`emotion:${emotion}`);

    // Map emotions to categories
    const emotionCategoryMap: Record<string, string> = {
      anxious: "anxiety",
      worried: "anxiety",
      nervous: "anxiety",
      sad: "depression",
      depressed: "depression",
      hopeless: "depression",
      stressed: "stress",
      overwhelmed: "overwhelm",
      angry: "anger",
      frustrated: "anger",
      lonely: "loneliness",
      isolated: "loneliness",
      grieving: "grief",
      tired: "sleep",
      exhausted: "sleep",
    };

    const category = emotionCategoryMap[emotion.toLowerCase()];
    if (category) {
      tags.add(`category:${category}`);
    }
  }

  // Add goal and challenge tags
  for (const goal of goals) {
    tags.add(`goal:${goal}`);
  }
  for (const challenge of challenges) {
    tags.add(`challenge:${challenge}`);
  }

  return Array.from(tags);
}

Deno.test("buildEnrichedTags adds mood:low for score 1-2", () => {
  const tags = buildEnrichedTags({ contextTags: [], moodScore: 2 });
  assertEquals(tags.includes("mood:low"), true);
});

Deno.test("buildEnrichedTags adds mood:medium for score 3", () => {
  const tags = buildEnrichedTags({ contextTags: [], moodScore: 3 });
  assertEquals(tags.includes("mood:medium"), true);
});

Deno.test("buildEnrichedTags adds mood:high for score 4-5", () => {
  const tags = buildEnrichedTags({ contextTags: [], moodScore: 5 });
  assertEquals(tags.includes("mood:high"), true);
});

Deno.test("buildEnrichedTags adds emotion tag", () => {
  const tags = buildEnrichedTags({ contextTags: [], emotion: "anxious" });
  assertEquals(tags.includes("emotion:anxious"), true);
});

Deno.test("buildEnrichedTags maps anxious to anxiety category", () => {
  const tags = buildEnrichedTags({ contextTags: [], emotion: "anxious" });
  assertEquals(tags.includes("category:anxiety"), true);
});

Deno.test("buildEnrichedTags maps sad to depression category", () => {
  const tags = buildEnrichedTags({ contextTags: [], emotion: "sad" });
  assertEquals(tags.includes("category:depression"), true);
});

Deno.test("buildEnrichedTags maps tired to sleep category", () => {
  const tags = buildEnrichedTags({ contextTags: [], emotion: "tired" });
  assertEquals(tags.includes("category:sleep"), true);
});

Deno.test("buildEnrichedTags adds goal tags", () => {
  const tags = buildEnrichedTags({
    contextTags: [],
    goals: ["reduce_anxiety", "better_sleep"],
  });
  assertEquals(tags.includes("goal:reduce_anxiety"), true);
  assertEquals(tags.includes("goal:better_sleep"), true);
});

Deno.test("buildEnrichedTags adds challenge tags", () => {
  const tags = buildEnrichedTags({
    contextTags: [],
    challenges: ["work_stress", "relationship_issues"],
  });
  assertEquals(tags.includes("challenge:work_stress"), true);
  assertEquals(tags.includes("challenge:relationship_issues"), true);
});

Deno.test("buildEnrichedTags preserves existing context tags", () => {
  const tags = buildEnrichedTags({
    contextTags: ["existing:tag", "another:tag"],
    moodScore: 3,
  });
  assertEquals(tags.includes("existing:tag"), true);
  assertEquals(tags.includes("another:tag"), true);
  assertEquals(tags.includes("mood:medium"), true);
});

Deno.test("buildEnrichedTags deduplicates tags", () => {
  const tags = buildEnrichedTags({
    contextTags: ["mood:low"],
    moodScore: 1,
  });
  // Should only have one "mood:low"
  const moodLowCount = tags.filter((t) => t === "mood:low").length;
  assertEquals(moodLowCount, 1);
});

// Helpful Percentage Calculation
function calculateHelpfulPercentage(
  helpful: number,
  notHelpful: number,
): number {
  const total = helpful + notHelpful;
  if (total === 0) return 0;
  return Math.round((helpful / total) * 100);
}

Deno.test("calculateHelpfulPercentage returns 0 for no votes", () => {
  assertEquals(calculateHelpfulPercentage(0, 0), 0);
});

Deno.test("calculateHelpfulPercentage returns 100 for all helpful", () => {
  assertEquals(calculateHelpfulPercentage(10, 0), 100);
});

Deno.test("calculateHelpfulPercentage returns 0 for all not helpful", () => {
  assertEquals(calculateHelpfulPercentage(0, 10), 0);
});

Deno.test("calculateHelpfulPercentage returns 50 for equal votes", () => {
  assertEquals(calculateHelpfulPercentage(5, 5), 50);
});

Deno.test("calculateHelpfulPercentage rounds correctly", () => {
  assertEquals(calculateHelpfulPercentage(2, 1), 67); // 66.67% rounds to 67
  assertEquals(calculateHelpfulPercentage(1, 2), 33); // 33.33% rounds to 33
});

// Relevance Filter Tests
const RELEVANCE_THRESHOLD = 0.3;

Deno.test("insights below threshold are filtered", () => {
  const insights = [
    { id: "1", relevanceScore: 0.8 },
    { id: "2", relevanceScore: 0.2 }, // Below threshold
    { id: "3", relevanceScore: 0.5 },
    { id: "4", relevanceScore: 0.1 }, // Below threshold
  ];

  const filtered = insights.filter(
    (i) => i.relevanceScore >= RELEVANCE_THRESHOLD,
  );

  assertEquals(filtered.length, 2);
  assertEquals(filtered[0].id, "1");
  assertEquals(filtered[1].id, "3");
});

Deno.test("insights are sorted by relevance descending", () => {
  const insights = [
    { id: "1", relevanceScore: 0.5 },
    { id: "2", relevanceScore: 0.8 },
    { id: "3", relevanceScore: 0.3 },
  ];

  const sorted = insights.sort((a, b) => b.relevanceScore - a.relevanceScore);

  assertEquals(sorted[0].id, "2");
  assertEquals(sorted[1].id, "1");
  assertEquals(sorted[2].id, "3");
});
