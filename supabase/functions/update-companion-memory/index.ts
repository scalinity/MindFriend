// Edge Function: update-companion-memory
// Creates or updates a companion memory, or sets a daily intent

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders } from "../_shared/cors.ts";
import {
  CommonErrors,
  createErrorResponse,
  ErrorCodes,
} from "../_shared/errors.ts";

type MemoryCategory =
  | "boundaries"
  | "preferences"
  | "triggers"
  | "avoid_topics"
  | "positive_reinforcement"
  | "life_context";

const VALID_CATEGORIES: MemoryCategory[] = [
  "boundaries",
  "preferences",
  "triggers",
  "avoid_topics",
  "positive_reinforcement",
  "life_context",
];

interface UpdateMemoryRequest {
  action: "memory" | "intent";
  // For memory action
  id?: string;
  category?: MemoryCategory;
  content?: string;
  // For intent action
  intent?: string;
}

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

interface UpdateMemoryResponse {
  success: boolean;
  memory?: CompanionMemory;
  dailyIntent?: DailyIntent;
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
    let body: UpdateMemoryRequest;
    try {
      body = await req.json();
    } catch {
      return CommonErrors.badRequest(corsHeaders, "Invalid JSON body");
    }

    const { action = "memory" } = body;

    // Handle daily intent
    if (action === "intent") {
      const { intent } = body;

      if (!intent || typeof intent !== "string") {
        return CommonErrors.badRequest(corsHeaders, "Intent text is required");
      }

      if (intent.length > 140) {
        return CommonErrors.badRequest(
          corsHeaders,
          "Intent must be 140 characters or less",
        );
      }

      if (intent.trim().length === 0) {
        return CommonErrors.badRequest(corsHeaders, "Intent cannot be empty");
      }

      // Insert new intent (will create a new one - old ones expire naturally)
      const expiresAt = new Date(
        Date.now() + 24 * 60 * 60 * 1000,
      ).toISOString(); // 24 hours
      const { data: newIntent, error: insertError } = await supabase
        .from("daily_intents")
        .insert({
          user_id: user.id,
          intent: intent.trim(),
          expires_at: expiresAt,
        })
        .select("id, intent, created_at, expires_at")
        .single();

      if (insertError) {
        console.error("Error creating intent:", insertError);
        return CommonErrors.internalError(corsHeaders);
      }

      const response: UpdateMemoryResponse = {
        success: true,
        dailyIntent: {
          id: newIntent.id,
          intent: newIntent.intent,
          createdAt: newIntent.created_at,
          expiresAt: newIntent.expires_at,
        },
      };

      return new Response(JSON.stringify(response), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Handle memory action
    const { id, category, content } = body;

    // Validate category
    if (!category || !VALID_CATEGORIES.includes(category)) {
      return CommonErrors.badRequest(
        corsHeaders,
        `Invalid category. Must be one of: ${VALID_CATEGORIES.join(", ")}`,
      );
    }

    // Validate content
    if (!content || typeof content !== "string") {
      return CommonErrors.badRequest(corsHeaders, "Content is required");
    }

    if (content.length > 500) {
      return CommonErrors.badRequest(
        corsHeaders,
        "Content must be 500 characters or less",
      );
    }

    if (content.trim().length === 0) {
      return CommonErrors.badRequest(corsHeaders, "Content cannot be empty");
    }

    // Update existing memory
    if (id) {
      const { data: updatedMemory, error: updateError } = await supabase
        .from("companion_memory")
        .update({
          category,
          content: content.trim(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", id)
        .eq("user_id", user.id)
        .is("deleted_at", null)
        .select(
          "id, category, content, last_used_at, usage_count, created_at, updated_at",
        )
        .single();

      if (updateError) {
        if (updateError.code === "PGRST116") {
          return CommonErrors.notFound(corsHeaders, "Memory");
        }
        console.error("Error updating memory:", updateError);
        return CommonErrors.internalError(corsHeaders);
      }

      const response: UpdateMemoryResponse = {
        success: true,
        memory: {
          id: updatedMemory.id,
          category: updatedMemory.category,
          content: updatedMemory.content,
          lastUsedAt: updatedMemory.last_used_at,
          usageCount: updatedMemory.usage_count,
          createdAt: updatedMemory.created_at,
          updatedAt: updatedMemory.updated_at,
        },
      };

      return new Response(JSON.stringify(response), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Create new memory
    const { data: newMemory, error: insertError } = await supabase
      .from("companion_memory")
      .insert({
        user_id: user.id,
        category,
        content: content.trim(),
      })
      .select(
        "id, category, content, last_used_at, usage_count, created_at, updated_at",
      )
      .single();

    if (insertError) {
      // Check for memory limit trigger error
      if (insertError.message?.includes("Memory limit reached")) {
        return createErrorResponse(
          corsHeaders,
          "Memory limit reached (20/20). Delete a memory before adding a new one.",
          ErrorCodes.QUOTA_EXCEEDED,
          409,
        );
      }
      console.error("Error creating memory:", insertError);
      return CommonErrors.internalError(corsHeaders);
    }

    const response: UpdateMemoryResponse = {
      success: true,
      memory: {
        id: newMemory.id,
        category: newMemory.category,
        content: newMemory.content,
        lastUsedAt: newMemory.last_used_at,
        usageCount: newMemory.usage_count,
        createdAt: newMemory.created_at,
        updatedAt: newMemory.updated_at,
      },
    };

    return new Response(JSON.stringify(response), {
      status: 201,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Unexpected error in update-companion-memory:", error);
    return CommonErrors.internalError(corsHeaders);
  }
});
