// Real Postgres Changes delivery and RLS isolation, with synthetic local accounts.
const statusPath = Deno.env.get("MINDFRIEND_LOCAL_STATUS");
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
Deno.test({ name: "local Realtime delivers an owned action and filters another user's action", ignore: !statusPath, fn: async () => {
  const cfg = JSON.parse(await Deno.readTextFile(statusPath!));
  const base = cfg.API_URL;
  assert(base === "http://127.0.0.1:55321", "Only the isolated stack is allowed");
  async function api(path: string, body: unknown, token = cfg.SERVICE_ROLE_KEY) {
    const response = await fetch(base + path, { method: "POST", headers: { apikey: cfg.ANON_KEY, Authorization: `Bearer ${token}`, "Content-Type": "application/json", Prefer: "return=representation" }, body: JSON.stringify(body) });
    const data = await response.json();
    assert(response.ok, `Local API returned ${response.status}`);
    return data;
  }
  const password = crypto.randomUUID();
  const sessions: { access_token: string; user: { id: string } }[] = [];
  for (let i = 0; i < 2; i++) {
    const email = `realtime-${crypto.randomUUID()}@example.invalid`;
    await api("/auth/v1/admin/users", { email, password, email_confirm: true });
    sessions.push(await api("/auth/v1/token?grant_type=password", { email, password }, cfg.ANON_KEY));
  }
  const [a, b] = sessions;
  const ws = new WebSocket(base.replace("http:", "ws:") + "/realtime/v1/websocket?apikey=" + cfg.ANON_KEY + "&vsn=1.0.0");
  const delivered: string[] = [];
  let resolveJoined: () => void;
  let rejectJoined: (error: Error) => void;
  const joined = new Promise<void>((resolve, reject) => { resolveJoined = resolve; rejectJoined = reject; });
  let resolveSubscribed: () => void;
  let rejectSubscribed: (error: Error) => void;
  const subscribed = new Promise<void>((resolve, reject) => { resolveSubscribed = resolve; rejectSubscribed = reject; });
  let resolveOwn: () => void;
  const own = new Promise<void>((resolve) => { resolveOwn = resolve; });
  const topic = "realtime:synthetic-actions-" + crypto.randomUUID();
  const timer = setTimeout(() => { rejectJoined(new Error("Realtime join timed out")); rejectSubscribed(new Error("Postgres subscription timed out")); }, 10000);
  let ownTimer: ReturnType<typeof setTimeout> | undefined;
  try {
    ws.onopen = () => ws.send(JSON.stringify({ topic, event: "phx_join", ref: "1", payload: { config: { broadcast: { self: false }, presence: { key: "" }, postgres_changes: [{ event: "INSERT", schema: "public", table: "agent_actions" }] }, access_token: a.access_token } }));
    ws.onerror = () => rejectJoined(new Error("Local Realtime connection failed"));
    ws.onmessage = ({ data }) => {
      const event = JSON.parse(data);
      if (event.event === "phx_reply" && event.ref === "1") {
        if (event.payload.status === "ok" && event.payload.response.postgres_changes?.length === 1) resolveJoined();
        else rejectJoined(new Error("Postgres Changes subscription rejected"));
      }
      if (event.event === "postgres_changes") {
        delivered.push(event.payload.data.record.id);
        resolveOwn();
      }
      if (event.event === "system" && event.payload.extension === "postgres_changes") {
        if (event.payload.status === "ok") resolveSubscribed();
        else rejectSubscribed(new Error("Postgres Changes registration failed: " + event.payload.message));
      }
    };
    await Promise.all([joined, subscribed]);
    clearTimeout(timer);
    const [otherAction] = await api("/rest/v1/agent_actions", { user_id: b.user.id, action_type: "check_in", status: "cancelled", channel: "in_app", content: { synthetic: true } });
    const [ownAction] = await api("/rest/v1/agent_actions", { user_id: a.user.id, action_type: "check_in", status: "cancelled", channel: "in_app", content: { synthetic: true } });
    await Promise.race([own, new Promise((_, reject) => { ownTimer = setTimeout(() => reject(new Error("Owned event not delivered")), 10000); })]);
    await new Promise((resolve) => setTimeout(resolve, 300));
    assert(delivered.includes(ownAction.id), "Owned event missing");
    assert(!delivered.includes(otherAction.id), "Cross-user event leaked");
  } finally {
    clearTimeout(timer);
    clearTimeout(ownTimer);
    await new Promise<void>((resolve) => { if (ws.readyState === WebSocket.CLOSED) resolve(); else { ws.onclose = () => resolve(); ws.close(); } });
  }
} });
