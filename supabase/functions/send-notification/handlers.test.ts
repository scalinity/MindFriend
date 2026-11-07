import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.19";
import { TYPE_TO_SETTING } from "../_shared/notification-utils.ts";

// Exercise the deployed handlers and pinned SDK, with every network boundary
// intercepted. No environment secrets or listening server are needed.
type Handler = (req: Request) => Response | Promise<Response>;
let captured!: Handler;
let sendHandler!: Handler;
let queueHandler!: Handler;
let capsuleHandler!: Handler;
const originalServe = Deno.serve;
try {
  Deno.serve = ((handler: Handler) => {
    captured = handler;
    return {};
  }) as typeof Deno.serve;
  await import("./index.ts");
  sendHandler = captured;
  await import("../process-notification-queue/index.ts");
  queueHandler = captured;
  await import("../deliver-capsules/index.ts");
  capsuleHandler = captured;
} finally {
  Deno.serve = originalServe;
}

const recipient = "11111111-1111-4111-8111-111111111111";
const sender = "22222222-2222-4222-8222-222222222222";
const other = "33333333-3333-4333-8333-333333333333";
const serviceKey = "synthetic-service-key";
const legacyTypes = [
  "circle_activity",
  "hug",
  "streak_risk",
  "weekly_summary",
  "challenge",
  "family_member_joined",
  "together_invitation",
  "family_alert",
  "family_challenge_progress",
  "parental_consent_request",
];
// These concrete categories already have content builders and real callers.
const addedTypes = [
  "shield_used",
  "shield_reset",
  "recovery_available",
  "reengagement_gentle",
  "reengagement_social",
  "reengagement_progress",
  "reengagement_fresh_start",
  "proactive_mood_decline",
  "proactive_streak_risk",
  "proactive_milestone",
  "proactive_reengagement",
  "proactive_pattern_insight",
  "assessment_reminder",
  "buddy_encouragement",
  "couples_exercise_invite",
  "agent_action",
  "capsule_ready",
];
const keyPair = await crypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign", "verify"],
);
const testKey = btoa(String.fromCharCode(
  ...new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keyPair.privateKey),
  ),
));

type Row = Record<string, any>;
class Fixture {
  rows: Row[] = [];
  events: string[] = [];
  calls: { url: URL; method: string; body: Row | null }[] = [];
  settings: Row = {
    user_id: recipient,
    quiet_hours_start_local: null,
    quiet_hours_end_local: null,
  };
  tokens = [{ user_id: recipient, device_token: "synthetic-device-token" }];
  members = [sender, recipient];
  relationships: Row[] = [];
  encouragements: Row[] = [];
  session: Row | null = null;
  link: Row | null = null;
  allowedTypes = new Set([...legacyTypes, ...addedTypes]);
  insertError = false;
  updateError = false;
  updateErrorAfterClaim = false;
  zeroUpdatedRows = false;
  tokenError = false;
  settingsError = false;
  missingSettings = false;
  profileError = false;
  configured = true;
  pushStatus = 200;
  pushThrows = false;
  pushBodies: Row[] = [];
  deletedTokens: URL[] = [];
  capsule: Row = {
    id: "44444444-4444-4444-8444-444444444444",
    user_id: recipient,
    title: "A future note",
    status: "delivered",
    deliver_at: "2020-01-01T00:00:00Z",
    deleted_at: null,
    delivery_notification_queued_at: null,
  };
  notificationInvokeError = false;

  queue(type = "agent_action", id = crypto.randomUUID()) {
    this.rows.push({
      id,
      user_id: recipient,
      notification_type: type,
      title: "MindFriend",
      body: "A reminder",
      deep_link: "mindfriend://home",
      metadata: {},
      status: "pending",
      scheduled_for: "2020-01-01T00:00:00Z",
      sent_at: null,
    });
    return id;
  }

  quiet() {
    // Use a timezone whose current hour is safely inside a full quiet window.
    this.timezone = new Intl.DateTimeFormat("en-US", {
        timeZone: "Etc/UTC",
        hour: "numeric",
        hour12: false,
      }).format(new Date()) === "24"
      ? "Etc/GMT+12"
      : "Etc/UTC";
    this.settings.quiet_hours_start_local = "00:00";
    this.settings.quiet_hours_end_local = "24:00";
  }
  timezone = "America/New_York";

