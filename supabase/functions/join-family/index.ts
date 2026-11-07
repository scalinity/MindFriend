// Spec 11: Family Wellness - Join Family Edge Function
// Allows users to join a family group via invite code

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import {
  isValidInviteCode,
  validateFamilyInviteCode,
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
  if (isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== birthDate) {
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

Deno.serve(async (req: Request): Promise<Response> => {
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
  const rateLimit = await checkRateLimit(
    supabaseAdmin,
    user.id,
    "join-family",
    {
      windowMs: 60 * 1000, // 1 minute
      maxRequests: 10,
    },
  );

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
    const body: JoinFamilyRequest = await req.json();
    const { inviteCode, nickname, birthDate } = body;

    if (typeof inviteCode !== "string" || !inviteCode) {
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
          error: validationError instanceof Error
            ? validationError.message
            : "Invalid input",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: result, error } = await supabaseAdmin.rpc(
      "join_family_atomic",
      {
        p_user_id: user.id,
        p_invite_code: validationResult.normalized,
        p_nickname: validatedNickname,
        p_birth_date: validatedBirthDate,
      },
    );
    if (error || !result?.success) {
      const status = error?.code === "42501"
        ? 403
        : error?.code === "22023"
        ? 400
        : 500;
      return new Response(
        JSON.stringify({
          error: status < 500 ? error?.message : "Failed to join family",
        }),
        {
          status,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    const family = { id: result.family_id, name: result.family_name };
    const member = {
      id: result.member_id,
      role: result.role,
      family_id: result.family_id,
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
      } catch {
        console.error("Failed to save family notification");
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
