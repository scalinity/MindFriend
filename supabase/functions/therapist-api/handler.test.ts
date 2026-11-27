// Exercise the actual handler and Supabase SDK with HTTP mocked; no server or credentials are used.
import { hashAPIKey } from "../_shared/therapist-auth.ts";

Deno.env.set("SUPABASE_URL", "http://localhost:54321");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-therapist-api-test-key");

let registered: ((request: Request) => Promise<Response>) | undefined;
const originalServe = Object.getOwnPropertyDescriptor(Deno, "serve")!;
Object.defineProperty(Deno, "serve", {
  configurable: true,
  value: (handler: (request: Request) => Promise<Response>) => {
    registered = handler;
  },
});
try {
  await import("./index.ts");
} finally {
  Object.defineProperty(Deno, "serve", originalServe);
}
if (!registered) throw new Error("Therapist API handler was not registered");
const handle = registered;

const apiKey = "synthetic-therapist-api-key";
const therapist = "22222222-2222-4222-8222-222222222222";
const otherTherapist = "33333333-3333-4333-8333-333333333333";
const rateLimit = 3;

// Columns of public.therapy_access_log (supabase/migrations/20260122000000_remote_schema.sql).
// PostgREST rejects a filter on any other column with 400 / 42703, as production does.
const accessLogColumns = new Set([
  "id",
  "connection_id",
  "therapist_id",
  "action",
  "resource_type",
  "resource_id",
  "ip_address",
  "user_agent",
  "created_at",
]);
type AccessLogRow = { therapist_id: string; created_at: string };

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
function minutesAgo(minutes: number) {
  return new Date(Date.now() - minutes * 60 * 1000).toISOString();
}

function matches(row: AccessLogRow, column: string, filter: string) {
  const value = (row as Record<string, string>)[column];
  if (filter.startsWith("eq.")) return value === filter.slice(3);
  if (filter.startsWith("gte.")) {
    return value !== undefined &&
      new Date(value).getTime() >= new Date(filter.slice(4)).getTime();
  }
  throw new Error(`Unsupported filter ${column}=${filter}`);
}

async function withDatabase(
  accessLog: AccessLogRow[],
  test: (db: { paths: string[] }) => Promise<void>,
) {
  const keyHash = await hashAPIKey(apiKey);
  const originalFetch = globalThis.fetch;
  const db = { paths: [] as string[] };
  const respond = (req: Request) => {
    const url = new URL(req.url);
    assert(
      url.origin === "http://localhost:54321",
      "Unexpected network destination",
    );
    db.paths.push(`${req.method} ${url.pathname}`);

    if (url.pathname === "/rest/v1/integration_api_keys") {
      if (req.method === "PATCH") return new Response(null, { status: 204 });
      assert(
        url.searchParams.get("api_key_hash") === `eq.${keyHash}`,
        "API key lookup did not use the key hash",
      );
      return Response.json({
        id: "synthetic-key",
        therapist_id: therapist,
        name: "Synthetic EHR",
        permissions: [],
        rate_limit_per_hour: rateLimit,
        is_active: true,
        expires_at: null,
        therapist_accounts: {
          id: therapist,
          user_id: "44444444-4444-4444-8444-444444444444",
          is_verified: true,
          practice_name: null,
        },
      });
    }

    if (url.pathname === "/rest/v1/therapy_access_log") {
      assert(req.method === "HEAD", "Access log was not counted with HEAD");
      let rows = accessLog;
      for (const [column, filter] of url.searchParams) {
        if (column === "select") continue;
        if (!accessLogColumns.has(column)) {
          return Response.json({
            code: "42703",
            message: `column therapy_access_log.${column} does not exist`,
          }, { status: 400 });
        }
        rows = rows.filter((row) => matches(row, column, filter));
      }
      return new Response(null, {
        status: 200,
        headers: { "Content-Range": `*/${rows.length}` },
      });
    }

    if (url.pathname === "/rest/v1/therapy_connections") {
      return Response.json([], { headers: { "Content-Range": "*/0" } });
    }

    throw new Error(`Unexpected backend request ${req.method} ${url.pathname}`);
  };
  globalThis.fetch = (input, init) =>
    Promise.resolve().then(() => respond(new Request(input, init)));
  try {
    await test(db);
  } finally {
    globalThis.fetch = originalFetch;
  }
}

async function listClients() {
  const response = await handle(
    new Request("http://localhost/therapist-api/clients", {
      headers: { "X-API-Key": apiKey },
    }),
  );
  return { status: response.status, body: await response.json() };
}

Deno.test("requests at the hourly limit are refused before any client data is read", async () => {
  const accessLog = Array.from({ length: rateLimit }, () => ({
    therapist_id: therapist,
    created_at: minutesAgo(5),
  }));
  await withDatabase(accessLog, async (db) => {
    const result = await listClients();
    assert(
      result.status === 429,
      `Expected 429 at the limit, got ${result.status}`,
    );
    assert(
      result.body.error === "RATE_LIMIT_EXCEEDED",
      "Limit response did not carry RATE_LIMIT_EXCEEDED",
    );
    assert(
      !db.paths.includes("GET /rest/v1/therapy_connections"),
      "Client connections were read after the limit was reached",
    );
  });
});

Deno.test("requests under the hourly limit count only this therapist's last hour and proceed", async () => {
  const accessLog = [
    ...Array.from({ length: rateLimit - 1 }, () => ({
      therapist_id: therapist,
      created_at: minutesAgo(5),
    })),
    ...Array.from({ length: rateLimit }, () => ({
      therapist_id: therapist,
      created_at: minutesAgo(61),
    })),
    ...Array.from({ length: rateLimit }, () => ({
      therapist_id: otherTherapist,
      created_at: minutesAgo(5),
    })),
  ];
  await withDatabase(accessLog, async (db) => {
    const result = await listClients();
    assert(
      result.status === 200,
      `Expected 200 under the limit, got ${result.status}`,
    );
    assert(
      Array.isArray(result.body.clients),
      "Under-limit request did not reach the clients handler",
    );
    assert(
      db.paths.includes("GET /rest/v1/therapy_connections"),
      "Under-limit request did not read client connections",
    );
  });
});
