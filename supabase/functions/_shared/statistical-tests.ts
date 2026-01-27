/**
 * Longitudinal Intelligence - Statistical Tests
 * Implements t-test, ANOVA, and linear regression for pattern detection
 */

/**
 * Result of a statistical test
 */
export interface StatisticalTestResult {
  statistic: number;
  pValue: number;
  significant: boolean; // p < 0.05
  confidence: number; // 1 - pValue, bounded [0, 1]
}

/**
 * Two-sample t-test (Welch's t-test for unequal variances)
 * Used for comparing weekday vs weekend moods
 * @param group1 - First group of values
 * @param group2 - Second group of values
 * @returns Test result with t-statistic and p-value
 */
export function tTest(
  group1: number[],
  group2: number[],
): StatisticalTestResult {
  const n1 = group1.length;
  const n2 = group2.length;

  // Require minimum sample size
  if (n1 < 3 || n2 < 3) {
    return { statistic: 0, pValue: 1, significant: false, confidence: 0 };
  }

  const mean1 = group1.reduce((a, b) => a + b, 0) / n1;
  const mean2 = group2.reduce((a, b) => a + b, 0) / n2;

  const var1 =
    group1.reduce((sum, x) => sum + Math.pow(x - mean1, 2), 0) / (n1 - 1);
  const var2 =
    group2.reduce((sum, x) => sum + Math.pow(x - mean2, 2), 0) / (n2 - 1);

  // Handle zero variance case
  if (var1 === 0 && var2 === 0) {
    return { statistic: 0, pValue: 1, significant: false, confidence: 0 };
  }

  const se = Math.sqrt(var1 / n1 + var2 / n2);
  if (se === 0) {
    return { statistic: 0, pValue: 1, significant: false, confidence: 0 };
  }

  const t = (mean1 - mean2) / se;

  // Welch-Satterthwaite degrees of freedom
  const v1 = var1 / n1;
  const v2 = var2 / n2;
  const df =
    Math.pow(v1 + v2, 2) /
    (Math.pow(v1, 2) / (n1 - 1) + Math.pow(v2, 2) / (n2 - 1));

  // Calculate p-value using t-distribution approximation
  const pValue = tDistributionPValue(Math.abs(t), df);

  return {
    statistic: Math.round(t * 1000) / 1000,
    pValue: Math.round(pValue * 1000) / 1000,
    significant: pValue < 0.05,
    confidence: Math.min(1, Math.max(0, 1 - pValue)),
  };
}

/**
 * One-way ANOVA (F-test)
 * Used for comparing seasonal mood groups
 * @param groups - Array of groups, each containing numeric values
 * @returns Test result with F-statistic and p-value
 */
export function anova(groups: number[][]): StatisticalTestResult {
  // Require at least 2 groups with minimum samples
  const validGroups = groups.filter((g) => g.length >= 2);
  if (validGroups.length < 2) {
    return { statistic: 0, pValue: 1, significant: false, confidence: 0 };
  }

  const k = validGroups.length;
  const allValues = validGroups.flat();
  const n = allValues.length;

  if (n < k + 2) {
    return { statistic: 0, pValue: 1, significant: false, confidence: 0 };
  }

  const grandMean = allValues.reduce((a, b) => a + b, 0) / n;

  // Calculate group means
  const groupMeans = validGroups.map(
    (g) => g.reduce((a, b) => a + b, 0) / g.length,
  );

  // Between-group sum of squares (SSB)
  const ssb = validGroups.reduce((sum, group, i) => {
    return sum + group.length * Math.pow(groupMeans[i] - grandMean, 2);
  }, 0);

  // Within-group sum of squares (SSW)
  const ssw = validGroups.reduce((sum, group, i) => {
    return sum + group.reduce((s, x) => s + Math.pow(x - groupMeans[i], 2), 0);
  }, 0);

  // Degrees of freedom
  const dfBetween = k - 1;
  const dfWithin = n - k;

  if (dfWithin <= 0 || ssw === 0) {
    return { statistic: 0, pValue: 1, significant: false, confidence: 0 };
  }

  // Mean squares
  const msb = ssb / dfBetween;
  const msw = ssw / dfWithin;

  // F-statistic
  const f = msw > 0 ? msb / msw : 0;

  // Calculate p-value using F-distribution approximation
  const pValue = fDistributionPValue(f, dfBetween, dfWithin);

  return {
    statistic: Math.round(f * 1000) / 1000,
    pValue: Math.round(pValue * 1000) / 1000,
    significant: pValue < 0.05,
    confidence: Math.min(1, Math.max(0, 1 - pValue)),
  };
}

