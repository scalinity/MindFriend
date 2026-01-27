import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface RewriteFeedbackRequest {
  rewriteHistoryId: string;
  rating: number;
  comment?: string;
}

serve(async (req: Request): Promise<Response> => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization" }), {
      status: 401,
    });
  }

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
    });
  }

  try {
    const { rewriteHistoryId, rating, comment } =
      (await req.json()) as RewriteFeedbackRequest;

    if (rating < 1 || rating > 5) {
      return new Response(
        JSON.stringify({ error: "Rating must be between 1 and 5" }),
        { status: 400 },
      );
    }

    const { error: updateError } = await supabase
      .from("rewrite_history")
      .update({
        feedback_rating: rating,
        feedback_comment: comment,
      })
      .eq("id", rewriteHistoryId)
      .eq("user_id", user.id);

    if (updateError) {
      return new Response(
        JSON.stringify({ error: "Failed to submit feedback" }),
        { status: 500 },
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        recordedAt: new Date().toISOString(),
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error submitting feedback:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
    });
  }
});
