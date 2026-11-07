import { authenticateStaffRequest } from "../_shared/staff-auth.ts";
import { isAuthError } from "../_shared/auth.ts";

interface ReviewRequest {
  applicationId: string;
  decision: "approved" | "rejected";
  reviewNotes?: string;
  rejectionReason?: string;
  rejectionCategory?: "credentials" | "quality" | "other";
}

interface ApplicationData {
  id: string;
  user_id: string;
  full_name: string;
  email: string;
  status: string;
  credentials: Array<{
    type: string;
    name: string;
    issuer: string;
    year?: number;
  }>;
}

function validateUUID(uuid: string): boolean {
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(uuid);
}

Deno.serve(async (req) => {
  const auth = await authenticateStaffRequest(req, ["admin"]);
  if (isAuthError(auth)) return auth.response;
  const { user, supabaseAdmin: supabase } = auth;

  const review: ReviewRequest = await req.json();

  // Validate input
  if (!review.applicationId || !validateUUID(review.applicationId)) {
    return new Response(JSON.stringify({ error: "Invalid application ID" }), {
      status: 400,
    });
  }

  if (!review.decision || !["approved", "rejected"].includes(review.decision)) {
    return new Response(
      JSON.stringify({
        error: "Invalid decision. Must be 'approved' or 'rejected'",
      }),
      { status: 400 },
    );
  }

  if (review.decision === "rejected" && !review.rejectionReason) {
    return new Response(
      JSON.stringify({ error: "Rejection reason is required" }),
      { status: 400 },
    );
  }

  try {
    // Fetch the application
    const { data: application, error: fetchError } = (await supabase
      .from("creator_applications")
      .select("*")
      .eq("id", review.applicationId)
      .single()) as unknown as {
      data: ApplicationData | null;
      error: Error | null;
    };

    if (fetchError || !application) {
      return new Response(JSON.stringify({ error: "Application not found" }), {
        status: 404,
      });
    }

    if (
      application.status !== "pending" &&
      application.status !== "under_review"
    ) {
      return new Response(
        JSON.stringify({
          error: `Application has already been ${application.status}`,
        }),
        { status: 400 },
      );
    }

    // Update application status
    const { error: updateError } = await supabase
      .from("creator_applications")
      .update({
        status: review.decision === "approved" ? "approved" : "rejected",
        reviewer_id: user.id,
        review_notes: review.reviewNotes,
        rejection_reason: review.rejectionReason,
        rejection_category: review.rejectionCategory,
        reviewed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", review.applicationId);

    if (updateError) throw updateError;

    // If approved, create the creator profile
    if (review.decision === "approved") {
      const { data: existingCreator } = await supabase
        .from("creators")
        .select("id")
        .eq("user_id", application.user_id)
        .single();

      if (!existingCreator) {
        const { data: newCreator, error: creatorError } = await supabase
          .from("creators")
          .insert({
            user_id: application.user_id,
            display_name: application.full_name,
            bio: null,
            credentials: application.credentials,
            status: "approved",
          })
          .select()
          .single();

        if (creatorError) throw creatorError;

        console.log(
          `Creator profile created: ${newCreator.id} for user ${application.user_id}`,
        );
      }
    }

    // Log the action
    console.log(
      `Application ${review.applicationId} ${review.decision} by admin ${user.id}`,
    );

    // Send email notification (would integrate with email service)
    // For now, just log it
    console.log(
      `Would send email to ${application.email}: Your application has been ${review.decision}`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        message:
          review.decision === "approved"
            ? "Application approved. Creator profile created."
            : "Application rejected.",
        applicationId: review.applicationId,
        decision: review.decision,
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Application review error:", error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
    });
  }
});
