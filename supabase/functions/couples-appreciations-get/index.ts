// GET /functions/v1/couples/appreciations-get
// Get appreciation messages received from partner

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getPartnerId } from "../_shared/couples-utils.ts";
import { CouplesErrors, formatSuccess } from "../_shared/couples-errors.ts";

serve(async (req) => {
  try {
    // Only accept GET method
    if (req.method !== "GET") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    // Validate environment variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseKey) {
      console.error("Missing required environment variables");
      return CouplesErrors.unexpectedError(new Error("Server configuration error"));
    }

    // Initialize Supabase client with service role
    const supabase = createClient(supabaseUrl, supabaseKey, {
      global: {
        headers: { Authorization: req.headers.get("Authorization")! },
      },
    });

    // Authenticate user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return CouplesErrors.missingAuth();
    }

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return CouplesErrors.missingAuth();
    }

    const userId = user.id;

    // Parse query parameters
    const url = new URL(req.url);
    const limitParam = url.searchParams.get("limit");
    const offsetParam = url.searchParams.get("offset");

    const limit = limitParam ? parseInt(limitParam, 10) : 20;
    const offset = offsetParam ? parseInt(offsetParam, 10) : 0;

    if (isNaN(limit) || limit < 1 || limit > 100) {
      return CouplesErrors.invalidFieldValue(
        "limit",
        "must be between 1 and 100",
      );
    }

    if (isNaN(offset) || offset < 0) {
      return CouplesErrors.invalidFieldValue("offset", "must be >= 0");
    }

    // Get partner ID
    let partnerId: string | null;
    try {
      partnerId = await getPartnerId(supabase, userId);
    } catch (error) {
      console.error("Error getting partner ID:", error);
      return CouplesErrors.databaseError(error as Error);
    }

    if (!partnerId) {
      return CouplesErrors.notPartner();
    }

    // Fetch appreciation messages received ONLY from the partner
    const { data: messages, error: messagesError } = await supabase
      .from("appreciations")
      .select("*")
      .eq("to_user_id", userId)
      .eq("from_user_id", partnerId)
      .order("created_at", { ascending: false })
      .range(offset, offset + limit - 1);

    if (messagesError) {
      console.error("Failed to fetch appreciations:", messagesError);
      return CouplesErrors.databaseError(messagesError);
    }

    // Get total count from partner
    const { count: totalCount, error: countError } = await supabase
      .from("appreciations")
      .select("*", { count: "exact", head: true })
      .eq("to_user_id", userId)
      .eq("from_user_id", partnerId);

    if (countError) {
      console.error("Failed to count appreciations:", countError);
      // Continue with partial data
    }

    // Get partner's profile for name
    const { data: partnerProfile } = await supabase
      .from("profiles")
      .select("display_name")
      .eq("id", partnerId)
      .single();

    const partnerName = partnerProfile?.display_name || "Your partner";

    // Format messages response
    const formattedMessages = (messages || []).map((msg) => ({
      messageId: msg.id,
      fromPartner: partnerName,
      message: msg.message,
      sentAt: msg.created_at,
      readAt: null, // Not implemented yet - would need read_at column
    }));

    // Calculate unread count (all messages for now since we don't track read status yet)
    const unreadCount = formattedMessages.length;

    return formatSuccess(
      {
        messages: formattedMessages,
        totalCount: totalCount || 0,
        unreadCount: unreadCount,
      },
      200,
    );
  } catch (error) {
    console.error("Unexpected error in appreciations GET:", error);
    return CouplesErrors.unexpectedError(error as Error);
  }
});
