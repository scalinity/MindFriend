/**
 * F009: Personalized Daily Briefing - Generation Edge Function
 *
 * MVP scope: Generates daily briefing with mood prediction, quest, calendar events, and suggestions
 * Excludes: Wellness score, voice, important dates, push notifications (Phase 2)
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { corsHeaders } from "../_shared/cors.ts";

// MARK: - Types

interface GenerateBriefingRequest {
  local_date: string; // YYYY-MM-DD
  timezone: string; // IANA timezone (e.g., "America/New_York")
  calendar_events?: CalendarEventInput[];
}

interface CalendarEventInput {
  id: string;
  title: string;
  start_time: string; // ISO 8601
  end_time: string; // ISO 8601
  location?: string;
}

interface MoodPrediction {
  predicted_mood: number;
  confidence: number;
  context?: string;
}

interface Quest {
  id: string;
  title: string;
  description?: string;
}

interface SuggestionContext {
  sleepDurationHours?: number;
  calendarEvents: CalendarEventInput[];
  predictedMood?: number;
  userName?: string;
}

// MARK: - Handler

Deno.serve(async (req) => {

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Step 2: Check authorization header
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

    // Step 3: Create Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseKey) {
      throw new Error("Missing Supabase configuration");
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    // Step 4: Validate JWT and get user
    const token = authHeader.replace("Bearer ", "");
    const { data: authData, error: authError } =
      await supabase.auth.getUser(token);

    if (authError) {
      return new Response(
        JSON.stringify({
          error: "Unauthorized",
          code: "UNAUTHORIZED",
          details: authError.message,
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const user = authData?.user;
    if (!user) {
      return new Response(
        JSON.stringify({
          error: "Unauthorized",
          code: "UNAUTHORIZED",
          details: "No user found",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Step 5: Parse request body
    let requestBody: GenerateBriefingRequest;
    try {
      requestBody = await req.json();
    } catch (parseError) {
      throw new Error(`Failed to parse request body: ${parseError}`);
    }

    const { local_date, timezone, calendar_events = [] } = requestBody;

    // Step 6: Validate date format
    if (!/^\d{4}-\d{2}-\d{2}$/.test(local_date)) {
      return new Response(
        JSON.stringify({
          error: "Invalid date format",
          code: "INVALID_DATE",
          message: "local_date must be in YYYY-MM-DD format",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Step 7: Check for existing briefing
    const { data: existingBriefing } = await supabase
      .from("daily_briefings")
      .select("*")
      .eq("user_id", user.id)
      .eq("local_date", local_date)
      .maybeSingle();

    if (existingBriefing) {
      return new Response(JSON.stringify(existingBriefing), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Step 8: Fetch user preferences
    const { data: preferences } = await supabase
      .from("briefing_preferences")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();

    const userPrefs = preferences || {
      enabled: true,
      include_calendar: true,
      calendar_lookahead_hours: 24,
    };

    if (!userPrefs.enabled) {
      return new Response(
        JSON.stringify({
          error: "Briefing disabled",
          code: "BRIEFING_DISABLED",
          message: "Daily briefing is disabled in preferences",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Step 9: Fetch user profile
    const { data: profile } = await supabase
      .from("profiles")
      .select("display_name, timezone")
      .eq("id", user.id)
      .maybeSingle();

    const userName = profile?.display_name || "there";
    const userTimezone = timezone || profile?.timezone || "UTC";

    // Step 10: Generate greeting
    let greeting: string;
    try {
      greeting = generateGreeting(userName, userTimezone);
    } catch (greetingError) {
      greeting = `Hello, ${userName}!`;
    }

    // Step 11: Fetch mood prediction
    const moodPrediction = await fetchMoodPrediction(supabase, user.id);

    // Step 12: Fetch quest
    const quest = await fetchOrAssignQuest(supabase, user.id, local_date);

    // Step 13: Process calendar events
    const processedEvents = processCalendarEvents(
      calendar_events,
      userPrefs.include_calendar,
    );

    // Step 14: Fetch sleep data
    const sleepData = await fetchSleepData(supabase, user.id);

    // Step 15: Generate suggestion
    let suggestion: string;
    try {
      suggestion = generateSuggestion({
        sleepDurationHours: sleepData?.sleep_duration_hours,
        calendarEvents: processedEvents,
        predictedMood: moodPrediction?.predicted_mood,
        userName,
      });
    } catch (suggestionError) {
      suggestion =
        "Your quest today is ready. Starting with a small win sets the tone for the day.";
    }

    // Step 16: Prepare insert data
    const insertData = {
      user_id: user.id,
      local_date,
      greeting,
      predicted_mood: moodPrediction?.predicted_mood ?? null,
      mood_context: moodPrediction?.context ?? null,
      quest_id: quest?.id ?? null,
      quest_title: quest?.title ?? null,
      calendar_events: processedEvents,
      suggestion,
      generated_at: new Date().toISOString(),
    };

    // Step 17: Insert briefing
    const { data: briefing, error: insertError } = await supabase
      .from("daily_briefings")
      .insert(insertData)
      .select()
      .single();

    if (insertError) {
      throw new Error(
        `Database insert failed: ${insertError.message} (code: ${insertError.code})`,
      );
    }

    // Log only the outcome: briefing content and database errors can contain PHI.
    console.info("Daily briefing generated");

    // Step 18: Return response

    return new Response(JSON.stringify(briefing), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    const error = err as Error;
    console.error("Daily briefing generation failed");

    return new Response(
      JSON.stringify({
        error: "Briefing generation failed",
        code: "GENERATION_FAILED",
        message: error?.message || "Unknown error",
        stack: error?.stack,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

// MARK: - Helper Functions

/**
 * Generate personalized greeting based on time of day
 */
