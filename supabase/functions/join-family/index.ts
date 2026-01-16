// Spec 11: Family Wellness - Join Family Edge Function
// Allows users to join a family group via invite code

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface JoinFamilyRequest {
  inviteCode: string;
  nickname?: string;
  birthDate?: string; // ISO 8601 date string (YYYY-MM-DD)
}

interface JoinFamilyResponse {
  success: boolean;
  family?: {
    id: string;
    name: string;
  };
  member?: {
    id: string;
    role: string;
    familyId: string;
  };
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
    const body: JoinFamilyRequest = await req.json();
    const { inviteCode, nickname, birthDate } = body;

    if (!inviteCode) {
      return new Response(
        JSON.stringify({ error: "Invite code is required" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Find family by invite code (case-insensitive)
    const { data: family, error: familyError } = await supabase
      .from("family_groups")
      .select("*")
      .eq("invite_code", inviteCode.toUpperCase())
      .single();

    if (familyError || !family) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired invite code" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Check if already a member
    const { data: existingMember } = await supabase
      .from("family_members")
      .select("id")
      .eq("family_id", family.id)
      .eq("user_id", user.id)
      .eq("status", "active")
      .single();

    if (existingMember) {
      return new Response(
        JSON.stringify({ error: "Already a member of this family" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Check member limit
    const { count } = await supabase
      .from("family_members")
      .select("*", { count: "exact", head: true })
      .eq("family_id", family.id)
      .eq("status", "active");

    if (count && count >= (family.max_members || 6)) {
      return new Response(
        JSON.stringify({ error: "Family has reached maximum members" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Check for invitation record to get role and birth date
    const { data: invitation } = await supabase
      .from("family_invitations")
      .select("*")
      .eq("family_id", family.id)
      .eq("invite_code", inviteCode.toUpperCase())
      .eq("status", "pending")
      .single();

    let role = "child";
    let memberBirthDate = birthDate;

    if (invitation) {
      role = invitation.intended_role || "child";
      memberBirthDate = memberBirthDate || invitation.intended_birth_date;

      // Mark invitation as accepted
      await supabase
        .from("family_invitations")
        .update({
          status: "accepted",
          accepted_by: user.id,
        })
        .eq("id", invitation.id);
    }

    // Calculate age-based role if birth date provided
    if (memberBirthDate) {
      const age = calculateAge(new Date(memberBirthDate));
      if (age >= 18) role = "parent";
      else if (age >= 13) role = "teen";
      else role = "child";
    }

    // Create family member
    const { data: member, error: memberError } = await supabase
      .from("family_members")
      .insert({
        family_id: family.id,
        user_id: user.id,
        role: role,
        nickname: nickname || null,
        birth_date: memberBirthDate || null,
        status: "active",
        joined_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (memberError) throw memberError;

    // Notify family admins via notification_history table
    const { data: admins } = await supabase
      .from("family_members")
      .select("user_id")
      .eq("family_id", family.id)
      .in("role", ["admin", "parent"]);

    for (const admin of admins || []) {
      await supabase.from("notification_history").insert({
        user_id: admin.user_id,
        notification_type: "family_member_joined",
        title: "New Family Member",
        body: `${nickname || "Someone"} joined your family group!`,
        deep_link: `mindfriend://family/${family.id}`,
        metadata: {
          family_id: family.id,
          member_id: member.id,
          member_name: nickname,
        },
        status: "pending",
      });
    }

    return new Response(
      JSON.stringify({
        success: true,
        family: {
          id: family.id,
          name: family.name,
        },
        member: {
          id: member.id,
          role: member.role,
          familyId: member.family_id,
        },
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error joining family:", error);
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
