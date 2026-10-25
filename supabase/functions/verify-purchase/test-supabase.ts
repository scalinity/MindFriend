// Imported only by deno.test.json; never used by the deployed function.
export const callerId = "abcdefab-cdef-4abc-8def-abcdefabcdef";

export const database = {
  authenticated: true,
  subscription: null as Record<string, unknown> | null,
  lookupError: null as { code: string } | null,
  profile: { subscription_tier: "premium", daily_ai_quota: -1, premium_badge: "premium_supporter" } as Record<string, unknown>,
  stats: { streak_shields_max: 3, recovery_attempts_max: 2 } as Record<string, unknown>,
  failTable: "",
  failOperation: "",
  reads: [] as string[],
  writes: [] as {
    table: string;
    operation: string;
    data: Record<string, unknown>;
  }[],
  reset() {
    this.authenticated = true;
    this.subscription = null;
    this.lookupError = null;
    this.profile = { subscription_tier: "premium", daily_ai_quota: -1, premium_badge: "premium_supporter" };
    this.stats = { streak_shields_max: 3, recovery_attempts_max: 2 };
    this.failTable = "";
    this.failOperation = "";
    this.reads = [];
    this.writes = [];
  },
};

// The production SDK uses an untyped database schema; the fixture records its actual operations.
// deno-lint-ignore no-explicit-any
export function createClient(..._args: unknown[]): any {
  return {
    auth: {
      getUser: (_token?: string) =>
        Promise.resolve({
          data: { user: database.authenticated ? { id: callerId } : null },
          error: null,
        }),
    },
    from(table: string) {
      database.reads.push(table);
      let operation = "select";
      let writeData: Record<string, unknown> | undefined;
      const result = () => {
        const error = table === database.failTable && operation === database.failOperation
          ? { code: "synthetic-write-failure", message: "Synthetic persistence failure" }
          : operation === "select" && table === "subscriptions" ? database.lookupError : null;
        if (!error && writeData) {
          if (table === "subscriptions") database.subscription = { id: "test-subscription", ...database.subscription, ...writeData };
          if (table === "profiles") Object.assign(database.profile, writeData);
          if (table === "user_stats") Object.assign(database.stats, writeData);
        }
        return ({
        data: table === "subscriptions"
          ? database.subscription
          : table === "family_groups"
          ? { id: "test-family", circle_id: "test-circle" }
          : table === "profiles" ? database.profile
          : table === "user_stats" ? database.stats
          : null,
        error,
      }); };
      const query = {
        select: (_columns?: string) => query,
        eq: (_column: string, _value: unknown) => query,
        maybeSingle: () => Promise.resolve(result()),
        single: () => Promise.resolve(result()),
        update(data: Record<string, unknown>) {
          operation = "update";
          writeData = data;
          database.writes.push({ table, operation, data });
          return query;
        },
        upsert(data: Record<string, unknown>, _options?: unknown) {
          operation = "upsert";
          writeData = data;
          database.writes.push({ table, operation, data });
          return query;
        },
        insert(data: Record<string, unknown>) {
          operation = "insert";
          writeData = data;
          database.writes.push({ table, operation, data });
          return query;
        },
        then: <T>(resolve: (value: ReturnType<typeof result>) => T) =>
          Promise.resolve(result()).then(resolve),
      };
      return query;
    },
  };
}
