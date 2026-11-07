import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { validatePagination } from "../_shared/validation.ts";

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
    // The RPC checks auth.uid(); keep the verified caller's JWT on every read.
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
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json({ error: "Invalid request" }, 400);
    }
    const { limit = 5, offset = 0 } = body;
    const pagination = validatePagination(limit, offset);
    if (
      !pagination.valid || !Number.isInteger(limit) || !Number.isInteger(offset)
    ) {
      return json({ error: "Invalid pagination parameters" }, 400);
    }

    const { data: profile, error: profileError } = await supabase.from(
      "mentorship_profiles",
    )
      .select("seeking_areas").eq("user_id", user.id).maybeSingle();
    if (profileError) throw profileError;
    const { data: rows, error } = await supabase.rpc("find_mentor_matches", {
      p_user_id: user.id,
      p_seeking_areas: profile?.seeking_areas ?? [],
      // The database returns at most ten candidates. Page that bounded result.
      p_limit: Math.min(limit + offset, 10),
    });
    if (error) throw error;
    const page = (rows ?? []).slice(offset, offset + limit);
    const ids = page.map((row: { mentor_user_id: string }) =>
      row.mentor_user_id
    );
    const { data: profiles, error: metadataError } = ids.length
      ? await supabase.from("mentorship_profiles").select(
        "user_id,timezone,verified",
      ).in("user_id", ids)
      : { data: [], error: null };
    if (metadataError) throw metadataError;
    const metadata = new Map(
      (profiles ?? []).map((item) => [item.user_id, item]),
    );
    const matches = page.map((row: Record<string, unknown>) => {
      const profile = metadata.get(row.mentor_user_id);
      return {
        mentor_id: row.mentor_user_id,
        // Discovery does not expose real names; aliases are assigned to a match.
        mentor_name: "Mentor",
        mentor_alias: "",
        expertise_areas: row.expertise_areas,
        availability_hours_week: row.availability_hours_week ?? 0,
        languages: row.languages,
        timezone: profile?.timezone ?? "UTC",
        compatibility_score: Number(row.compatibility_score),
        match_reasons: row.match_reason ? [row.match_reason] : [],
        is_verified: profile?.verified === true,
      };
    });
    return json({
      success: true,
      matches,
      count: matches.length,
      timestamp: new Date().toISOString(),
    });
  } catch {
    return json({ error: "Failed to find mentor matches" }, 500);
  }
}

if (import.meta.main) Deno.serve(handler);
