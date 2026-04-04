// Spec 11: Family Wellness - Join Family Edge Function
// Allows users to join a family group via invite code

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  validateFamilyInviteCode,
  isValidInviteCode,
} from "../_shared/validation.ts";
import { getCorsHeaders } from "../_shared/cors.ts";
import { checkRateLimit, getRateLimitHeaders } from "../_shared/ratelimit.ts";

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

/**
 * Validate nickname for safety and length
 * Prevents XSS and injection attacks
 */
function validateNickname(nickname: string | undefined): string | null {
  if (!nickname) return null;

  // Trim and check length (max 50 characters)
  const trimmed = nickname.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > 50) {
    throw new Error("Nickname must be 50 characters or less");
  }

  // Basic XSS prevention: check for HTML/script patterns
  if (/<[^>]*>/.test(trimmed) || /javascript:/i.test(trimmed)) {
    throw new Error("Nickname contains invalid characters");
  }

  return trimmed;
}

/**
 * Validate birth date for safety and reasonableness
 * Checks ISO 8601 format, prevents future dates, and reasonable age range
 */
function validateBirthDate(birthDate: string | undefined): string | null {
  if (!birthDate) return null;

  // Validate ISO 8601 format (YYYY-MM-DD)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(birthDate)) {
    throw new Error("Birth date must be in YYYY-MM-DD format");
  }

  const date = new Date(birthDate);
  if (isNaN(date.getTime())) {
    throw new Error("Invalid birth date");
  }

  // Prevent future dates
  if (date > new Date()) {
    throw new Error("Birth date cannot be in the future");
  }

  // Reasonable age check: must be at least 1 year old, no more than 130 years old
  const today = new Date();
  let age = today.getFullYear() - date.getFullYear();
  const monthDiff = today.getMonth() - date.getMonth();

  if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < date.getDate())) {
    age--;
  }

  if (age < 1 || age > 130) {
    throw new Error(
      "Birth date must result in an age between 1 and 130 years old",
    );
  }

  return birthDate;
}

