// Request handler for the `support-session` Edge function, with every dependency
// injected so it can be tested offline. index.ts only wires real implementations.
//
// Ownership always comes from verified auth: the user id is never read from the body,
// and every database call runs as the caller (auth.uid() inside the RPCs).
// Logging is content-free: operation, kind, outcome and duration only.

import {
  parseSupportRequest,
  statusForCode,
  SUPPORT_LIMITS,
  type SupportCapabilities,
  type SupportErrorCode,
  type SupportRequest,
} from "./support-contract.ts";

export interface RpcResult {
  data: unknown;
  error: { code?: string; message: string } | null;
}
export interface SupportCaller {
  userId: string;
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
}
export interface SupportHandlerDeps {
  /** Returns the verified caller, or a ready 401 Response. */
  authenticate(req: Request): Promise<SupportCaller | Response>;
  /** Per-user limiter. Defaults allow everything when omitted. */
  rateLimit?(
    userId: string,
    bucket: "read" | "write",
  ): { allowed: boolean; resetInSeconds?: number };
  cors(origin: string | null): Record<string, string>;
  now?(): number;
  log?(entry: Record<string, unknown>): void;
}

const NOT_DEPLOYED: SupportCapabilities = {
  session_contract: 0,
  context_policy: 0,
  voice_context: 0,
  status: "not_deployed",
};

function json(
  body: unknown,
  status: number,
  headers: Record<string, string>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, "Content-Type": "application/json" },
  });
}

function isMissingFunction(
  e: { code?: string; message: string } | null,
): boolean {
  // PostgREST PGRST202 / Postgres 42883: the RPC is not deployed in this environment.
  return !!e &&
    (e.code === "PGRST202" || e.code === "42883" ||
      /could not find the function/i.test(e.message));
}

export function createSupportSessionHandler(
  deps: SupportHandlerDeps,
): (req: Request) => Promise<Response> {
  const now = deps.now ?? (() => Date.now());
  const log = deps.log ?? ((e) => console.log(JSON.stringify(e)));

  return async (req: Request): Promise<Response> => {
    const started = now();
    const headers = deps.cors(req.headers.get("Origin"));
    if (req.method === "OPTIONS") return new Response("ok", { headers });
    if (req.method !== "POST") {
      return json(
        { ok: false, code: "INVALID_PAYLOAD", message: "POST required" },
        405,
        headers,
      );
    }

    const caller = await deps.authenticate(req);
    if (caller instanceof Response) return caller;

    // Bound the body before parsing.
    const declared = Number(req.headers.get("content-length") ?? "0");
    if (declared > SUPPORT_LIMITS.requestBodyBytes) {
      return json(
        { ok: false, code: "INVALID_PAYLOAD", message: "request too large" },
        413,
        headers,
      );
    }
    let text: string;
    try {
      text = await req.text();
    } catch {
      return json(
        { ok: false, code: "INVALID_PAYLOAD", message: "unreadable body" },
        400,
        headers,
      );
    }
    if (
      new TextEncoder().encode(text).length > SUPPORT_LIMITS.requestBodyBytes
    ) {
      return json(
        { ok: false, code: "INVALID_PAYLOAD", message: "request too large" },
        413,
        headers,
      );
    }
    let body: unknown;
    try {
      body = JSON.parse(text);
    } catch {
      return json(
        { ok: false, code: "INVALID_PAYLOAD", message: "invalid JSON" },
        400,
        headers,
      );
    }

    const parsed = parseSupportRequest(body);
    if (!parsed.ok) {
      return json(
        { ok: false, code: parsed.code, message: parsed.message },
        400,
        headers,
      );
    }
    const request = parsed.value;

    const bucket = request.op === "mutate" || request.op === "memory_mutate"
      ? "write"
      : "read";
    const limited = deps.rateLimit?.(caller.userId, bucket);
    if (limited && !limited.allowed) {
      return json(
        {
          ok: false,
          code: "RATE_LIMITED",
          retry_after_seconds: limited.resetInSeconds,
        },
        429,
        {
          ...headers,
          ...(limited.resetInSeconds
            ? { "Retry-After": String(limited.resetInSeconds) }
            : {}),
        },
      );
    }

    const respond = (
      body: unknown,
      status: number,
      extra: Record<string, unknown> = {},
    ) => {
      log({
        fn: "support-session",
        op: request.op,
        kind: (request as { envelope?: { kind?: string } }).envelope?.kind,
        status,
        ms: now() - started,
        ...extra,
      });
      return json(body, status, headers);
    };

    try {
      return await dispatch(request, caller, respond);
    } catch {
      // Never echo internals or content.
      return respond({ ok: false, code: "TEMPORARY_FAILURE" }, 503);
    }
  };
}

