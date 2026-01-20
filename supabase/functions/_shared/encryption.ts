// GDPR Article 32 - Encryption of Special Category Data (Health Information)
// Implements AES-256-GCM encryption for sensitive email payloads

const ENCRYPTION_KEY_LENGTH = 32; // 256 bits for AES-256
const NONCE_LENGTH = 12; // 96 bits for GCM
const TAG_LENGTH = 16; // 128 bits authentication tag

/**
 * Get or generate encryption key from environment
 * In production, this should be stored in Supabase Vault or similar KMS
 */
function getEncryptionKey(): Uint8Array {
  const keyEnv = Deno.env.get("EMAIL_ENCRYPTION_KEY");

  if (!keyEnv) {
    throw new Error(
      "EMAIL_ENCRYPTION_KEY not set. Set via: echo 'base64-key-here' | base64 -d > key"
    );
  }

  // Key should be base64-encoded 32 bytes (256 bits)
  const binaryString = atob(keyEnv);
  const bytes = new Uint8Array(binaryString.length);

  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }

  if (bytes.length !== ENCRYPTION_KEY_LENGTH) {
    throw new Error(
      `Encryption key must be ${ENCRYPTION_KEY_LENGTH} bytes, got ${bytes.length}`
    );
  }

  return bytes;
}

/**
 * Encrypt sensitive payload using AES-256-GCM
 * Returns base64-encoded string: base64(nonce + ciphertext + tag)
 */
export async function encryptPayload(
  payload: Record<string, unknown>
): Promise<string> {
  const jsonString = JSON.stringify(payload);
  const data = new TextEncoder().encode(jsonString);

  // Generate random nonce
  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_LENGTH));

  // Import key
  const key = getEncryptionKey();
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt"]
  );

  // Encrypt
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
    cryptoKey,
    data
  );

  // Combine nonce + ciphertext
  const result = new Uint8Array(nonce.length + encrypted.byteLength);
  result.set(nonce);
  result.set(new Uint8Array(encrypted), nonce.length);

  // Return base64-encoded
  const binaryString = String.fromCharCode(...result);
  return btoa(binaryString);
}

/**
 * Decrypt encrypted payload using AES-256-GCM
 * Input is base64-encoded string: base64(nonce + ciphertext)
 */
export async function decryptPayload(
  encryptedBase64: string
): Promise<Record<string, unknown>> {
  try {
    // Decode base64
    const binaryString = atob(encryptedBase64);
    const encrypted = new Uint8Array(binaryString.length);

    for (let i = 0; i < binaryString.length; i++) {
      encrypted[i] = binaryString.charCodeAt(i);
    }

    // Extract nonce and ciphertext
    const nonce = encrypted.slice(0, NONCE_LENGTH);
    const ciphertext = encrypted.slice(NONCE_LENGTH);

    // Import key
    const key = getEncryptionKey();
    const cryptoKey = await crypto.subtle.importKey(
      "raw",
      key,
      { name: "AES-GCM", length: 256 },
      false,
      ["decrypt"]
    );

    // Decrypt
    const decrypted = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: nonce },
      cryptoKey,
      ciphertext
    );

    // Parse JSON
    const jsonString = new TextDecoder().decode(decrypted);
    return JSON.parse(jsonString);
  } catch (error) {
    console.error("Decryption failed:", error);
    throw new Error(`Failed to decrypt payload: ${String(error)}`);
  }
}

/**
 * Check if a string appears to be encrypted (base64-encoded with minimum length)
 */
export function isEncrypted(value: string): boolean {
  // Encrypted payloads are base64 and much longer than typical JSON
  if (value.length < 50) return false;

  // Try to decode as base64
  try {
    atob(value);
    return true;
  } catch {
    return false;
  }
}

/**
 * Safely decrypt with fallback to plaintext for backwards compatibility
 * Used during migration period when some payloads are encrypted and some are not
 */
export async function decryptPayloadSafe(
  value: string | Record<string, unknown>
): Promise<Record<string, unknown>> {
  // If already a record, return as-is
  if (typeof value === "object" && value !== null) {
    return value;
  }

  // If it's a string, try to decrypt
  if (typeof value === "string") {
    // Check if it looks encrypted
    if (isEncrypted(value)) {
      try {
        return await decryptPayload(value);
      } catch (error) {
        console.error("Decryption failed, falling back to plaintext:", error);
        // Fall through to try JSON parsing
      }
    }

    // Try parsing as plaintext JSON (backwards compatibility)
    try {
      return JSON.parse(value);
    } catch {
      throw new Error("Payload is neither valid encrypted data nor valid JSON");
    }
  }

  throw new Error(`Unexpected payload type: ${typeof value}`);
}