/**
 * Linear regression with significance test
 * Used for detecting improvement/decline trends
 * @param x - Independent variable (e.g., week number)
 * @param y - Dependent variable (e.g., mood values)
 * @returns Regression result with slope, intercept, and significance
 */
export interface LinearRegressionResult extends StatisticalTestResult {
  slope: number;
  intercept: number;
  rSquared: number;
}

export function linearRegression(
  x: number[],
  y: number[],
): LinearRegressionResult {
  const n = x.length;

  if (n < 4 || n !== y.length) {
    return {
      statistic: 0,
      pValue: 1,
      significant: false,
      confidence: 0,
      slope: 0,
      intercept: 0,
      rSquared: 0,
    };
  }

  const meanX = x.reduce((a, b) => a + b, 0) / n;
  const meanY = y.reduce((a, b) => a + b, 0) / n;

  // Calculate slope and intercept
  let numerator = 0;
  let denominator = 0;

  for (let i = 0; i < n; i++) {
    numerator += (x[i] - meanX) * (y[i] - meanY);
    denominator += Math.pow(x[i] - meanX, 2);
  }

  if (denominator === 0) {
    return {
      statistic: 0,
      pValue: 1,
      significant: false,
      confidence: 0,
      slope: 0,
      intercept: meanY,
      rSquared: 0,
    };
  }

  const slope = numerator / denominator;
  const intercept = meanY - slope * meanX;

  // Calculate R-squared
  let ssRes = 0;
  let ssTot = 0;

  for (let i = 0; i < n; i++) {
    const predicted = slope * x[i] + intercept;
    ssRes += Math.pow(y[i] - predicted, 2);
    ssTot += Math.pow(y[i] - meanY, 2);
  }

  const rSquared = ssTot > 0 ? 1 - ssRes / ssTot : 0;

  // Calculate t-statistic for slope significance
  const se = Math.sqrt(ssRes / (n - 2));
  const slopeStdErr = se / Math.sqrt(denominator);

  const t = slopeStdErr > 0 ? slope / slopeStdErr : 0;
  const pValue = tDistributionPValue(Math.abs(t), n - 2);

  return {
    statistic: Math.round(t * 1000) / 1000,
    pValue: Math.round(pValue * 1000) / 1000,
    significant: pValue < 0.05,
    confidence: Math.min(1, Math.max(0, 1 - pValue)),
    slope: Math.round(slope * 10000) / 10000,
    intercept: Math.round(intercept * 100) / 100,
    rSquared: Math.round(rSquared * 1000) / 1000,
  };
}

/**
 * Approximate p-value from t-distribution
 * Uses the approximation for two-tailed test
 * @param t - t-statistic (absolute value)
 * @param df - degrees of freedom
 * @returns Approximate p-value
 */
function tDistributionPValue(t: number, df: number): number {
  if (df <= 0 || !isFinite(t)) return 1;

  // Use normal approximation for large df
  if (df > 100) {
    return 2 * (1 - normalCDF(Math.abs(t)));
  }

  // Beta function approximation for smaller df
  const x = df / (df + t * t);
  const p = incompleteBeta(x, df / 2, 0.5);

  return Math.min(1, Math.max(0, p));
}

/**
 * Approximate p-value from F-distribution
 * @param f - F-statistic
 * @param df1 - numerator degrees of freedom
 * @param df2 - denominator degrees of freedom
 * @returns Approximate p-value
 */
function fDistributionPValue(f: number, df1: number, df2: number): number {
  if (df1 <= 0 || df2 <= 0 || !isFinite(f) || f < 0) return 1;

  const x = df2 / (df2 + df1 * f);
  const p = incompleteBeta(x, df2 / 2, df1 / 2);

  return Math.min(1, Math.max(0, p));
}

/**
 * Standard normal CDF approximation
 * @param x - z-score
 * @returns Cumulative probability
 */
