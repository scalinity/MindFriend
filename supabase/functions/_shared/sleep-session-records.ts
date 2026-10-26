/** Keep historical imports, but count only the complete owned session that contains them. */
export function withoutContainedSleepImports<T extends Record<string, any>>(
  entries: T[],
): T[] {
  const imported = (row: T) =>
    ["healthkit", "apple_watch"].includes(row.source ?? "");
  return entries.filter((entry) =>
    !entries.some((other) => {
      if (
        other.id === entry.id || other.user_id !== entry.user_id ||
        !imported(other) || !imported(entry)
      ) return false;
      const bed = Date.parse(other.bedtime), wake = Date.parse(other.wake_time);
      const entryBed = Date.parse(entry.bedtime),
        entryWake = Date.parse(entry.wake_time);
      if (
        !(wake > bed && wake - bed <= 86400000 &&
          other.time_in_bed_minutes >= 60 &&
          other.time_in_bed_minutes <= 1440 &&
          (other.time_asleep_minutes ?? 0) > 0 &&
          other.time_asleep_minutes! <= other.time_in_bed_minutes &&
          bed <= entryBed && wake >= entryWake)
      ) return false;
      const stages = [other.deep_sleep_minutes, other.rem_sleep_minutes, other.light_sleep_minutes];
      if (stages.some(value => value != null && (!Number.isFinite(value) || value < 0)) ||
        stages.reduce((sum, value) => sum + (value ?? 0), 0) > other.time_asleep_minutes ||
        (other.awake_minutes != null && (!Number.isFinite(other.awake_minutes) || other.awake_minutes < 0 ||
          other.time_asleep_minutes + other.awake_minutes > other.time_in_bed_minutes))) return false;
      if (bed < entryBed || wake > entryWake) return true;
      // Equal intervals have one deterministic winner, including records predating updated_at.
      const otherUpdated = Date.parse(other.updated_at ?? "") || 0;
      const entryUpdated = Date.parse(entry.updated_at ?? "") || 0;
      return otherUpdated > entryUpdated ||
        (otherUpdated === entryUpdated && other.id < entry.id);
    })
  );
}
