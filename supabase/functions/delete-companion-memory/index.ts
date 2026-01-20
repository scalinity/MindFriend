// Edge Function: delete-companion-memory
// Soft-deletes a companion memory or clears the current daily intent

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { CommonErrors } from "../_shared/errors.ts";

interface DeleteMemoryRequest {
  action: "memory" | "intent";
  id?: string; // Required for memory action
}

interface DeleteMemoryResponse {
  success: boolean;
  error?: string;
}

serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return CommonErrors.badRequest(corsHeaders, "Method not allowed");
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

    // Parse request body
    let body: DeleteMemoryRequest;
    try {
      body = await req.json();
    } catch {
      return CommonErrors.badRequest(corsHeaders, "Invalid JSON body");
    }

    const { action = "memory", id } = body;

    // Handle intent deletion
    if (action === "intent") {
      // Delete all active intents for user (effectively clearing current intent)
      const now = new Date().toISOString();
      const { error: deleteError } = await supabase
        .from("daily_intents")
        .delete()
        .eq("user_id", user.id)
        .gt("expires_at", now);

      if (deleteError) {
        console.error("Error deleting intent:", deleteError);
        return CommonErrors.internalError(corsHeaders);
      }

      const response: DeleteMemoryResponse = { success: true };
      return new Response(JSON.stringify(response), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Handle memory deletion
    if (!id) {
      return CommonErrors.badRequest(corsHeaders, "Memory ID is required");
    }

    // Soft delete: set deleted_at timestamp
    const { data: deletedMemory, error: deleteError } = await supabase
      .from("companion_memory")
      .update({ deleted_at: new Date().toISOString() })
      .eq("id", id)
      .eq("user_id", user.id)
      .is("deleted_at", null)
      .select("id")
      .single();

    if (deleteError) {
      if (deleteError.code === "PGRST116") {
        return CommonErrors.notFound(corsHeaders, "Memory");
      }
      console.error("Error deleting memory:", deleteError);
      return CommonErrors.internalError(corsHeaders);
    }

    if (!deletedMemory) {
      return CommonErrors.notFound(corsHeaders, "Memory");
    }

    const response: DeleteMemoryResponse = { success: true };
    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Unexpected error in delete-companion-memory:", error);
    return CommonErrors.internalError(corsHeaders);
  }
});
