import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";

interface SafetyPlanPayload {
  warningSigns: SafetyPlanItem[];
  coping: CopingStrategy[];
  contacts: TrustedContact[];
  resources: ProfessionalResource[];
  environmentSteps: SafetyPlanItem[];
  anchors: SafetyPlanItem[];
}

interface SafetyPlanItem {
  id: string;
  text: string;
  isCustom?: boolean;
  order?: number;
  isFavorite?: boolean;
}

interface CopingStrategy {
  id: string;
  type: "exercise" | "custom";
  exerciseId?: string;
  exercise_id?: string;
  label: string;
  duration?: number;
  category: string;
  isFavorite?: boolean;
  is_favorite?: boolean;
  order?: number;
}

interface TrustedContact {
  id: string;
  name: string;
  phone: string;
  relationship: string;
  preferredMethod: "call" | "text";
  preferred_method?: "call" | "text";
  whatToSay?: string;
  what_to_say?: string;
  isPrimary?: boolean;
  is_primary?: boolean;
  order?: number;
}

interface ProfessionalResource {
  id: string;
  type: "hotline" | "therapist" | "crisis-line" | "custom";
  name: string;
  phone?: string;
  url?: string;
  country?: string;
  notes?: string;
}

interface SafetyPlanSettings {
  allow_ai_reference?: boolean;
  allowAiReference?: boolean;
}

interface RequestBody {
  operation: "get" | "create" | "update" | "delete";
  payload?: SafetyPlanPayload;
  settings?: SafetyPlanSettings;
}

interface ResponseData {
  id: string;
  version: number;
  payload: SafetyPlanPayload;
  settings: {
    allow_ai_reference: boolean;
    pinned_to_quick_actions: boolean;
  };
  created_at: string;
  updated_at: string;
}

const MAX_ITEMS_PER_SECTION = 10;
const MAX_CONTACTS = 3;
const PHONE_PATTERN = /^\+[1-9]\d{6,14}$/;
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

function responseWithCors(
  body: Record<string, unknown>,
  status: number,
  headers: Record<string, string>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, "Content-Type": "application/json" },
  });
}

