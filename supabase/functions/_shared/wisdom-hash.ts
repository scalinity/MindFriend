/**
 * HMAC-SHA256 hashing utility for Community Wisdom Engine
 * Provides cryptographically secure anonymization of user IDs
 * 
 * Security:
 * - Uses HMAC-SHA256 with pepper (not simple SHA-256)
 * - Prevents rainbow table attacks
 * - User IDs cannot be reversed even with salt leak
 */

/**
 * Validates that required environment variables are set
 * Call this at startup to fail fast
 */
export function validateEnvironment(): void {
  const salt = Deno.env.get("WISDOM_HASH_SALT");
  const pepper = Deno.env.get("WISDOM_HASH_PEPPER");
  
  if (!salt) {
    throw new Error("WISDOM_HASH_SALT environment variable is not set");
  }
  if (!pepper) {
    throw new Error("WISDOM_HASH_PEPPER environment variable is not set");
  }
  if (salt.length < 32) {
    throw new Error("WISDOM_HASH_SALT must be at least 32 characters");
  }
  if (pepper.length < 32) {
    throw new Error("WISDOM_HASH_PEPPER must be at least 32 characters");
  }
}

/**
 * Creates an HMAC-SHA256 hash of user ID with salt and pepper
 * @param userId User UUID to anonymize
 * @returns 64-character hex string (HMAC-SHA256 hash)
 */
export async function hashUserId(userId: string): Promise<string> {
  const salt = Deno.env.get("WISDOM_HASH_SALT");
  const pepper = Deno.env.get("WISDOM_HASH_PEPPER");
  
  if (!salt || !pepper) {
    throw new Error("Hash environment variables not configured");
  }

  // Validate userId format (UUID)
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(userId)) {
    throw new Error("Invalid user ID format");
  }

  // Combine user ID with salt
  const data = `${userId}:${salt}`;

  // Use HMAC-SHA256 with pepper as the secret key
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(pepper),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(data)
  );

  // Convert to hex string
  const hashArray = Array.from(new Uint8Array(signature));
  const hashHex = hashArray
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return hashHex;
}

/**
 * Validates that a hash is a valid SHA-256 format
 * @param hash Hash string to validate
 * @returns boolean True if valid SHA-256 hex string
 */
export function isValidHash(hash: string): boolean {
  if (typeof hash !== "string") return false;
  if (hash.length !== 64) return false;
  return /^[a-f0-9]+$/.test(hash);
}
