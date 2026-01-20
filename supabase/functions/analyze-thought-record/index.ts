import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

interface ThoughtRecord {
  id: string;
  user_id: string;
  situation: string;
  automatic_thought: string;
  emotions: Array<{ emotion: string; intensity: number }>;
  evidence_for: string | null;
  evidence_against: string | null;
  balanced_thought: string | null;
}

interface CognitiveDistortion {
  type: string;
  displayName: string;
  description: string;
  reframingTip: string;
}

const COGNITIVE_DISTORTIONS: Record<string, CognitiveDistortion> = {
  all_or_nothing: {
    type: "all_or_nothing",
    displayName: "All-or-Nothing Thinking",
    description:
      "Seeing things in black-and-white categories. If performance falls short of perfect, seeing oneself as a total failure.",
    reframingTip:
      "Look for shades of gray. Are there any partial successes or middle ground?",
  },
  overgeneralization: {
    type: "overgeneralization",
    displayName: "Overgeneralization",
    description:
      "Viewing a single negative event as a never-ending pattern of defeat.",
    reframingTip:
      "Challenge words like 'always' and 'never'. Is this really true every time?",
  },
  mental_filter: {
    type: "mental_filter",
    displayName: "Mental Filter",
    description:
      "Picking out a single negative detail and dwelling on it exclusively.",
    reframingTip: "Zoom out. What positive aspects might you be overlooking?",
  },
  disqualifying_positive: {
    type: "disqualifying_positive",
    displayName: "Disqualifying the Positive",
    description:
      'Rejecting positive experiences by insisting they "don\'t count."',
    reframingTip:
      "Consider: Why does this positive not count? What evidence supports it?",
  },
  mind_reading: {
    type: "mind_reading",
    displayName: "Mind Reading",
    description: "Assuming you know what others are thinking without evidence.",
    reframingTip:
      "Ask: Do I have evidence for what they're thinking? Could there be other explanations?",
  },
  fortune_telling: {
    type: "fortune_telling",
    displayName: "Fortune Telling",
    description: "Predicting things will turn out badly without evidence.",
    reframingTip:
      "Consider other possible outcomes. What evidence supports your prediction?",
  },
  catastrophizing: {
    type: "catastrophizing",
    displayName: "Catastrophizing",
    description:
      "Exaggerating the importance of things or expecting the worst.",
    reframingTip:
      "What's the realistic worst case? How likely is it? What would you do if it happened?",
  },
  emotional_reasoning: {
    type: "emotional_reasoning",
    displayName: "Emotional Reasoning",
    description:
      'Assuming that negative emotions reflect reality: "I feel it, so it must be true."',
    reframingTip:
      "Feelings are valid but not facts. What evidence exists outside how you feel?",
  },
  should_statements: {
    type: "should_statements",
    displayName: "Should Statements",
    description:
      'Using "should" and "must" statements that create pressure and guilt.',
    reframingTip: "Replace 'should' with 'I prefer' or 'It would be nice if'.",
  },
  labeling: {
    type: "labeling",
    displayName: "Labeling",
    description:
      "Attaching a negative label to yourself or others instead of describing behavior.",
    reframingTip:
      "Describe the behavior instead of using a label. What specifically happened?",
  },
};

