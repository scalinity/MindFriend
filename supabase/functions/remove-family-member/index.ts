import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { getCorsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  const headers = {
    ...getCorsHeaders(req.headers.get("Origin")),
    "Content-Type": "application/json",
  };
  const reply = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers });
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);
  try {
    const token = req.headers.get("Authorization")?.replace(/^Bearer /i, "");
    if (!token) return reply({ error: "Unauthorized" }, 401);
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: { user }, error: authError } = await admin.auth.getUser(
      token,
    );
    if (authError || !user) return reply({ error: "Unauthorized" }, 401);
    const body = await req.json().catch(() => null);
    if (
      typeof body?.member_id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        body.member_id,
      )
    ) {
      return reply({ error: "Invalid member" }, 400);
    }
    const { data, error } = await admin.rpc("remove_family_member_atomic", {
      p_actor_id: user.id,
      p_member_id: body.member_id,
    });
    if (error) {
      return reply(
        { error: "Unable to remove family member" },
        error.code === "42501" ? 403 : error.code === "22023" ? 400 : 500,
      );
    }
    if (!data?.success) {
      return reply({ error: "Unable to remove family member" }, 500);
    }
    return reply({ success: true });
  } catch {
    return reply({ error: "Unable to remove family member" }, 500);
  }
});
