import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1.0.19";
import { observedTrajectory } from "./observations.ts";

Deno.env.set("SUPABASE_URL", "https://efficacy.synthetic.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-service-key");
type Handler = (request: Request) => Promise<Response>;
const handlers: Handler[] = [];
const originalServe = Deno.serve;
Deno.serve = ((handler: Handler) => { handlers.push(handler); return {}; }) as typeof Deno.serve;
await import("./index.ts");
await import("../get-efficacy-dashboard/index.ts");
await import("../get-recommendations/index.ts");
await import("../aggregate-efficacy-profiles/index.ts");
Deno.serve = originalServe;
const [calculate, dashboard, recommend, aggregate] = handlers;
const owner = "11111111-1111-4111-8111-111111111111";
const exercise = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const session = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

function storedObservation() {
  return {
    id: "trajectory", user_id: owner, exercise_id: exercise, session_id: session,
    measurement_status: "observed", measurement_source: "self_reported_valence", created_at: new Date().toISOString(),
    samples: [0, 0.2, 0.2].map((valence, i) => ({
      timestamp: new Date(i * 30_000).toISOString(), seconds_from_start: i * 30,
      emotion_classification: { primary: "calm", valence },
      // Unsupported legacy fields are never read or propagated as observations.
      composite_score: 1, hrv_reading: 80, nervous_system_state: "rest",
    })),
  };
}

Deno.test("only explicitly sourced observations qualify; legacy, synthetic and invalid values stay unavailable", () => {
  const record = storedObservation();
  for (const status of [undefined, "legacy_unverified", "synthetic"]) {
    assertEquals(observedTrajectory({ ...record, measurement_status: status }), null);
  }
  assertEquals(observedTrajectory({ ...record, measurement_source: "unknown" }), null);
  assertEquals(observedTrajectory({ ...record, samples: record.samples.slice(0, 2) }), null);
  for (const value of [NaN, Infinity, -1.1, 1.1, "0.2"]) {
    const invalid = structuredClone(record);
    invalid.samples[1].emotion_classification.valence = value as number;
    assertEquals(observedTrajectory(invalid), null);
  }
  const duplicate = structuredClone(record);
  duplicate.samples[1].seconds_from_start = 0;
  assertEquals(observedTrajectory(duplicate), null);
  const points = observedTrajectory(record)!;
  assertEquals(points.map(p => p.compositeScore), [0, 0.2, 0.2]);
  assertEquals(points.some(p => p.hrvReading !== undefined || p.nervousSystemState !== undefined), false);
});

type Row = Record<string, any>;
class Fixture {
  tables: Record<string, Row[]> = {
    exercise_sessions: [{ id: session, user_id: owner, exercise_id: exercise }],
    exercises: [{ id: exercise, title: "Synthetic breathing", type: "breathing", duration_minutes: 5 }],
  };
  writes: { table: string; data: any }[] = [];
  reads: { table: string; query: URLSearchParams }[] = [];
  install() {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
      const request = input instanceof Request ? input : new Request(input, init);
      const url = new URL(request.url);
      assertEquals(url.origin, "https://efficacy.synthetic.invalid", "No live network access is permitted");
      const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
        status, headers: { "Content-Type": "application/json" },
      });
      if (url.pathname === "/auth/v1/user") return json({ id: owner });
      const table = url.pathname.split("/").at(-1)!;
      if (request.method === "POST") {
        const data = await request.json();
        this.writes.push({ table, data: structuredClone(data) });
        const rows = (Array.isArray(data) ? data : [data]).map(row => ({ id: crypto.randomUUID(), ...row }));
        if (table === "user_efficacy_profiles") this.tables[table] = rows;
        else (this.tables[table] ??= []).push(...rows);
        return json(request.headers.get("Accept")?.includes("vnd.pgrst.object") ? rows[0] : rows, 201);
      }
      assertEquals(request.method, "GET");
      this.reads.push({ table, query: url.searchParams });
      let rows = (this.tables[table] ?? []).filter(row => [...url.searchParams].every(([key, filter]) => {
        if (["select", "order", "limit", "offset"].includes(key)) return true;
        const [op, ...parts] = filter.split(".");
        const value = parts.join(".");
        if (op === "eq") return String(row[key]) === value;
        if (op === "gte") return row[key] >= (typeof row[key] === "number" ? Number(value) : value);
        if (op === "in") return value.slice(1, -1).split(",").includes(String(row[key]));
        throw new Error(`Unsupported fixture filter: ${filter}`);
      }));
      const order = url.searchParams.get("order");
      if (order) {
        const [key, direction] = order.split(".");
        rows.sort((a, b) => (a[key] < b[key] ? -1 : a[key] > b[key] ? 1 : 0) * (direction === "desc" ? -1 : 1));
      }
      const limit = url.searchParams.get("limit");
      if (limit) rows = rows.slice(0, Number(limit));
      if (url.searchParams.get("select")?.includes("exercises:exercise_id")) {
        const projection = url.searchParams.get("select")!;
        if (projection.includes("name")) assertEquals(projection.includes("name:title"), true,
          "Dashboard must preserve its name response via the actual title column");
        rows = rows.map(row => ({ ...row, exercises: { id: exercise, title: "Synthetic breathing", name: "Synthetic breathing", type: "breathing", duration_minutes: 5 } }));
      }
      return json(request.headers.get("Accept")?.includes("vnd.pgrst.object") ? rows[0] ?? null : rows);
    }) as typeof fetch;
    return () => { globalThis.fetch = originalFetch; };
  }
}
function request(body: Row = {}, cron = false) {
  return new Request("https://function.synthetic.invalid", { method: "POST", headers: {
    Authorization: `Bearer ${cron ? "synthetic-service-key" : "synthetic-user"}`, "Content-Type": "application/json",
  }, body: JSON.stringify(body) });
}
function legacyEfficacy(status = "legacy_unverified", score = 99): Row {
  return { id: "legacy", user_id: owner, exercise_id: exercise, session_id: session,
    measurement_status: status, efficacy_score: score, completed_at: new Date().toISOString(),
    starting_state: { primaryEmotion: "calm" }, time_of_day: "morning", net_emotional_change: 0.2,
    breakthrough_detected: false, trajectory_shape: "flat" };
}

