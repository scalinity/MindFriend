// Shared auth helpers for Edge Functions

export function constantTimeCompare(a: string, b: string): boolean {
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);

  if (aBytes.length !== bBytes.length) return false;

  let diff = 0;
  for (let i = 0; i < aBytes.length; i++) {
    diff |= aBytes[i] ^ bBytes[i];
  }
  return diff === 0;
}

export function isAuthorizedCronRequest(
  headers: Headers,
  expectedCronSecret: string,
  serviceRoleKey: string,
): boolean {
  const cronSecret = headers.get("X-Cron-Secret");
  const authHeader = headers.get("Authorization");

  const isCron =
    expectedCronSecret.length > 0 &&
    cronSecret !== null &&
    constantTimeCompare(cronSecret, expectedCronSecret);

  const bearerToken = authHeader?.startsWith("Bearer ")
    ? authHeader.replace("Bearer ", "")
    : "";
  const isServiceRole =
    serviceRoleKey.length > 0 &&
    bearerToken.length > 0 &&
    constantTimeCompare(bearerToken, serviceRoleKey);

  return isCron || isServiceRole;
}
