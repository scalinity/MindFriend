// Local time of day for a person, from profiles.timezone.
//
// profiles.timezone defaults to 'UTC' and only becomes the person's zone once the app has
// synced it, so 'UTC' means "not known yet" rather than "lives in UTC". Time-of-day rewards
// wait until the zone is known instead of guessing.

/** The person's IANA zone, or null while it is still the 'UTC' default or not a valid zone. */
export function knownTimeZone(timezone: string | null | undefined): string | null {
  if (!timezone || timezone === "UTC") return null;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: timezone });
    return timezone;
  } catch {
    return null;
  }
}

/** Hour of day, 0 to 23, in `timezone`. (hour12: false formats midnight as "24" in en-US.) */
export function localHour(timezone: string, now: Date): number {
  return Number(
    new Intl.DateTimeFormat("en-US", { timeZone: timezone, hour: "numeric", hourCycle: "h23" })
      .format(now),
  );
}

/**
 * Night Owl ("after midnight", 00:00 to 04:59) and Early Bird ("before 6am", 05:00 to 05:59),
 * in the person's own time. Never earned while the zone is unknown.
 */
export function timeOfDayBadgeEarned(
  requirement: "activity_after_midnight" | "activity_before_6am",
  timezone: string | null | undefined,
  now: Date,
): boolean {
  const zone = knownTimeZone(timezone);
  if (!zone) return false;
  const hour = localHour(zone, now);
  return requirement === "activity_after_midnight" ? hour < 5 : hour === 5;
}