function normalCDF(x: number): number {
  // Approximation using error function
  const a1 = 0.254829592;
  const a2 = -0.284496736;
  const a3 = 1.421413741;
  const a4 = -1.453152027;
  const a5 = 1.061405429;
  const p = 0.3275911;

  const sign = x < 0 ? -1 : 1;
  x = Math.abs(x) / Math.sqrt(2);

  const t = 1.0 / (1.0 + p * x);
  const y =
    1.0 - ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * Math.exp(-x * x);

  return 0.5 * (1.0 + sign * y);
}

/**
 * Incomplete beta function approximation
 * Used for t and F distribution p-values
 * @param x - upper limit of integration
 * @param a - alpha parameter
 * @param b - beta parameter
 * @returns Approximate regularized incomplete beta function
 */
function incompleteBeta(x: number, a: number, b: number): number {
  if (x <= 0) return 0;
  if (x >= 1) return 1;

  // Use continued fraction representation
  const maxIterations = 100;
  const epsilon = 1e-10;

  // Use series expansion for small x
  if (x < (a + 1) / (a + b + 2)) {
    return (
      (betaCF(x, a, b) * Math.pow(x, a) * Math.pow(1 - x, b)) / (a * beta(a, b))
    );
  } else {
    return (
      1 -
      (betaCF(1 - x, b, a) * Math.pow(1 - x, b) * Math.pow(x, a)) /
        (b * beta(a, b))
    );
  }
}

/**
 * Continued fraction for incomplete beta
 */
function betaCF(x: number, a: number, b: number): number {
  const maxIterations = 100;
  const epsilon = 1e-10;

  let am = 1,
    bm = 1,
    az = 1;
  const qab = a + b;
  const qap = a + 1;
  const qam = a - 1;
  let bz = 1 - (qab * x) / qap;

  for (let m = 1; m <= maxIterations; m++) {
    const em = m;
    const tem = em + em;
    let d = (em * (b - m) * x) / ((qam + tem) * (a + tem));
    const ap = az + d * am;
    const bp = bz + d * bm;
    d = (-(a + em) * (qab + em) * x) / ((a + tem) * (qap + tem));
    const app = ap + d * az;
    const bpp = bp + d * bz;
    const aold = az;
    am = ap / bpp;
    bm = bp / bpp;
    az = app / bpp;
    bz = 1;
    if (Math.abs(az - aold) < epsilon * Math.abs(az)) {
      return az;
    }
  }

  return az;
}

/**
 * Beta function approximation using log gamma
 */
function beta(a: number, b: number): number {
  return Math.exp(logGamma(a) + logGamma(b) - logGamma(a + b));
}

/**
 * Log gamma function approximation (Lanczos)
 */
function logGamma(x: number): number {
  const g = 7;
  const c = [
    0.99999999999980993, 676.5203681218851, -1259.1392167224028,
    771.32342877765313, -176.61502916214059, 12.507343278686905,
    -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7,
  ];

  if (x < 0.5) {
    return Math.log(Math.PI / Math.sin(Math.PI * x)) - logGamma(1 - x);
  }

  x -= 1;
  let a = c[0];
  for (let i = 1; i < g + 2; i++) {
    a += c[i] / (x + i);
  }

  const t = x + g + 0.5;
  return (
    0.5 * Math.log(2 * Math.PI) + (x + 0.5) * Math.log(t) - t + Math.log(a)
  );
}

/**
 * Paired t-test for dependent samples
 * Used for comparing same users across different conditions
 * @param before - Values before condition
 * @param after - Values after condition
 * @returns Test result
 */
export function pairedTTest(
  before: number[],
  after: number[],
): StatisticalTestResult {
  if (before.length !== after.length || before.length < 3) {
    return { statistic: 0, pValue: 1, significant: false, confidence: 0 };
  }

  const differences = before.map((b, i) => after[i] - b);
  const n = differences.length;
  const meanDiff = differences.reduce((a, b) => a + b, 0) / n;
  const variance =
    differences.reduce((sum, d) => sum + Math.pow(d - meanDiff, 2), 0) /
    (n - 1);

  if (variance === 0) {
    return { statistic: 0, pValue: 1, significant: false, confidence: 0 };
  }

  const se = Math.sqrt(variance / n);
  const t = meanDiff / se;
  const pValue = tDistributionPValue(Math.abs(t), n - 1);

  return {
    statistic: Math.round(t * 1000) / 1000,
    pValue: Math.round(pValue * 1000) / 1000,
    significant: pValue < 0.05,
    confidence: Math.min(1, Math.max(0, 1 - pValue)),
  };
}
