import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface CoachingModeRequest {
  operation: CoachingModeOperation;
  mode?: string;
  thought_record?: ThoughtRecordPayload;
  preferences?: CoachingModePreferences;
}

type CoachingModeOperation =
  | "getState"
  | "startSession"
  | "endSession"
  | "saveThoughtRecord"
  | "getThoughtRecords"
  | "getSuggestedQuests"
  | "acceptQuest"
  | "updatePreferences"
  | "getPromptsForMode";

interface ThoughtRecordPayload {
  id?: string;
  activating_event: string;
  automatic_thoughts: string[];
  emotions: { emotion: string; intensity: string }[];
  physical_sensations?: string;
  behaviors?: string;
  identified_distortions: string[];
  evidence_for_thoughts?: string;
  evidence_against_thoughts?: string;
  balanced_thought?: string;
  alternative_perspective?: string;
  emotion_after_reframing?: { emotion: string; intensity: string }[];
  lesson_learned?: string;
  is_completed: boolean;
}

interface CoachingModePreferences {
  default_mode?: string;
  preferred_tone?: string;
  reflection_prompts_enabled: boolean;
  reframe_reminders_enabled: boolean;
  weekly_reflection_day?: number;
  weekly_reflection_time?: string;
}

interface ThoughtRecord {
  id: string;
  user_id: string;
  conversation_id: string | null;
  created_at: string;
  updated_at: string;
  activating_event: string;
  automatic_thoughts: string[];
  emotions: { emotion: string; intensity: string }[];
  physical_sensations: string | null;
  behaviors: string | null;
  identified_distortions: string[];
  evidence_for_thoughts: string | null;
  evidence_against_thoughts: string | null;
  balanced_thought: string | null;
  alternative_perspective: string | null;
  emotion_after_reframing: { emotion: string; intensity: string }[] | null;
  lesson_learned: string | null;
  is_completed: boolean;
}

interface AISuggestedQuest {
  id: string;
  user_id: string;
  conversation_id: string | null;
  suggested_quest_template_id: string | null;
  title: string;
  description: string;
  category: string;
  difficulty: number;
  estimated_minutes: number;
  rationale: string;
  related_thoughts: string[] | null;
  expires_at: string | null;
  is_accepted: boolean | null;
  created_at: string;
}

