// Phase 2: deploy only after relay-capable clients ship. Provider secrets stay here.
import { OPENAI_TRANSCRIPTION_MODEL, SAFETY_NOTE } from "./ai-provider.ts";
import {
  hasNewContractKeys,
  type LeaseEnd,
  parseVoiceContextRequest,
  PrivacyLease,
  VOICE_CONTEXT_ERROR_STATUS,
  VoiceContextError,
  type VoiceContextPort,
} from "./support-voice.ts";
export const XAI_REALTIME_MODEL = "grok-voice-3.0";
export const PROVIDER_URL =
  `wss://api.x.ai/v1/realtime?model=${XAI_REALTIME_MODEL}`;
// AI_PROVIDER=standard relays to OpenAI Realtime (see _shared/ai-provider.ts).
export type RelayVendor = "xai" | "openai";
export const OPENAI_REALTIME_MODEL = "gpt-realtime-2.1-mini";
// The provider route chosen at admission (POST) and stored with the session. GET issues the
// secret, opens the socket and normalizes frames from THIS route, never from ambient config.
export interface VoiceRoute {
  vendor: RelayVendor;
  model: string;
  routeVersion: string;
}
export const VOICE_ROUTE_VERSION = "voice-relay-1";
export function voiceRouteFor(vendor: RelayVendor): VoiceRoute {
  return {
    vendor,
    model: vendor === "openai" ? OPENAI_REALTIME_MODEL : XAI_REALTIME_MODEL,
    routeVersion: VOICE_ROUTE_VERSION,
  };
}
export const OPENAI_REALTIME_URL =
  `wss://api.openai.com/v1/realtime?model=${OPENAI_REALTIME_MODEL}`;
