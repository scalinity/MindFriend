import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface SubmitContentRequest {
  contentId: string;
}

interface CreatorInfo {
  id: string;
  user_id: string;
  verification_level: string;
  display_name: string;
}

interface ContentData {
  id: string;
  creator_id: string;
  title: string;
  status: string;
  media_url: string | null;
  category: string;
  duration_seconds: number | null;
  creator: CreatorInfo;
}

function validateUUID(uuid: string): boolean {
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(uuid);
}

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization")!;
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
    });
  }

  const { contentId }: SubmitContentRequest = await req.json();

  // Validate UUID format
  if (!contentId || !validateUUID(contentId)) {
    return new Response(
      JSON.stringify({ error: "Invalid content ID format" }),
      { status: 400 },
    );
  }

  try {
    // Verify ownership and get content
    const { data: content, error: fetchError } = (await supabase
      .from("creator_content")
      .select(
        `
        id,
        creator_id,
        title,
        status,
        media_url,
        category,
        duration_seconds,
        creator:creators!inner(id, user_id, verification_level, display_name)
      `,
      )
      .eq("id", contentId)
      .single()) as unknown as {
      data: ContentData | null;
      error: Error | null;
    };

    if (fetchError || !content) {
      return new Response(JSON.stringify({ error: "Content not found" }), {
        status: 404,
      });
    }

    if (content.creator.user_id !== user.id) {
      return new Response(
        JSON.stringify({ error: "Not authorized to submit this content" }),
        { status: 403 },
      );
    }

    if (content.status !== "draft") {
      return new Response(
        JSON.stringify({ error: "Content must be in draft status to submit" }),
        { status: 400 },
      );
    }

    // Validate required fields
    const missingFields: string[] = [];
    if (!content.title) missingFields.push("title");
    if (!content.media_url) missingFields.push("media file");
    if (!content.category) missingFields.push("category");
    if (!content.duration_seconds) missingFields.push("duration");

    if (missingFields.length > 0) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields",
          missingFields,
        }),
        { status: 400 },
      );
    }

    // Update status to submitted
    const { error: updateError } = await supabase
      .from("creator_content")
      .update({
        status: "submitted",
        submitted_at: new Date().toISOString(),
      })
      .eq("id", contentId);

    if (updateError) throw updateError;

    console.log(
      `Content submitted for review: ${contentId} by creator ${content.creator.id}`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        message:
          "Content submitted for review. Expected review time: 3 business days.",
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Content submission error:", error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
    });
  }
});
