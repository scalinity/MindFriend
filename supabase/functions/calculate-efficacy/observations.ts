import type { TrajectoryPoint } from "./calculation.ts";

/** Only explicitly sourced, stored self-reports support an emotional trajectory.
 * Historical composite/HRV values have unknown provenance and cannot be relabeled
 * from their shape. Physiology and nervous-system state are not inferred here.
 */
export function observedTrajectory(record: any): TrajectoryPoint[] | null {
  if (record?.measurement_status !== "observed" ||
      record?.measurement_source !== "self_reported_valence" ||
      !Array.isArray(record.samples) || record.samples.length < 3) return null;

  const points: TrajectoryPoint[] = [];
  for (const sample of record.samples) {
    const valence = sample?.emotion_classification?.valence;
    const primary = sample?.emotion_classification?.primary;
    const seconds = sample?.seconds_from_start;
    const timestamp = Date.parse(sample?.timestamp);
    if (!Number.isFinite(valence) || valence < -1 || valence > 1 ||
        typeof primary !== "string" || !primary.trim() ||
        !Number.isInteger(seconds) || seconds < 0 || !Number.isFinite(timestamp)) return null;
    const previous = points.at(-1);
    if (previous && (seconds <= previous.secondsFromStart || timestamp <= Date.parse(previous.timestamp))) return null;
    points.push({
      timestamp: sample.timestamp,
      secondsFromStart: seconds,
      emotionClassification: { primary, valence },
      compositeScore: valence,
    });
  }
  return points;
}