async function analyzeWithGrok(
  thoughtRecord: ThoughtRecord,
  xaiApiKey: string,
): Promise<{
  distortions: string[];
  explanations: Record<string, string>;
  suggestions: string[];
  validation: string;
  copingStrategies: string[];
}> {
  const prompt = `You are a compassionate CBT (Cognitive Behavioral Therapy) assistant analyzing a thought record. Your role is to help identify cognitive distortions while being supportive and validating.

SITUATION: ${thoughtRecord.situation}

AUTOMATIC THOUGHT: ${thoughtRecord.automatic_thought}

EMOTIONS: ${thoughtRecord.emotions.map((e) => `${e.emotion} (intensity: ${e.intensity}/100)`).join(", ")}

${thoughtRecord.evidence_for ? `EVIDENCE FOR THE THOUGHT: ${thoughtRecord.evidence_for}` : ""}
${thoughtRecord.evidence_against ? `EVIDENCE AGAINST THE THOUGHT: ${thoughtRecord.evidence_against}` : ""}
${thoughtRecord.balanced_thought ? `BALANCED THOUGHT ATTEMPT: ${thoughtRecord.balanced_thought}` : ""}

COGNITIVE DISTORTION TYPES TO CONSIDER:
${Object.values(COGNITIVE_DISTORTIONS)
  .map((d) => `- ${d.displayName}: ${d.description}`)
  .join("\n")}

Please analyze this thought record and provide:

1. IDENTIFIED DISTORTIONS: List which cognitive distortions (if any) are present in the automatic thought. Use the exact type keys: all_or_nothing, overgeneralization, mental_filter, disqualifying_positive, mind_reading, fortune_telling, catastrophizing, emotional_reasoning, should_statements, labeling

2. DISTORTION EXPLANATIONS: For each identified distortion, explain specifically how it appears in this thought.

3. VALIDATION STATEMENT: A brief, compassionate statement validating the person's emotions while gently introducing the idea that thoughts can be examined.

4. REFRAMING SUGGESTIONS: 2-3 alternative ways to think about the situation that are more balanced and realistic.

5. COPING STRATEGIES: 2-3 practical coping strategies relevant to this specific situation.

Respond in JSON format:
{
  "distortions": ["type1", "type2"],
  "explanations": {
    "type1": "explanation of how this distortion appears",
    "type2": "explanation"
  },
  "validation": "Your compassionate validation statement",
  "suggestions": ["alternative thought 1", "alternative thought 2"],
  "copingStrategies": ["strategy 1", "strategy 2"]
}`;

  const response = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${xaiApiKey}`,
    },
    body: JSON.stringify({
      model: "grok-3-mini",
      messages: [
        {
          role: "system",
          content:
            "You are a compassionate CBT therapist assistant. Always respond with valid JSON. Be supportive and non-judgmental while helping identify thinking patterns.",
        },
        { role: "user", content: prompt },
      ],
      temperature: 0.7,
      max_tokens: 1000,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error("Grok API error:", errorText);
    throw new Error(`Grok API error: ${response.status}`);
  }

  const data = await response.json();
  const content = data.choices[0]?.message?.content;

  if (!content) {
    throw new Error("No response from Grok");
  }

  // Parse JSON from response (handle potential markdown code blocks)
  let jsonContent = content;
  if (content.includes("```json")) {
    jsonContent = content.split("```json")[1].split("```")[0].trim();
  } else if (content.includes("```")) {
    jsonContent = content.split("```")[1].split("```")[0].trim();
  }

  try {
    return JSON.parse(jsonContent);
  } catch {
    console.error("Failed to parse Grok response:", content);
    // Return a fallback analysis
    return {
      distortions: [],
      explanations: {},
      validation:
        "Your feelings are valid. Let's explore your thoughts together.",
      suggestions: [
        "Consider what a supportive friend might say about this situation.",
      ],
      copingStrategies: [
        "Take a few deep breaths and revisit this thought later.",
      ],
    };
  }
}

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Verify authorization
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Create Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Verify user
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request
    const { thoughtRecordId } = await req.json();

    if (!thoughtRecordId) {
      return new Response(
        JSON.stringify({ error: "thoughtRecordId is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch the thought record
    const { data: thoughtRecord, error: fetchError } = await supabase
      .from("thought_records")
      .select("*")
      .eq("id", thoughtRecordId)
      .eq("user_id", user.id)
      .single();

    if (fetchError || !thoughtRecord) {
      return new Response(
        JSON.stringify({ error: "Thought record not found" }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get API key
    const xaiApiKey = Deno.env.get("XAI_API_KEY");
    if (!xaiApiKey) {
      console.error("XAI_API_KEY not configured");
      return new Response(
        JSON.stringify({ error: "AI analysis temporarily unavailable" }),
        {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Analyze with Grok
    const analysis = await analyzeWithGrok(thoughtRecord, xaiApiKey);

    // Build the response
    const aiAnalysis = {
      identified_distortions: analysis.distortions,
      distortion_explanations: analysis.explanations,
      reframing_suggestions: analysis.suggestions,
      validation_statement: analysis.validation,
      coping_strategies: analysis.copingStrategies,
    };

    // Update the thought record with analysis
    const { error: updateError } = await supabase
      .from("thought_records")
      .update({
        cognitive_distortions: analysis.distortions,
        ai_analysis: aiAnalysis,
        updated_at: new Date().toISOString(),
      })
      .eq("id", thoughtRecordId);

    if (updateError) {
      console.error("Failed to update thought record:", updateError);
    }

    return new Response(
      JSON.stringify({
        analysis: aiAnalysis,
        distortions: analysis.distortions,
        distortionDetails: analysis.distortions.map(
          (d) =>
            COGNITIVE_DISTORTIONS[d] || {
              type: d,
              displayName: d,
              description: "",
              reframingTip: "",
            },
        ),
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Error analyzing thought record:", error);
    return new Response(
      JSON.stringify({
        error: "Failed to analyze thought record",
        details: error.message,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
