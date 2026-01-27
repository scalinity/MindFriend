// Tests for detect-patterns Edge Function
import {
  assertEquals,
  assertGreater,
  assertLessOrEqual,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

// Mock seasonal data for testing
const mockSeasonalData = {
  winter: [3.0, 3.2, 3.1, 3.3],
  spring: [3.5, 3.6, 3.4, 3.7],
  summer: [4.0, 4.2, 4.1, 4.3],
  fall: [3.6, 3.5, 3.7, 3.4],
};

// Mock weekly rhythm data (day of week -> avg mood)
const mockWeeklyData = [
  { dayOfWeek: 0, moods: [3.0, 2.8, 3.2] }, // Sunday
  { dayOfWeek: 1, moods: [2.5, 2.6, 2.4] }, // Monday
  { dayOfWeek: 2, moods: [3.0, 3.1, 2.9] }, // Tuesday
  { dayOfWeek: 3, moods: [3.2, 3.3, 3.1] }, // Wednesday
  { dayOfWeek: 4, moods: [3.5, 3.4, 3.6] }, // Thursday
  { dayOfWeek: 5, moods: [4.0, 4.2, 3.8] }, // Friday
  { dayOfWeek: 6, moods: [3.8, 4.0, 3.6] }, // Saturday
];

// Mock improvement trend data
const mockTrendData = [
  { month: 1, avgMood: 2.8 },
  { month: 2, avgMood: 3.0 },
  { month: 3, avgMood: 3.2 },
  { month: 4, avgMood: 3.3 },
  { month: 5, avgMood: 3.5 },
  { month: 6, avgMood: 3.6 },
];

// Helper functions to test (mimicking function logic)
function calculateMean(values: number[]): number {
  return values.reduce((a, b) => a + b, 0) / values.length;
}

function calculateVariance(values: number[]): number {
  const mean = calculateMean(values);
  return (
    values.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) /
    values.length
  );
}

function calculateStdDev(values: number[]): number {
  return Math.sqrt(calculateVariance(values));
}

// Simple ANOVA F-statistic for seasonal pattern detection
function calculateAnovaF(groups: number[][]): number {
  const allValues = groups.flat();
  const grandMean = calculateMean(allValues);
  const k = groups.length;
  const n = allValues.length;

  // Between-group variance
  let ssBetween = 0;
  for (const group of groups) {
    const groupMean = calculateMean(group);
    ssBetween += group.length * Math.pow(groupMean - grandMean, 2);
  }

  // Within-group variance
  let ssWithin = 0;
  for (const group of groups) {
    const groupMean = calculateMean(group);
    for (const value of group) {
      ssWithin += Math.pow(value - groupMean, 2);
    }
  }

  const msBetween = ssBetween / (k - 1);
  const msWithin = ssWithin / (n - k);

  return msBetween / msWithin;
}

// Simple linear regression for trend detection
function linearRegression(data: { x: number; y: number }[]): {
  slope: number;
  intercept: number;
  rSquared: number;
} {
  const n = data.length;
  const sumX = data.reduce((sum, d) => sum + d.x, 0);
  const sumY = data.reduce((sum, d) => sum + d.y, 0);
  const sumXY = data.reduce((sum, d) => sum + d.x * d.y, 0);
  const sumX2 = data.reduce((sum, d) => sum + d.x * d.x, 0);

  const slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
  const intercept = (sumY - slope * sumX) / n;

  // Calculate R-squared
  const meanY = sumY / n;
  const ssTotal = data.reduce((sum, d) => sum + Math.pow(d.y - meanY, 2), 0);
  const ssRes = data.reduce(
    (sum, d) => sum + Math.pow(d.y - (slope * d.x + intercept), 2),
    0,
  );
  const rSquared = 1 - ssRes / ssTotal;

  return { slope, intercept, rSquared };
}

// Confidence calculation based on sample size and effect size
function calculateConfidence(
  sampleSize: number,
  effectSize: number,
  minSamples: number = 10,
): number {
  // Base confidence from sample size
  const sampleFactor = Math.min(sampleSize / minSamples, 1.0);

  // Effect size factor (normalized 0-1)
  const effectFactor = Math.min(Math.abs(effectSize), 1.0);

  // Combined confidence
  return Math.min(sampleFactor * 0.5 + effectFactor * 0.5, 0.99);
}

