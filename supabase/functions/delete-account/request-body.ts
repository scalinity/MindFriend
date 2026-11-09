/** Parses a deletion request body. Released clients (1.0.4/1.0.5) send an empty POST. */
export function parseDeletionRequest(raw: string): Record<string, unknown> | null {
  if (raw.trim() === "") return {};
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}
