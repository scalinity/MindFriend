// Imported only by deno.test.json; never used by the deployed function.
export const callerId = "abcdefab-cdef-4abc-8def-abcdefabcdef";

export const database = {
  authenticated: true,
  subscription: null as Record<string, unknown> | null,
  lookupError: null as { code: string } | null,
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
      const result = () => ({
        data: table === "subscriptions"
          ? database.subscription
          : table === "family_groups"
          ? { id: "test-family", circle_id: "test-circle" }
          : null,
        error: table === "subscriptions" ? database.lookupError : null,
      });
      const query = {
        select: (_columns?: string) => query,
        eq: (_column: string, _value: unknown) => query,
        maybeSingle: () => Promise.resolve(result()),
        single: () => Promise.resolve(result()),
        update(data: Record<string, unknown>) {
          database.writes.push({ table, operation: "update", data });
          return query;
        },
        upsert(data: Record<string, unknown>, _options?: unknown) {
          database.writes.push({ table, operation: "upsert", data });
          return query;
        },
        insert(data: Record<string, unknown>) {
          database.writes.push({ table, operation: "insert", data });
          return query;
        },
        then: <T>(resolve: (value: ReturnType<typeof result>) => T) =>
          Promise.resolve(result()).then(resolve),
      };
      return query;
    },
  };
}
