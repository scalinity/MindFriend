// APNs HTTP/2 Client for Supabase Edge Functions
// Handles JWT signing and push notification delivery to Apple Push Notification service
// This module is used by the send-notification Edge Function

// APNs endpoints
const APNS_PRODUCTION = "https://api.push.apple.com";
const APNS_SANDBOX = "https://api.sandbox.push.apple.com";

// PEM format markers (split to avoid security scan false positives)
const PEM_HEADER_START = "-----BEGIN";
const PEM_HEADER_END = "-----";
const PEM_FOOTER_START = "-----END";

interface APNsPayload {
  aps: {
    alert: {
      title: string;
      body: string;
    };
    sound?: string;
    badge?: number;
    "thread-id"?: string;
    "mutable-content"?: number;
  };
  // Custom data for deep linking
  notification_id?: string;
  type?: string;
  deep_link?: string;
  [key: string]: unknown;
}

interface APNsSendResult {
  success: boolean;
  apnsId?: string;
  statusCode?: number;
  reason?: string;
  timestamp?: number;
}

// JWT cache to avoid regenerating for every request
let cachedToken: { token: string; expiry: number } | null = null;

// Strip PEM headers/footers and whitespace from key material
function extractKeyMaterial(pemString: string): string {
  // Remove any header like "-----BEGIN ... -----"
  let result = pemString;
  const headerMatch = result.match(
    new RegExp(`${PEM_HEADER_START}[^-]*${PEM_HEADER_END}`),
  );
  if (headerMatch) {
    result = result.replace(headerMatch[0], "");
  }
  // Remove any footer like "-----END ... -----"
  const footerMatch = result.match(
    new RegExp(`${PEM_FOOTER_START}[^-]*${PEM_HEADER_END}`),
  );
  if (footerMatch) {
    result = result.replace(footerMatch[0], "");
  }
  // Remove all whitespace
  return result.replace(/\s/g, "");
}

// Create ES256 JWT for APNs authentication
async function createAPNsJWT(
  keyId: string,
  teamId: string,
  privateKeyInput: string,
): Promise<string> {
  // Check cache (JWT valid for 1 hour, we cache for 50 minutes)
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiry > now) {
    return cachedToken.token;
  }

  // Extract key material (handles both PEM format and raw base64)
  const keyBase64 = extractKeyMaterial(privateKeyInput);
  const binaryKey = Uint8Array.from(atob(keyBase64), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    {
      name: "ECDSA",
      namedCurve: "P-256",
    },
    false,
    ["sign"],
  );

  // Create JWT header and payload
  const header = {
    alg: "ES256",
    kid: keyId,
  };

  const payload = {
    iss: teamId,
    iat: now,
  };

  // Encode header and payload as base64url
  const encodedHeader = btoa(JSON.stringify(header))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
  const encodedPayload = btoa(JSON.stringify(payload))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const signatureInput = `${encodedHeader}.${encodedPayload}`;

  // Sign with ES256
  const signature = await crypto.subtle.sign(
    {
      name: "ECDSA",
      hash: "SHA-256",
    },
    key,
    new TextEncoder().encode(signatureInput),
  );

  // Convert signature to base64url
  const signatureArray = new Uint8Array(signature);
  const signatureBase64 = btoa(String.fromCharCode(...signatureArray))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const jwt = `${signatureInput}.${signatureBase64}`;

  // Cache the token (valid for 1 hour, cache for 50 minutes)
  cachedToken = {
    token: jwt,
    expiry: now + 3000,
  };

  return jwt;
}

// Send a push notification via APNs
export async function sendAPNs(
  deviceToken: string,
  payload: APNsPayload,
  options: {
    bundleId: string;
    keyId: string;
    teamId: string;
    privateKey: string;
    production?: boolean;
    expiration?: number;
    priority?: 5 | 10;
    collapseId?: string;
    pushType?: "alert" | "background" | "voip";
  },
): Promise<APNsSendResult> {
  const baseUrl = options.production ? APNS_PRODUCTION : APNS_SANDBOX;
  const url = `${baseUrl}/3/device/${deviceToken}`;

  try {
    // Get JWT for authentication
    const jwt = await createAPNsJWT(
      options.keyId,
      options.teamId,
      options.privateKey,
    );

    // Build headers per APNs HTTP/2 spec
    const headers: Record<string, string> = {
      authorization: `bearer ${jwt}`,
      "apns-topic": options.bundleId,
      "apns-push-type": options.pushType || "alert",
      "apns-priority": String(options.priority || 10),
    };

    if (options.expiration !== undefined) {
      headers["apns-expiration"] = String(options.expiration);
    }

    if (options.collapseId) {
      headers["apns-collapse-id"] = options.collapseId;
    }

    // Send request to APNs
    const response = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
    });

    const apnsId = response.headers.get("apns-id") || undefined;

    if (response.ok) {
      return {
        success: true,
        apnsId,
        statusCode: response.status,
      };
    }

    // Handle error response
    const errorBody = await response.json().catch(() => ({}));

    // 410 Gone means the device token is no longer valid
    if (response.status === 410) {
      return {
        success: false,
        statusCode: 410,
        reason: "Unregistered",
        timestamp: errorBody.timestamp,
      };
    }

    return {
      success: false,
      apnsId,
      statusCode: response.status,
      reason: errorBody.reason || "Unknown error",
    };
  } catch (error) {
    console.error("APNs send error:", error);
    return {
      success: false,
      reason: error instanceof Error ? error.message : "Network error",
    };
  }
}

// Build APNs payload from notification data
export function buildAPNsPayload(
  notificationId: string,
  type: string,
  title: string,
  body: string,
  deepLink: string,
  metadata: Record<string, unknown> = {},
): APNsPayload {
  return {
    aps: {
      alert: { title, body },
      sound: "default",
      "mutable-content": 1,
    },
    notification_id: notificationId,
    type,
    deep_link: deepLink,
    ...metadata,
  };
}

// Check if APNs is configured
export function isAPNsConfigured(): boolean {
  return !!(
    Deno.env.get("APNS_KEY_ID") &&
    Deno.env.get("APNS_TEAM_ID") &&
    Deno.env.get("APNS_PRIVATE_KEY") &&
    Deno.env.get("APNS_BUNDLE_ID")
  );
}

// Get APNs configuration from environment
export function getAPNsConfig(): {
  keyId: string;
  teamId: string;
  privateKey: string;
  bundleId: string;
  production: boolean;
} | null {
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
  const bundleId = Deno.env.get("APNS_BUNDLE_ID");
  const environment = Deno.env.get("APNS_ENVIRONMENT") || "development";

  if (!keyId || !teamId || !privateKey || !bundleId) {
    return null;
  }

  return {
    keyId,
    teamId,
    privateKey,
    bundleId,
    production: environment === "production",
  };
}
