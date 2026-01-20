// Edge Function: get-companion-memory
// Fetches all active companion memories and current daily intent for a user

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { CommonErrors } from "../_shared/errors.ts";

interface CompanionMemory {
  id: string;
  category: string;
  content: string;
  lastUsedAt: string | null;
  usageCount: number;
  createdAt: string;
  updatedAt: string;
}

interface DailyIntent {
  id: string;
  intent: string;
  createdAt: string;
  expiresAt: string;
}

interface GetMemoryResponse {
  memories: CompanionMemory[];
  dailyIntent: DailyIntent | null;
  totalCount: number;
  maxLimit: number;
}

serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Create Supabase client with user's JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return CommonErrors.unauthorized(corsHeaders);
    }

    const token = authHeader.replace("Bearer ", "");
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );

    // Verify user authentication
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return CommonErrors.invalidToken(corsHeaders);
    }

    // Fetch all active memories for user (sorted by category then lastUsedAt)
    const { data: memories, error: memoriesError } = await supabase
      .from("companion_memory")
      .select(
        "id, category, content, last_used_at, usage_count, created_at, updated_at",
      )
      .eq("user_id", user.id)
      .is("deleted_at", null)
      .order("category")
      .order("last_used_at", { ascending: false, nullsFirst: false });

    if (memoriesError) {
      console.error("Error fetching memories:", memoriesError);
      return CommonErrors.internalError(corsHeaders);
    }

    // Fetch current active daily intent (not expired)
    const now = new Date().toISOString();
    const { data: intents, error: intentsError } = await supabase
      .from("daily_intents")
      .select("id, intent, created_at, expires_at")
      .eq("user_id", user.id)
      .gt("expires_at", now)
      .order("created_at", { ascending: false })
      .limit(1);

    if (intentsError) {
      console.error("Error fetching intents:", intentsError);
      return CommonErrors.internalError(corsHeaders);
    }

    // Transform memories to camelCase
    const memoriesResponse: CompanionMemory[] = (memories ?? []).map((m) => ({
      id: m.id,
      category: m.category,
      content: m.content,
      lastUsedAt: m.last_used_at,
      usageCount: m.usage_count,
      createdAt: m.created_at,
      updatedAt: m.updated_at,
    }));

    // Transform intent to camelCase
    const dailyIntent: DailyIntent | null =
      intents && intents.length > 0
        ? {
            id: intents[0].id,
            intent: intents[0].intent,
            createdAt: intents[0].created_at,
            expiresAt: intents[0].expires_at,
          }
        : null;

    const response: GetMemoryResponse = {
      memories: memoriesResponse,
      dailyIntent,
      totalCount: memoriesResponse.length,
      maxLimit: 20,
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Unexpected error in get-companion-memory:", error);
    return CommonErrors.internalError(corsHeaders);
  }
});
