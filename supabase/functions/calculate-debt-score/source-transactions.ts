import { checkedTimeZone, localDateFormatter, localDayStart } from "./calendar.ts";
import { withoutContainedSleepImports } from "../_shared/sleep-session-records.ts";
import type { Transaction } from "../_shared/wellbeing-debt-types.ts";
import {
  calculatePoorSleepWithdrawal,
  calculateSleepDeposit,
  calculateSleepQuality,
} from "../_shared/wellbeing-debt-utils.ts";

type SourceRow = Record<string, any>;
const dayMS = 86_400_000;
export function ledgerDate(date: string, offset = 0): string {
  const value = new Date(`${date}T00:00:00Z`);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
    value.toISOString().slice(0, 10) !== date
  ) throw new Error("Invalid ledger date");
  value.setUTCDate(value.getUTCDate() + offset);
  return value.toISOString().slice(0, 10);
}

/** Build a current, owned view without rewriting the historical automatic ledger. */
export async function currentSourceTransactions(
  supabase: any,
  userId: string,
  endDate: string,
  timeZone = "UTC",
): Promise<Transaction[]> {
  checkedTimeZone(timeZone);
  const startDate = ledgerDate(endDate, -29);
  const startInstant = localDayStart(startDate, timeZone);
  const endExclusive = localDayStart(ledgerDate(endDate, 1), timeZone);
  const followingSleepLimit = new Date(Date.parse(endExclusive) + dayMS).toISOString();
  const dayOf = localDateFormatter(timeZone);
  function eventDate(value: unknown): string | null {
    if (typeof value !== "string") return null;
    const milliseconds = Date.parse(value);
    return Number.isFinite(milliseconds) ? dayOf(new Date(milliseconds)) : null;
  }
  async function read(
    table: string,
    columns: string,
    dateColumn: string,
    timestamp = false,
    includeFollowingSleepDay = false,
  ): Promise<SourceRow[]> {
    const rows: SourceRow[] = [];
    for (let offset = 0;; offset += 500) {
      let query = supabase.from(table).select(columns).eq("user_id", userId)
        .gte(dateColumn, timestamp ? startInstant : startDate);
      query = timestamp
        ? query.lt(dateColumn, includeFollowingSleepDay ? followingSleepLimit : endExclusive)
        : query.lte(dateColumn, endDate);
      const { data, error } = await query.order("id", { ascending: true })
        .range(offset, offset + 499);
      if (error || !data) throw new Error(`Source unavailable: ${table}`);
      rows.push(...data.filter((row: SourceRow) => row.user_id === userId).map((row: SourceRow) =>
        timestamp ? { ...row, accounting_date: eventDate(row[dateColumn]) } : row
      ));
      if (data.length < 500) return rows;
    }
  }
  const { data: account, error: accountError } = await supabase.from("profiles")
    .select("created_at").eq("id", userId).single();
  if (accountError || !account?.created_at) {
    throw new Error("Account date unavailable");
  }
  const accountDate = eventDate(account.created_at);
  if (!accountDate) throw new Error("Invalid account date");
  const [manual, sleep, exercise, posts, quests, moods] = await Promise.all([
    read(
      "wellbeing_transactions",
      "id,user_id,date,type,category,amount,source,description,metadata",
      "date",
    ),
    read(
      "sleep_entries",
      "id,user_id,date,source,bedtime,wake_time,time_in_bed_minutes,time_asleep_minutes,deep_sleep_minutes,rem_sleep_minutes,light_sleep_minutes,awake_minutes,updated_at",
      "wake_time",
      true,
      true,
    ),
    read("exercise_sessions", "id,user_id,completed_at", "completed_at", true),
    read("circle_posts", "id,user_id,created_at", "created_at", true),
    read("quests", "id,user_id,local_date,status", "local_date"),
    read("moods", "id,user_id,local_date,mood_score", "local_date"),
  ]);
  const result: Transaction[] = manual.filter((row) =>
    row.source === "user_logged" && row.date >= startDate && row.date <= endDate
  ).map((row) => {
    const amount = Number(row.amount);
    if (!Number.isFinite(amount) || amount < 0) {
      throw new Error("Invalid recorded amount");
    }
    return { ...row, amount } as Transaction;
  });
  function append(
    date: string,
    type: Transaction["type"],
    category: Transaction["category"],
    amount: number,
    source: Transaction["source"],
    rows: SourceRow[],
    description: string,
  ) {
    if (amount <= 0) return;
    result.push({
      id: crypto.randomUUID(),
      user_id: userId,
      date,
      type,
      category,
      amount,
      source,
      description,
      metadata: {
        source_ids: rows.map((row) => row.id),
        accounting: "current_source_records",
      },
    });
  }
  for (let offset = 0; offset < 30; offset++) {
    const date = ledgerDate(startDate, offset);
    const age = Math.floor(
      (Date.parse(`${date}T00:00:00Z`) -
        Date.parse(accountDate)) / dayMS,
    );
    const dayExercises = exercise.filter((row) =>
      row.accounting_date === date
    );
    append(
      date,
      "deposit",
      "exercise_completion",
      dayExercises.length * 8,
      "exercise_sessions",
      dayExercises,
      `${dayExercises.length} completed exercises`,
    );
    const dayPosts = posts.filter((row) => row.accounting_date === date);
    append(
      date,
      "deposit",
      "social_connection",
      Math.min(12, dayPosts.length * 3),
      "circle_posts",
      dayPosts,
      `${dayPosts.length} circle posts`,
    );
    const dayQuests = quests.filter((row) =>
      row.local_date === date && row.status === "completed"
    );
    append(
      date,
      "deposit",
      "quest_completion",
      dayQuests.length * 8,
      "quests",
      dayQuests,
      `${dayQuests.length} completed quests`,
    );
    if (age >= 3) {
      const lowMoods = moods.filter((row) =>
        row.local_date === date && Number.isFinite(row.mood_score) &&
        row.mood_score >= 1 && row.mood_score < 4
      ).slice(0, 2);
      append(
        date,
        "withdrawal",
        "negative_mood",
        lowMoods.length * 2,
        "mood_log",
        lowMoods,
        `${lowMoods.length} low mood check-ins`,
      );
    }
    // Only wearable/Health records supply automatic sleep measurements. Missing data adds no event.
    const daySleep = withoutContainedSleepImports(sleep).filter((row) =>
      row.accounting_date === date &&
      ["healthkit", "apple_watch"].includes(row.source) &&
      Number.isFinite(row.time_asleep_minutes) && row.time_asleep_minutes > 0 &&
      row.time_asleep_minutes <= row.time_in_bed_minutes &&
      Date.parse(row.wake_time) > Date.parse(row.bedtime) &&
      [row.deep_sleep_minutes, row.rem_sleep_minutes].every((value) =>
        value == null || (Number.isFinite(value) && value >= 0)
      ) &&
      (row.deep_sleep_minutes ?? 0) + (row.rem_sleep_minutes ?? 0) <=
        row.time_asleep_minutes
    );
    const lastSleep = daySleep.sort((a, b) =>
      Date.parse(b.wake_time) - Date.parse(a.wake_time)
    )[0];
    if (lastSleep) {
      const quality = calculateSleepQuality(
        lastSleep.time_asleep_minutes * 60,
        lastSleep.deep_sleep_minutes == null
          ? null
          : lastSleep.deep_sleep_minutes * 60,
        lastSleep.rem_sleep_minutes == null
          ? null
          : lastSleep.rem_sleep_minutes * 60,
      );
      append(
        date,
        "deposit",
        "sleep_quality",
        calculateSleepDeposit(quality),
        "healthkit",
        [lastSleep],
        "Recorded sleep quality",
      );
      if (age >= 3) {
        append(
          date,
          "withdrawal",
          "poor_sleep",
          calculatePoorSleepWithdrawal(lastSleep.time_asleep_minutes / 60),
          "healthkit",
          [lastSleep],
          "Recorded sleep below 6 hours",
        );
      }
    }
  }
  return result.sort((a, b) => a.date.localeCompare(b.date));
}