serve(async (req: Request): Promise<Response> => {
  // Handle CORS
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle OPTIONS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Only allow POST
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Get authenticated user
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Missing authorization header" }),
      {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error: authError,
  } = await supabaseAdmin.auth.getUser(token);

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Rate limit: 10 requests per minute per user
  // Prevents brute-force enumeration of invite codes
  const rateLimit = await checkRateLimit(supabaseAdmin, user.id, "join-family", {
    windowMs: 60 * 1000, // 1 minute
    maxRequests: 10,
  });

  if (!rateLimit.allowed) {
    return new Response(
      JSON.stringify({
        error: "Too many requests. Please try again later.",
        retryAfter: rateLimit.retryAfter,
      }),
      {
        status: 429,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
          ...getRateLimitHeaders(rateLimit),
        },
      },
    );
  }

  try {
    const anonKey =
      Deno.env.get("SUPABASE_ANON_KEY") ??
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY");

    if (!anonKey) {
      return new Response(
        JSON.stringify({ error: "Missing Supabase anon key" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUser = createClient(Deno.env.get("SUPABASE_URL")!, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      },
    });

    const body: JoinFamilyRequest = await req.json();
    const { inviteCode, nickname, birthDate } = body;

    if (!inviteCode) {
      return new Response(
        JSON.stringify({ error: "Invite code is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate invite code format before any database queries
    // Prevents injection attacks and enumeration attacks
    const validationResult = validateFamilyInviteCode(inviteCode);
    if (!isValidInviteCode(validationResult)) {
      return new Response(
        JSON.stringify({
          error: "Invalid invite code format",
          details: { reason: validationResult.error },
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate nickname and birth date inputs
    let validatedNickname: string | null = null;
    let validatedBirthDate: string | null = null;

    try {
      validatedNickname = validateNickname(nickname);
      validatedBirthDate = validateBirthDate(birthDate);
    } catch (validationError) {
      return new Response(
        JSON.stringify({
          error:
            validationError instanceof Error
              ? validationError.message
              : "Invalid input",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Find family by invite code using validated, normalized code
    const { data: family, error: familyError } = await supabaseAdmin
      .from("family_groups")
      .select("*")
      .eq("invite_code", validationResult.normalized)
      .single();

    console.log(
      `Found family for code ${validationResult.normalized}:`,
      JSON.stringify(family),
      familyError,
    );

    // SECURITY: Use constant-time response to prevent timing attacks
    // Return identical error for all failure modes (invalid code, already member, etc)
    // Add random jitter to obscure timing side-channel

    if (familyError || !family) {
      // Add random delay (5-50ms) to obscure timing information
      const jitterMs = Math.floor(Math.random() * 45) + 5;
      await new Promise((resolve) => setTimeout(resolve, jitterMs));

      return new Response(
        JSON.stringify({
          error: "Invalid request or insufficient permissions",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if user is already a member of this family
    const { data: existingMember } = await supabaseAdmin
      .from("family_members")
      .select("id")
      .eq("family_id", family.id)
      .eq("user_id", user.id)
      .eq("status", "active")
      .maybeSingle();

    console.log(
      `Existing member check for family ${family.id}, user ${user.id}:`,
      JSON.stringify(existingMember),
    );

    if (existingMember) {
      // Use SAME error message for all failure modes (prevent enumeration)
      // Add random delay to obscure timing information
      const jitterMs = Math.floor(Math.random() * 45) + 5;
      await new Promise((resolve) => setTimeout(resolve, jitterMs));

      return new Response(
        JSON.stringify({
          error: "Invalid request or insufficient permissions",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check for invitation record to get role and birth date
    const { data: invitation } = await supabaseAdmin
      .from("family_invitations")
      .select("*")
      .eq("family_id", family.id)
      .eq("invite_code", validationResult.normalized)
      .eq("status", "pending")
      .single();

    let role = "child";
    let memberBirthDate = validatedBirthDate;

    let explicitRole = false;

    if (invitation) {
      const invitationRole = invitation.intended_role;
      role = invitationRole || "child";
      explicitRole = !!invitationRole && invitationRole !== "child";
      memberBirthDate = memberBirthDate || invitation.intended_birth_date;

      // Mark invitation as accepted
      const { error: inviteUpdateError } = await supabaseAdmin
        .from("family_invitations")
        .update({
          status: "accepted",
          accepted_by: user.id,
        })
        .eq("id", invitation.id);

      if (inviteUpdateError) {
        console.error(
          "Warning: Failed to mark invitation as accepted:",
          inviteUpdateError,
        );
        // Don't block the flow - invitation status update is non-critical
      }
    }

    // Calculate age-based role only if no explicit role was set via invitation
    if (memberBirthDate && !explicitRole) {
      const age = calculateAge(new Date(memberBirthDate));
      if (age >= 18) role = "parent";
      else if (age >= 13) role = "teen";
      else role = "child";
    }

    // Use atomic RPC to add family member
    // This prevents TOCTOU race condition by checking member limit and inserting in single transaction
    const { data: rpcResult, error: rpcError } = await supabaseUser.rpc(
      "add_family_member",
      {
        p_family_id: family.id,
        p_user_id: user.id,
        p_role: role,
        p_nickname: validatedNickname,
        p_birth_date: memberBirthDate,
      },
    );

    if (rpcError || !rpcResult) {
      console.error("RPC Error adding family member:", JSON.stringify(rpcError));
      return new Response(
        JSON.stringify({
          error: "Failed to add family member",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if RPC succeeded (could return failure as JSON due to constraints)
    if (!rpcResult.success) {
      return new Response(
        JSON.stringify({ error: rpcResult.error || "Failed to join family" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Extract member data from RPC result
    const member = {
      id: rpcResult.member_id,
      role: rpcResult.role,
      family_id: rpcResult.family_id,
      user_id: rpcResult.user_id,
      joined_at: rpcResult.joined_at,
    };

    // Notify family admins via notification_history table
    const { data: admins } = await supabaseAdmin
      .from("family_members")
      .select("user_id")
      .eq("family_id", family.id)
      .in("role", ["admin", "parent"]);

    // Send notifications to all admins (non-blocking - failures are logged)
    for (const admin of admins || []) {
      try {
        await supabaseAdmin.from("notification_history").insert({
          user_id: admin.user_id,
          notification_type: "family_member_joined",
          title: "New Family Member",
          body: `${validatedNickname || "Someone"} joined your family group!`,
          deep_link: `mindfriend://family/${family.id}`,
          metadata: {
            family_id: family.id,
            member_id: member.id,
            member_name: validatedNickname,
          },
          status: "pending",
        });
      } catch (notificationError) {
        console.error(
          `Warning: Failed to send notification to admin ${admin.user_id}:`,
          notificationError,
        );
        // Don't block the flow - notifications are best-effort
      }
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
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Join family error:", error);
    // Don't expose raw error messages to client - return generic message
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
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
