// Exercise the actual handler and Supabase SDK with HTTP mocked; no server or credentials are used.
Deno.env.set("SUPABASE_URL", "http://localhost:54321");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-safety-plan-test-key");

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
if (!registered) throw new Error("Safety plan handler was not registered");
const handle = registered;
const owner = "11111111-1111-4111-8111-111111111111";
const content = {
  warningSigns: [],
  coping: [],
  contacts: [],
  resources: [],
  environmentSteps: [],
  anchors: [],
};

type Row = {
  id: string;
  user_id: string;
  payload: typeof content;
  allow_ai_reference: boolean;
  version: number;
  created_at: string;
  updated_at: string;
};
function row(preference: boolean): Row {
  return {
    id: "synthetic-plan",
    user_id: owner,
    payload: content,
    allow_ai_reference: preference,
    version: 1,
    created_at: "2026-10-23T12:00:00Z",
    updated_at: "2026-10-23T12:00:00Z",
  };
}
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
async function request(body: Record<string, unknown>) {
  const response = await handle(
    new Request("http://localhost/manage-safety-plan", {
      method: "POST",
      headers: {
        Authorization: "Bearer synthetic-token",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    }),
  );
  return { status: response.status, body: await response.json() };
}

async function withDatabase(
  initial: Row | null,
  test: (
    db: {
      current: Row | null;
      writes: Record<string, unknown>[];
      pauseContent?: () => Promise<void>;
    },
  ) => Promise<void>,
) {
  const originalFetch = globalThis.fetch;
  const db = {
    current: initial,
    writes: [] as Record<string, unknown>[],
    pauseContent: undefined as (() => Promise<void>) | undefined,
  };
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    assert(
      url.origin === "http://localhost:54321",
      "Unexpected network destination",
    );
    if (url.pathname === "/auth/v1/user") return Response.json({ id: owner });
    if (url.pathname === "/rest/v1/safety_plan_cache") {
      return new Response(null, { status: 204 });
    }
    assert(url.pathname === "/rest/v1/safety_plans", "Unexpected backend path");
    if (req.method === "GET") {
      assert(
        url.searchParams.get("user_id") === `eq.${owner}`,
        "Read did not check owner",
      );
      return Response.json(db.current ? [db.current] : []);
    }
    const body = await req.json();
    db.writes.push(body);
    if (req.method === "PATCH") {
      assert(
        url.searchParams.get("user_id") === `eq.${owner}`,
        "Update did not check owner",
      );
      if ("payload" in body) await db.pauseContent?.();
      if (!db.current) return Response.json(null);
      db.current = { ...db.current, ...body };
    } else {
      assert(
        req.method === "POST" && body.user_id === owner,
        "Creation did not check owner",
      );
      assert(db.current === null, "Creation overwrote an existing plan");
      db.current = { ...row(false), ...body };
    }
    return Response.json(db.current);
  };
  try {
    await test(db);
  } finally {
    globalThis.fetch = originalFetch;
  }
}

Deno.test("content-only updates preserve absent preference for both opt-in and opt-out", async () => {
  for (const preference of [false, true]) {
    await withDatabase(row(preference), async (db) => {
      for (
        const settings of [undefined, {}, { allow_ai_reference: !preference }]
      ) {
        const result = await request({
          operation: "update",
          payload: content,
          ...(settings ? { settings } : {}),
        });
        assert(
          result.status === 200 && result.body.success,
          "Content update failed",
        );
        assert(
          db.current?.allow_ai_reference === preference,
          "Content update changed an existing preference",
        );
        assert(
          db.writes.every((write) => !("allow_ai_reference" in write)),
          "Content write included preference",
        );
      }
    });
  }
});

Deno.test("only explicit settings actions change existing preference, including false and legacy true", async () => {
  await withDatabase(row(true), async (db) => {
    for (
      const [settings, expected] of [
        [{ allow_ai_reference: false }, false],
        [{ allow_ai_reference: true }, true],
        [{ allowAiReference: false }, false],
        [{ allowAiReference: true }, true],
      ] as const
    ) {
      const result = await request({ operation: "update", settings });
      assert(
        result.status === 200 && result.body.success,
        "Settings action failed",
      );
      assert(
        db.current?.allow_ai_reference === expected,
        "Explicit boolean preference was lost",
      );
      assert(
        db.writes.at(-1)?.allow_ai_reference === expected,
        "Settings write did not contain exact preference",
      );
      assert(
        !("payload" in db.writes.at(-1)!),
        "Settings action overwrote content",
      );
    }
    const invalid = await request({ operation: "update", settings: {} });
    assert(
      invalid.status === 400 && db.current?.allow_ai_reference === true,
      "Missing explicit setting changed preference",
    );
  });
});

Deno.test("creation defaults safely to false and honors explicit initial true or false", async () => {
  for (
    const [settings, expected] of [
      [undefined, false],
      [{}, false],
      [{ allow_ai_reference: false }, false],
      [{ allow_ai_reference: true }, true],
    ] as const
  ) {
    await withDatabase(null, async (db) => {
      const result = await request({
        operation: "create",
        payload: content,
        ...(settings ? { settings } : {}),
      });
      assert(
        result.status === 200 && db.current?.allow_ai_reference === expected,
        "Creation preference/default incorrect",
      );
      const duplicate = await request({
        operation: "create",
        payload: content,
        settings: { allow_ai_reference: !expected },
      });
      assert(
        duplicate.status === 409 && db.current?.allow_ai_reference === expected,
        "Duplicate creation changed preference",
      );
    });
  }
});

Deno.test("opt-out wins whether it commits before or after an in-flight content save", async () => {
  for (const optOutFirst of [false, true]) {
    await withDatabase(row(true), async (db) => {
      let release!: () => void;
      let entered!: () => void;
      const blocked = new Promise<void>((resolve) => {
        release = resolve;
      });
      const contentStarted = new Promise<void>((resolve) => {
        entered = resolve;
      });
      db.pauseContent = () => {
        entered();
        return blocked;
      };
      // Older clients can still send a stale true snapshot. Existing content writes ignore it.
      const saving = request({
        operation: "update",
        payload: content,
        settings: { allow_ai_reference: true },
      });
      await contentStarted;
      if (optOutFirst) {
        const optedOut = await request({
          operation: "update",
          settings: { allow_ai_reference: false },
        });
        assert(optedOut.status === 200, "Opt-out failed");
      }
      release();
      assert((await saving).status === 200, "Content save failed");
      if (!optOutFirst) {
        await request({
          operation: "update",
          settings: { allow_ai_reference: false },
        });
      }
      assert(
        db.current?.allow_ai_reference === false,
        "Reordered content save restored stale opt-in",
      );
    });
  }
});
