/** Validate measured coverage; stale metadata from an older client cannot hide another record. */
function recordedCoverage(row: Record<string, any>): [number, number][] | null {
  if (!Array.isArray(row.recorded_periods) || !row.recorded_periods.length) return null;
  if (row.recorded_periods.some((period: any) => !period || typeof period !== "object" ||
    typeof period.start !== "string" || typeof period.end !== "string")) return null;
  const periods = [...row.recorded_periods].sort((a, b) => Date.parse(a.start) - Date.parse(b.start));
  let previousEnd = -Infinity, inBed = 0, asleep = 0;
  const ranges: [number, number][] = [];
  for (const period of periods) {
    if (!period || typeof period !== "object") return null;
    const start = Date.parse(period.start), end = Date.parse(period.end);
    const bedSeconds = period.in_bed_seconds, asleepSeconds = period.asleep_seconds;
    if (!(end > start && end - start <= 86400000 && start >= previousEnd &&
      Number.isFinite(bedSeconds) && bedSeconds > 0 && bedSeconds <= (end - start) / 1000 + 0.001 &&
      Number.isFinite(asleepSeconds) && asleepSeconds > 0 && asleepSeconds <= bedSeconds)) return null;
    inBed += bedSeconds; asleep += asleepSeconds; previousEnd = end; ranges.push([start, end]);
  }
  const matches = (seconds: number, minutes: number) => Number.isInteger(minutes) &&
    seconds >= minutes * 60 - 0.001 && seconds < (minutes + 1) * 60 + 0.001;
  if (!(Math.abs(ranges[0][0] - Date.parse(row.bedtime)) < 1000 &&
    Math.abs(ranges[ranges.length - 1][1] - Date.parse(row.wake_time)) < 1000 &&
    matches(inBed, row.time_in_bed_minutes) && matches(asleep, row.time_asleep_minutes))) return null;
  return ranges;
}

/** Keep historical imports, but count only the complete owned measured coverage that contains them. */
export function withoutContainedSleepImports<T extends Record<string, any>>(
  entries: T[],
): T[] {
  const imported = (row: T) =>
    ["healthkit", "apple_watch"].includes(row.source ?? "");
  const covers = (outer: T, inner: T) => {
    const measured = recordedCoverage(outer);
    if (outer.recorded_periods != null && !measured) return false;
    const bed = Date.parse(outer.bedtime), wake = Date.parse(outer.wake_time);
    const start = Date.parse(inner.bedtime), end = Date.parse(inner.wake_time);
    if (!(wake > bed && end > start)) return false;
    const coverage = measured ?? (wake - bed <= 86400000 ? [[bed, wake]] : null);
    const contained = recordedCoverage(inner) ?? [[start, end]];
    // Both old outer DTOs and new coverage use one canonical precision for identity only.
    const seconds = (value: number) => Math.floor(value / 1000);
    return coverage != null && contained.every(([start, end]) =>
      coverage.some(([coveredStart, coveredEnd]) => seconds(coveredStart) <= seconds(start) && seconds(coveredEnd) >= seconds(end)));
  };
  return entries.filter((entry) =>
    !entries.some((other) => {
      if (
        other.id === entry.id || other.user_id !== entry.user_id ||
        !imported(other) || !imported(entry)
      ) return false;
      const bed = Date.parse(other.bedtime), wake = Date.parse(other.wake_time);
      if (
        !(wake > bed &&
          other.time_in_bed_minutes >= 1 &&
          other.time_in_bed_minutes <= 1440 &&
          (other.time_asleep_minutes ?? 0) > 0 &&
          other.time_asleep_minutes! <= other.time_in_bed_minutes)
      ) return false;
      if (!covers(other, entry)) return false;
      const stages = [other.deep_sleep_minutes, other.rem_sleep_minutes, other.light_sleep_minutes];
      if (stages.some(value => value != null && (!Number.isFinite(value) || value < 0)) ||
        stages.reduce((sum, value) => sum + (value ?? 0), 0) > other.time_asleep_minutes ||
        (other.awake_minutes != null && (!Number.isFinite(other.awake_minutes) || other.awake_minutes < 0 ||
          other.time_asleep_minutes + other.awake_minutes > other.time_in_bed_minutes))) return false;
      if (!covers(entry, other)) return true;
      const otherMeasured = recordedCoverage(other) != null;
      const entryMeasured = recordedCoverage(entry) != null;
      if (otherMeasured !== entryMeasured) return otherMeasured;
      // Mutual coverage has one deterministic winner; neither row can remove the other in turn.
      const otherUpdated = Date.parse(other.updated_at ?? "") || 0;
      const entryUpdated = Date.parse(entry.updated_at ?? "") || 0;
      return otherUpdated > entryUpdated ||
        (otherUpdated === entryUpdated && other.id < entry.id);
    })
  );
}
