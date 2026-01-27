// Spec 11: Family Wellness - Start Together Session Edge Function
// Creates a synchronized family wellness session and notifies members

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface StartSessionRequest {
  familyId: string;
  templateId?: string;
  exerciseId?: string;
  title?: string;
  invitedMemberIds?: string[];
  syncMode?: "realtime" | "async_window";
}

interface StartSessionResponse {
  success: boolean;
  session?: {
    id: string;
    familyId: string;
    title: string;
    status: string;
  };
  participantCount?: number;
  error?: string;
}

serve(async (req: Request): Promise<Response> => {
  // Only allow POST
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Get authenticated user
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Missing authorization header" }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body: StartSessionRequest = await req.json();
    const {
      familyId,
      templateId,
      exerciseId,
      title,
      invitedMemberIds,
      syncMode,
    } = body;

    if (!familyId) {
      return new Response(JSON.stringify({ error: "Family ID is required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Verify user is family member
    const { data: member } = await supabase
      .from("family_members")
      .select("*")
      .eq("family_id", familyId)
      .eq("user_id", user.id)
      .eq("status", "active")
      .single();

    if (!member) {
      return new Response(
        JSON.stringify({ error: "Not a member of this family" }),
        { status: 403, headers: { "Content-Type": "application/json" } },
      );
    }

    // Get template or exercise details
    let sessionTitle = title || "Family Activity";
    let templateData = null;

    if (templateId) {
      const { data: template } = await supabase
        .from("together_templates")
        .select("*")
        .eq("id", templateId)
        .single();

      if (template) {
        sessionTitle = template.title;
        templateData = template;
      }
    }

    // Create session
    const { data: session, error: sessionError } = await supabase
      .from("together_sessions")
      .insert({
        family_id: familyId,
        exercise_id: exerciseId || null,
        together_template_id: templateId || null,
        title: sessionTitle,
        status: "pending",
        sync_mode: syncMode || "realtime",
        created_by: user.id,
      })
      .select()
      .single();

    if (sessionError) throw sessionError;

    // Get members to invite
    let membersToInvite: string[] = [];

    if (invitedMemberIds && invitedMemberIds.length > 0) {
      membersToInvite = invitedMemberIds;
    } else {
      // Invite all family members by default
      const { data: allMembers } = await supabase
        .from("family_members")
        .select("id")
        .eq("family_id", familyId)
        .eq("status", "active");

      membersToInvite = (allMembers || []).map((m) => m.id);
    }

    // Filter by age if template has minimum age requirement
    if (templateData?.minimum_age) {
      const { data: eligibleMembers } = await supabase
        .from("family_members")
        .select("id, birth_date")
        .eq("family_id", familyId)
        .eq("status", "active")
        .in("id", membersToInvite);

      membersToInvite = (eligibleMembers || [])
        .filter((m) => {
          if (!m.birth_date) return true;
          const age = calculateAge(new Date(m.birth_date));
          return age >= templateData.minimum_age;
        })
        .map((m) => m.id);
    }

    // Create participant records
    const participants = membersToInvite.map(
      (memberId: string, index: number) => ({
        session_id: session.id,
        member_id: memberId,
        status: memberId === member.id ? "joined" : "invited",
        joined_at: memberId === member.id ? new Date().toISOString() : null,
        turn_order: index + 1,
      }),
    );

    await supabase.from("together_participants").insert(participants);

    // Send invitations to other members
    const { data: membersWithUsers } = await supabase
      .from("family_members")
      .select("id, user_id, nickname")
      .in("id", membersToInvite)
      .neq("user_id", user.id);

    for (const invitedMember of membersWithUsers || []) {
      // Insert notification
      await supabase.from("notification_history").insert({
        user_id: invitedMember.user_id,
        notification_type: "together_invitation",
        title: "Family Activity Invitation",
        body: `${member.nickname || "A family member"} invited you to: ${sessionTitle}`,
        deep_link: `mindfriend://family/session/${session.id}`,
        metadata: {
          session_id: session.id,
          family_id: familyId,
          invited_by: member.id,
        },
        status: "pending",
      });

      // Note: Push notification via send-notification function would be called here
      // For MVP, we rely on notification_history and polling
    }

    return new Response(
      JSON.stringify({
        success: true,
        session: {
          id: session.id,
          familyId: session.family_id,
          title: session.title,
          status: session.status,
        },
        participantCount: membersToInvite.length,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error starting together session:", error);
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Internal server error",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

// Helper function: Calculate age from birth date
function calculateAge(birthDate: Date): number {
  const today = new Date();
  let age = today.getFullYear() - birthDate.getFullYear();
  const monthDiff = today.getMonth() - birthDate.getMonth();

  if (
    monthDiff < 0 ||
    (monthDiff === 0 && today.getDate() < birthDate.getDate())
  ) {
    age--;
  }

  return age;
}