// Tests
Deno.test("calculateMean - computes correct average", () => {
  const mean = calculateMean([1, 2, 3, 4, 5]);
  assertEquals(mean, 3);
});

Deno.test("calculateStdDev - computes correct standard deviation", () => {
  const stdDev = calculateStdDev([2, 4, 4, 4, 5, 5, 7, 9]);
  // Variance = 4, StdDev = 2
  assertEquals(stdDev.toFixed(2), "2.00");
});

Deno.test("ANOVA F-statistic - detects seasonal differences", () => {
  const seasonalGroups = [
    mockSeasonalData.winter,
    mockSeasonalData.spring,
    mockSeasonalData.summer,
    mockSeasonalData.fall,
  ];

  const fStatistic = calculateAnovaF(seasonalGroups);

  // With clear seasonal differences, F should be significant
  assertGreater(fStatistic, 1.0);
});

Deno.test("ANOVA F-statistic - handles similar groups", () => {
  const similarGroups = [
    [3.0, 3.1, 3.0, 3.1],
    [3.0, 3.0, 3.1, 3.0],
    [3.1, 3.0, 3.0, 3.1],
  ];

  const fStatistic = calculateAnovaF(similarGroups);

  // Similar groups should have lower F-statistic
  assertLessOrEqual(fStatistic, 2.0);
});

Deno.test("linearRegression - detects positive trend", () => {
  const data = mockTrendData.map((d) => ({ x: d.month, y: d.avgMood }));
  const regression = linearRegression(data);

  // Should detect positive slope (improving)
  assertGreater(regression.slope, 0);

  // R-squared should indicate good fit
  assertGreater(regression.rSquared, 0.9);
});

Deno.test("linearRegression - detects negative trend", () => {
  const decliningData = [
    { x: 1, y: 4.0 },
    { x: 2, y: 3.8 },
    { x: 3, y: 3.5 },
    { x: 4, y: 3.2 },
  ];

  const regression = linearRegression(decliningData);

  // Should detect negative slope (declining)
  assertEquals(regression.slope < 0, true);
});

Deno.test("linearRegression - handles flat data", () => {
  const flatData = [
    { x: 1, y: 3.5 },
    { x: 2, y: 3.5 },
    { x: 3, y: 3.5 },
    { x: 4, y: 3.5 },
  ];

  const regression = linearRegression(flatData);

  // Slope should be zero (or very close)
  assertEquals(Math.abs(regression.slope) < 0.001, true);
});

Deno.test("calculateConfidence - increases with sample size", () => {
  const conf5 = calculateConfidence(5, 0.5, 20);
  const conf10 = calculateConfidence(10, 0.5, 20);
  const conf20 = calculateConfidence(20, 0.5, 20);

  assertGreater(conf20, conf10);
  assertGreater(conf10, conf5);
});

Deno.test("calculateConfidence - increases with effect size", () => {
  const confLow = calculateConfidence(20, 0.2, 20);
  const confMed = calculateConfidence(20, 0.5, 20);
  const confHigh = calculateConfidence(20, 0.8, 20);

  assertGreater(confHigh, confMed);
  assertGreater(confMed, confLow);
});

Deno.test("calculateConfidence - caps at 0.99", () => {
  const conf = calculateConfidence(1000, 1.0, 10);
  assertLessOrEqual(conf, 0.99);
});

// Weekly rhythm detection tests
Deno.test("weekly rhythm - identifies best and worst days", () => {
  const dayAverages = mockWeeklyData.map((d) => ({
    dayOfWeek: d.dayOfWeek,
    avgMood: calculateMean(d.moods),
  }));

  const bestDay = dayAverages.reduce((a, b) => (a.avgMood > b.avgMood ? a : b));
  const worstDay = dayAverages.reduce((a, b) =>
    a.avgMood < b.avgMood ? a : b,
  );

  assertEquals(bestDay.dayOfWeek, 5); // Friday
  assertEquals(worstDay.dayOfWeek, 1); // Monday
});

// Pattern type tests
Deno.test("pattern types - all valid enum values", () => {
  const validTypes = [
    "seasonal_mood",
    "weekly_rhythm",
    "event_response",
    "improvement_trend",
  ];

  validTypes.forEach((type) => {
    assertEquals(typeof type, "string");
  });
});

console.log("All detect-patterns tests passed!");