// Exact route tuples this deployment can dispatch. An admission stores the FULL tuple; GET
// dispatches only a stored tuple found here, and derives the secret request, socket URL and
// protocols from that registry entry. A stored tuple that is not listed (a model or route
// version changed by a later deployment) fails closed before the claim, secret and socket and
// requires a fresh admission. It is never rewritten to the currently deployed model.
export const SUPPORTED_VOICE_ROUTES: readonly VoiceRoute[] = [
  {
    vendor: "openai",
    model: OPENAI_REALTIME_MODEL,
    routeVersion: VOICE_ROUTE_VERSION,
  },
  {
    vendor: "xai",
    model: XAI_REALTIME_MODEL,
    routeVersion: VOICE_ROUTE_VERSION,
  },
];
function registered(
  route: VoiceRoute,
  registry: readonly VoiceRoute[],
): VoiceRoute | undefined {
  return registry.find((entry) =>
    entry.vendor === route.vendor && entry.model === route.model &&
    entry.routeVersion === route.routeVersion
  );
}
export function isSupportedVoiceRoute(
  route: VoiceRoute,
  registry: readonly VoiceRoute[] = SUPPORTED_VOICE_ROUTES,
): boolean {
  return registered(route, registry) !== undefined;
}
export interface VoiceDispatch {
  secretUrl: string;
  secretBody: Json;
  socketUrl: string;
  protocols(secret: string): string[];
}
// Provider requests for a stored route, built from the vetted registry entry (never from a
// caller-supplied string or ambient configuration). Null when the tuple is unsupported.
export function voiceDispatchFor(
  route: VoiceRoute,
  registry: readonly VoiceRoute[] = SUPPORTED_VOICE_ROUTES,
): VoiceDispatch | null {
  const entry = registered(route, registry);
  if (!entry) return null;
  return entry.vendor === "openai"
    ? {
      secretUrl: "https://api.openai.com/v1/realtime/client_secrets",
      secretBody: {
        expires_after: { anchor: "created_at", seconds: 300 },
        session: { type: "realtime", model: entry.model },
      },
      socketUrl: `wss://api.openai.com/v1/realtime?model=${entry.model}`,
      protocols: (secret) => ["realtime", "openai-insecure-api-key." + secret],
    }
    : {
      secretUrl: "https://api.x.ai/v1/realtime/client_secrets",
      secretBody: { expires_after: { seconds: 300 } },
      socketUrl: `wss://api.x.ai/v1/realtime?model=${entry.model}`,
      protocols: (secret) => ["xai-client-secret." + secret],
    };
}
// Installed clients pick xAI voice names; each maps to the closest OpenAI voice.
const OPENAI_VOICES: Record<string, string> = {
  ara: "marin", // warm, conversational
  rex: "cedar", // professional, clear
  sal: "sage", // calm, balanced
  eve: "coral", // energetic, upbeat
  leo: "ash", // authoritative, strong
};
// OpenAI events the installed clients do not use. They are dropped, not relayed.
const OPENAI_DROPPED_EVENTS = new Set([
  "conversation.item.done",
  "conversation.item.input_audio_transcription.delta",
  "conversation.item.input_audio_transcription.segment",
  "input_audio_buffer.timeout_triggered",
  "rate_limits.updated",
]);
// Installed clients cancel and commit without tracking provider state. OpenAI
// reports these as errors; xAI did not. They end nothing and are dropped.
const OPENAI_BENIGN_ERRORS = new Set([
  "response_cancel_not_active",
  "input_audio_buffer_commit_empty",
  "conversation_already_has_active_response",
]);
export const MAX_SECONDS = 120;
export const MONTHLY_VOICE_RESERVE_MICRODOLLARS = 240_000;
const MAX_FRAME = 96 * 1024;
const MAX_BUFFER = 256 * 1024;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type Json = Record<string, unknown>;
export interface Clock {
  now(): number;
  set(fn: () => void, ms: number): number;
  clear(id: number): void;
}
export const realClock: Clock = {
  now: () => performance.now(),
  set: (fn, ms) => setTimeout(fn, ms) as unknown as number,
  clear: (id) => clearTimeout(id),
};
export interface RelayDependencies {
  anonKey: string;
  vendor?: RelayVendor;
  authenticate(jwt: string, signal: AbortSignal): Promise<string | null>;
  rpc(name: string, args: Json, signal: AbortSignal): Promise<Json>;
  // `route` is the full tuple stored at admission (new contract); legacy callers omit it and
  // keep the ambient `vendor`. A route that is not exactly supported must not be dispatched.
  issueSecret(signal: AbortSignal, route?: VoiceRoute): Promise<string>;
  connect(secret: string, route?: VoiceRoute): WebSocket;
  upgrade(req: Request): { socket: WebSocket; response: Response };
  // Local credential presence for a route, checked BEFORE any claim consumes allowance.
  providerConfigured?(vendor: RelayVendor): boolean;
  // New-contract context/admission/lease adapter. Absent => new-contract requests fail closed.
  voiceContext?: VoiceContextPort;
  clock?: Clock;
  waitUntil?(work: Promise<unknown>): void;
}
function object(value: unknown): Json {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw Error("INVALID_FRAME");
  }
  return value as Json;
}
function text(value: unknown, limit: number): string {
  if (typeof value !== "string" || value.length > limit) {
    throw Error("INVALID_FRAME");
  }
  return value;
}
function keys(value: Json, allowed: string[]) {
  if (Object.keys(value).some((key) => !allowed.includes(key))) {
    throw Error("INVALID_FRAME");
  }
}
// Reconstruct each allowed event. No tools, search, MCP, resume, model or URLs pass through.
// Returns null for an event the provider does not accept and the relay drops.
// `authority` is the server-frozen final instruction text of a new-contract session: EVERY
// session.update substitutes it, so client instructions can never add to or replace the
// admitted packet. The client's own instructions are still validated, then discarded.
export function clientEvent(
  raw: string,
  premium: boolean,
  vendor: RelayVendor = "xai",
  authority?: string,
): string | null {
  const e = object(JSON.parse(raw));
  const type = text(e.type, 80);
  keys(e, [
    "type",
    "event_id",
    ...(type === "session.update"
      ? ["session"]
      : type === "input_audio_buffer.append"
      ? ["audio"]
      : type === "conversation.item.truncate"
      ? ["item_id", "content_index", "audio_end_ms"]
      : type === "response.create"
      ? ["response"]
      : type === "response.cancel"
      ? ["response_id"]
      : []),
  ]);
  switch (type) {
    case "session.update": {
      const s = object(e.session);
      keys(s, [
        "instructions",
        "voice",
        "turn_detection",
        "audio",
        "input_audio_format",
        "output_audio_format",
        "input_audio_transcription",
        "modalities",
      ]);
      const voice = s.voice ?? "ara";
      if (
        !(premium ? ["ara", "rex", "sal", "eve", "leo"] : ["ara"]).includes(
          String(voice),
        )
      ) throw Error("INVALID_FRAME");
      const vad = s.turn_detection === null
        ? null
        : object(s.turn_detection ?? { type: "server_vad" });
      if (vad) {
        keys(vad, [
          "type",
          "threshold",
          "prefix_padding_ms",
          "silence_duration_ms",
          "create_response",
          "interrupt_response",
        ]);
        if (vad.type !== "server_vad") throw Error("INVALID_FRAME");
        for (const [key, value] of Object.entries(vad)) {
          if (key === "type") continue;
          if (["create_response", "interrupt_response"].includes(key)) {
            if (typeof value !== "boolean") throw Error("INVALID_FRAME");
          } else if (
            typeof value !== "number" || !Number.isFinite(value) || value < 0 ||
            value > (key === "threshold" ? 1 : 2000)
          ) throw Error("INVALID_FRAME");
        }
      }
      const clientInstructions = text(
        s.instructions ?? "You are a supportive voice companion.",
        12000,
      );
      // The authority already contains the standard route's SAFETY_NOTE; legacy appends it.
      const instructions = authority ?? clientInstructions;
      if (vendor === "openai") {
        return JSON.stringify({
          type,
          session: {
            type: "realtime",
            instructions: authority ??
              `${clientInstructions}\n\n${SAFETY_NOTE}`,
            output_modalities: ["audio"],
            tools: [],
            audio: {
              input: {
                format: { type: "audio/pcm", rate: 24000 },
                transcription: { model: OPENAI_TRANSCRIPTION_MODEL },
                turn_detection: vad,
              },
              output: {
                format: { type: "audio/pcm", rate: 24000 },
                voice: OPENAI_VOICES[String(voice)],
              },
            },
          },
        });
      }
      return JSON.stringify({
        type,
        session: {
          instructions,
          voice,
          turn_detection: vad,
          tools: [],
          audio: {
            input: {
              format: { type: "audio/pcm", rate: 24000 },
              transcription: { model: "grok-transcribe" },
            },
            output: { format: { type: "audio/pcm", rate: 24000 } },
          },
        },
      });
    }
    case "input_audio_buffer.append": {
      const audio = text(e.audio, 65536);
      if (
        !audio.length || audio.length % 4 ||
        !/^[A-Za-z0-9+/]*={0,2}$/.test(audio)
      ) throw Error("INVALID_FRAME");
      return JSON.stringify({ type, audio });
    }
    case "pong":
      // OpenAI sends no pings and rejects pong.
      return vendor === "openai" ? null : JSON.stringify({ type });
    case "input_audio_buffer.commit":
    case "input_audio_buffer.clear":
    case "response.cancel":
      return JSON.stringify({ type });
    case "response.create":
      if (e.response && Object.keys(object(e.response)).length) {
        throw Error("INVALID_FRAME");
      }
      return JSON.stringify({ type });
    // The app uses audio and session instructions. Text item creation incurs a
    // separate provider charge and is outside its audio-seconds reservation.
    case "conversation.item.truncate":
      if (
        !Number.isInteger(e.content_index) || e.content_index !== 0 ||
        !Number.isInteger(e.audio_end_ms) || Number(e.audio_end_ms) < 0 ||
        Number(e.audio_end_ms) > 120000
      ) throw Error("INVALID_FRAME");
      return JSON.stringify({
        type,
        item_id: text(e.item_id, 128),
        content_index: 0,
        audio_end_ms: e.audio_end_ms,
      });
    default:
      throw Error("INVALID_FRAME");
  }
}

