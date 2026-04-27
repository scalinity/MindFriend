import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  AIFeature,
  ALL_AI_FEATURES,
  ConsentCheckFailedError,
  ConsentRequiredError,
  CURRENT_POLICY_VERSION,
  aiConsentErrorResponse,
  requireAIConsent,
} from "../ai-consent.ts";

const USER_ID = "11111111-1111-1111-1111-111111111111";

function fakeClient(rows: Record<string, { state: string; policy_version: number } | null>) {
  return {
    from(_table: string) {
      return {
        select(_cols: string) {
          return {
            eq(_col1: string, val1: string) {
              return {
                eq(_col2: string, val2: string) {
                  return {
                    maybeSingle: async () => ({
                      data: rows[`${val1}|${val2}`] ?? null,
                      error: null,
                    }),
                  };
                },
              };
            },
          };
        },
      };
    },
  } as any;
}

Deno.test("granted current-version row passes", async () => {
  const sb = fakeClient({
    [`${USER_ID}|chat`]: { state: "granted", policy_version: CURRENT_POLICY_VERSION },
  });
  await requireAIConsent(sb, USER_ID, "chat");
});

Deno.test("missing row throws ConsentRequiredError", async () => {
  const sb = fakeClient({});
  await assertRejects(
    () => requireAIConsent(sb, USER_ID, "chat"),
    ConsentRequiredError,
  );
});

Deno.test("denied state throws", async () => {
  const sb = fakeClient({
    [`${USER_ID}|chat`]: { state: "denied", policy_version: CURRENT_POLICY_VERSION },
  });
  await assertRejects(
    () => requireAIConsent(sb, USER_ID, "chat"),
    ConsentRequiredError,
  );
});

Deno.test("unknown state throws", async () => {
  const sb = fakeClient({
    [`${USER_ID}|chat`]: { state: "unknown", policy_version: CURRENT_POLICY_VERSION },
  });
  await assertRejects(
    () => requireAIConsent(sb, USER_ID, "chat"),
    ConsentRequiredError,
  );
});

Deno.test("stale policy_version throws", async () => {
  const sb = fakeClient({
    [`${USER_ID}|chat`]: { state: "granted", policy_version: CURRENT_POLICY_VERSION - 1 },
  });
  await assertRejects(
    () => requireAIConsent(sb, USER_ID, "chat"),
    ConsentRequiredError,
  );
});

Deno.test("aiConsentErrorResponse returns 403 with expected body", async () => {
  const err = new ConsentRequiredError("chat");
  const resp = aiConsentErrorResponse(err, { "Access-Control-Allow-Origin": "*" });
  assertEquals(resp.status, 403);
  const body = await resp.json();
  assertEquals(body, { code: "ai_consent_required", feature: "chat" });
  assertEquals(resp.headers.get("Content-Type"), "application/json");
  assertEquals(resp.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("ALL_AI_FEATURES contains exactly the 6 expected feature keys", () => {
  const expected: AIFeature[] = [
    "chat", "journal_ai", "voice_journal_ai",
    "image_gen", "insights", "tts_voice",
  ];
  assertEquals([...ALL_AI_FEATURES].sort(), expected.sort());
});

function fakeClientWithError(err: { message: string }) {
  return {
    from(_table: string) {
      return {
        select(_cols: string) {
          return {
            eq(_col1: string, _val1: string) {
              return {
                eq(_col2: string, _val2: string) {
                  return {
                    maybeSingle: async () => ({ data: null, error: err }),
                  };
                },
              };
            },
          };
        },
      };
    },
  } as any;
}

Deno.test("db error throws ConsentCheckFailedError (propagates as 5xx)", async () => {
  const sb = fakeClientWithError({ message: "connection timeout" });
  await assertRejects(
    () => requireAIConsent(sb, USER_ID, "chat"),
    ConsentCheckFailedError,
  );
});

Deno.test("ConsentCheckFailedError is not a ConsentRequiredError", () => {
  const err = new ConsentCheckFailedError("chat", new Error("db down"));
  assert(!(err instanceof ConsentRequiredError));
});

Deno.test("future policy_version passes (>= current is sufficient)", async () => {
  const sb = fakeClient({
    [`${USER_ID}|chat`]: { state: "granted", policy_version: CURRENT_POLICY_VERSION + 1 },
  });
  await requireAIConsent(sb, USER_ID, "chat"); // must not throw
});
