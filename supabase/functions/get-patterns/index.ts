import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

Deno.serve(async (req: Request): Promise<Response> => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const url = new URL(req.url);
    const category = url.searchParams.get("category");
    const difficulty = url.searchParams.get("difficulty");

    let query = supabase
      .from("breathing_patterns")
      .select("*")
      .order("category", { ascending: true })
      .order("difficulty", { ascending: true });

    if (category) {
      query = query.eq("category", category);
    }
    if (difficulty) {
      query = query.eq("difficulty", difficulty);
    }

    const { data: patterns, error } = await query;

    if (error) {
      console.error("Get patterns error:", error);
      return new Response(
        JSON.stringify({ error: "Failed to fetch patterns" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        patterns: patterns ?? [],
        categories: ["calming", "energizing", "focus"],
        difficulties: ["beginner", "intermediate", "advanced"],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Get patterns error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
