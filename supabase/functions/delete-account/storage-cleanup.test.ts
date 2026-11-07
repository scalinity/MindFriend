import { deepStrictEqual, ok, strictEqual } from "node:assert";

type Handler = (request: Request) => Promise<Response>;
let handler: Handler;
const originalServe = Deno.serve;
Deno.serve = ((fn: Handler) => { handler = fn; return {}; }) as typeof Deno.serve;
try { await import("./index.ts"); } finally { Deno.serve = originalServe; }

const USER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const OTHER = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const BUCKETS = ["creative-works", "capsule-media", "mood-photos", "generated-audio"];
type Failure = "buckets" | "list" | "remove" | "no-op" | undefined;

function fixture(failure?: Failure) {
  const objects = new Map(BUCKETS.map((name) => [name, new Set([
    `${USER.toUpperCase()}/voice-journals/recording.m4a`,
    `${USER}/drawings/sketch.png`,
    `${OTHER}/keep.png`,
  ])]));
  const creative = objects.get("creative-works")!;
  for (let i = 0; i < 125; i++) creative.add(`${USER}/nested/deeper/${i}.png`);
  // Force root pagination before the target folder, and preserve every other owner.
  for (let i = 0; i < 125; i++) creative.add(`0000-${i}/keep.png`);
  const originalOther = [...objects.values()].flatMap((set) => [...set].filter((path) =>
    path.split("/")[0].toLowerCase() !== USER
  )).sort();
  const calls: string[] = [];
  const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
    status, headers: { "Content-Type": "application/json" },
  });
  const fail = () => json({ message: "synthetic failure", error: "StorageError", statusCode: "503" }, 503);
  const fetch: typeof globalThis.fetch = async (input, init) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    strictEqual(url.origin, "https://account-delete.invalid");
    calls.push(`${req.method} ${url.pathname}`);
    if (url.pathname === "/auth/v1/user") return json({ id: USER });
    if (url.pathname === "/storage/v1/bucket") {
      if (failure === "buckets") return fail();
      const buckets = [...Array.from({ length: 101 }, (_, i) => `catalog-${i}`), ...BUCKETS];
      const offset = Number(url.searchParams.get("offset"));
      const limit = Number(url.searchParams.get("limit"));
      return json(buckets.slice(offset, offset + limit).map((id) => ({ id })));
    }
    if (url.pathname.startsWith("/storage/v1/object/list/")) {
      if (failure === "list") return fail();
      const bucket = decodeURIComponent(url.pathname.split("/").at(-1)!);
      const { prefix, limit, offset } = await req.json();
      const entries = new Map<string, { name: string; id: string | null }>();
      for (const path of objects.get(bucket)!) {
        const directory = prefix ? `${prefix}/` : "";
        if (!path.startsWith(directory)) continue;
        const suffix = path.slice(directory.length);
        const name = suffix.split("/")[0];
        entries.set(name, { name, id: suffix.includes("/") ? null : path });
      }
      return json([...entries.values()].sort((a, b) => a.name.localeCompare(b.name)).slice(offset, offset + limit));
    }
    if (req.method === "DELETE" && url.pathname.startsWith("/storage/v1/object/")) {
      if (failure === "remove") return fail();
      const bucket = decodeURIComponent(url.pathname.split("/").at(-1)!);
      const { prefixes } = await req.json();
      ok(prefixes.length <= 100);
      for (const path of prefixes) {
        strictEqual(path.split("/")[0].toLowerCase(), USER);
        if (failure !== "no-op") objects.get(bucket)!.delete(path);
      }
      return json([]);
    }
    // No account mutation may precede verified storage cleanup.
    for (const paths of objects.values()) {
      ok([...paths].every((path) => path.split("/")[0].toLowerCase() !== USER));
    }
    if (url.pathname.startsWith("/rest/v1/")) return json([]);
    if (url.pathname === `/auth/v1/admin/users/${USER}` && req.method === "DELETE") return json({});
    throw new Error(`Unexpected fixture request: ${req.method} ${url.pathname}`);
  };
  return {
    fetch, calls, objects,
    clearFailure() { failure = undefined; },
    assertPreserved() {
      const remaining = [...objects.values()].flatMap((set) => [...set]).sort();
      deepStrictEqual(remaining, originalOther);
    },
  };
}

async function run(f: ReturnType<typeof fixture>) {
  const originalFetch = globalThis.fetch;
  const originalEnvGet = Deno.env.get;
  globalThis.fetch = f.fetch;
  Deno.env.get = (key) => ({
    SUPABASE_URL: "https://account-delete.invalid", SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-key",
  }[key]);
  try {
    const response = await handler(new Request("https://account-delete.invalid/function", {
      method: "POST", headers: { Authorization: "Bearer synthetic-user-token" },
    }));
    await response.text();
    return response.status;
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.get = originalEnvGet;
  }
}

Deno.test("account deletion removes all nested pages and UUID casings before deleting records", async () => {
  const f = fixture();
  strictEqual(await run(f), 200);
  f.assertPreserved();
  ok(f.calls.includes(`DELETE /auth/v1/admin/users/${USER}`));
});

for (const failure of ["buckets", "list", "remove", "no-op"] as const) {
  Deno.test(`account deletion retains records after ${failure} failure and can retry`, async () => {
    const f = fixture(failure);
    strictEqual(await run(f), 500);
    ok(!f.calls.some((call) => call.includes("/rest/v1/") || call.includes("/auth/v1/admin/")));
    f.clearFailure();
    strictEqual(await run(f), 200);
    f.assertPreserved();
  });
}