type Respond = (
  body: unknown,
  status: number,
  extra?: Record<string, unknown>,
) => Response;

async function dispatch(
  request: SupportRequest,
  caller: SupportCaller,
  respond: Respond,
): Promise<Response> {
  const call = async (
    fn: string,
    args: Record<string, unknown>,
  ): Promise<{ data: Record<string, unknown> } | { response: Response }> => {
    const { data, error } = await caller.rpc(fn, args);
    if (error) {
      if (isMissingFunction(error)) {
        return {
          response: respond(
            {
              ok: false,
              code: "TEMPORARY_FAILURE",
              capability: "not_deployed",
            },
            503,
            { outcome: "not_deployed" },
          ),
        };
      }
      if (error.code === "42501" || /AUTH_REQUIRED/.test(error.message)) {
        return { response: respond({ ok: false, code: "AUTH_REQUIRED" }, 401) };
      }
      return {
        response: respond({ ok: false, code: "TEMPORARY_FAILURE" }, 503, {
          outcome: "db_error",
          db_code: error.code,
        }),
      };
    }
    if (data === null || typeof data !== "object") {
      return {
        response: respond({ ok: false, code: "TEMPORARY_FAILURE" }, 503, {
          outcome: "bad_shape",
        }),
      };
    }
    return { data: data as Record<string, unknown> };
  };
  const finish = (data: Record<string, unknown>): Response => {
    if (data.ok === false) {
      const code = String(data.code ?? "TEMPORARY_FAILURE") as SupportErrorCode;
      return respond(data, statusForCode(code), { outcome: code });
    }
    return respond(data, 200, {
      outcome: data.no_op === true
        ? "no_op"
        : data.replayed === true
        ? "replayed"
        : "ok",
    });
  };

  switch (request.op) {
    case "capabilities": {
      const { data, error } = await caller.rpc("support_capabilities", {});
      if (isMissingFunction(error)) {
        return respond(NOT_DEPLOYED, 200, { outcome: "not_deployed" });
      }
      if (error || !data || typeof data !== "object") {
        return respond({ ok: false, code: "TEMPORARY_FAILURE" }, 503);
      }
      return respond({ ...(data as SupportCapabilities), status: "ok" }, 200);
    }
    case "get": {
      const r = await call("support_get_session", {
        p_session_id: request.session_id,
        p_after_seq: request.after_seq,
        p_event_limit: request.limit,
      });
      return "response" in r ? r.response : finish(r.data);
    }
    case "list": {
      const r = await call("support_list_sessions", {
        p_limit: request.limit,
        p_cursor_updated_at: request.cursor?.updated_at ?? null,
        p_cursor_id: request.cursor?.id ?? null,
        p_status: request.status,
        p_direction: request.direction,
        p_include_deleted: request.include_deleted,
      });
      return "response" in r ? r.response : finish(r.data);
    }
    case "mutate": {
      const r = await call("support_apply_mutation", {
        p_envelope: request.envelope,
      });
      return "response" in r ? r.response : finish(r.data);
    }
    case "memory_list": {
      const r = await call("support_list_memory", {});
      return "response" in r ? r.response : finish(r.data);
    }
    case "memory_mutate": {
      const r = await call("support_memory_mutate", {
        p_envelope: request.envelope,
      });
      return "response" in r ? r.response : finish(r.data);
    }
    case "receipt": {
      const r = await call("support_get_context_receipt", {
        p_request_id: request.request_id,
      });
      return "response" in r ? r.response : finish(r.data);
    }
  }
}
