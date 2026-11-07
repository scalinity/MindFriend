import { assertEquals } from "jsr:@std/assert@1.0.19";

type Handler = (req: Request) => Response | Promise<Response>;
let handler!: Handler;
const serve = Deno.serve;
try {
  Deno.serve = ((value: Handler) => {
    handler = value;
    return {};
  }) as typeof Deno.serve;
  await import("./index.ts");
} finally {
  Deno.serve = serve;
}

for (const profileFailure of [true, false]) {
  Deno.test(`capsule profile ${profileFailure ? "query failure" : "absence"} never deletes retained content`, async () => {
    const originalFetch = globalThis.fetch;
    const originalEnv = Deno.env.get;
    const writes: string[] = [];
    let deletedFilter: string | null = null;
    try {
      Deno.env.get = (name) => ({
        SUPABASE_URL: "http://localhost:54321",
        SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-key",
        CRON_SECRET: "synthetic-cron-secret",
      })[name];
      globalThis.fetch = async (input, init) => {
        const request = new Request(input, init);
        const url = new URL(request.url);
        assertEquals(url.origin, "http://localhost:54321");
        if (request.method !== "GET") writes.push(request.method);
        if (url.pathname.endsWith("time_capsules")) {
          deletedFilter = url.searchParams.get("deleted_at");
          return Response.json([{
            id: "11111111-1111-4111-8111-111111111111",
            user_id: "22222222-2222-4222-8222-222222222222",
          }]);
        }
        assertEquals(url.pathname, "/rest/v1/profiles");
        return profileFailure
          ? Response.json({ code: "XX000", message: "Synthetic read failure" }, { status: 503 })
          : Response.json([]);
      };
      const response = await handler(new Request("http://localhost/deliver-capsules", {
        headers: { Authorization: "Bearer synthetic-service-key" },
      }));
      assertEquals(response.status, 200);
      assertEquals((await response.json()).failed, 1);
      assertEquals(writes, []);
      assertEquals(deletedFilter, "is.null");
    } finally {
      globalThis.fetch = originalFetch;
      Deno.env.get = originalEnv;
    }
  });
}
