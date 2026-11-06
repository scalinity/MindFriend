// MindFriend Update UI Preferences Edge Function
// Updates user's UI preferences including Calm Screen Mode settings

import { authenticateRequest, isAuthError } from "../_shared/auth.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

// Allowed fields for updates
const ALLOWED_FIELDS = [
  "screen_mode",
  "reduced_motion",
  "reduced_transparency",
  "reduced_noise",
  "ios_reduced_motion_linked",
  "schedule_enabled",
  "schedule_start_time",
  "schedule_end_time",
  "schedule_timezone",
] as const;

type PreferenceField = (typeof ALLOWED_FIELDS)[number];

interface UpdatePreferencesRequest {
  screen_mode?: "standard" | "calm";
  reduced_motion?: boolean;
  reduced_transparency?: boolean;
  reduced_noise?: boolean;
  ios_reduced_motion_linked?: boolean;
  schedule_enabled?: boolean;
  schedule_start_time?: string;
  schedule_end_time?: string;
  schedule_timezone?: string;
}

/**
 * Validate that only allowed fields are present in the request
 */
function validateRequestBody(body: unknown): UpdatePreferencesRequest {
  if (!body || typeof body !== "object") {
    throw new Error("Invalid request body");
  }

  const updates: UpdatePreferencesRequest = {};
  const input = body as Record<string, unknown>;

  for (const key of Object.keys(input)) {
    if (!ALLOWED_FIELDS.includes(key as PreferenceField)) {
      throw new Error(`Invalid field: ${key}`);
    }
  }

  // Validate screen_mode
  if (input.screen_mode !== undefined) {
    if (input.screen_mode !== "standard" && input.screen_mode !== "calm") {
      throw new Error("screen_mode must be 'standard' or 'calm'");
    }
    updates.screen_mode = input.screen_mode;
  }

  // Validate boolean fields
  const booleanFields = [
    "reduced_motion",
    "reduced_transparency",
    "reduced_noise",
    "ios_reduced_motion_linked",
    "schedule_enabled",
  ] as const;

  for (const field of booleanFields) {
    if (input[field] !== undefined) {
      if (typeof input[field] !== "boolean") {
        throw new Error(`${field} must be a boolean`);
      }
      updates[field] = input[field];
    }
  }

  // Validate time fields
  if (input.schedule_start_time !== undefined) {
    if (typeof input.schedule_start_time !== "string") {
      throw new Error("schedule_start_time must be a string");
    }
    // Validate HH:MM format
    if (!/^([01]?[0-9]|2[0-3]):[0-5][0-9]$/.test(input.schedule_start_time)) {
      throw new Error("schedule_start_time must be in HH:MM format");
    }
    updates.schedule_start_time = input.schedule_start_time;
  }

  if (input.schedule_end_time !== undefined) {
    if (typeof input.schedule_end_time !== "string") {
      throw new Error("schedule_end_time must be a string");
    }
    // Validate HH:MM format
    if (!/^([01]?[0-9]|2[0-3]):[0-5][0-9]$/.test(input.schedule_end_time)) {
      throw new Error("schedule_end_time must be in HH:MM format");
    }
    updates.schedule_end_time = input.schedule_end_time;
  }

  if (input.schedule_timezone !== undefined) {
    if (typeof input.schedule_timezone !== "string") {
      throw new Error("schedule_timezone must be a string");
    }
    // Validate IANA timezone format
    try {
      new Intl.DateTimeFormat("en", { timeZone: input.schedule_timezone })
        .format();
    } catch {
      throw new Error(
        "schedule_timezone must be a valid IANA timezone (e.g., America/New_York)",
      );
    }
    updates.schedule_timezone = input.schedule_timezone;
  }

  return updates;
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Authenticate the request
  const authResult = await authenticateRequest(req);

  if (isAuthError(authResult)) {
    return authResult.response;
  }

  const { user, supabaseAdmin, supabaseUser } = authResult;

  try {
    // Parse and validate request body
    let updates: UpdatePreferencesRequest;
    try {
      const body = await req.json();
      updates = validateRequestBody(body);
    } catch (validationError) {
      const error = validationError as Error;
      return new Response(
        JSON.stringify({ error: "Validation error", message: error.message }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate schedule consistency
    if (
      updates.schedule_enabled &&
      updates.schedule_start_time &&
      updates.schedule_end_time
    ) {
      // Parse times for comparison
      const startParts = updates.schedule_start_time.split(":").map(Number);
      const endParts = updates.schedule_end_time.split(":").map(Number);
      const startMinutes = startParts[0] * 60 + startParts[1];
      const endMinutes = endParts[0] * 60 + endParts[1];

      // If times are equal, it's a 24-hour schedule - allowed
      // If start < end, same-day schedule
      // If start > end, overnight schedule (e.g., 22:00 - 07:00)
      if (startMinutes === endMinutes) {
        // 24-hour schedule, valid
      } else if (startMinutes > endMinutes && startMinutes - endMinutes < 60) {
        // Less than 1 hour overnight schedule - might be unintended
        console.warn(
          `Short overnight schedule detected: ${updates.schedule_start_time} to ${updates.schedule_end_time}`,
        );
      }
    }

    // Upsert preferences using authenticated client (respects RLS)
    const { data, error } = await supabaseUser
      .from("ui_preferences")
      .upsert({
        user_id: user.id,
        ...updates,
        updated_at: new Date().toISOString(),
      })
      .select("*")
      .single();

    if (error) {
      console.error("Database error updating preferences:", error);
      return new Response(
        JSON.stringify({ error: "Database error", message: error.message }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(JSON.stringify({ preferences: data }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Unexpected error:", err);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: "An unexpected error occurred",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
