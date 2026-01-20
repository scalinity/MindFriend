// Couples Mode Shared Utilities
// Base58 encoding, SHA-256 hashing, type definitions, constants

const BASE58_ALPHABET =
  "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

/**
 * Encode a number to Base58 string
 * Used for generating human-friendly invite codes
 */
export function encodeBase58(num: bigint): string {
  if (num === 0n) return BASE58_ALPHABET[0];

  let encoded = "";
  while (num > 0n) {
    encoded = BASE58_ALPHABET[Number(num % 58n)] + encoded;
    num = num / 58n;
  }
  return encoded;
}

/**
 * Generate a random Base58 invite code (8 characters)
 * Excludes 0, O, I, l to reduce confusion
 */
export async function generateInviteCode(): Promise<string> {
  const buffer = new Uint8Array(6);
  crypto.getRandomValues(buffer);

  let num = 0n;
  for (const byte of buffer) {
    num = (num << 8n) | BigInt(byte);
  }

  const code = encodeBase58(num);
  return code.slice(0, 8).padEnd(8, "1");
}

/**
 * SHA-256 hash a string
 * Used for storing hashed invite codes
 */
export async function sha256Hash(text: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);

  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ============================================================================
// TYPE DEFINITIONS (Supabase auto-generated, manually copied for reference)
// ============================================================================

export interface Database {
  public: {
    Tables: {
      partner_links: {
        Row: {
          id: string;
          user_id_1: string;
          user_id_2: string | null;
          invite_code: string;
          invite_code_hash: string;
          created_by: string;
          status: "pending" | "active" | "ended";
          started_at: string | null;
          activated_at: string | null;
          ended_at: string | null;
          expires_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: Omit<
          Database["public"]["Tables"]["partner_links"]["Row"],
          "id" | "created_at" | "updated_at"
        >;
        Update: Partial<
          Database["public"]["Tables"]["partner_links"]["Insert"]
        >;
      };
      couples_exercise_sessions: {
        Row: {
          id: string;
          exercise_id: string;
          user_id_1: string;
          user_id_2: string | null;
          status: "pending" | "in_progress" | "completed" | "abandoned";
          user_1_joined_at: string | null;
          user_2_joined_at: string | null;
          user_1_rating: number | null;
          user_1_notes: string | null;
          user_2_rating: number | null;
          user_2_notes: string | null;
          completed_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: Omit<
          Database["public"]["Tables"]["couples_exercise_sessions"]["Row"],
          "id" | "created_at" | "updated_at"
        >;
        Update: Partial<
          Database["public"]["Tables"]["couples_exercise_sessions"]["Insert"]
        >;
      };
      appreciations: {
        Row: {
          id: string;
          from_user_id: string;
          to_user_id: string;
          message: string;
          created_at: string;
        };
        Insert: Omit<
          Database["public"]["Tables"]["appreciations"]["Row"],
          "id" | "created_at"
        >;
        Update: Partial<
          Database["public"]["Tables"]["appreciations"]["Insert"]
        >;
      };
      rate_limit_tracker: {
        Row: {
          id: string;
          user_id: string;
          action: string;
          created_at: string;
        };
        Insert: Omit<
          Database["public"]["Tables"]["rate_limit_tracker"]["Row"],
          "id" | "created_at"
        >;
        Update: Partial<
          Database["public"]["Tables"]["rate_limit_tracker"]["Insert"]
        >;
      };
    };
  };
}

// ============================================================================
// CONSTANTS
// ============================================================================

export const COUPLES_MODE_CONSTANTS = {
  INVITE_EXPIRY_HOURS: 72,
  MAX_INVITES_PER_24H: 3,
  MAX_APPRECIATIONS_PER_24H: 10,
  MAX_FAILED_ATTEMPTS_PER_MINUTE: 5,
  SESSION_RATING_MIN: 1,
  SESSION_RATING_MAX: 5,
  APPRECIATION_MAX_LENGTH: 500,
  BASE58_CODE_LENGTH: 8,
} as const;

// ============================================================================
// HELPER FUNCTIONS (Pre-built from Phase 1.1)
// ============================================================================

/**
 * Check if user has premium access
 * Returns true if user's own subscription is active OR partner's subscription is active
 */
export async function userHasPremiumAccess(
  supabase: any,
  userId: string,
): Promise<boolean> {
  try {
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("status")
      .eq("user_id", userId)
      .single();

    if (subscription?.status === "active") {
      return true;
    }

    // Check partner's subscription
    const { data: partnership } = await supabase
      .from("partner_links")
      .select("user_id_1, user_id_2")
      .or(`user_id_1.eq.${userId},user_id_2.eq.${userId}`)
      .eq("status", "active")
      .single();

    if (!partnership) {
      return false;
    }

    const partnerId =
      partnership.user_id_1 === userId
        ? partnership.user_id_2
        : partnership.user_id_1;

    const { data: partnerSubscription } = await supabase
      .from("subscriptions")
      .select("status")
      .eq("user_id", partnerId)
      .single();

    return partnerSubscription?.status === "active";
  } catch (error) {
    console.error("Error checking premium access:", error);
    return false;
  }
}

/**
 * Check if two users are partners
 */
export async function isPartnerWith(
  supabase: any,
  userId1: string,
  userId2: string,
): Promise<boolean> {
  try {
    const { data } = await supabase
      .from("partner_links")
      .select("id")
      .or(
        `and(user_id_1.eq.${userId1},user_id_2.eq.${userId2}),and(user_id_1.eq.${userId2},user_id_2.eq.${userId1})`,
      )
      .eq("status", "active")
      .single();

    return !!data;
  } catch (error) {
    return false;
  }
}

/**
 * Get partner ID (returns the other user in the active partnership)
 */
export async function getPartnerId(
  supabase: any,
  userId: string,
): Promise<string | null> {
  try {
    const { data } = await supabase
      .from("partner_links")
      .select("user_id_1, user_id_2")
      .or(`user_id_1.eq.${userId},user_id_2.eq.${userId}`)
      .eq("status", "active")
      .single();

    if (!data) {
      return null;
    }

    return data.user_id_1 === userId ? data.user_id_2 : data.user_id_1;
  } catch (error) {
    return null;
  }
}
