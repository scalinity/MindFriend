import { assertEquals } from "jsr:@std/assert@1.0.19";

type Handler = (req: Request) => Response | Promise<Response>;
let handler!: Handler;
const originalServe = Deno.serve;
try {
  Deno.serve = ((value: Handler) => {
    handler = value;
    return {};
  }) as typeof Deno.serve;
  await import("./index.ts");
} finally {
  Deno.serve = originalServe;
}

const owner = "11111111-1111-4111-8111-111111111111";
const track = "22222222-2222-4222-8222-222222222222";
const first = "33333333-3333-4333-8333-333333333333";
const second = "44444444-4444-4444-8444-444444444444";

for (
  const requested of [first, undefined, "55555555-5555-4555-8555-555555555555"]
) {
  Deno.test(`playback completion binds owner/track/session: ${requested ?? "legacy fallback"}`, async () => {
    const oldFetch = globalThis.fetch;
    const oldEnv = Deno.env.get;
    const updated: string[] = [];
    try {
      Deno.env.get = (name) =>
        ({
          SUPABASE_URL: "http://localhost:54321",
          SUPABASE_SERVICE_ROLE_KEY: "synthetic-key",
        })[name];
      globalThis.fetch = async (input, init) => {
        const req = new Request(input, init);
        const url = new URL(req.url);
        assertEquals(url.origin, "http://localhost:54321");
        if (url.pathname.endsWith("/auth/v1/user")) {
          return Response.json({ id: owner });
        }
        if (url.pathname.endsWith("/audio_tracks")) return Response.json(null);
        assertEquals(url.pathname, "/rest/v1/playback_sessions");
        assertEquals(url.searchParams.get("user_id"), `eq.${owner}`);
        assertEquals(url.searchParams.get("track_id"), `eq.${track}`);
        const id = url.searchParams.get("id")?.slice(3);
        if (req.method === "PATCH") {
          updated.push(id!);
          assertEquals((await req.json()).completed, true);
          return new Response(null, { status: 204 });
        }
        if (id && ![first, second].includes(id)) return Response.json(null);
        if (!id) assertEquals(url.searchParams.get("order"), "created_at.desc");
        return Response.json({ id: id ?? second });
      };
      const response = await handler(
        new Request("http://localhost/record-playback", {
          method: "POST",
          headers: { Authorization: "Bearer synthetic-user" },
          body: JSON.stringify({
            trackId: track,
            eventType: "complete",
            positionSeconds: 100,
            playbackSessionId: requested,
          }),
        }),
      );
      const available = requested === first || requested === undefined;
      assertEquals(response.status, available ? 200 : 404);
      assertEquals(updated, available ? [requested ?? second] : []);
      if (available) assertEquals(await response.json(), { success: true });
    } finally {
      globalThis.fetch = oldFetch;
      Deno.env.get = oldEnv;
    }
  });
}
