import { assertEquals } from "jsr:@std/assert@1.0.19";
import { withoutContainedSleepImports } from "./sleep-session-records.ts";
const full = {
  id: "a",
  user_id: "owner",
  source: "healthkit",
  bedtime: "2026-10-24T14:00:00Z",
  wake_time: "2026-10-25T09:00:00Z",
  time_in_bed_minutes: 1140,
  time_asleep_minutes: 1080,
};
Deno.test("complete owned import supersedes both contained fragments without mutation", () => {
  const entries = [full, {
    ...full,
    id: "b",
    wake_time: "2026-10-25T04:00:00Z",
  }, { ...full, id: "c", bedtime: "2026-10-25T04:00:00Z" }];
  assertEquals(withoutContainedSleepImports(entries), [full]);
  assertEquals(entries.length, 3);
});
Deno.test("manual and other owners remain separate; duplicate bounds have one stable winner", () => {
  const manual = { ...full, id: "manual", source: "manual" };
  const other = { ...full, id: "other", user_id: "other" };
  const entries = [manual, full, { ...full, id: "z" }, other];
  assertEquals(withoutContainedSleepImports(entries), [manual, full, other]);
  assertEquals(withoutContainedSleepImports(entries.toReversed()), [
    other,
    full,
    manual,
  ]);
});
Deno.test("incomplete or invalid enclosing import cannot hide a valid record", () => {
  for (const bad of [null, 0, 2000]) {
    const invalid = { ...full, id: "bad", time_asleep_minutes: bad };
    const fragment = {
      ...full,
      id: "fragment",
      bedtime: "2026-10-25T00:00:00Z",
    };
    assertEquals(withoutContainedSleepImports([invalid, fragment]).length, 2);
  }
});
Deno.test("newest equal-bounds import wins and nested records are counted once", () => {
  const fresh = { ...full, id: "new", updated_at: "2026-10-25T20:00:00Z" };
  const nested = { ...full, id: "nested", bedtime: "2026-10-25T04:00:00Z" };
  assertEquals(withoutContainedSleepImports([full, nested, fresh]), [fresh]);
});

