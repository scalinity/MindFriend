/**
 * F009: Personalized Daily Briefing - Generation Edge Function
 *
 * MVP scope: Generates daily briefing with mood prediction, quest, calendar events, and suggestions
 * Excludes: Wellness score, voice, important dates, push notifications (Phase 2)
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
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

serve(async (req) => {
  console.log("========== DAILY BRIEFING START ==========");
  console.log(`[1] Request method: ${req.method}`);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    console.log("[1] CORS preflight - returning 200");
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Step 2: Check authorization header
    console.log("[2] Checking authorization header...");
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      console.log("[2] ERROR: Missing authorization header");
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    console.log("[2] Authorization header present");

    // Step 3: Create Supabase client
    console.log("[3] Creating Supabase client...");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    console.log(`[3] SUPABASE_URL present: ${!!supabaseUrl}`);
    console.log(`[3] SUPABASE_SERVICE_ROLE_KEY present: ${!!supabaseKey}`);

    if (!supabaseUrl || !supabaseKey) {
      console.log("[3] ERROR: Missing Supabase env vars");
      throw new Error("Missing Supabase configuration");
    }

    const supabase = createClient(supabaseUrl, supabaseKey);
    console.log("[3] Supabase client created");

    // Step 4: Validate JWT and get user
    console.log("[4] Validating JWT...");
    const token = authHeader.replace("Bearer ", "");
    console.log(`[4] Token length: ${token.length}`);

    const { data: authData, error: authError } =
      await supabase.auth.getUser(token);

    if (authError) {
      console.log(`[4] ERROR: Auth error - ${authError.message}`);
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
      console.log("[4] ERROR: No user found from token");
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
    console.log(`[4] User authenticated: ${user.id}`);

    // Step 5: Parse request body
    console.log("[5] Parsing request body...");
    let requestBody: GenerateBriefingRequest;
    try {
      requestBody = await req.json();
      console.log(`[5] Request body:`, JSON.stringify(requestBody));
    } catch (parseError) {
      console.log(`[5] ERROR: Failed to parse request body - ${parseError}`);
      throw new Error(`Failed to parse request body: ${parseError}`);
    }

    const { local_date, timezone, calendar_events = [] } = requestBody;
    console.log(
      `[5] local_date: ${local_date}, timezone: ${timezone}, events count: ${calendar_events.length}`,
    );

    // Step 6: Validate date format
    console.log("[6] Validating date format...");
    if (!/^\d{4}-\d{2}-\d{2}$/.test(local_date)) {
      console.log(`[6] ERROR: Invalid date format - ${local_date}`);
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
    console.log("[6] Date format valid");

    // Step 7: Check for existing briefing
    console.log("[7] Checking for existing briefing...");
    const { data: existingBriefing, error: existingError } = await supabase
      .from("daily_briefings")
      .select("*")
      .eq("user_id", user.id)
      .eq("local_date", local_date)
      .maybeSingle();

    if (existingError) {
      console.log(
        `[7] ERROR checking existing briefing: ${existingError.message}`,
        existingError,
      );
    } else {
      console.log(
        `[7] Existing briefing check complete. Found: ${!!existingBriefing}`,
      );
    }

    if (existingBriefing) {
      console.log(`[7] Returning cached briefing: ${existingBriefing.id}`);
      return new Response(JSON.stringify(existingBriefing), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Step 8: Fetch user preferences
    console.log("[8] Fetching user preferences...");
    const { data: preferences, error: prefError } = await supabase
      .from("briefing_preferences")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();

    if (prefError) {
      console.log(
        `[8] ERROR fetching preferences: ${prefError.message}`,
        prefError,
      );
    } else {
      console.log(`[8] Preferences found: ${!!preferences}`);
    }

    const userPrefs = preferences || {
      enabled: true,
      include_calendar: true,
      calendar_lookahead_hours: 24,
    };
    console.log(
      `[8] Using prefs: enabled=${userPrefs.enabled}, include_calendar=${userPrefs.include_calendar}`,
    );

    if (!userPrefs.enabled) {
      console.log("[8] Briefing disabled by user preferences");
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
    console.log("[9] Fetching user profile...");
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("display_name, timezone")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError) {
      console.log(
        `[9] ERROR fetching profile: ${profileError.message}`,
        profileError,
      );
    } else {
      console.log(
        `[9] Profile found: ${!!profile}, display_name: ${profile?.display_name}`,
      );
    }

    const userName = profile?.display_name || "there";
    const userTimezone = timezone || profile?.timezone || "UTC";
    console.log(`[9] Using userName: ${userName}, timezone: ${userTimezone}`);

    // Step 10: Generate greeting
    console.log("[10] Generating greeting...");
    let greeting: string;
    try {
      greeting = generateGreeting(userName, userTimezone);
      console.log(`[10] Greeting generated: ${greeting}`);
    } catch (greetingError) {
      console.log(`[10] ERROR generating greeting: ${greetingError}`);
      greeting = `Hello, ${userName}!`;
    }

    // Step 11: Fetch mood prediction
    console.log("[11] Fetching mood prediction...");
    const moodPrediction = await fetchMoodPrediction(supabase, user.id);
    console.log(
      `[11] Mood prediction: ${moodPrediction ? `mood=${moodPrediction.predicted_mood}` : "null"}`,
    );

    // Step 12: Fetch quest
    console.log("[12] Fetching quest...");
    const quest = await fetchOrAssignQuest(supabase, user.id, local_date);
    console.log(
      `[12] Quest: ${quest ? `id=${quest.id}, title=${quest.title}` : "null"}`,
    );

    // Step 13: Process calendar events
    console.log("[13] Processing calendar events...");
    const processedEvents = processCalendarEvents(
      calendar_events,
      userPrefs.include_calendar,
    );
    console.log(`[13] Processed events count: ${processedEvents.length}`);

    // Step 14: Fetch sleep data
    console.log("[14] Fetching sleep data...");
    const sleepData = await fetchSleepData(supabase, user.id);
    console.log(
      `[14] Sleep data: ${sleepData ? `hours=${sleepData.sleep_duration_hours}` : "null"}`,
    );

    // Step 15: Generate suggestion
    console.log("[15] Generating suggestion...");
    let suggestion: string;
    try {
      suggestion = generateSuggestion({
        sleepDurationHours: sleepData?.sleep_duration_hours,
        calendarEvents: processedEvents,
        predictedMood: moodPrediction?.predicted_mood,
        userName,
      });
      console.log(
        `[15] Suggestion generated: ${suggestion.substring(0, 50)}...`,
      );
    } catch (suggestionError) {
      console.log(`[15] ERROR generating suggestion: ${suggestionError}`);
      suggestion =
        "Your quest today is ready. Starting with a small win sets the tone for the day.";
    }

    // Step 16: Prepare insert data
    console.log("[16] Preparing insert data...");
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
    console.log(
      "[16] Insert data prepared:",
      JSON.stringify(insertData, null, 2),
    );

    // Step 17: Insert briefing
    console.log("[17] Inserting briefing into database...");
    const { data: briefing, error: insertError } = await supabase
      .from("daily_briefings")
      .insert(insertData)
      .select()
      .single();

    if (insertError) {
      console.log(`[17] ERROR inserting briefing: ${insertError.message}`);
      console.log(`[17] Error code: ${insertError.code}`);
      console.log(`[17] Error details:`, JSON.stringify(insertError, null, 2));
      throw new Error(
        `Database insert failed: ${insertError.message} (code: ${insertError.code})`,
      );
    }

    console.log(`[17] Briefing inserted successfully: ${briefing?.id}`);

    // Step 18: Return response
    console.log("[18] Returning success response");
    console.log("========== DAILY BRIEFING END (SUCCESS) ==========");

    return new Response(JSON.stringify(briefing), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    const error = err as Error;
    console.log("========== DAILY BRIEFING ERROR ==========");
    console.log(`Error type: ${error?.constructor?.name}`);
    console.log(`Error message: ${error?.message}`);
    console.log(`Error stack: ${error?.stack}`);
    console.log("==========================================");

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
  console.log(`[generateGreeting] userName=${userName}, timezone=${timezone}`);

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
    console.log(`[generateGreeting] Parsed hour: ${hour}`);
  } catch (tzError) {
    console.log(`[generateGreeting] Timezone error, using UTC: ${tzError}`);
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
  console.log(`[fetchMoodPrediction] userId=${userId}`);

  try {
    const todayDate = new Date().toISOString().split("T")[0];
    console.log(`[fetchMoodPrediction] Querying for date >= ${todayDate}`);

    const { data, error } = await supabase
      .from("mood_predictions")
      .select("predicted_mood, confidence, factors")
      .eq("user_id", userId)
      .gte("predicted_for", todayDate)
      .order("predicted_for", { ascending: true })
      .limit(1)
      .maybeSingle();

    if (error) {
      console.log(`[fetchMoodPrediction] Query error: ${error.message}`, error);
      return null;
    }

    if (!data) {
      console.log("[fetchMoodPrediction] No mood prediction found");
      return null;
    }

    console.log(
      `[fetchMoodPrediction] Found prediction: mood=${data.predicted_mood}`,
    );
    return {
      predicted_mood: data.predicted_mood,
      confidence: data.confidence,
      context: data.factors?.primary_factor || null,
    };
  } catch (error) {
    console.log(`[fetchMoodPrediction] Exception: ${error}`);
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
  console.log(`[fetchOrAssignQuest] userId=${userId}, localDate=${localDate}`);

  try {
    // First, try to fetch existing quest for today
    console.log(
      "[fetchOrAssignQuest] Querying quests table with join to quest_templates...",
    );

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
      console.log(
        `[fetchOrAssignQuest] Query error: ${questError.message}`,
        questError,
      );
      return null;
    }

    if (existingQuest) {
      console.log(`[fetchOrAssignQuest] Found quest: id=${existingQuest.id}`);
      console.log(
        `[fetchOrAssignQuest] Quest data:`,
        JSON.stringify(existingQuest, null, 2),
      );

      // PostgREST returns nested object for joins
      const template = existingQuest.quest_templates;
      return {
        id: existingQuest.id,
        title: template?.title || "Daily Quest",
        description: template?.description,
      };
    }

    console.log(`[fetchOrAssignQuest] No quest found for ${localDate}`);
    return null;
  } catch (error) {
    console.log(`[fetchOrAssignQuest] Exception: ${error}`);
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
  console.log(
    `[processCalendarEvents] events=${events?.length || 0}, includeCalendar=${includeCalendar}`,
  );

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
  console.log(`[processCalendarEvents] Returning ${result.length} events`);
  return result;
}

/**
 * Fetch sleep data from biometric_daily_summaries (for suggestion context)
 */
