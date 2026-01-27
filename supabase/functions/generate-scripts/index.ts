// Boundary & Needs Planner: Generate Scripts
// Endpoint: POST /functions/v1/generate-scripts
// Generates boundary conversation scripts from templates with placeholder replacement

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders } from "../_shared/cors.ts";

// Types
interface GenerateScriptsRequest {
  boundaryId: string;
  relationshipType:
    | "manager"
    | "colleague"
    | "partner"
    | "parent"
    | "friend"
    | "other";
  variations: Array<"direct" | "gentle" | "assertive" | "collaborative">;
}

interface ScriptResponse {
  variation: string;
  script: string;
  toneDescription: string;
  tips: string[];
}

// Placeholder replacement specification
const PLACEHOLDER_MAP: Record<
  string,
  { column: string; required: boolean; fallback: string }
> = {
  "[boundary]": {
    column: "statement_text",
    required: true,
    fallback: "",
  },
  "[why_matters]": {
    column: "why_matters",
    required: false,
    fallback: "maintain healthy boundaries",
  },
  "[stakeholder]": {
    column: "stakeholder",
    required: false,
    fallback: "the other person",
  },
  "[contact_method]": {
    column: "preferred_contact", // From user_settings
    required: false,
    fallback: "text message",
  },
};

/**
 * Replace placeholders in template text with actual boundary data
 */
function replacePlaceholders(
  templateText: string,
  boundary: any,
  userSettings: any,
): string {
  let result = templateText;

  for (const [placeholder, spec] of Object.entries(PLACEHOLDER_MAP)) {
    let value: string | null = null;

    // Get value from appropriate source
    if (spec.column === "preferred_contact") {
      value = userSettings?.[spec.column] || null;
    } else {
      value = boundary[spec.column] || null;
    }

    // Handle missing required values
    if (spec.required && !value) {
      throw new Error(`Template requires missing field: ${spec.column}`);
    }

    // Use fallback if needed
    const replacement = value || spec.fallback;

    // Replace placeholder
    result = result.replace(
      new RegExp(placeholder.replace(/[[\]]/g, "\\$&"), "g"),
      replacement,
    );
  }

  return result;
}

/**
 * Generate practice prompts based on boundary type
 */
function generatePracticePrompts(boundaryType: string): string[] {
  const promptTemplates: Record<string, string[]> = {
    time: [
      "Practice saying: 'I need to protect my personal time.'",
      "Try this: 'I've set a boundary around my work hours.'",
      "Rehearse: 'My evenings are reserved for family time.'",
    ],
    emotional: [
      "Practice saying: 'I can support you without taking on your emotions.'",
      "Try this: 'I care about you, but I need to set this boundary.'",
      "Rehearse: 'I'm setting this limit to protect my emotional well-being.'",
    ],
    digital: [
      "Practice saying: 'I won't be checking messages after 8pm.'",
      "Try this: 'I'm taking a break from social media on weekends.'",
      "Rehearse: 'I need digital downtime to recharge.'",
    ],
    physical: [
      "Practice saying: 'I need personal space right now.'",
      "Try this: 'Please give me notice before visiting.'",
      "Rehearse: 'I'm setting a boundary around physical touch.'",
    ],
    financial: [
      "Practice saying: 'I can't lend money, but I can help in other ways.'",
      "Try this: 'I've set a budget and need to stick to it.'",
      "Rehearse: 'I'm not comfortable discussing my finances.'",
    ],
  };

  return promptTemplates[boundaryType] || promptTemplates.time;
}

/**
 * Generate tips based on script variation
 */
