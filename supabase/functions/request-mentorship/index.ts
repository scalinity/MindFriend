import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import {
  sanitizeInput,
  validateIntroductionMessage,
  validateUUID,
} from "../_shared/validation.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

export async function handler(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authorization.slice(7),
    );
    if (authError || !user) return json({ error: "Unauthorized" }, 401);
    const body = await req.json().catch(() => null);
    if (
      !body || !validateUUID(body.mentor_id) ||
      !validateIntroductionMessage(body.introduction_message).valid
    ) {
      return json({ error: "Invalid mentor or introduction message" }, 400);
    }
    if (user.id.toLowerCase() === body.mentor_id.toLowerCase()) {
      return json({ error: "Cannot mentor yourself" }, 400);
    }

    // This transaction validates eligibility/capacity and generates both aliases.
    const { data: matchID, error } = await supabase.rpc(
      "create_mentorship_request",
      {
        p_mentor_id: body.mentor_id,
        p_introduction_message: sanitizeInput(body.introduction_message.trim()),
      },
    );
    if (error) {
      if (
        error.message === "Match already exists" ||
        error.message === "Mentor at capacity"
      ) {
        return json({ error: error.message }, 409);
      }
      if (error.message === "Mentor not available") {
        return json({ error: error.message }, 400);
      }
      throw error;
    }
    if (!validateUUID(matchID)) throw new Error("Missing persisted match ID");
    const { data: match, error: readError } = await supabase.from(
      "mentorship_matches",
    )
      .select("id,status,created_at").eq("id", matchID).single();
    if (readError || !match) {
      throw readError ?? new Error("Saved match unavailable");
    }

    // Notification failure does not undo an already persisted request.
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      {
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );
    try {
      await admin.functions.invoke("send-notification", {
        body: {
          user_id: body.mentor_id,
          title: "New Mentorship Request",
          body: "Someone is interested in being your mentee",
          type: "mentorship_request",
          data: { match_id: match.id },
        },
      });
    } catch {
      /* The saved match remains available in the mentor's request list. */
    }
    return json({
      success: true,
      match_id: match.id,
      status: match.status,
      message: "Mentorship request sent.",
      timestamp: match.created_at,
    }, 201);
  } catch {
    return json({ error: "Failed to create mentorship request" }, 500);
  }
}

if (import.meta.main) Deno.serve(handler);