async function fetchSleepData(
  supabase: any,
  userId: string,
): Promise<{ sleep_duration_hours: number } | null> {
  console.log(`[fetchSleepData] userId=${userId}`);

  try {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayDate = yesterday.toISOString().split("T")[0];
    console.log(`[fetchSleepData] Querying for date=${yesterdayDate}`);

    const { data, error } = await supabase
      .from("biometric_daily_summaries")
      .select("sleep_duration_hours")
      .eq("user_id", userId)
      .eq("summary_date", yesterdayDate)
      .maybeSingle();

    if (error) {
      console.log(`[fetchSleepData] Query error: ${error.message}`, error);
      return null;
    }

    if (!data || !data.sleep_duration_hours) {
      console.log("[fetchSleepData] No sleep data found");
      return null;
    }

    console.log(
      `[fetchSleepData] Found sleep data: ${data.sleep_duration_hours} hours`,
    );
    return { sleep_duration_hours: data.sleep_duration_hours };
  } catch (error) {
    console.log(`[fetchSleepData] Exception: ${error}`);
    return null;
  }
}

/**
 * Generate personalized suggestion based on context
 * Priority: Sleep deficit > Calendar event prep > Low mood armor > Default encouragement
 */
function generateSuggestion(context: SuggestionContext): string {
  console.log(`[generateSuggestion] context:`, JSON.stringify(context));

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
