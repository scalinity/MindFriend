// Local handler tests. No socket permissions, credentials or provider calls.
// Print the transaction fixture for the parent's local database rehearsal with:
// deno run recipient-entitlement-authorization.test.ts --sql-fixture
import { deepStrictEqual, ok, strictEqual } from "node:assert/strict";

type Handler = (request: Request) => Response | Promise<Response>;
type Row = Record<string, unknown>;
const actor = "10000000-0000-4000-8000-000000000001";
const recipient = "a0000000-0000-4000-8000-000000000002";
const outsider = "10000000-0000-4000-8000-000000000003";
const circle = "20000000-0000-4000-8000-000000000001";
const relationship = "30000000-0000-4000-8000-000000000001";
const session = "40000000-0000-4000-8000-000000000001";
const link = "50000000-0000-4000-8000-000000000001";
const userToken = "synthetic-user-token";
const serviceToken = "synthetic-service-key";
const future = "2999-01-01T00:00:00Z";

Deno.test("recipient and organization authorization through actual handlers with mocked HTTP dependencies", async (t) => {
  // All configuration is synthetic; importing handlers opens no listeners.
  Deno.env.set("SUPABASE_URL", "https://supabase.invalid");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", serviceToken);
  Deno.env.set("SUPABASE_ANON_KEY", "synthetic-anon-key");
  const originalServe = Deno.serve;
  const originalFetch = globalThis.fetch;
  const handlers: Handler[] = [];
  let rows: Record<string, Row[]> = {};
  let calls: {
    path: string;
    method: string;
    body?: Row;
    authorization: string | null;
  }[] = [];
  let joinResult: Row = {};
  let brokenTable = "";
  let forwardedResult: Row | undefined;
  const reply = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  const reset = () => {
    calls = [];
    brokenTable = "";
    forwardedResult = undefined;
    rows = {
      user_settings: [{ user_id: recipient, quiet_hours_enabled: false }],
      profiles: [{ id: recipient, timezone: "America/New_York" }],
      organization_admins: [{
        id: actor,
        organization_id: circle,
        role: "admin",
      }],
      push_tokens: [],
      notification_history: [],
      organization_invites: [{
        id: relationship,
        invite_code: "JOINME",
        organization_id: circle,
        created_by_admin_id: actor,
        is_active: true,
        max_uses: 5,
        uses_count: 2,
        expires_at: future,
        organizations: {
          name: "Synthetic organization",
          status: "active",
          subscription_status: "active",
        },
      }],
    };
    joinResult = {
      success: true,
      member: { user_id: actor, organization_id: circle },
      subscription: {
        tier: "organization",
        access_source: "organization_sponsored",
      },
    };
  };
  const pair = () => {
    rows.buddy_relationships = [{
      id: relationship,
      inviter_id: actor,
      invitee_id: recipient,
      status: "accepted",
    }];
    rows.buddy_encouragements = [{
      id: session,
      buddy_relationship_id: relationship,
      sender_id: actor,
      recipient_id: recipient,
    }];
  };
  const partners = () => {
    rows.couples_exercise_sessions = [{
      id: session,
      partner_link_id: link,
      user_id_1: actor,
      user_id_2: recipient,
      status: "pending",
    }];
    rows.partner_links = [{
      id: link,
      user_id_1: actor,
      user_id_2: recipient,
      status: "active",
    }];
  };
  const members = () => {
    rows.circle_members = [actor, recipient].map((user_id) => ({
      id: user_id,
      circle_id: circle,
      user_id,
    }));
  };
  const invoke = async (
    index: number,
    body: Row,
    token: string | null = userToken,
  ) => {
    const response = await handlers[index](
      new Request("https://supabase.invalid/test", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token === null ? {} : { Authorization: `Bearer ${token}` }),
        },
        body: JSON.stringify(body),
      }),
    );
    return { status: response.status, data: await response.json() };
  };
  const noRecipientReads = () =>
    ok(
      !calls.some((c) =>
        /\/(user_settings|profiles|push_tokens)$/.test(c.path)
      ),
    );
  const notification = (type = "buddy_encouragement", data: Row = {}) => ({
    type,
    recipientId: recipient,
    data,
  });

  Deno.serve = ((handler: Handler) => {
    handlers.push(handler);
  }) as typeof Deno.serve;
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    // Unexpected hosts are rejected even if a future test gets net permission.
    strictEqual(url.hostname, "supabase.invalid");
    const body: Row | undefined =
      request.method === "POST" || request.method === "PATCH"
        ? await request.json()
        : undefined;
    calls.push({
      path: url.pathname,
      method: request.method,
      body,
      authorization: request.headers.get("Authorization"),
    });
    if (url.pathname === "/auth/v1/user") {
      return request.headers.get("Authorization") === `Bearer ${userToken}`
        ? reply({
          id: actor,
          aud: "authenticated",
          role: "authenticated",
          email: "actor@example.invalid",
        })
        : reply({ message: "Invalid or expired JWT" }, 401);
    }
    if (url.pathname === "/functions/v1/send-notification") {
      if (forwardedResult) return reply(forwardedResult);
      return handlers[0](
        new Request(request.url, {
          method: "POST",
          headers: request.headers,
          body: JSON.stringify(body),
        }),
      );
    }
    if (url.pathname === "/rest/v1/rpc/check_rate_limit") {
      return reply([{ allowed: true, remaining: 9, reset_at: future }]);
    }
    if (url.pathname === "/rest/v1/rpc/join_organization_with_invite") {
      return reply(joinResult);
    }
    const table = url.pathname.replace("/rest/v1/", "");
    ok(
      url.pathname.startsWith("/rest/v1/"),
      `Unexpected mocked path ${url.pathname}`,
    );
    if (table === brokenTable) {
      return reply({ code: "XX000", message: "Synthetic query failure" }, 500);
    }
    if (request.method === "HEAD") {
      return new Response(null, { headers: { "content-range": "*/0" } });
    }
    strictEqual(
      request.method,
      "GET",
      `Unexpected database mutation to ${table}`,
    );
    let result = rows[table] || [];
    for (const [key, filter] of url.searchParams) {
      if (filter.startsWith("eq.")) {
        result = result.filter((row) => String(row[key]) === filter.slice(3));
      } else if (filter.startsWith("in.(")) {
        const values = filter.slice(4, -1).split(",").map((value) =>
          value.replaceAll('"', "")
        );
        result = result.filter((row) => values.includes(String(row[key])));
      }
    }
    if (url.searchParams.has("limit")) {
      result = result.slice(0, Number(url.searchParams.get("limit")));
    }
    if (
      request.headers.get("Accept")?.includes(
        "application/vnd.pgrst.object+json",
      )
    ) {
      return result.length === 1
        ? reply(result[0])
        : reply({ code: "PGRST116", message: "No row" }, 406);
    }
    return reply(result);
  };
  try {
    await import("../../send-notification/index.ts");
    await import("../../send-notification-batch/index.ts");
    await import("../../join-organization/index.ts");
    await import("../../validate-invite-code/index.ts");
    strictEqual(handlers.length, 4);

    for (const index of [0, 1, 2, 3]) {
      await t.step(
        `handler ${index}: anonymous, empty and expired tokens rejected`,
        async () => {
          for (const token of [null, "", "expired-token"]) {
            reset();
            strictEqual(
              (await invoke(index, notification(), token)).status,
              401,
            );
            ok(!calls.some((c) => c.path.startsWith("/rest/")));
          }
        },
      );
    }
    await t.step(
      "buddy notification rejects unrelated recipient before recipient reads",
      async () => {
        reset();
        strictEqual((await invoke(0, notification())).status, 403);
        noRecipientReads();
      },
    );
    await t.step(
      "buddy relationship must be accepted and have a persisted addressed message",
      async () => {
        for (const status of ["pending", "expired", "declined", "accepted"]) {
          reset();
          pair();
          rows.buddy_relationships[0].status = status;
          if (status === "accepted") {
            rows.buddy_encouragements[0].recipient_id = outsider;
          }
          strictEqual((await invoke(0, notification())).status, 403);
          noRecipientReads();
        }
      },
    );
    await t.step(
      "accepted buddies retain their direct iOS encouragement path in either direction",
      async () => {
        for (const reverse of [false, true]) {
          reset();
          pair();
          if (reverse) {
            Object.assign(rows.buddy_relationships[0], {
              inviter_id: recipient,
              invitee_id: actor,
            });
          }
          const result = await invoke(0, notification());
          strictEqual(result.status, 200);
          strictEqual(result.data.reason, "no_push_token");
        }
      },
    );
    await t.step(
      "uppercase recipient UUIDs from Swift retain valid single and batch paths",
      async () => {
        reset();
        partners();
        strictEqual(
          (await invoke(0, {
            ...notification("couples_exercise_invite", { sessionId: session }),
            recipientId: recipient.toUpperCase(),
          })).status,
          200,
        );
        reset();
        members();
        const result = await invoke(1, {
          type: "hug",
          recipientIds: [recipient.toUpperCase()],
          data: { circleId: circle },
        });
        strictEqual(result.status, 200);
        strictEqual(result.data.results.length, 1);
        strictEqual(result.data.results[0].reason, "no_push_token");
      },
    );
    await t.step(
      "relationship database errors deny recipient access",
      async () => {
        reset();
        pair();
        brokenTable = "buddy_relationships";
        strictEqual((await invoke(0, notification())).status, 403);
        noRecipientReads();
      },
    );
    await t.step(
      "couples notification rejects missing, other-user and nonpending sessions",
      async () => {
        for (const change of ["missing", "other-user", "completed"]) {
          reset();
          partners();
          if (change === "other-user") {
            rows.couples_exercise_sessions[0].user_id_2 = outsider;
          }
          if (change === "completed") {
            rows.couples_exercise_sessions[0].status = "completed";
          }
          strictEqual(
            (await invoke(
              0,
              notification(
                "couples_exercise_invite",
                change === "missing" ? {} : { sessionId: session },
              ),
            )).status,
            403,
          );
          noRecipientReads();
        }
      },
    );
    await t.step(
      "ended partner links deny invitations even for a persisted pending session",
      async () => {
        reset();
        partners();
        rows.partner_links[0].status = "ended";
        strictEqual(
          (await invoke(
            0,
            notification("couples_exercise_invite", { sessionId: session }),
          )).status,
          403,
        );
        noRecipientReads();
      },
    );
    await t.step(
      "active partners retain the persisted iOS exercise invitation path",
      async () => {
        reset();
        partners();
        const result = await invoke(
          0,
          notification("couples_exercise_invite", { sessionId: session }),
        );
        strictEqual(result.status, 200);
        strictEqual(result.data.reason, "no_push_token");
      },
    );
    await t.step(
      "single circle sends require both persisted memberships",
      async () => {
        for (const missing of [actor, recipient]) {
          reset();
          members();
          rows.circle_members = rows.circle_members.filter((row) =>
            row.user_id !== missing
          );
          strictEqual(
            (await invoke(0, notification("hug", { circleId: circle }))).status,
            403,
          );
          noRecipientReads();
        }
        reset();
        members();
        strictEqual(
          (await invoke(0, notification("hug", { circleId: circle }))).status,
          200,
        );
      },
    );
    await t.step(
      "only a verified service credential bypasses user recipient restrictions",
      async () => {
        reset();
        strictEqual(
          (await invoke(0, notification("weekly_summary"), userToken)).status,
          403,
        );
        noRecipientReads();
        reset();
        strictEqual(
          (await invoke(
            0,
            notification("weekly_summary"),
            "forged-service-role-jwt",
          )).status,
          401,
        );
        reset();
        const result = await invoke(
          0,
          notification("weekly_summary"),
          serviceToken,
        );
        strictEqual(result.status, 200);
        strictEqual(result.data.reason, "no_push_token");
        ok(!calls.some((c) => c.path.startsWith("/auth/")));
      },
    );
    await t.step(
      "all batch circle types validate their sender before forwarding",
      async () => {
        for (const type of ["circle_activity", "hug", "challenge"]) {
          reset();
          rows.circle_members = [{
            id: recipient,
            user_id: recipient,
            circle_id: circle,
          }];
          strictEqual(
            (await invoke(1, {
              type,
              recipientIds: [recipient],
              data: { circleId: circle },
            })).status,
            403,
          );
          ok(!calls.some((c) => c.path.startsWith("/functions/")));
        }
      },
    );
    await t.step(
      "batch missing context and forbidden types cannot forward",
      async () => {
        for (
          const [type, data, status] of [["hug", {}, 400], ["weekly_summary", {
            circleId: circle,
          }, 403]] as const
        ) {
          reset();
          members();
          strictEqual(
            (await invoke(1, { type, recipientIds: [recipient], data })).status,
            status,
          );
          ok(!calls.some((c) => c.path.startsWith("/functions/")));
        }
      },
    );
    await t.step(
      "batch filters outsiders and single handler revalidates using original user JWT",
      async () => {
        reset();
        members();
        const result = await invoke(1, {
          type: "challenge",
          recipientIds: [recipient, outsider],
          data: { circleId: circle, senderId: outsider },
        });
        strictEqual(result.status, 200);
        const forwarded = calls.filter((c) => c.path.startsWith("/functions/"));
        strictEqual(forwarded.length, 1);
        strictEqual(forwarded[0].authorization, `Bearer ${userToken}`);
        strictEqual(forwarded[0].body?.recipientId, recipient);
        strictEqual((forwarded[0].body?.data as Row).senderId, actor);
        strictEqual(result.data.results.length, 1);
        strictEqual(result.data.results[0].reason, "no_push_token");
      },
    );
    await t.step(
      "batch delivery counts distinguish sent, queued, skipped and failed",
      async () => {
        for (
          const [payload, expected] of [
            [{ success: true, sent: true }, [1, 0, 0, 0]],
            [{ success: true, sent: false }, [0, 0, 0, 1]],
            [{ success: true, queued: true }, [0, 1, 0, 0]],
            [{ success: true, skipped: true }, [0, 0, 1, 0]],
          ] as const
        ) {
          reset();
          members();
          forwardedResult = { ...payload };
          const result = await invoke(1, {
            type: "challenge",
            recipientIds: [recipient],
            data: { circleId: circle },
          });
          strictEqual(result.status, 200);
          deepStrictEqual([
            result.data.sent,
            result.data.queued,
            result.data.skipped,
            result.data.failed,
          ], expected);
        }
      },
    );
    await t.step(
      "invite validation is read-only and repeated previews preserve quota",
      async () => {
        reset();
        for (let i = 0; i < 2; i++) {
          const result = await invoke(3, { inviteCode: " joinme " });
          strictEqual(result.status, 200);
          strictEqual(result.data.remainingUses, 3);
        }
        strictEqual(rows.organization_invites[0].uses_count, 2);
        ok(
          calls.every((c) => c.path.startsWith("/auth/") || c.method === "GET"),
        );
      },
    );
    await t.step(
      "expired, disabled and exhausted invitations fail validation",
      async () => {
        for (
          const change of [{ expires_at: "2000-01-01T00:00:00Z" }, {
            is_active: false,
          }, { uses_count: 5 }]
        ) {
          reset();
          Object.assign(rows.organization_invites[0], change);
          strictEqual((await invoke(3, { inviteCode: "JOINME" })).status, 400);
        }
      },
    );
    await t.step(
      "inactive, canceled and past-due sponsors cannot validate invitations",
      async () => {
        for (const status of ["inactive", "canceled", "past_due"]) {
          reset();
          (rows.organization_invites[0].organizations as Row)
            .subscription_status = status;
          strictEqual((await invoke(3, { inviteCode: "JOINME" })).status, 403);
        }
        reset();
        (rows.organization_invites[0].organizations as Row).status = "churned";
        strictEqual((await invoke(3, { inviteCode: "JOINME" })).status, 403);
      },
    );
    await t.step(
      "invite preview rejects an issuer from another organization or a viewer",
      async () => {
        for (
          const change of [{ organization_id: outsider }, { role: "viewer" }]
        ) {
          reset();
          Object.assign(rows.organization_admins[0], change);
          strictEqual((await invoke(3, { inviteCode: "JOINME" })).status, 403);
        }
      },
    );
    await t.step(
      "batch recipient query errors cannot forward notifications",
      async () => {
        reset();
        members();
        brokenTable = "circle_members";
        strictEqual(
          (await invoke(1, {
            type: "hug",
            recipientIds: [recipient],
            data: { circleId: circle },
          })).status,
          403,
        );
        ok(!calls.some((c) => c.path.startsWith("/functions/")));
      },
    );
    await t.step(
      "join RPC receives verified identity and normalized invite, ignoring caller role and organization",
      async () => {
        reset();
        const result = await invoke(2, {
          inviteCode: " joinme ",
          userId: outsider,
          organizationId: outsider,
          role: "admin",
        });
        strictEqual(result.status, 200);
        deepStrictEqual(
          calls.find((c) => c.path.endsWith("/join_organization_with_invite"))
            ?.body,
          { p_user_id: actor, p_invite_code: "JOINME" },
        );
        strictEqual(result.data.member.user_id, actor);
        ok(
          !calls.some((c) =>
            c.path.startsWith("/rest/") && !c.path.includes("/rpc/")
          ),
        );
      },
    );
    await t.step(
      "join propagates transactional entitlement, expiry and capacity denials",
      async () => {
        for (
          const [errorCode, status] of [
            ["SPONSORSHIP_INACTIVE", 403],
            ["INVITE_EXPIRED", 400],
            ["MAX_USES_EXCEEDED", 400],
            ["SEAT_LIMIT_REACHED", 400],
            ["ALREADY_MEMBER", 400],
          ] as const
        ) {
          reset();
          joinResult = {
            success: false,
            error: "Synthetic rejection",
            errorCode,
          };
          const result = await invoke(2, { inviteCode: "JOINME" });
          strictEqual(result.status, status);
          strictEqual(result.data.errorCode, errorCode);
        }
      },
    );
  } finally {
    Deno.serve = originalServe;
    globalThis.fetch = originalFetch;
  }
});