export function bridgeRelay(client: WebSocket, provider: WebSocket, options: {
  seconds: number;
  premium: boolean;
  vendor?: RelayVendor;
  secret: string;
  clock: Clock;
  deadline: number;
  providerStartedAt?: number;
  // New contract only: the five-second terminal privacy lease (support-voice.ts) and the
  // frozen server instructions that every session.update substitutes.
  lease?: PrivacyLease;
  authority?: string;
  finalize(seconds: number, limited: boolean): Promise<unknown>;
  waitUntil?(work: Promise<unknown>): void;
}): void {
  const { clock } = options;
  let finishLifetime = () => {};
  const lifetime = new Promise<void>((resolve) => {
    finishLifetime = resolve;
  });
  // Upgrading completes the HTTP request. Retain the worker until the provider
  // closes or the existing wall deadline cleans up this bridge.
  options.waitUntil?.(lifetime);
  // Capture before connect, including its synchronous setup and handshake.
  const started = options.providerStartedAt ?? clock.now();
  const timers = new Set<number>();
  const listeners: Array<[WebSocket, string, EventListener]> = [];
  const pending = new Map<WebSocket, string[]>();
  let pendingBytes = 0;
  let stopping = false, finalized = false, limited = false, configured = false;
  let providerOpened = provider.readyState === 1, providerClosed = false;
  let providerCleanClose = false, uncertain = false;
  let frames = 0, bytes = 0, textBytes = 0, windowStart = started;
  function timer(fn: () => void, ms: number) {
    const id = clock.set(() => {
      timers.delete(id);
      fn();
    }, Math.max(0, ms));
    timers.add(id);
  }
  function listen(socket: WebSocket, name: string, fn: EventListener) {
    socket.addEventListener(name, fn);
    listeners.push([socket, name, fn]);
  }
  function clean() {
    for (const id of timers) clock.clear(id);
    timers.clear();
    for (const [s, n, f] of listeners) s.removeEventListener(n, f);
    listeners.length = 0;
    pending.clear();
    pendingBytes = 0;
    options.lease?.dispose();
    finishLifetime();
  }
  function account() {
    if (finalized || !providerClosed || provider.readyState !== 3) return;
    finalized = true;
    const confirmed = providerOpened && providerCleanClose && !uncertain;
    clean();
    // Unknown remote closure keeps the database session active and the fixed
    // monthly reservation intact. A local disconnect is not an invoice cap.
    if (!confirmed) return;
    const seconds = Math.min(
      options.seconds,
      Math.max(0, Math.ceil((clock.now() - started) / 1000)),
    );
    const work = options.finalize(seconds, limited).catch(() => {});
    options.waitUntil?.(work);
  }
  function stop(reason: string) {
    if (reason === "RELAY_ERROR" || reason === "SETUP_TIMEOUT") {
      uncertain = true;
    }
    if (!stopping) {
      stopping = true;
      // Nothing is forwarded after this point; stop refreshing. Accounting listeners stay.
      options.lease?.dispose();
      limited = reason === "SESSION_LIMIT_REACHED";
      try {
        if (client.readyState === 1) {
          client.send(
            JSON.stringify({
              type: "error",
              error: { code: reason, message: reason },
            }),
          );
        }
      } catch { /* socket failed */ }
      for (const s of [client, provider]) {
        try {
          if (s.readyState < 2) s.close(1000, reason);
        } catch { /* retain reservation until confirmed closed */ }
      }
    }
    account();
  }
  // True only while the privacy lease (new contract) is live. Checked against the monotonic
  // clock on every call, so a delayed timer can never admit a late frame.
  function leaseLive(): boolean {
    return options.lease ? options.lease.live() : true;
  }
  function discardPending() {
    pending.clear();
    pendingBytes = 0;
  }
  function send(target: WebSocket, data: string) {
    if (stopping || !leaseLive()) return;
    const size = new TextEncoder().encode(data).byteLength;
    // Each side opens independently. Retain bounded initial events until its
    // handshake completes, including the client's first session.update.
    if (target.readyState === 0) {
      if (pendingBytes + size > MAX_BUFFER) {
        stop("RELAY_BACKPRESSURE");
        return;
      }
      const messages = pending.get(target) ?? [];
      messages.push(data);
      pending.set(target, messages);
      pendingBytes += size;
      return;
    }
    if (
      target.readyState !== 1 ||
      target.bufferedAmount + size > MAX_BUFFER
    ) {
      stop("RELAY_BACKPRESSURE");
      return;
    }
    try {
      target.send(data);
    } catch {
      stop("RELAY_ERROR");
    }
  }
  listen(client, "message", (event) => {
    if (stopping || !leaseLive()) return;
    try {
      const raw = (event as MessageEvent).data;
      if (
        typeof raw !== "string" ||
        new TextEncoder().encode(raw).byteLength > MAX_FRAME
      ) {
        throw Error("FRAME_TOO_LARGE");
      }
      if (clock.now() - windowStart >= 1000) {
        frames = 0;
        bytes = 0;
        windowStart = clock.now();
      }
      if (++frames > 80 || (bytes += raw.length) > 192 * 1024) {
        throw Error("FRAME_RATE_EXCEEDED");
      }
      const filtered = clientEvent(
        raw,
        options.premium,
        options.vendor,
        options.authority,
      );
      if (filtered === null) return;
      if (filtered.startsWith('{"type":"session.update",')) configured = true;
      if (!configured && filtered !== '{"type":"pong"}') {
        throw Error("CONFIGURATION_REQUIRED");
      }
      if (
        !filtered.includes('"type":"input_audio_buffer.append"') &&
        // The substituted server instructions are not the client's to spend.
        (textBytes += options.authority === undefined
            ? filtered.length
            : raw.length) > 32000
      ) throw Error("CONTEXT_LIMIT_REACHED");
      send(provider, filtered);
    } catch {
      stop("INVALID_FRAME");
    }
  });
  listen(provider, "message", (event) => {
    if (stopping || !leaseLive()) return;
    try {
      const raw = (event as MessageEvent).data;
      if (
        typeof raw !== "string" ||
        new TextEncoder().encode(raw).byteLength > MAX_FRAME ||
        raw.includes(options.secret)
      ) throw Error("INVALID_PROVIDER_FRAME");
      const e = object(JSON.parse(raw));
      if (options.vendor === "openai") {
        if (OPENAI_DROPPED_EVENTS.has(String(e.type))) return;
        const code = e.type === "error" && e.error && typeof e.error === "object"
          ? String((e.error as Json).code)
          : "";
        if (OPENAI_BENIGN_ERRORS.has(code)) return;
      }
      if (e.type === "error") {
        stop("PROVIDER_ERROR");
        return;
      }
      if (e.type === "ping") {
        send(client, '{"type":"ping"}');
        return;
      }
      if (e.type === "conversation.created") {
        send(
          client,
          JSON.stringify({ type: e.type, conversation: { id: "relay" } }),
        );
        return;
      }
      if (e.type === "session.created" || e.type === "session.updated") {
        send(
          client,
          JSON.stringify({
            type: e.type,
            session: { id: "relay", voice: "ara" },
          }),
        );
        return;
      }
      // grok-voice-3.0 names new history items "added"; existing clients use
      // the equivalent "created" event. Preserve the item and event metadata.
      if (e.type === "conversation.item.added") {
        send(
          client,
          JSON.stringify({ ...e, type: "conversation.item.created" }),
        );
        return;
      }
      if (
        typeof e.type !== "string" ||
        !/^(response\.(created|done|audio\.(delta|done)|text\.(delta|done)|audio_transcript\.(delta|done)|output_audio\.(delta|done)|output_audio_transcript\.(delta|done)|content_part\.(added|done)|output_item\.(added|done))|input_audio_buffer\.(speech_started|speech_stopped|committed|cleared)|conversation\.item\.(created|truncated|input_audio_transcription\.(updated|completed|failed)))$/
          .test(e.type)
      ) throw Error("INVALID_PROVIDER_FRAME");
      send(client, raw);
    } catch {
      stop("PROVIDER_ERROR");
    }
  });
  for (const s of [client, provider]) {
    listen(s, "error", () => stop("RELAY_ERROR"));
    listen(s, "close", (event) => {
      if (s === provider && provider.readyState === 3) {
        providerClosed = true;
        // An abnormal transport loss does not prove the remote session stopped.
        providerCleanClose = (event as CloseEvent).wasClean === true;
      }
      stop("RELAY_CLOSED");
      account();
    });
    listen(s, "open", () => {
      if (s === provider && provider.readyState === 1) providerOpened = true;
      if (stopping) {
        try {
          s.close(1000, "RELAY_CLOSED");
        } catch { /* retained */ }
      } else if (!leaseLive()) {
        // An open (or queued flush) that completes after expiry is ignored, never replayed.
        discardPending();
      } else {
        const messages = pending.get(s) ?? [];
        pending.delete(s);
        for (const message of messages) {
          pendingBytes -= new TextEncoder().encode(message).byteLength;
          if (stopping) break;
          send(s, message);
        }
      }
    });
  }
  timer(() => {
    if (provider.readyState !== 1 || client.readyState !== 1) {
      stop("SETUP_TIMEOUT");
    }
  }, 12000);
  timer(
    () => stop("SESSION_LIMIT_REACHED"),
    options.seconds * 1000 - (clock.now() - started),
  );
  // End setup/connection within 135s, leaving 15s before the Free worker wall limit.
  timer(() => {
    stop("SESSION_LIMIT_REACHED");
    clean();
  }, options.deadline - clock.now());
  function checkBuffer() {
    if (stopping) return;
    if (
      provider.bufferedAmount > MAX_BUFFER || client.bufferedAmount > MAX_BUFFER
    ) stop("RELAY_BACKPRESSURE");
    else timer(checkBuffer, 250);
  }
  timer(checkBuffer, 250);
  // Privacy revocation/expiry/failure is terminal: queued frames are discarded at once, both
  // sockets close, and the accounting listeners above stay so trusted-close settlement (or an
  // unknown closure) is handled exactly as for any other stop. It proves nothing about
  // provider usage and never authorizes a refund.
  options.lease?.subscribe((end: LeaseEnd) => {
    discardPending();
    stop(
      end === "PRIVACY_REVISION_CHANGED"
        ? "PRIVACY_REVISION_CHANGED"
        : "PRIVACY_LEASE_EXPIRED",
    );
  });
  // Setup shares the lease. If it ran out while the sockets were being created, this bridge
  // starts terminal: nothing is queued, forwarded or opened for use.
  leaseLive();
}

