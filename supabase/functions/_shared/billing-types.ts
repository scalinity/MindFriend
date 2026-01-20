// Billing types and constants for monetization functions

export type PlanType = "individual" | "couples" | "family";
export type BillingPeriod = "monthly" | "annual";

export interface PlanDetails {
  planType: PlanType;
  billingPeriod: BillingPeriod;
  seatsTotal: number;
  badgeCode: string;
}

// Map product IDs to plan details
export const PRODUCT_PLAN_MAP: Record<string, PlanDetails> = {
  // Individual plans
  "com.mindfriend.premium.monthly": {
    planType: "individual",
    billingPeriod: "monthly",
    seatsTotal: 1,
    badgeCode: "premium_supporter",
  },
  "com.mindfriend.premium.yearly": {
    planType: "individual",
    billingPeriod: "annual",
    seatsTotal: 1,
    badgeCode: "annual_achiever",
  },
  // Couples plans
  "com.mindfriend.couples.monthly": {
    planType: "couples",
    billingPeriod: "monthly",
    seatsTotal: 2,
    badgeCode: "premium_supporter",
  },
  "com.mindfriend.couples.annual": {
    planType: "couples",
    billingPeriod: "annual",
    seatsTotal: 2,
    badgeCode: "annual_achiever",
  },
  // Family plans
  "com.mindfriend.family.monthly": {
    planType: "family",
    billingPeriod: "monthly",
    seatsTotal: 6,
    badgeCode: "premium_supporter",
  },
  "com.mindfriend.family.annual": {
    planType: "family",
    billingPeriod: "annual",
    seatsTotal: 6,
    badgeCode: "annual_achiever",
  },
};

// Default plan details for unknown products (fallback)
export const DEFAULT_PLAN: PlanDetails = {
  planType: "individual",
  billingPeriod: "monthly",
  seatsTotal: 1,
  badgeCode: "premium_supporter",
};

// Get plan details from product ID
export function getPlanDetails(productId: string): PlanDetails {
  return PRODUCT_PLAN_MAP[productId] || DEFAULT_PLAN;
}

// Check if plan is a family/couples plan
export function isFamilyPlan(planType: PlanType): boolean {
  return planType === "couples" || planType === "family";
}

// Generate an 8-character invite code using cryptographically secure random
export function generateInviteCode(): string {
  const chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  const randomBytes = new Uint8Array(8);
  crypto.getRandomValues(randomBytes);
  let result = "";
  for (let i = 0; i < 8; i++) {
    result += chars.charAt(randomBytes[i] % chars.length);
  }
  return result;
}

// Validate product ID is a known product
export function isValidProductId(productId: string): boolean {
  return productId in PRODUCT_PLAN_MAP;
}

// Get list of valid product IDs (for documentation/testing)
export const VALID_PRODUCT_IDS = Object.keys(
  PRODUCT_PLAN_MAP,
) as readonly string[];

// Calculate subscription expiry date
export function calculateExpiryDate(billingPeriod: BillingPeriod): Date {
  const now = new Date();
  if (billingPeriod === "annual") {
    now.setFullYear(now.getFullYear() + 1);
  } else {
    now.setMonth(now.getMonth() + 1);
  }
  return now;
}