// Synthetic SQL rehearsal for the parent lane's disposable restored database.
// Run after the migration; all fixture changes roll back. No production data.
export const organizationJoinSqlFixture = String.raw`
BEGIN;
INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
  ('91000000-0000-4000-8000-000000000001', 'synthetic-owner@example.invalid', '{}'),
  ('91000000-0000-4000-8000-000000000002', 'synthetic-first@example.invalid', '{}'),
  ('91000000-0000-4000-8000-000000000003', 'synthetic-second@example.invalid', '{}'),
  ('91000000-0000-4000-8000-000000000004', 'synthetic-personal@example.invalid', '{}');
INSERT INTO public.organizations(id, name, billing_email, seat_count, seats_used, status, subscription_status)
  VALUES ('92000000-0000-4000-8000-000000000001', 'Synthetic fixture', 'synthetic-billing@example.invalid', 1, 0, 'active', 'inactive');
INSERT INTO public.organization_admins(id, organization_id, user_id, role)
  VALUES ('93000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'admin');
INSERT INTO public.organization_invites(organization_id, invite_code, max_uses, uses_count, created_by_admin_id)
  VALUES ('92000000-0000-4000-8000-000000000001', 'SYNTHETIC_JOIN_GUARD', 5, 0, '93000000-0000-4000-8000-000000000001');
CREATE FUNCTION pg_temp.reject_synthetic_join_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.organization_id = '92000000-0000-4000-8000-000000000001'::uuid
    AND NEW.actor_id = '91000000-0000-4000-8000-000000000003'::uuid THEN
    RAISE EXCEPTION 'Synthetic late-write failure' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER synthetic_join_failure BEFORE INSERT ON public.audit_log
  FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_synthetic_join_audit();
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
DO $$
BEGIN
  BEGIN
    UPDATE public.organizations SET subscription_status = 'active'
      WHERE id = '92000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Authenticated organization admin changed sponsorship';
  EXCEPTION WHEN insufficient_privilege THEN
    IF SQLERRM <> 'Organization sponsorship fields require a service request' THEN RAISE; END IF;
  END;
  -- Normal organization editing must still work through the existing policy.
  UPDATE public.organizations SET name = 'Synthetic renamed fixture'
    WHERE id = '92000000-0000-4000-8000-000000000001';
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization details edit was blocked'; END IF;
END;
$$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$
DECLARE
  first_id uuid := '91000000-0000-4000-8000-000000000002';
  second_id uuid := '91000000-0000-4000-8000-000000000003';
  personal_id uuid := '91000000-0000-4000-8000-000000000004';
  org_id uuid := '92000000-0000-4000-8000-000000000001';
  result jsonb;
BEGIN
  IF has_function_privilege('anon', 'public.join_organization_with_invite(uuid,text)', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.join_organization_with_invite(uuid,text)', 'EXECUTE')
    OR NOT has_function_privilege('service_role', 'public.join_organization_with_invite(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'RPC execution grants are unsafe';
  END IF;
  result := public.join_organization_with_invite(first_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'errorCode' IS DISTINCT FROM 'SPONSORSHIP_INACTIVE' THEN RAISE EXCEPTION 'Inactive sponsor admitted: %', result; END IF;
  UPDATE public.organizations SET subscription_status = 'active' WHERE id = org_id;
  UPDATE public.organization_invites SET expires_at = now() - interval '1 minute' WHERE organization_id = org_id;
  result := public.join_organization_with_invite(first_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'errorCode' IS DISTINCT FROM 'INVITE_EXPIRED' THEN RAISE EXCEPTION 'Expired invite admitted: %', result; END IF;
  UPDATE public.organization_invites SET expires_at = NULL WHERE organization_id = org_id;
  UPDATE public.organization_admins SET role = 'viewer' WHERE organization_id = org_id;
  result := public.join_organization_with_invite(first_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'errorCode' IS DISTINCT FROM 'INVITE_DEACTIVATED' THEN RAISE EXCEPTION 'Viewer-issued invite admitted: %', result; END IF;
  UPDATE public.organization_admins SET role = 'admin' WHERE organization_id = org_id;
  result := public.join_organization_with_invite(first_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'success' IS DISTINCT FROM 'true' OR result->'member'->>'user_id' IS DISTINCT FROM first_id::text
    OR result->'member'->>'organization_id' IS DISTINCT FROM org_id::text THEN RAISE EXCEPTION 'Valid join failed: %', result; END IF;
  result := public.join_organization_with_invite(first_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'errorCode' IS DISTINCT FROM 'ALREADY_MEMBER' THEN RAISE EXCEPTION 'Duplicate join admitted: %', result; END IF;
  result := public.join_organization_with_invite(second_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'errorCode' IS DISTINCT FROM 'SEAT_LIMIT_REACHED' THEN RAISE EXCEPTION 'Last seat claimed twice: %', result; END IF;
  UPDATE public.organizations SET seat_count = 2 WHERE id = org_id;
  UPDATE public.organization_invites SET max_uses = 1 WHERE organization_id = org_id;
  result := public.join_organization_with_invite(second_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'errorCode' IS DISTINCT FROM 'MAX_USES_EXCEEDED' THEN RAISE EXCEPTION 'Exhausted invite admitted: %', result; END IF;
  UPDATE public.organization_invites SET max_uses = 5 WHERE organization_id = org_id;
  BEGIN
    PERFORM public.join_organization_with_invite(second_id, 'SYNTHETIC_JOIN_GUARD');
    RAISE EXCEPTION 'Expected the synthetic late-write failure';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF (SELECT uses_count FROM public.organization_invites WHERE organization_id = org_id) IS DISTINCT FROM 1
    OR (SELECT seats_used FROM public.organizations WHERE id = org_id) IS DISTINCT FROM 1
    OR (SELECT count(*) FROM public.organization_members WHERE organization_id = org_id) <> 1
    OR EXISTS (SELECT 1 FROM public.subscriptions WHERE user_id = second_id) THEN
    RAISE EXCEPTION 'Denied or failed join changed invite, seat, membership or entitlement';
  END IF;
  INSERT INTO public.subscriptions(user_id, product_id, original_transaction_id, plan_type, status, access_source, expires_at)
    VALUES (personal_id, 'synthetic_personal', 'synthetic_personal_transaction', 'individual', 'active', 'personal', now() + interval '1 day');
  result := public.join_organization_with_invite(personal_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'success' IS DISTINCT FROM 'true' OR NOT EXISTS (
    SELECT 1 FROM public.subscriptions WHERE user_id = personal_id AND access_source = 'personal'
      AND original_transaction_id = 'synthetic_personal_transaction') THEN
    RAISE EXCEPTION 'Existing personal purchase was not retained: %', result;
  END IF;
END;
$$;
RESET ROLE;
ROLLBACK;
`;
if (import.meta.main && Deno.args.includes("--sql-fixture")) {
  console.log(organizationJoinSqlFixture);
}