// Shared by the legacy and new-contract paths: the unchanged reservation contract.
function validReservation(claim: Json): number {
  const seconds = Number(claim.reserved_seconds);
  if (
    !Number.isInteger(seconds) || seconds < 1 || seconds > MAX_SECONDS ||
    claim.monthly_reserve_microdollars !== MONTHLY_VOICE_RESERVE_MICRODOLLARS ||
    typeof claim.monthly_budget_month !== "string" ||
    claim.monthly_budget_month.length !== 10 ||
    !/^\d{4}-(0[1-9]|1[0-2])-01$/.test(claim.monthly_budget_month)
  ) throw Error("INVALID_RESERVATION");
  return seconds;
}

export async function handleVoiceRelay(
  req: Request,
  deps: RelayDependencies,
  headers: Record<string, string> = {},
): Promise<Response> {
  const clock = deps.clock ?? realClock;
  const deadline = clock.now() + 135000;
  const response = (status: number, code: string, extra: Json = {}) =>
    new Response(JSON.stringify({ ...extra, error: code, code }), {
      status,
      headers,
    });
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (!["POST", "GET"].includes(req.method)) {
    return response(405, "METHOD_NOT_ALLOWED");
  }
  const controller = new AbortController();
  const signal = AbortSignal.any([controller.signal, req.signal]);
  let timeoutId = 0;
  const timeout = new Promise<never>((_, reject) => {
    timeoutId = clock.set(() => {
      controller.abort();
      reject(Error("SETUP_TIMEOUT"));
    }, 12000);
  });
  // Rejects when the privacy lease ends while setup is pending, so setup stops promptly even
  // if a provider call does not honor its abort signal. Never settles after setup returns.
  let setupDone = false;
  let rejectLeaseEnded: (error: Error) => void = () => {};
  const leaseEnded = new Promise<never>((_, reject) => {
    rejectLeaseEnded = reject;
  });
  let provider: WebSocket | undefined;
  let sessionId = "";
  // Owned by setup until the bridge takes it over; every setup failure must release it.
  let lease: PrivacyLease | undefined;
  try {
    return await Promise.race([
      timeout,
      leaseEnded,
      (async () => {
        const auth = req.headers.get("Authorization");
        if (
          !auth?.startsWith("Bearer ") ||
          // The public routing key may rotate. User authorization comes from
          // authenticate below, never from matching a public key's bytes.
          (req.method === "GET" && !req.headers.get("apikey")?.trim())
        ) return response(401, "UNAUTHORIZED");
        const userId = await deps.authenticate(
          auth.slice(7),
          signal,
        );
        signal.throwIfAborted();
        if (!userId) return response(401, "UNAUTHORIZED");
        if (req.method === "POST") {
          const reader = req.body?.getReader();
          let bodyText = "", bodySize = 0;
          if (reader) {
            try {
              const decoder = new TextDecoder();
              while (true) {
                const { value, done } = await reader.read();
                signal.throwIfAborted();
                if (done) break;
                bodySize += value.byteLength;
                if (bodySize > 1024) return response(413, "REQUEST_TOO_LARGE");
                bodyText += decoder.decode(value, { stream: true });
              }
            } finally {
              void reader.cancel().catch(() => {});
              reader.releaseLock();
            }
          }
          let body: Json;
          try {
            body = object(JSON.parse(bodyText));
          } catch {
            return response(426, "VOICE_APP_UPDATE_REQUIRED");
          }
          if (body.transport !== "relay") {
            return response(426, "VOICE_APP_UPDATE_REQUIRED");
          }
          signal.throwIfAborted();
          if (hasNewContractKeys(body)) {
            // New contract: every failure here is final. There is NO fallback to the
            // legacy prepare, so a missing capability can never downgrade the policy.
            const port = deps.voiceContext;
            if (!port) return response(503, "VOICE_CONTEXT_UNAVAILABLE");
            const parsed = parseVoiceContextRequest(body);
            if (!parsed.ok) return response(parsed.status, parsed.code);
            // Only a tuple this deployment can dispatch is ever admitted.
            const route = voiceRouteFor(deps.vendor ?? "xai");
            if (!isSupportedVoiceRoute(route)) {
              return response(409, "VOICE_ROUTE_UNSUPPORTED");
            }
            // The caller names the account it believes it is; it must be the JWT's.
            if (parsed.value.expectedOwner !== userId) {
              return response(403, "OWNER_MISMATCH");
            }
            const admitted = await port.admit({
              userId,
              request: parsed.value,
              // Frozen here: GET uses the stored route even if ambient config changes.
              route,
            }, signal);
            signal.throwIfAborted();
            if (!admitted.ok) {
              return response(admitted.status, admitted.code, admitted.extra);
            }
            return new Response(
              JSON.stringify({
                ...admitted.prepared,
                token: "",
                transport: "relay",
                max_duration_seconds: MAX_SECONDS,
                voice_context: admitted.voiceContext,
              }),
              { headers },
            );
          }
          const data = await deps.rpc("prepare_voice_relay", {
            p_user_id: userId,
          }, signal);
          signal.throwIfAborted();
          return new Response(
            JSON.stringify({
              ...data,
              token: "",
              transport: "relay",
              max_duration_seconds: MAX_SECONDS,
            }),
            { headers },
          );
        }
        if (
          req.headers.get("upgrade")?.toLowerCase() !== "websocket"
        ) {
          return response(400, "WEBSOCKET_REQUIRED");
        }
        const url = new URL(req.url);
        sessionId = url.searchParams.get("session_id") ?? "";
        if (!UUID.test(sessionId)) return response(400, "INVALID_SESSION");
        const contextParam = url.searchParams.get("voice_context");
        if (contextParam !== null && contextParam !== "1") {
          return response(400, "INVALID_VOICE_CONTEXT");
        }
        const contextual = contextParam === "1";
        let binding: Awaited<ReturnType<VoiceContextPort["binding"]>> = null;
        let frozen: { instructions: string } | undefined;
        if (contextual) {
          const port = deps.voiceContext;
          if (!port) return response(503, "VOICE_CONTEXT_UNAVAILABLE");
          binding = await port.binding(userId, sessionId, signal);
          signal.throwIfAborted();
          // A new-contract client never accepts an unbound (legacy) preparation.
          if (!binding) return response(409, "VOICE_CONTEXT_REQUIRED");
          // The stored vendor/model/route_version must be an exactly supported tuple. Nothing
          // else runs first: no configuration read, source read, claim, secret or socket, and
          // the stored tuple is never substituted with the currently deployed one.
          if (!isSupportedVoiceRoute(binding.route)) {
            return response(409, "VOICE_ROUTE_UNSUPPORTED");
          }
        }
        // The route is the admitted one for new-contract sessions; legacy keeps ambient.
        const vendor: RelayVendor = binding
          ? binding.route.vendor
          : deps.vendor ?? "xai";
        // Missing local configuration can never consume a claimed owner's allowance.
        if (deps.providerConfigured && !deps.providerConfigured(vendor)) {
          return response(503, "CONFIG_ERROR");
        }
        if (binding && deps.voiceContext) {
          // Revalidate the packet against current sources BEFORE any claim, secret or socket.
          frozen = await deps.voiceContext.freeze(binding, signal);
          signal.throwIfAborted();
        }
        // Monotonic START of the revision/eligibility check the claim performs atomically.
        const leaseStartedAt = clock.now();
        const claim = binding && deps.voiceContext
          ? await deps.voiceContext.claim(binding, signal)
          : await deps.rpc("claim_voice_relay", {
            p_user_id: userId,
            p_session_id: sessionId,
          }, signal);
        signal.throwIfAborted();
        const seconds = validReservation(claim);
        if (binding && deps.voiceContext) {
          const port = deps.voiceContext;
          const bound = binding;
          lease = new PrivacyLease({
            clock,
            startedAt: leaseStartedAt,
            check: (checkSignal) => port.check(bound, checkSignal),
          });
          // Setup shares this lease: expiry aborts a pending secret request, and a late
          // secret or socket is never used (see the live() checks below).
          lease.subscribe(() => {
            if (setupDone) return;
            const reason = Error("PRIVACY_LEASE_EXPIRED");
            controller.abort(reason);
            rejectLeaseEnded(reason);
          });
          if (!lease.live()) throw Error("PRIVACY_LEASE_EXPIRED");
        }
        // New contract passes the stored tuple; legacy passes nothing (ambient, as before).
        const storedRoute = binding?.route;
        const secret = await deps.issueSecret(signal, storedRoute);
        signal.throwIfAborted();
        if (lease && !lease.live()) throw Error("PRIVACY_LEASE_EXPIRED");
        if (
          !secret || secret.length > 4096 || !/^[\w.-]+$/.test(secret)
        ) throw Error("INVALID_SECRET");
        const providerStartedAt = clock.now();
        provider = deps.connect(secret, storedRoute);
        // A socket created after the lease ended is never used: close it, answer 409.
        if (lease && !lease.live()) throw Error("PRIVACY_LEASE_EXPIRED");
        const upgraded = deps.upgrade(req);
        // From here the bridge owns lease termination; the HTTP answer is the upgrade.
        setupDone = true;
        bridgeRelay(upgraded.socket, provider, {
          seconds,
          premium: claim.is_premium === true,
          vendor,
          secret,
          clock,
          deadline,
          providerStartedAt,
          lease,
          authority: frozen?.instructions,
          waitUntil: deps.waitUntil,
          finalize: (duration, limited) =>
            deps.rpc("finalize_voice_relay", {
              p_session_id: sessionId,
              p_duration_seconds: duration,
              p_was_quota_limited: limited,
            }, AbortSignal.timeout(4000)),
        });
        return upgraded.response;
      })(),
    ]);
  } catch (error) {
    // No bridge exists: stop refreshing. (Once the bridge owns the lease this is not reached.)
    lease?.dispose();
    if (provider) {
      try {
        provider.close(1000, "RELAY_ERROR");
      } catch { /* retain full reservation */ }
    }
    // No setup/catch path can settle money. Missing closure evidence retains the hold.
    const code = error instanceof Error ? error.message : "";
    if (code === "QUOTA_EXCEEDED") return response(403, code);
    if (
      code === "VOICE_BUDGET_EXCEEDED" ||
      code === "MONTHLY_AI_BUDGET_EXCEEDED"
    ) return response(503, code);
    if (code === "RATE_LIMITED") return response(429, code);
    if (code === "INVALID_SESSION") return response(404, code);
    if (error instanceof VoiceContextError) {
      return response(error.status, error.code, error.extra);
    }
    if (Object.hasOwn(VOICE_CONTEXT_ERROR_STATUS, code)) {
      return response(VOICE_CONTEXT_ERROR_STATUS[code], code);
    }
    return response(409, "VOICE_RELAY_UNAVAILABLE");
  } finally {
    clock.clear(timeoutId);
  }
}