function generateTips(variation: string): string[] {
  const tipsByVariation: Record<string, string[]> = {
    direct: [
      "Use calm, confident body language",
      "Make eye contact and speak clearly",
      "State your boundary without over-explaining",
    ],
    gentle: [
      "Use warm, empathetic tone",
      "Acknowledge their perspective first",
      "Frame as collaboration, not confrontation",
    ],
    assertive: [
      "Be firm but respectful",
      "Don't apologize for having needs",
      "Repeat your boundary if challenged",
    ],
    collaborative: [
      "Invite dialogue and input",
      "Express willingness to find solutions",
      "Emphasize mutual benefit",
    ],
  };

  return tipsByVariation[variation] || tipsByVariation.direct;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from JWT
    const authHeader = req.headers.get("Authorization")!;
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request body
    const body: GenerateScriptsRequest = await req.json();

    // Validate boundary ID
    if (!body.boundaryId) {
      return new Response(JSON.stringify({ error: "Missing boundaryId" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Fetch boundary from database
    const { data: boundary, error: boundaryError } = await supabase
      .from("defined_boundaries")
      .select("*")
      .eq("id", body.boundaryId)
      .eq("user_id", user.id)
      .single();

    if (boundaryError || !boundary) {
      return new Response(JSON.stringify({ error: "Boundary not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Get user settings for placeholder replacement
    const { data: userSettings } = await supabase
      .from("user_settings")
      .select("preferred_contact")
      .eq("user_id", user.id)
      .single();

    // Get user's subscription tier
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("subscription_tier")
      .eq("user_id", user.id)
      .single();

    const tier = subscription?.subscription_tier || "free";
    const isPremium = tier === "premium";

    // Get user's locale (default to 'en')
    const locale = "en"; // TODO: Get from user profile when localization is implemented

    // Query templates for each requested variation
    const scripts: ScriptResponse[] = [];

    for (const variation of body.variations) {
      // Try exact match first
      let { data: templates } = await supabase
        .from("boundary_script_templates")
        .select("*")
        .eq("boundary_type", boundary.boundary_type)
        .eq("relationship_type", body.relationshipType)
        .eq("template_variation", variation)
        .eq("locale", locale);

      // Fallback to 'other' relationship type if no exact match
      if (!templates || templates.length === 0) {
        const { data: fallbackTemplates } = await supabase
          .from("boundary_script_templates")
          .select("*")
          .eq("boundary_type", boundary.boundary_type)
          .eq("relationship_type", "other")
          .eq("template_variation", variation)
          .eq("locale", locale);

        templates = fallbackTemplates;
      }

      // Filter by premium status
      const availableTemplates =
        templates?.filter((t) => !t.is_premium || isPremium) || [];

      if (availableTemplates.length === 0) {
        // No template found - return error for this variation
        console.error(
          `No template found for ${boundary.boundary_type}/${body.relationshipType}/${variation}`,
        );
        continue;
      }

      // Use first available template
      const template = availableTemplates[0];

      try {
        // Replace placeholders
        const scriptText = replacePlaceholders(
          template.template_text,
          boundary,
          userSettings,
        );

        scripts.push({
          variation,
          script: scriptText,
          toneDescription: template.tone_description || "",
          tips: generateTips(variation),
        });
      } catch (error) {
        console.error(`Error replacing placeholders for ${variation}:`, error);
        // Continue with other variations
      }
    }

    // If no scripts were generated, return error
    if (scripts.length === 0) {
      return new Response(
        JSON.stringify({ error: "Template not found or database error" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Update boundary with generated scripts
    const { error: updateError } = await supabase
      .from("defined_boundaries")
      .update({
        scripts: scripts.map((s) => ({
          variation: s.variation,
          text: s.script,
          tone_description: s.toneDescription,
          template_id: null, // Could store template ID here if needed
        })),
      })
      .eq("id", body.boundaryId);

    if (updateError) {
      console.error("Error updating boundary with scripts:", updateError);
      // Continue anyway - scripts were generated successfully
    }

    // Generate practice prompts
    const practicePrompts = generatePracticePrompts(boundary.boundary_type);

    // Return success response
    return new Response(
      JSON.stringify({
        success: true,
        scripts,
        practicePrompts,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error generating scripts:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