const daily = {
  ...full, id: "daily", date: "2026-10-26", bedtime: "2026-10-26T02:00:00Z",
  wake_time: "2026-10-27T03:30:00Z", time_in_bed_minutes: 570, time_asleep_minutes: 570,
  recorded_periods: [
    { start: "2026-10-26T02:00:00Z", end: "2026-10-26T11:00:00Z", in_bed_seconds: 32400, asleep_seconds: 32400 },
    { start: "2026-10-27T03:00:00Z", end: "2026-10-27T03:30:00Z", in_bed_seconds: 1800, asleep_seconds: 1800 },
  ],
};
Deno.test("wide daily aggregate counts a contained legacy night once and preserves source rows", () => {
  const fragment = { ...full, id: "old", bedtime: daily.bedtime, wake_time: daily.recorded_periods[0].end,
    time_in_bed_minutes: 540, time_asleep_minutes: 540, notes: "Synthetic retained feedback" };
  assertEquals(withoutContainedSleepImports([fragment, daily]), [daily]);
  assertEquals(fragment.notes, "Synthetic retained feedback");
  const gap = { ...fragment, id: "gap", bedtime: "2026-10-26T16:00:00Z", wake_time: "2026-10-26T17:30:00Z",
    time_in_bed_minutes: 90, time_asleep_minutes: 90 };
  assertEquals(withoutContainedSleepImports([gap, daily]), [gap, daily]);
});
Deno.test("malformed or stale period metadata cannot hide another record", () => {
  const fragment = { ...full, id: "fragment", bedtime: daily.bedtime, wake_time: daily.recorded_periods[0].end };
  for (const periods of [null, {}, [null], [{ start: 1 }], [],
    [{ ...daily.recorded_periods[0], asleep_seconds: 1 }, daily.recorded_periods[1]],
    [{ ...daily.recorded_periods[0], end: "not-a-date" }, daily.recorded_periods[1]]]) {
    const invalid = { ...daily, recorded_periods: periods };
    assertEquals(withoutContainedSleepImports([fragment, invalid]).length, 2);
  }
  const manual = { ...fragment, id: "manual", source: "manual" };
  const other = { ...fragment, id: "other", user_id: "different-owner" };
  assertEquals(withoutContainedSleepImports([manual, other, daily]), [manual, other, daily]);
});
Deno.test("stale metadata on a shorter envelope never falls back to hiding an unmeasured record", () => {
  const fragment = { ...full, id: "fragment", bedtime: "2026-10-25T00:00:00Z", wake_time: "2026-10-25T01:00:00Z" };
  for (const periods of [[null], [], [{ start: "invalid", end: "invalid" }]]) {
    const invalid = { ...full, recorded_periods: periods };
    assertEquals(withoutContainedSleepImports([fragment, invalid]), [fragment, invalid]);
  }
});
Deno.test("legacy whole-second boundaries reconcile with fractional measured periods without filling gaps", () => {
  const precise = { ...daily, recorded_periods: daily.recorded_periods.map((period) => ({ ...period,
    start: period.start.replace('00Z', '00.123Z'), end: period.end.replace('00Z', '00.123Z') })) };
  const fragment = { ...full, id: "legacy-seconds", bedtime: daily.bedtime, wake_time: daily.recorded_periods[0].end,
    time_in_bed_minutes: 540, time_asleep_minutes: 540 };
  assertEquals(withoutContainedSleepImports([fragment, precise]), [precise]);
  const gap = { ...fragment, id: "gap", bedtime: "2026-10-26T16:00:00Z", wake_time: "2026-10-26T17:00:00Z",
    time_in_bed_minutes: 60, time_asleep_minutes: 60 };
  assertEquals(withoutContainedSleepImports([gap, precise]), [gap, precise]);
});
Deno.test("nearby legacy rows cannot mutually disappear and measured coverage wins mutual containment", () => {
  const shifted = { ...full, id: "shifted", bedtime: "2026-10-24T14:00:01Z", wake_time: "2026-10-25T09:00:01Z" };
  assertEquals(withoutContainedSleepImports([full, shifted]).length, 2);
  assertEquals(withoutContainedSleepImports([shifted, full]).length, 2);
  const precise = { ...full, id: "precise", recorded_periods: [{ start: "2026-10-24T14:00:00.123Z",
    end: "2026-10-25T09:00:00.123Z", in_bed_seconds: 1140 * 60, asleep_seconds: 1080 * 60 }] };
  const legacy = { ...full, id: "legacy", wake_time: full.wake_time, updated_at: "2026-10-27T00:00:00Z" };
  assertEquals(withoutContainedSleepImports([legacy, precise]), [precise]);
  assertEquals(withoutContainedSleepImports([precise, legacy]), [precise]);
});
Deno.test("mixed four-row measured and legacy coverage never forms a dominance cycle", () => {
  const base = Date.parse("2026-10-26T05:00:00Z");
  const row = (id: string, start: number, end: number, measured: boolean) => ({ ...full, id,
    bedtime: new Date(base + start * 1000).toISOString(), wake_time: new Date(base + end * 1000).toISOString(),
    time_in_bed_minutes: 1, time_asleep_minutes: 1,
    ...(measured ? {recorded_periods:[{start:new Date(base + start * 1000).toISOString(),
      end:new Date(base + end * 1000).toISOString(),in_bed_seconds:end-start,asleep_seconds:end-start}]} : {}) });
  const a=row("M1",0,100,true),b=row("L1",-1,101,false),c=row("M2",-1,99,true),d=row("L2",-2,100,false);
  for(const input of [[a,b,c,d],[d,c,b,a],[b,d,a,c],[c,a,d,b]]){
    assertEquals(withoutContainedSleepImports(input).map(r=>r.id).sort(),["L1","L2"]);
  }
});
