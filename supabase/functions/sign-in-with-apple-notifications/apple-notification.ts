import * as jose from "npm:jose@6.2.13";

const appleKeys = jose.createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
const eventTypes = new Set(["email-disabled", "email-enabled", "consent-revoked", "account-deleted"]);

export interface AppleAccountEvent {
  type: string;
  sub: string;
  event_time: number;
  email?: string;
}

export async function verifyAppleNotification(
  token: string,
  audience: string,
  keys: jose.JWTVerifyGetKey = appleKeys,
): Promise<AppleAccountEvent> {
  const { payload } = await jose.jwtVerify(token, keys, {
    issuer: "https://appleid.apple.com",
    audience,
    algorithms: ["RS256"],
    requiredClaims: ["iat", "jti", "events"],
  });
  // Apple's notification examples omit exp; delayed delivery remains valid.
  // The signed event timestamp makes effects monotonic and replay-safe in SQL.
  const event = payload.events as Partial<AppleAccountEvent> | null;
  const futureLimit = Math.floor(Date.now() / 1000) + 300;
  if (
    !Number.isSafeInteger(payload.iat) || payload.iat! <= 0 || payload.iat! > futureLimit ||
    typeof payload.jti !== "string" || !payload.jti.trim() ||
    !event || typeof event !== "object" || Array.isArray(event) ||
    typeof event.type !== "string" || !eventTypes.has(event.type) ||
    (event.email !== undefined && (typeof event.email !== "string" || event.email.length > 320)) ||
    typeof event.sub !== "string" || !event.sub.trim() || event.sub.length > 255 ||
    !Number.isSafeInteger(event.event_time) || event.event_time! <= 0 || event.event_time! > futureLimit
  ) throw new jose.errors.JWTClaimValidationFailed("Invalid Apple account event", payload, "events", "invalid");
  return event as AppleAccountEvent;
}