function normalizeAllowAiReference(settings?: SafetyPlanSettings): boolean {
  if (!settings) return false;
  if (typeof settings.allow_ai_reference === "boolean") {
    return settings.allow_ai_reference;
  }
  if (typeof settings.allowAiReference === "boolean") {
    return settings.allowAiReference;
  }
  return false;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function validatePayload(payload: SafetyPlanPayload | undefined):
  | { ok: true }
  | { ok: false; error: string } {
  if (!payload || !isRecord(payload)) {
    return { ok: false, error: "Payload is required for create/update" };
  }

  const sections: Array<keyof SafetyPlanPayload> = [
    "warningSigns",
    "coping",
    "contacts",
    "resources",
    "environmentSteps",
    "anchors",
  ];

  for (const section of sections) {
    const value = payload[section];
    if (!Array.isArray(value)) {
      return { ok: false, error: `${section} must be an array` };
    }
    if (value.length > MAX_ITEMS_PER_SECTION) {
      return { ok: false, error: `${section} exceeds ${MAX_ITEMS_PER_SECTION} items` };
    }
  }

  if (payload.contacts.length > MAX_CONTACTS) {
    return { ok: false, error: "Trusted contacts exceeds limit" };
  }

  for (const contact of payload.contacts) {
    const phone = contact.phone;
    if (typeof phone !== "string" || !PHONE_PATTERN.test(phone)) {
      return { ok: false, error: "Trusted contact phone must be E.164" };
    }
  }

  return { ok: true };
}

serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return responseWithCors(
      { success: false, error: { code: "METHOD_NOT_ALLOWED", message: "Method not allowed" } },
      405,
      corsHeaders,
    );
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { autoRefreshToken: false } },
  );

  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return responseWithCors(
      {
        success: false,
        error: {
          code: "UNAUTHORIZED",
          message: "Please sign in to access your safety plan",
        },
      },
      401,
      corsHeaders,
    );
  }

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(token);

  if (authError || !user) {
    return responseWithCors(
      {
        success: false,
        error: { code: "UNAUTHORIZED", message: "Invalid or expired token" },
      },
      401,
      corsHeaders,
    );
  }

  try {
    const body: RequestBody = await req.json();
    const { operation, payload, settings } = body;
    const allowAiReference = normalizeAllowAiReference(settings);
    const now = new Date().toISOString();

    if (operation === "get") {
      const { data: existingPlan, error } = await supabase
        .from("safety_plans")
        .select("id, version, payload, allow_ai_reference, created_at, updated_at")
        .eq("user_id", user.id)
        .maybeSingle();

      if (error) throw error;

      if (!existingPlan) {
        return responseWithCors(
          { success: true, data: null, error: null },
          200,
          corsHeaders,
        );
      }

      const responseData: ResponseData = {
        id: existingPlan.id,
        version: existingPlan.version,
        payload: existingPlan.payload as SafetyPlanPayload,
        settings: {
          allow_ai_reference: existingPlan.allow_ai_reference ?? false,
          pinned_to_quick_actions: false,
        },
        created_at: existingPlan.created_at,
        updated_at: existingPlan.updated_at,
      };

      return responseWithCors(
        { success: true, data: responseData, error: null },
        200,
        corsHeaders,
      );
    }

    if (operation === "delete") {
      const { error } = await supabase
        .from("safety_plans")
        .delete()
        .eq("user_id", user.id);

      if (error) throw error;

      await supabase
        .from("safety_plan_cache")
        .delete()
        .eq("user_id", user.id);

      return responseWithCors(
        { success: true, data: null, error: null },
        200,
        corsHeaders,
      );
    }

    if (operation === "update" && !payload && settings) {
      const { data: updatedPlan, error } = await supabase
        .from("safety_plans")
        .update({ allow_ai_reference: allowAiReference })
        .eq("user_id", user.id)
        .select("id, version, payload, allow_ai_reference, created_at, updated_at")
        .maybeSingle();

      if (error) throw error;

      if (!updatedPlan) {
        return responseWithCors(
          {
            success: false,
            error: { code: "NOT_FOUND", message: "Safety plan not found" },
          },
          200,
          corsHeaders,
        );
      }

      const responseData: ResponseData = {
        id: updatedPlan.id,
        version: updatedPlan.version,
        payload: updatedPlan.payload as SafetyPlanPayload,
        settings: {
          allow_ai_reference: updatedPlan.allow_ai_reference ?? false,
          pinned_to_quick_actions: false,
        },
        created_at: updatedPlan.created_at,
        updated_at: updatedPlan.updated_at,
      };

      await supabase
        .from("safety_plan_cache")
        .upsert({
          user_id: user.id,
          payload: updatedPlan.payload,
          cached_at: now,
          expires_at: new Date(Date.now() + CACHE_TTL_MS).toISOString(),
        });

      return responseWithCors(
        { success: true, data: responseData, error: null },
        200,
        corsHeaders,
      );
    }

    if (operation !== "create" && operation !== "update") {
      return responseWithCors(
        { success: false, error: { code: "INVALID_OPERATION", message: "Invalid operation" } },
        400,
        corsHeaders,
      );
    }

    const validation = validatePayload(payload);
    if (!validation.ok) {
      return responseWithCors(
        {
          success: false,
          error: { code: "VALIDATION_ERROR", message: validation.error },
        },
        400,
        corsHeaders,
      );
    }

    const { data: existingPlan, error: fetchError } = await supabase
      .from("safety_plans")
      .select("id")
      .eq("user_id", user.id)
      .maybeSingle();

    if (fetchError) throw fetchError;

    if (operation === "create" && existingPlan) {
      return responseWithCors(
        {
          success: false,
          error: { code: "CONFLICT", message: "A plan already exists" },
        },
        409,
        corsHeaders,
      );
    }

    const { data: result, error: saveError } = await supabase
      .from("safety_plans")
      .upsert(
        {
          user_id: user.id,
          payload: payload,
          allow_ai_reference: allowAiReference,
        },
        { onConflict: "user_id" },
      )
      .select("id, version, payload, allow_ai_reference, created_at, updated_at")
      .single();

    if (saveError) throw saveError;

    const responseData: ResponseData = {
      id: result.id,
      version: result.version,
      payload: result.payload as SafetyPlanPayload,
      settings: {
        allow_ai_reference: result.allow_ai_reference,
        pinned_to_quick_actions: false,
      },
      created_at: result.created_at,
      updated_at: result.updated_at,
    };

    await supabase
      .from("safety_plan_cache")
      .upsert({
        user_id: user.id,
        payload: result.payload,
        cached_at: now,
        expires_at: new Date(Date.now() + CACHE_TTL_MS).toISOString(),
      });

    return responseWithCors(
      { success: true, data: responseData, error: null },
      200,
      corsHeaders,
    );
  } catch (error) {
    console.error("Error managing safety plan:", error);

    const errorMessage =
      error instanceof Error ? error.message : "Unknown error";

    if (errorMessage.includes("payload too large")) {
      return responseWithCors(
        {
          success: false,
          error: {
            code: "PAYLOAD_TOO_LARGE",
            message: "Plan is too large; please reduce content",
          },
        },
        413,
        corsHeaders,
      );
    }

    if (errorMessage.includes("violates unique constraint")) {
      return responseWithCors(
        {
          success: false,
          error: {
            code: "CONFLICT",
            message: "A plan already exists",
          },
        },
        409,
        corsHeaders,
      );
    }

    return responseWithCors(
      {
        success: false,
        error: {
          code: "SERVER_ERROR",
          message: "Unable to save plan; please try again",
        },
      },
      500,
      corsHeaders,
    );
  }
});
