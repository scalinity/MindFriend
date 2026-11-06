// Executes real handler guards with synthetic configuration. All outbound fetches fail.
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("scheduled handlers reject anonymous requests before any workload", async () => {
  const names = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY", "CRON_SECRET"];
  const previous = names.map((name) => Deno.env.get(name));
  const originalServe = Deno.serve;
  const originalFetch = globalThis.fetch;
  const capture: { handler?: (request: Request) => Promise<Response> } = {};
  function registeredHandler() {
    assert(capture.handler, "No handler registered");
    return capture.handler;
  }
  let fetches = 0;
  try {
    for (const name of names) Deno.env.set(name, name === "SUPABASE_URL" ? "http://127.0.0.1:55321" : "synthetic-only");
    Object.defineProperty(Deno, "serve", { configurable: true, value: (value: (request: Request) => Promise<Response>) => { capture.handler = value; } });
    globalThis.fetch = (() => { fetches++; throw new Error("Unexpected outbound request"); }) as typeof fetch;
    for (const slug of ["generate-weekly-summary", "check-streak-risk", "check-lapsed-users", "proactive-scheduler", "process-notification-queue", "send-assessment-reminders", "predict-mood", "send-weekly-summary", "aggregate-efficacy-profiles", "agent-act", "agent-monitor"]) {
      delete capture.handler;
      await import(`../functions/${slug}/index.ts`);
      const response = await registeredHandler()(new Request(`http://localhost/${slug}`, { method: "POST", body: "{}" }));
      assert(response.status === 401, `${slug}: expected 401, received ${response.status}`);
      await response.body?.cancel();
    }
    assert(fetches === 0, "Anonymous caller reached a workload");
  } finally {
    Object.defineProperty(Deno, "serve", { configurable: true, value: originalServe });
    globalThis.fetch = originalFetch;
    names.forEach((name, i) => previous[i] === undefined ? Deno.env.delete(name) : Deno.env.set(name, previous[i]!));
  }
});
