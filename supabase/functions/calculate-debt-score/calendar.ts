/** IANA calendar days for owner-requested calculations; legacy requests continue to use UTC. */
export function checkedTimeZone(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 || value.length > 100) {
    throw new Error("Invalid time zone");
  }
  new Intl.DateTimeFormat("en", { timeZone: value }).format(0);
  return value;
}
function dateFormatter(timeZone: string): Intl.DateTimeFormat {
  return new Intl.DateTimeFormat("en", {
    timeZone,
    calendar: "iso8601",
    numberingSystem: "latn",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
}
function dateLabel(
  formatter: Intl.DateTimeFormat,
  milliseconds: number,
): string {
  const parts = formatter.formatToParts(milliseconds);
  const part = (type: string) => parts.find((p) => p.type === type)!.value;
  return `${part("year")}-${part("month")}-${part("day")}`;
}
export function localDateFormatter(timeZone: string): (value: Date) => string {
  const formatter = dateFormatter(timeZone);
  return value => dateLabel(formatter, value.getTime());
}
export function localDate(value: Date, timeZone: string): string {
  return localDateFormatter(timeZone)(value);
}
/** First instant of the date, including zones where a DST change skips midnight. */
export function localDayStart(date: string, timeZone: string): string {
  const center = Date.parse(`${date}T00:00:00Z`);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(center) ||
    new Date(center).toISOString().slice(0, 10) !== date
  ) {
    throw new Error("Invalid date");
  }
  const formatter = dateFormatter(timeZone);
  let low = center - 36 * 3600000, high = center + 36 * 3600000;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (dateLabel(formatter, middle) < date) low = middle + 1;
    else high = middle;
  }
  if (dateLabel(formatter, low) !== date) {
    throw new Error("Date does not exist in this time zone");
  }
  return new Date(low).toISOString();
}