  json(value: unknown, status = 200, headers: Record<string, string> = {}) {
    return new Response(JSON.stringify(value), {
      status,
      headers: { "Content-Type": "application/json", ...headers },
    });
  }
  error(code: string, status = 400) {
    return this.json({ code, message: "Synthetic database failure" }, status);
  }

  fetch: typeof fetch = async (input, init) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    const body = req.method === "POST" || req.method === "PATCH"
      ? await req.json()
      : null;
    this.calls.push({ url, method: req.method, body });
    if (url.hostname === "api.sandbox.push.apple.com") {
      this.events.push("apns.send");
      this.pushBodies.push(body);
      if (this.pushThrows) {
        throw new TypeError("Synthetic lost provider response");
      }
      return this.pushStatus === 200
        ? new Response(null, {
          status: 200,
          headers: { "apns-id": "mock-apns-id" },
        })
        : this.json({ reason: "SyntheticFailure" }, this.pushStatus);
    }
    assertEquals(
      url.origin,
      "http://localhost:54321",
      "Unexpected outbound target",
    );
    if (url.pathname === "/auth/v1/user") {
      return this.json({
        id: sender,
        aud: "authenticated",
        role: "authenticated",
      });
    }
    const table = url.pathname.split("/").at(-1);
    const single = req.headers.get("accept")?.includes("vnd.pgrst.object+json");
    if (url.pathname === "/functions/v1/send-notification") {
      if (this.notificationInvokeError) return this.error("XX000", 503);
      return await sendHandler(
        new Request(req.url, {
          method: "POST",
          headers: req.headers,
          body: JSON.stringify(body),
        }),
      );
    }
    if (table === "time_capsules") {
      if (req.method === "PATCH") {
        Object.assign(this.capsule, body);
        return new Response(null, { status: 204 });
      }
      if (url.searchParams.has("id")) return this.json(this.capsule);
      return this.json(
        this.capsule.delivery_notification_queued_at ? [] : [this.capsule],
      );
    }
    if (table === "notification_history") {
      if (req.method === "HEAD") {
        return new Response(null, { headers: { "content-range": "*/0" } });
      }
      if (req.method === "POST") {
        this.events.push("history.insert");
        if (
          this.insertError || !this.allowedTypes.has(body.notification_type)
        ) {
          return this.error("23514");
        }
        if (this.rows.some((r) => r.id === body.id)) {
          return this.error("23505", 409);
        }
        this.rows.push({ scheduled_for: null, sent_at: null, ...body });
        return new Response(null, { status: 201 });
      }
      if (req.method === "PATCH") {
        this.events.push("history.update");
        if (this.updateError || (this.updateErrorAfterClaim && body.status)) {
          return this.error("23514");
        }
        if (this.zeroUpdatedRows) return this.error("PGRST116", 406);
        const row = this.rows.find((r) =>
          `eq.${r.id}` === url.searchParams.get("id")
        );
        assert(row, "Update must address an existing notification UUID");
        if (
          url.searchParams.has("scheduled_for") &&
          (!row.scheduled_for || row.status !== "pending" ||
            new Date(row.scheduled_for) > new Date())
        ) {
          return this.json(null);
        }
        Object.assign(row, body);
        return this.json({ id: row.id });
      }
      // The restored schema has no direct relationship to user_settings.
      if (url.searchParams.get("select")?.includes("user_settings!inner")) {
        return this.error("PGRST200");
      }
      if (url.searchParams.has("id")) {
        return this.json(
          this.rows.find((r) => `eq.${r.id}` === url.searchParams.get("id")) ||
            null,
        );
      }
      return this.json(
        this.rows.filter((r) =>
          r.status === "pending" && r.scheduled_for &&
          new Date(r.scheduled_for) <= new Date()
        ).map((r) => ({ ...r, profiles: { timezone: this.timezone } })),
      );
    }
    if (table === "push_tokens") {
      if (req.method === "DELETE") {
        this.deletedTokens.push(url);
        return new Response(null, { status: 204 });
      }
      const columns = url.searchParams.get("select")?.split(",").map((s) =>
        s.trim()
      );
      if (this.tokenError || columns?.includes("token")) {
        return this.error("42703");
      }
      return this.json(this.tokens);
    }
    if (table === "user_settings") {
      if (this.settingsError) return this.error("XX000");
      return this.json(
        single
          ? (this.missingSettings ? null : this.settings)
          : this.missingSettings
          ? []
          : [this.settings],
      );
    }
    if (table === "profiles") {
      return this.profileError
        ? this.error("XX000")
        : this.json({ timezone: this.timezone });
    }
    if (table === "circle_members") {
      return this.json(this.members.map((user_id) => ({ user_id })));
    }
    if (table === "buddy_relationships") return this.json(this.relationships);
    if (table === "buddy_encouragements") return this.json(this.encouragements);
    if (table === "couples_exercise_sessions") return this.json(this.session);
    if (table === "partner_links") return this.json(this.link);
    throw new Error(`Unmocked call: ${req.method} ${url.pathname}`);
  };

  async run<T>(callback: () => Promise<T>): Promise<T> {
    const originalFetch = globalThis.fetch;
    const originalGet = Deno.env.get;
    const env: Record<string, string> = {
      SUPABASE_URL: "http://localhost:54321",
      SUPABASE_SERVICE_ROLE_KEY: serviceKey,
      CRON_SECRET: "synthetic-cron-secret",
      ...(this.configured
        ? {
          APNS_KEY_ID: "TESTKEY",
          APNS_TEAM_ID: "TESTTEAM",
          APNS_PRIVATE_KEY: testKey,
          APNS_BUNDLE_ID: "test.mindfriend",
        }
        : {}),
    };
    try {
      Deno.env.get = (name) => env[name];
      globalThis.fetch = this.fetch;
      return await callback();
    } finally {
      globalThis.fetch = originalFetch;
      Deno.env.get = originalGet;
    }
  }

  async send(type = "agent_action", data: Row = {}, user = false) {
    return await this.run(async () => {
      const response = await sendHandler(
        new Request("http://localhost/send-notification", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${user ? "user-jwt" : serviceKey}`,
          },
          body: JSON.stringify({
            type,
            recipientId: recipient.toUpperCase(),
            data: type === "capsule_ready"
              ? { capsuleId: this.capsule.id, ...data }
              : data,
          }),
        }),
      );
      return { status: response.status, body: await response.json() };
    });
  }
  async process(authorization = `Bearer ${serviceKey}`) {
    return await this.run(async () => {
      const response = await queueHandler(
        new Request("http://localhost/process-notification-queue", {
          method: "POST",
          headers: { Authorization: authorization },
        }),
      );
      return { status: response.status, body: await response.json() };
    });
  }
}

Deno.test("notification types: all current handler categories persist and deliver", async () => {
  assertEquals(
    new Set(Object.keys(TYPE_TO_SETTING)),
    new Set([
      ...legacyTypes.slice(0, 5),
      ...addedTypes,
    ]),
  );
  for (const type of Object.keys(TYPE_TO_SETTING)) {
    const fixture = new Fixture();
    const result = await fixture.send(type);
    assertEquals(result.status, 200, type);
    if (type === "capsule_ready") {
      assertEquals(result.body.queued, true);
      assertEquals(fixture.pushBodies.length, 0);
      assertEquals((await fixture.process()).body.sent, 1);
      assertEquals(fixture.rows[0].id, fixture.capsule.id);
      continue;
    }
    assertEquals(result.body.sent, true, type);
    assertEquals(fixture.rows[0].notification_type, type);
    assertEquals(fixture.rows[0].status, "sent");
    assertEquals(fixture.rows[0].id, fixture.pushBodies[0].notification_id);
    assertEquals(fixture.events, [
      "history.insert",
      "apns.send",
      "history.update",
    ]);
  }
});

Deno.test("capsule delivery uses the real contract and retries durable admission without duplicates", async () => {
  const fixture = new Fixture();
  const deliver = () =>
    fixture.run(async () => {
      const response = await capsuleHandler(
        new Request("http://localhost/deliver-capsules", {
          headers: { Authorization: `Bearer ${serviceKey}` },
        }),
      );
      return await response.json();
    });
  fixture.notificationInvokeError = true;
  assertEquals((await deliver()).notificationFailures, 1);
  assertEquals(fixture.capsule.status, "delivered");
  assertEquals(fixture.capsule.delivery_notification_queued_at, null);
  assertEquals(fixture.rows.length, 0);
  fixture.notificationInvokeError = false;
  assertEquals((await deliver()).notificationsAdmitted, 1);
  assert(fixture.capsule.delivery_notification_queued_at);
  assertEquals(fixture.rows[0].notification_type, "capsule_ready");
  assertEquals(fixture.rows[0].id, fixture.capsule.id);
  assertEquals(fixture.pushBodies.length, 0);
  // A lost marker response must only confirm the existing queue admission.
  fixture.capsule.delivery_notification_queued_at = null;
  assertEquals((await deliver()).notificationsAdmitted, 1);
  assertEquals(fixture.rows.length, 1);
  fixture.settings.reminders_enabled = false;
  assertEquals((await fixture.process()).body.skipped, 1);
  assertEquals(fixture.pushBodies.length, 0);
});

Deno.test("legacy type constraint rejection prevents push; retry after repair sends once", async () => {
  const fixture = new Fixture();
  fixture.allowedTypes = new Set(legacyTypes);
  const rejected = await fixture.send("agent_action");
  assertEquals(rejected.status, 500);
  assertEquals(rejected.body.success, false);
  assertEquals(fixture.pushBodies.length, 0);
  assertEquals(fixture.rows.length, 0);
  fixture.allowedTypes.add("agent_action");
  assertEquals((await fixture.send("agent_action")).status, 200);
  assertEquals(fixture.pushBodies.length, 1);
});

Deno.test("unknown types, invented wildcards, and schema-only family types cannot enter send", async () => {
  for (
    const type of [
      "unknown",
      "agent_action_extra",
      "reengagement_other",
      "proactive_other",
      "family_alert",
    ]
  ) {
    const fixture = new Fixture();
    assertEquals((await fixture.send(type)).status, 400, type);
    assertEquals(fixture.rows.length, 0);
    assertEquals(fixture.pushBodies.length, 0);
  }
});

Deno.test("quiet hours require durable history before reporting queued; failed insert is retryable", async () => {
  const fixture = new Fixture();
  fixture.quiet();
  fixture.insertError = true;
  const failed = await fixture.send("assessment_reminder");
  assertEquals(failed.status, 500);
  assertEquals(failed.body.success, false);
  assertEquals(failed.body.queued, false);
  assertEquals(fixture.rows.length, 0);
  fixture.insertError = false;
  const queued = await fixture.send("assessment_reminder");
  assertEquals(queued.status, 200);
  assertEquals(queued.body.queued, true);
  assertEquals(fixture.rows[0].status, "pending");
  assert(fixture.rows[0].scheduled_for);
  assertEquals(fixture.pushBodies.length, 0);
});

Deno.test("send token query errors cannot masquerade as no-token success", async () => {
  const fixture = new Fixture();
  fixture.tokenError = true;
  assertEquals((await fixture.send()).status, 500);
  assertEquals(fixture.rows.length, 0);
  assertEquals(fixture.pushBodies.length, 0);
});

Deno.test("unconfigured push providers never record sent notifications", async () => {
  const fixture = new Fixture();
  fixture.configured = false;
  assertEquals((await fixture.send()).status, 503);
  assertEquals(fixture.rows.length, 0);
  fixture.queue();
  assertEquals((await fixture.process()).status, 503);
  assertEquals(fixture.rows[0].status, "pending");
  assertEquals(fixture.rows[0].sent_at, null);
  assertEquals(fixture.pushBodies.length, 0);
});

Deno.test("direct provider failure records failed and does not report success", async () => {
  const fixture = new Fixture();
  fixture.pushStatus = 400;
  const result = await fixture.send();
  assertEquals(result.status, 502);
  assertEquals(result.body.success, false);
  assertEquals(result.body.sent, false);
  assertEquals(fixture.rows[0].status, "failed");
  assertEquals(fixture.rows[0].sent_at, null);
});

Deno.test("send status persistence failure is explicit; unscheduled attempt is not queued for resend", async () => {
  for (const zeroRows of [false, true]) {
    const fixture = new Fixture();
    fixture.updateError = !zeroRows;
    fixture.zeroUpdatedRows = zeroRows;
    const result = await fixture.send();
    assertEquals(result.status, 500);
    assertEquals(result.body.success, false);
    assertEquals(result.body.sent, true);
    assertEquals(result.body.error, "notification_status_persistence_failed");
    assertEquals(fixture.rows[0].status, "pending");
    assertEquals(fixture.rows[0].scheduled_for, null);
    assertEquals((await fixture.process()).body.processed, 0);
    assertEquals(fixture.pushBodies.length, 1);
  }
});

Deno.test("retrying an immediate request after post-send failure has no exactly-once guarantee", async () => {
  const fixture = new Fixture();
  fixture.updateError = true;
  const first = await fixture.send();
  fixture.updateError = false;
  const retry = await fixture.send();
  assertEquals(first.status, 500);
  assertEquals(retry.status, 200);
  assertNotEquals(first.body.id, retry.body.id);
  assertEquals(fixture.pushBodies.length, 2);
});

Deno.test("privacy: opt-out and recovery suppression still prevent history and pushes", async () => {
  const disabled = new Fixture();
  disabled.settings.proactive_enabled = false;
  assertEquals(
    (await disabled.send()).body.reason,
    "notification_type_disabled",
  );
  assertEquals(disabled.rows.length, 0);
  assertEquals(disabled.pushBodies.length, 0);
  const recovery = new Fixture();
  recovery.settings.recovery_mode_active = true;
  assertEquals(
    (await recovery.send("reengagement_gentle")).body.reason,
    "recovery_mode_active",
  );
  assertEquals(recovery.rows.length, 0);
  assertEquals(recovery.pushBodies.length, 0);
});

Deno.test("authority: service-only types remain forbidden for authenticated users", async () => {
  for (
    const type of addedTypes.filter((t) =>
      !["buddy_encouragement", "couples_exercise_invite"].includes(t)
    )
  ) {
    const fixture = new Fixture();
    assertEquals((await fixture.send(type, {}, true)).status, 403, type);
    assertEquals(fixture.rows.length, 0);
    assertEquals(fixture.pushBodies.length, 0);
  }
});

Deno.test("authority: circle recipients and sender identity remain checked", async () => {
  const fixture = new Fixture();
  fixture.members = [sender, other];
  assertEquals(
    (await fixture.send(
      "hug",
      { circleId: "test-circle", senderId: other },
      true,
    )).status,
    403,
  );
  fixture.members = [sender, recipient];
  assertEquals(
    (await fixture.send(
      "hug",
      { circleId: "test-circle", senderId: other },
      true,
    )).status,
    200,
  );
  assertEquals(fixture.rows[0].metadata.senderId, sender);
});

Deno.test("authority: buddy and couples notifications still require persisted recipient context", async () => {
  const buddy = new Fixture();
  assertEquals((await buddy.send("buddy_encouragement", {}, true)).status, 403);
  buddy.relationships = [{ id: "buddy-link" }];
  assertEquals((await buddy.send("buddy_encouragement", {}, true)).status, 403);
  buddy.encouragements = [{ id: "persisted-encouragement" }];
  assertEquals((await buddy.send("buddy_encouragement", {}, true)).status, 200);
  const couples = new Fixture();
  couples.session = {
    partner_link_id: "partner-link",
    user_id_1: sender,
    user_id_2: other,
  };
  assertEquals(
    (await couples.send(
      "couples_exercise_invite",
      { sessionId: "session" },
      true,
    )).status,
    403,
  );
  couples.session.user_id_2 = recipient;
  couples.link = { user_id_1: sender, user_id_2: other };
  assertEquals(
    (await couples.send(
      "couples_exercise_invite",
      { sessionId: "session" },
      true,
    )).status,
    403,
  );
  couples.link.user_id_2 = recipient;
  assertEquals(
    (await couples.send(
      "couples_exercise_invite",
      { sessionId: "session" },
      true,
    )).status,
    200,
  );
});

Deno.test("queue uses device_token and real settings lookup; existing UUID survives delivery", async () => {
  const fixture = new Fixture();
  const id = fixture.queue();
  const result = await fixture.process();
  assertEquals(result.status, 200);
  assertEquals(result.body.sent, 1);
  assertEquals(fixture.rows[0].status, "sent");
  assertEquals(fixture.pushBodies[0].notification_id, id);
  assert(fixture.calls.some((c) => c.url.pathname.endsWith("user_settings")));
  assertEquals((await fixture.process()).body.processed, 0);
  assertEquals(fixture.pushBodies.length, 1);
});

Deno.test("queue token/settings failures leave pending rows untouched for retry", async () => {
  for (
    const failure of ["tokenError", "settingsError", "missingSettings"] as const
  ) {
    const fixture = new Fixture();
    fixture.queue();
    fixture[failure] = true;
    assertEquals((await fixture.process()).status, 500, failure);
    assertEquals(fixture.rows[0].status, "pending");
    assertEquals(fixture.pushBodies.length, 0);
    fixture[failure] = false;
    assertEquals((await fixture.process()).body.sent, 1);
  }
});

Deno.test("queue respects quiet hours and distinguishes no token from provider rejection", async () => {
  const quiet = new Fixture();
  quiet.queue();
  quiet.quiet();
  const queued = await quiet.process();
  assertEquals(queued.body.stillQueued, 1);
  assertEquals(quiet.rows[0].status, "pending");
  assertEquals(quiet.pushBodies.length, 0);
  const noToken = new Fixture();
  noToken.queue();
  noToken.tokens = [];
  assertEquals((await noToken.process()).body.noToken, 1);
  assertEquals(noToken.rows[0].status, "failed");
  const rejected = new Fixture();
  rejected.queue();
  rejected.pushStatus = 400;
  assertEquals((await rejected.process()).body.failed, 1);
  assertEquals(rejected.rows[0].status, "failed");
  assertEquals(rejected.rows[0].sent_at, null);
});

Deno.test("queue claim failure sends nothing and remains retryable", async () => {
  for (const zeroRows of [false, true]) {
    const fixture = new Fixture();
    const id = fixture.queue();
    fixture.updateError = !zeroRows;
    fixture.zeroUpdatedRows = zeroRows;
    const failed = await fixture.process();
    assertEquals(failed.status, 500);
    assertEquals(failed.body.success, false);
    assertEquals(failed.body.claimFailures, 1);
    assertEquals(fixture.rows[0].status, "pending");
    assertEquals(fixture.pushBodies.length, 0);
    fixture.updateError = false;
    fixture.zeroUpdatedRows = false;
    assertEquals((await fixture.process()).body.sent, 1);
    assertEquals(fixture.pushBodies.map((p) => p.notification_id), [id]);
  }
});

Deno.test("queue post-send persistence failure retains uncertainty without replay", async () => {
  const fixture = new Fixture();
  fixture.queue();
  fixture.updateErrorAfterClaim = true;
  const failed = await fixture.process();
  assertEquals(failed.status, 500);
  assertEquals(failed.body.persistenceFailures, 1);
  assertEquals(fixture.rows[0].scheduled_for, null);
  assertEquals(fixture.rows[0].metadata.delivery_state, "attempting");
  fixture.updateErrorAfterClaim = false;
  assertEquals((await fixture.process()).body.processed, 0);
  assertEquals(fixture.pushBodies.length, 1);
});

Deno.test("queue retries explicit 503 rejection with the same identity, then succeeds", async () => {
  const fixture = new Fixture();
  const id = fixture.queue();
  fixture.pushStatus = 503;
  assertEquals((await fixture.process()).body.stillQueued, 1);
  assertEquals(fixture.rows[0].status, "pending");
  assertEquals(fixture.rows[0].metadata.delivery_attempts, 1);
  assert(new Date(fixture.rows[0].scheduled_for) > new Date());
  assertEquals((await fixture.process()).body.processed, 0);
  fixture.rows[0].scheduled_for = "2020-01-01T00:00:00Z";
  fixture.pushStatus = 200;
  assertEquals((await fixture.process()).body.sent, 1);
  assertEquals(fixture.rows[0].status, "sent");
  assertEquals(fixture.rows[0].metadata.provider_results[0].apnsId, "mock-apns-id");
  assertEquals(fixture.pushBodies.map((p) => p.notification_id), [id, id]);
});

Deno.test("queue bounds temporary rejection retries at four attempts", async () => {
  const fixture = new Fixture();
  fixture.queue();
  fixture.pushStatus = 429;
  for (let attempt = 1; attempt <= 4; attempt++) {
    fixture.rows[0].scheduled_for = "2020-01-01T00:00:00Z";
    await fixture.process();
    assertEquals(fixture.rows[0].metadata.delivery_attempts, attempt);
    assertEquals(fixture.rows[0].status, attempt < 4 ? "pending" : "failed");
  }
  assertEquals((await fixture.process()).body.processed, 0);
  assertEquals(fixture.pushBodies.length, 4);
});

Deno.test("queue transport uncertainty is retained and never automatically replayed", async () => {
  const fixture = new Fixture();
  fixture.queue();
  fixture.pushThrows = true;
  const result = await fixture.process();
  assertEquals(result.status, 500);
  assertEquals(result.body.uncertain, 1);
  assertEquals(fixture.rows[0].metadata.delivery_state, "uncertain");
  assertEquals(fixture.rows[0].scheduled_for, null);
  fixture.pushThrows = false;
  assertEquals((await fixture.process()).body.processed, 0);
  assertEquals(fixture.pushBodies.length, 1);
});

Deno.test("concurrent queue runs claim one provider attempt", async () => {
  const fixture = new Fixture();
  fixture.queue();
  await fixture.run(async () => {
    const request = () =>
      new Request("http://localhost/process-notification-queue", {
        method: "POST",
        headers: { Authorization: `Bearer ${serviceKey}` },
      });
    await Promise.all([queueHandler(request()), queueHandler(request())]);
  });
  assertEquals(fixture.pushBodies.length, 1);
});

Deno.test("invalid-token cleanup uses device_token and exact user in both handlers", async () => {
  const send = new Fixture();
  send.pushStatus = 410;
  await send.send();
  const queue = new Fixture();
  queue.queue();
  queue.pushStatus = 410;
  await queue.process();
  for (const fixture of [send, queue]) {
    assertEquals(fixture.deletedTokens.length, 1);
    assertEquals(
      fixture.deletedTokens[0].searchParams.get("device_token"),
      "eq.synthetic-device-token",
    );
    assertEquals(
      fixture.deletedTokens[0].searchParams.get("user_id"),
      `eq.${recipient}`,
    );
    assertEquals(fixture.deletedTokens[0].searchParams.has("token"), false);
  }
});

Deno.test("queue requires service/cron authority before any database access", async () => {
  const fixture = new Fixture();
  assertEquals((await fixture.process("Bearer user-jwt")).status, 401);
  assertEquals(fixture.calls.length, 0);
});

Deno.test("immediate preference/profile failures stop before history or APNs", async () => {
  for (
    const failure of [
      "settingsError",
      "missingSettings",
      "profileError",
    ] as const
  ) {
    const fixture = new Fixture();
    fixture[failure] = true;
    const result = await fixture.send();
    assertEquals(result.status, 503);
    assertEquals(result.body.success, false);
    assertEquals(fixture.rows.length, 0);
    assertEquals(fixture.pushBodies.length, 0);
  }
});

Deno.test("queued delivery rechecks current opt-out and settles without a push", async () => {
  const fixture = new Fixture();
  fixture.queue("agent_action");
  fixture.settings.proactive_enabled = false;
  const result = await fixture.process();
  assertEquals(result.status, 200);
  assertEquals(result.body.skipped, 1);
  assertEquals(result.body.sent, 0);
  assertEquals(fixture.rows[0].status, "failed");
  assertEquals(fixture.rows[0].sent_at, null);
  assertEquals(
    fixture.rows[0].metadata.skipped_reason,
    "notification_type_disabled",
  );
  assertEquals(fixture.pushBodies.length, 0);
  fixture.settings.proactive_enabled = true;
  assertEquals((await fixture.process()).body.processed, 0);
  assertEquals(fixture.pushBodies.length, 0);
});

Deno.test("queued recovery suppression uses current preferences and no delivery marker", async () => {
  const fixture = new Fixture();
  fixture.queue("reengagement_gentle");
  fixture.settings.recovery_mode_active = true;
  const result = await fixture.process();
  assertEquals(result.body.skipped, 1);
  assertEquals(fixture.rows[0].status, "failed");
  assertEquals(fixture.rows[0].metadata.skipped_reason, "recovery_mode_active");
  assertEquals(fixture.rows[0].sent_at, null);
  assertEquals(fixture.pushBodies.length, 0);
});

Deno.test("suppression persistence failure stays retryable without contacting APNs", async () => {
  const fixture = new Fixture();
  fixture.queue();
  fixture.settings.proactive_enabled = false;
  fixture.updateError = true;
  assertEquals((await fixture.process()).status, 500);
  assertEquals(fixture.rows[0].status, "pending");
  assertEquals(fixture.pushBodies.length, 0);
  fixture.updateError = false;
  assertEquals((await fixture.process()).body.skipped, 1);
  assertEquals(fixture.pushBodies.length, 0);
});