serve(async (req: Request) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { autoRefreshToken: false } },
  );

  // Verify authorization
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "UNAUTHORIZED",
          message: "Please sign in to access AI coaching",
        },
      }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(token);

  if (authError || !user) {
    return new Response(
      JSON.stringify({
        success: false,
        error: { code: "UNAUTHORIZED", message: "Invalid or expired token" },
      }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    const body: CoachingModeRequest = await req.json();
    const { operation, mode, thought_record, preferences } = body;

    // Handle GET STATE operation
    if (operation === "getState") {
      // Get user's coaching session state from conversation_modes table
      const { data: sessionData, error: sessionError } = await supabase
        .from("conversation_modes")
        .select("current_mode, session_active, session_started_at")
        .eq("user_id", user.id)
        .single();

      // Get user preferences
      const { data: prefsData, error: prefsError } = await supabase
        .from("coaching_preferences")
        .select("*")
        .eq("user_id", user.id)
        .single();

      if (sessionError && sessionError.code !== "PGRST116") throw sessionError;
      if (prefsError && prefsError.code !== "PGRST116") throw prefsError;

      return new Response(
        JSON.stringify({
          success: true,
          data: {
            current_mode: sessionData?.current_mode || null,
            session_active: sessionData?.session_active || false,
            session_started_at: sessionData?.session_started_at || null,
            preferences: prefsData
              ? {
                  default_mode: prefsData.default_mode,
                  preferred_tone: prefsData.preferred_tone,
                  reflection_prompts_enabled:
                    prefsData.reflection_prompts_enabled,
                  reframe_reminders_enabled:
                    prefsData.reframe_reminders_enabled,
                  weekly_reflection_day: prefsData.weekly_reflection_day,
                  weekly_reflection_time: prefsData.weekly_reflection_time,
                }
              : null,
          },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Handle START SESSION operation
    if (operation === "startSession") {
      if (!mode) {
        return new Response(
          JSON.stringify({
            success: false,
            error: { code: "VALIDATION_ERROR", message: "Mode is required" },
          }),
          { status: 400, headers: { "Content-Type": "application/json" } },
        );
      }

      const sessionStartedAt = new Date().toISOString();

      // Upsert session state
      const { error: upsertError } = await supabase
        .from("conversation_modes")
        .upsert({
          user_id: user.id,
          current_mode: mode,
          session_active: true,
          session_started_at: sessionStartedAt,
          updated_at: new Date().toISOString(),
        })
        .select()
        .single();

      if (upsertError) throw upsertError;

      // Get mode-specific prompts
      const prompts = getPromptsForMode(mode);

      return new Response(
        JSON.stringify({
          success: true,
          data: {
            current_mode: mode,
            session_active: true,
            session_started_at: sessionStartedAt,
            prompts,
          },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Handle END SESSION operation
    if (operation === "endSession") {
      const { error: updateError } = await supabase
        .from("conversation_modes")
        .update({
          session_active: false,
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", user.id);

      if (updateError) throw updateError;

      return new Response(
        JSON.stringify({
          success: true,
          data: {
            current_mode: null,
            session_active: false,
            session_started_at: null,
          },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Handle SAVE THOUGHT RECORD operation
    if (operation === "saveThoughtRecord") {
      if (!thought_record) {
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "VALIDATION_ERROR",
              message: "Thought record is required",
            },
          }),
          { status: 400, headers: { "Content-Type": "application/json" } },
        );
      }

      const recordData = {
        user_id: user.id,
        activating_event: thought_record.activating_event,
        automatic_thoughts: thought_record.automatic_thoughts,
        emotions: thought_record.emotions,
        physical_sensations: thought_record.physical_sensations,
        behaviors: thought_record.behaviors,
        identified_distortions: thought_record.identified_distortions,
        evidence_for_thoughts: thought_record.evidence_for_thoughts,
        evidence_against_thoughts: thought_record.evidence_against_thoughts,
        balanced_thought: thought_record.balanced_thought,
        alternative_perspective: thought_record.alternative_perspective,
        emotion_after_reframing: thought_record.emotion_after_reframing,
        lesson_learned: thought_record.lesson_learned,
        is_completed: thought_record.is_completed,
        updated_at: new Date().toISOString(),
      };

      let result;

      if (thought_record.id) {
        // Update existing record
        const { data, error } = await supabase
          .from("thought_records")
          .update(recordData)
          .eq("id", thought_record.id)
          .select()
          .single();

        if (error) throw error;
        result = data;
      } else {
        // Create new record
        const { data, error } = await supabase
          .from("thought_records")
          .insert({ ...recordData, user_id: user.id })
          .select()
          .single();

        if (error) throw error;
        result = data;
      }

      return new Response(
        JSON.stringify({
          success: true,
          data: { thought_record: result },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Handle GET THOUGHT RECORDS operation
    if (operation === "getThoughtRecords") {
      const { data: records, error } = await supabase
        .from("thought_records")
        .select("*")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false });

      if (error) throw error;

      return new Response(
        JSON.stringify({
          success: true,
          data: { thought_records: records || [] },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Handle GET SUGGESTED QUESTS operation
    if (operation === "getSuggestedQuests") {
      const { data: quests, error } = await supabase
        .from("ai_suggested_quests")
        .select("*")
        .eq("user_id", user.id)
        .is("is_accepted", null)
        .gte("expires_at", new Date().toISOString())
        .order("created_at", { ascending: false });

      if (error) throw error;

      return new Response(
        JSON.stringify({
          success: true,
          data: { suggested_quests: quests || [] },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Handle UPDATE PREFERENCES operation
    if (operation === "updatePreferences") {
      if (!preferences) {
        return new Response(
          JSON.stringify({
            success: false,
            error: {
              code: "VALIDATION_ERROR",
              message: "Preferences is required",
            },
          }),
          { status: 400, headers: { "Content-Type": "application/json" } },
        );
      }

      const { error: prefsError } = await supabase
        .from("coaching_preferences")
        .upsert({
          user_id: user.id,
          default_mode: preferences.default_mode,
          preferred_tone: preferences.preferred_tone,
          reflection_prompts_enabled: preferences.reflection_prompts_enabled,
          reframe_reminders_enabled: preferences.reframe_reminders_enabled,
          weekly_reflection_day: preferences.weekly_reflection_day,
          weekly_reflection_time: preferences.weekly_reflection_time,
          updated_at: new Date().toISOString(),
        })
        .select()
        .single();

      if (prefsError) throw prefsError;

      return new Response(
        JSON.stringify({
          success: true,
          data: { preferences },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Handle GET PROMPTS FOR MODE operation
    if (operation === "getPromptsForMode") {
      if (!mode) {
        return new Response(
          JSON.stringify({
            success: false,
            error: { code: "VALIDATION_ERROR", message: "Mode is required" },
          }),
          { status: 400, headers: { "Content-Type": "application/json" } },
        );
      }

      const prompts = getPromptsForMode(mode);

      return new Response(
        JSON.stringify({
          success: true,
          data: { prompts },
          error: null,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({
        success: false,
        error: { code: "INVALID_OPERATION", message: "Invalid operation" },
      }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error in AI coaching function:", error);

    const errorMessage =
      error instanceof Error ? error.message : "Unknown error";

    return new Response(
      JSON.stringify({
        success: false,
        error: {
          code: "SERVER_ERROR",
          message: "Unable to process request; please try again",
        },
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

// Helper function to get mode-specific prompts
function getPromptsForMode(mode: string): string[] {
  const prompts: Record<string, string[]> = {
    reflect: [
      "What's been on your mind lately?",
      "How have you been feeling about yourself?",
      "What situations have been most challenging for you recently?",
      "Tell me more about what's been triggering these feelings.",
      "How do these thoughts affect your daily life?",
    ],
    plan: [
      "What goals would you like to work on?",
      "What's one small step you could take today?",
      "What obstacles do you see in the way of your goals?",
      "How can we break this down into manageable pieces?",
      "What support would help you stay on track?",
    ],
    reframe: [
      "What's a situation you'd like to look at from a different angle?",
      "What would you tell a friend who was thinking this way?",
      "What's another way to interpret what happened?",
      "What evidence supports or challenges this thought?",
      "How might this look a year from now?",
    ],
  };

  return prompts[mode] || prompts["reflect"];
}