Deno.test("ordinary or legacy-client session is unavailable and creates no physiological or efficacy records", async () => {
  const db = new Fixture();
  const legacy = { ...storedObservation(), measurement_status: "legacy_unverified", measurement_source: null };
  db.tables.emotional_trajectories = [legacy];
  const before = structuredClone(db.tables);
  const restore = db.install();
  try {
    for (const points of [[], [{ compositeScore: -1 }, { compositeScore: 0 }, { compositeScore: 1 }]]) {
      const response = await calculate(request({ sessionId: session, exerciseId: exercise, trajectoryPoints: points }));
      assertEquals(response.status, 200);
      assertEquals((await response.json()).status, "unavailable");
    }
    assertEquals(db.writes, []);
    assertEquals(db.tables, before, "Historical records remain untouched");
  } finally { restore(); }
});

Deno.test("observed stored reports determine the persisted and dashboard scores; request mock values are ignored", async () => {
  const db = new Fixture();
  db.tables.emotional_trajectories = [storedObservation()];
  db.tables.intervention_efficacy = [legacyEfficacy()];
  const restore = db.install();
  try {
    const response = await calculate(request({ sessionId: session, exerciseId: exercise,
      trajectoryPoints: [-1, 0, 1].map(compositeScore => ({ compositeScore })) }));
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.status, "observed");
    assertAlmostEquals(body.efficacy_score, 79.2, 1e-10);
    assertEquals(db.writes.length, 1);
    assertEquals(db.writes[0].table, "intervention_efficacy");
    assertEquals(db.writes[0].data.measurement_status, "observed");
    assertEquals(db.writes[0].data.measurement_source, "self_reported_valence");
    assertEquals(db.writes[0].data.starting_state, { primaryEmotion: "calm" });
    const dashboardResponse = await dashboard(request());
    assertEquals(dashboardResponse.status, 200);
    const displayed = await dashboardResponse.json();
    assertEquals(displayed.recentSessions.length, 1);
    assertEquals(displayed.recentSessions[0].exerciseName, "Synthetic breathing");
    assertAlmostEquals(displayed.recentSessions[0].efficacyScore, body.efficacy_score, 1e-10);
  } finally { restore(); }
});

Deno.test("legacy profiles and sessions do not populate the dashboard or personalized recommendations", async () => {
  const db = new Fixture();
  db.tables.intervention_efficacy = [legacyEfficacy()];
  db.tables.user_efficacy_profiles = [{ ...legacyEfficacy(), completion_count: 20, overall_efficacy_score: 100 }];
  const before = structuredClone(db.tables);
  const restore = db.install();
  try {
    const response = await dashboard(request());
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.recentSessions, []);
    assertEquals(body.topExercises, []);
    assertEquals(body.measurementStatus, "unavailable");
    const recommendations = await recommend(request({ limit: 3 }));
    assertEquals(recommendations.status, 200);
    const fallback = await recommendations.json();
    assertEquals(fallback.recommendations.length, 1);
    assertEquals(fallback.recommendations[0].contentId, exercise);
    assertEquals(fallback.fallbackReason.includes("measurements"), true);
    assertEquals(db.writes, []);
    assertEquals(db.tables, before);
  } finally { restore(); }
});

Deno.test("aggregation uses only observed results and marks the derived profile observed", async () => {
  const db = new Fixture();
  db.tables.intervention_efficacy = [legacyEfficacy(), legacyEfficacy("synthetic"), legacyEfficacy("observed", 79.2)];
  const restore = db.install();
  try {
    const response = await aggregate(request({}, true));
    assertEquals(response.status, 200);
    assertEquals((await response.json()).updatedCount, 1);
    const profile = db.writes.find(w => w.table === "user_efficacy_profiles")!.data[0];
    assertEquals(profile.completion_count, 1);
    assertEquals(profile.overall_efficacy_score, 79.2);
    assertEquals(profile.measurement_status, "observed");
    assertEquals(profile.efficacy_by_state, {}, "Absent physiological observations must not become an unknown-state claim");
    for (const read of db.reads.filter(r => r.table === "intervention_efficacy")) {
      assertEquals(read.query.get("measurement_status"), "eq.observed");
    }
  } finally { restore(); }
});
