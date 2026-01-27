import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface ContentReviewRequest {
  contentId: string;
  decision: "approved" | "rejected" | "needs_changes";
  feedback?: string;
  feedbackCategories?: string[];
  checklist?: {
    audioQualityOk?: boolean;
    contentSafetyOk?: boolean;
    accuracyOk?: boolean;
    originalityOk?: boolean;
    metadataOk?: boolean;
    accessibilityOk?: boolean;
  };
  internalNotes?: string;
}

interface ContentData {
  id: string;
  creator_id: string;
  title: string;
  status: string;
  creator: {
    user_id: string;
    display_name: string;
  };
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

  // Verify authentication
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

  // Check if user is a clinical reviewer (admin or designated reviewer)
  const { data: adminCheck } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .single();

  if (adminCheck?.role !== "admin" && adminCheck?.role !== "reviewer") {
    return new Response(JSON.stringify({ error: "Reviewer access required" }), {
      status: 403,
    });
  }

  const review: ContentReviewRequest = await req.json();

  // Validate input
  if (!review.contentId || !validateUUID(review.contentId)) {
    return new Response(JSON.stringify({ error: "Invalid content ID" }), {
      status: 400,
    });
  }

  if (
    !review.decision ||
    !["approved", "rejected", "needs_changes"].includes(review.decision)
  ) {
    return new Response(
      JSON.stringify({
        error:
          "Invalid decision. Must be 'approved', 'rejected', or 'needs_changes'",
      }),
      { status: 400 },
    );
  }

  try {
    // Fetch the content
    const { data: content, error: fetchError } = (await supabase
      .from("creator_content")
      .select(
        `
        id,
        creator_id,
        title,
        status,
        creator:creators!inner(id, user_id, display_name)
      `,
      )
      .eq("id", review.contentId)
      .single()) as unknown as {
      data: ContentData | null;
      error: Error | null;
    };

    if (fetchError || !content) {
      return new Response(JSON.stringify({ error: "Content not found" }), {
        status: 404,
      });
    }

    if (content.status !== "submitted" && content.status !== "in_review") {
      return new Response(
        JSON.stringify({
          error: `Content status is '${content.status}'. Only 'submitted' or 'in_review' content can be reviewed.`,
        }),
        { status: 400 },
      );
    }

    // Determine new status based on decision
    let newStatus: string;
    switch (review.decision) {
      case "approved":
        newStatus = "approved";
        break;
      case "rejected":
        newStatus = "rejected";
        break;
      case "needs_changes":
        newStatus = "submitted"; // Goes back to submitted for creator to fix
        break;
    }

    // Update content status
    const { error: updateError } = await supabase
      .from("creator_content")
      .update({
        status: newStatus,
        reviewed_at: new Date().toISOString(),
        reviewer_id: user.id,
        review_feedback: review.feedback,
      })
      .eq("id", review.contentId);

    if (updateError) throw updateError;

    // Create content review record
    const { error: reviewError } = await supabase
      .from("content_reviews")
      .insert({
        content_id: review.contentId,
        reviewer_id: user.id,
        decision: review.decision,
        feedback: review.feedback,
        feedback_categories: review.feedbackCategories,
        audio_quality_ok: review.checklist?.audioQualityOk,
        content_safety_ok: review.checklist?.contentSafetyOk,
        accuracy_ok: review.checklist?.accuracyOk,
        originality_ok: review.checklist?.originalityOk,
        metadata_ok: review.checklist?.metadataOk,
        accessibility_ok: review.checklist?.accessibilityOk,
        internal_notes: review.internalNotes,
      });

    if (reviewError) throw reviewError;

    // If approved, publish the content
    if (review.decision === "approved") {
      const { error: publishError } = await supabase
        .from("creator_content")
        .update({
          status: "published",
          published_at: new Date().toISOString(),
        })
        .eq("id", review.contentId);

      if (publishError) throw publishError;

      console.log(
        `Content published: ${review.contentId} - "${content.title}" by creator ${content.creator.id}`,
      );
    }

    // Log the action
    console.log(
      `Content ${review.contentId} ${review.decision} by reviewer ${user.id}`,
    );

    // Send notification to creator (would integrate with notification service)
    console.log(
      `Would notify creator ${content.creator.user_id}: Your content "${content.title}" has been ${review.decision}`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        message:
          review.decision === "approved"
            ? "Content approved and published."
            : review.decision === "rejected"
              ? "Content rejected."
              : "Content returned for changes.",
        contentId: review.contentId,
        decision: review.decision,
        newStatus: review.decision === "approved" ? "published" : newStatus,
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Content review error:", error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
    });
  }
});
