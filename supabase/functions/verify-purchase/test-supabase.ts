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
  rpcCalls: [] as { name: string; args: Record<string, unknown> }[],
  familyMembers: [] as { id: string; user_id: string; joined_at: string }[],
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
    this.rpcCalls = [];
    this.familyMembers = [];
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
    rpc(name: string, args: Record<string, unknown>) {
      database.rpcCalls.push({ name, args });
      if (name === "remove_family_member_atomic") {
        // Mirrors release_family_seat: the member leaves and the owner's seat count drops.
        const subscription = database.subscription;
        database.familyMembers = database.familyMembers.filter((member) => member.id !== args.p_member_id);
        if (subscription) subscription.seats_used = Number(subscription.seats_used ?? 1) - 1;
        return Promise.resolve({ data: { success: true }, error: null });
      }
      if (name !== "revoke_verified_apple_transaction") throw new Error("Unexpected RPC");
      if (database.failOperation === "rpc") return Promise.resolve({ data: null, error: { code: "synthetic-revoke-failure" } });
      const subscription = database.subscription;
      const matches = subscription && subscription.user_id === args.p_user_id &&
        subscription.original_transaction_id === args.p_original_transaction_id &&
        subscription.last_transaction_id === args.p_transaction_id;
      if (matches) {
        subscription.status = "cancelled";
        database.writes.push({ table: "subscriptions", operation: "update", data: { status: "cancelled" } });
      }
      return Promise.resolve({ data: Boolean(matches), error: null });
    },
    from(table: string) {
      database.reads.push(table);
      let operation = "select";
      let writeData: Record<string, unknown> | undefined;
      let ascending = true;
      const result = () => {
        // chk_seats_used_lte_total: an update cannot leave more occupied seats than the plan holds.
        const seatsUsed = Number(database.subscription?.seats_used ?? 1);
        const seatsTotal = writeData?.seats_total as number | undefined;
        const error = table === database.failTable && operation === database.failOperation
          ? { code: "synthetic-write-failure", message: "Synthetic persistence failure" }
          : table === "subscriptions" && operation === "update" && seatsTotal !== undefined &&
              seatsTotal !== 0 && seatsUsed > seatsTotal
          ? { code: "23514", message: "chk_seats_used_lte_total" }
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
          : table === "family_members"
          ? [...database.familyMembers].sort((a, b) =>
            ascending ? a.joined_at.localeCompare(b.joined_at) : b.joined_at.localeCompare(a.joined_at))
          : table === "profiles" ? database.profile
          : table === "user_stats" ? database.stats
          : null,
        error,
      }); };
      const query = {
        select: (_columns?: string) => query,
        eq: (_column: string, _value: unknown) => query,
        neq: (_column: string, _value: unknown) => query,
        order(_column: string, options?: { ascending?: boolean }) {
          ascending = options?.ascending ?? true;
          return query;
        },
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