function generateGreeting(userName: string, timezone: string): string {

  // Get current hour in user's timezone
  const now = new Date();
  let hour: number;

  try {
    const formatter = new Intl.DateTimeFormat("en-US", {
      hour: "numeric",
      hour12: false,
      timeZone: timezone,
    });
    const hourStr = formatter.format(now);
    hour = parseInt(hourStr, 10);
  } catch (tzError) {
    hour = now.getUTCHours();
  }

  let timeGreeting: string;
  if (hour >= 5 && hour < 12) {
    timeGreeting = "Good morning";
  } else if (hour >= 12 && hour < 17) {
    timeGreeting = "Good afternoon";
  } else if (hour >= 17 && hour < 22) {
    timeGreeting = "Good evening";
  } else {
    timeGreeting = "Hello";
  }

  return `${timeGreeting}, ${userName}!`;
}

/**
 * Fetch mood prediction from F003 table
 */
async function fetchMoodPrediction(
  supabase: any,
  userId: string,
): Promise<MoodPrediction | null> {

  try {
    const todayDate = new Date().toISOString().split("T")[0];

    const { data, error } = await supabase
      .from("mood_predictions")
      .select("predicted_mood, confidence, factors")
      .eq("user_id", userId)
      .gte("predicted_for", todayDate)
      .order("predicted_for", { ascending: true })
      .limit(1)
      .maybeSingle();

    if (error) {
      return null;
    }

    if (!data) {
      return null;
    }

    return {
      predicted_mood: data.predicted_mood,
      confidence: data.confidence,
      context: data.factors?.primary_factor || null,
    };
  } catch (error) {
    return null;
  }
}

/**
 * Fetch today's quest or assign a new one
 */
async function fetchOrAssignQuest(
  supabase: any,
  userId: string,
  localDate: string,
): Promise<Quest | null> {

  try {
    // First, try to fetch existing quest for today

    const { data: existingQuest, error: questError } = await supabase
      .from("quests")
      .select(
        `
        id,
        template_id,
        quest_templates!inner(title, description)
      `,
      )
      .eq("user_id", userId)
      .eq("local_date", localDate)
      .maybeSingle();

    if (questError) {
      return null;
    }

    if (existingQuest) {

      // PostgREST returns nested object for joins
      const template = existingQuest.quest_templates;
      return {
        id: existingQuest.id,
        title: template?.title || "Daily Quest",
        description: template?.description,
      };
    }

    return null;
  } catch (error) {
    return null;
  }
}

/**
 * Process calendar events: filter, sort, limit
 */
function processCalendarEvents(
  events: CalendarEventInput[],
  includeCalendar: boolean,
): CalendarEventInput[] {

  if (!includeCalendar || !events || events.length === 0) {
    return [];
  }

  const now = new Date();

  // Filter: Only future events
  const futureEvents = events.filter((event) => {
    const startTime = new Date(event.start_time);
    return startTime >= now;
  });

  // Sort: By start time ascending
  futureEvents.sort((a, b) => {
    return new Date(a.start_time).getTime() - new Date(b.start_time).getTime();
  });

  // Limit: First 5 events
  const result = futureEvents.slice(0, 5);
  return result;
}

/**
 * Fetch sleep data from biometric_daily_summaries (for suggestion context)
 */
async function fetchSleepData(
  supabase: any,
  userId: string,
): Promise<{ sleep_duration_hours: number } | null> {

  try {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayDate = yesterday.toISOString().split("T")[0];

    const { data, error } = await supabase
      .from("biometric_daily_summaries")
      .select("sleep_duration_hours")
      .eq("user_id", userId)
      .eq("summary_date", yesterdayDate)
      .maybeSingle();

    if (error) {
      return null;
    }

    if (!data || !data.sleep_duration_hours) {
      return null;
    }

    return { sleep_duration_hours: data.sleep_duration_hours };
  } catch (error) {
    return null;
  }
}

/**
 * Generate personalized suggestion based on context
 * Priority: Sleep deficit > Calendar event prep > Low mood armor > Default encouragement
 */
function generateSuggestion(context: SuggestionContext): string {

  // Priority 1: Sleep deficit recovery
  if (context.sleepDurationHours && context.sleepDurationHours < 6) {
    const hours = context.sleepDurationHours.toFixed(1);
    return `Your sleep was light last night (${hours}h). A short rest or gentle breathing exercise might help replenish your energy.`;
  }

  // Priority 2: Calendar event preparation
  if (context.calendarEvents && context.calendarEvents.length > 0) {
    const nextEvent = context.calendarEvents[0];
    const startTime = new Date(nextEvent.start_time);
    const now = new Date();
    const hoursUntil = (startTime.getTime() - now.getTime()) / (1000 * 60 * 60);
    const duration =
      (new Date(nextEvent.end_time).getTime() - startTime.getTime()) /
      (1000 * 60);

    if (hoursUntil <= 4 && duration >= 60) {
      const eventTime = new Intl.DateTimeFormat("en-US", {
        hour: "numeric",
        minute: "numeric",
        hour12: true,
      }).format(startTime);

      return `You have ${nextEvent.title} at ${eventTime}. A 3-minute grounding exercise beforehand might help you focus.`;
    }
  }

  // Priority 3: Low mood armor
  if (context.predictedMood && context.predictedMood < 5) {
    return `Today might feel challenging. Consider scheduling a short walk or breathwork to build your armor.`;
  }

  // Priority 4: Default encouragement
  return `Your quest today is ready. Starting with a small win sets the tone for the day.`;
}
