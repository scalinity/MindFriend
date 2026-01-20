import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Get user from JWT
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(token);

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Invalid token" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const url = new URL(req.url);
  const action = url.searchParams.get("action") || "export";

  // Log access for HIPAA compliance
  await supabase.rpc("log_audit_event", {
    p_user_id: user.id,
    p_action: `fhir_${action}`,
    p_resource_type: "fhir_resource",
    p_resource_id: user.id,
    p_actor_type: "user",
    p_actor_id: user.id,
    p_details: JSON.stringify({
      action,
      ip: req.headers.get("X-Forwarded-For"),
    }),
  });

  try {
    switch (action) {
      case "export_mood": {
        const moodId = url.searchParams.get("mood_id");
        if (!moodId) {
          return new Response(JSON.stringify({ error: "mood_id required" }), {
            status: 400,
            headers: { "Content-Type": "application/json" },
          });
        }

        // Get mood data
        const { data: mood } = await supabase
          .from("moods")
          .select("*")
          .eq("id", moodId)
          .eq("user_id", user.id)
          .single();

        if (!mood) {
          return new Response(JSON.stringify({ error: "Mood not found" }), {
            status: 404,
            headers: { "Content-Type": "application/json" },
          });
        }

        // Convert to FHIR Observation
        const fhirObservation = {
          resourceType: "Observation",
          id: `mood-${mood.id}`,
          meta: {
            versionId: "1",
            lastUpdated: new Date().toISOString(),
          },
          status: "final",
          category: [
            {
              coding: [
                {
                  system:
                    "http://terminology.hl7.org/CodeSystem/observation-category",
                  code: "survey",
                  display: "Survey",
                },
              ],
            },
          ],
          code: {
            coding: [
              {
                system: "http://loinc.org",
                code: "44261-6",
                display: "Patient mood assessment",
              },
            ],
          },
          subject: {
            reference: `Patient/${user.id}`,
          },
          effectiveDateTime: mood.created_at,
          valueQuantity: {
            value: mood.mood_score,
            unit: "score",
            system: "http://unitsofmeasure.org",
            code: "/{score}",
          },
          note: mood.note ? [{ text: mood.note }] : undefined,
        };

        // Store FHIR resource
        await supabase.from("fhir_resources").insert({
          user_id: user.id,
          resource_type: "Observation",
          fhir_id: fhirObservation.id,
          resource_json: fhirObservation,
          source_table: "moods",
          source_id: mood.id,
        });

        return new Response(JSON.stringify(fhirObservation), {
          status: 200,
          headers: { "Content-Type": "application/fhir+json" },
        });
      }

      case "export_assessment": {
        const assessmentId = url.searchParams.get("assessment_id");
        if (!assessmentId) {
          return new Response(
            JSON.stringify({ error: "assessment_id required" }),
            {
              status: 400,
              headers: { "Content-Type": "application/json" },
            },
          );
        }

        // Get assessment data (PHQ-9 or GAD-7)
        const { data: assessment } = await supabase
          .from("assessment_results")
          .select("*")
          .eq("id", assessmentId)
          .eq("user_id", user.id)
          .single();

        if (!assessment) {
          return new Response(
            JSON.stringify({ error: "Assessment not found" }),
            {
              status: 404,
              headers: { "Content-Type": "application/json" },
            },
          );
        }

        // LOINC codes
        const loincCode =
          assessment.assessment_type === "phq9"
            ? "44249-1" // PHQ-9
            : "69737-5"; // GAD-7

        const loincTitle =
          assessment.assessment_type === "phq9"
            ? "Patient Health Questionnaire-9 (PHQ-9)"
            : "Generalized Anxiety Disorder-7 (GAD-7)";

        // Convert to FHIR QuestionnaireResponse
        const fhirQuestionnaire = {
          resourceType: "QuestionnaireResponse",
          id: `assessment-${assessment.id}`,
          meta: {
            versionId: "1",
            lastUpdated: new Date().toISOString(),
          },
          status: "completed",
          subject: {
            reference: `Patient/${user.id}`,
          },
          authored: assessment.completed_at,
          item: assessment.responses.map((response: any, index: number) => ({
            linkId: String(index + 1),
            answer: [{ valueInteger: response.answer }],
          })),
        };

        // Also create an Observation for the score
        const fhirObservation = {
          resourceType: "Observation",
          id: `assessment-score-${assessment.id}`,
          meta: {
            versionId: "1",
            lastUpdated: new Date().toISOString(),
          },
          status: "final",
          category: [
            {
              coding: [
                {
                  system:
                    "http://terminology.hl7.org/CodeSystem/observation-category",
                  code: "survey",
                  display: "Survey",
                },
              ],
            },
          ],
          code: {
            coding: [
              {
                system: "http://loinc.org",
                code: loincCode,
                display: loincTitle,
              },
            ],
          },
          subject: {
            reference: `Patient/${user.id}`,
          },
          effectiveDateTime: assessment.completed_at,
          valueQuantity: {
            value: assessment.total_score,
            unit: "score",
            system: "http://unitsofmeasure.org",
            code: "/{score}",
          },
          interpretation: [
            {
              coding: [
                {
                  system:
                    "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation",
                  code: assessment.severity,
                  display: assessment.severity,
                },
              ],
            },
          ],
        };

        // Store FHIR resources
        await supabase.from("fhir_resources").insert([
          {
            user_id: user.id,
            resource_type: "QuestionnaireResponse",
            fhir_id: fhirQuestionnaire.id,
            resource_json: fhirQuestionnaire,
            source_table: "assessment_results",
            source_id: assessment.id,
          },
          {
            user_id: user.id,
            resource_type: "Observation",
            fhir_id: fhirObservation.id,
            resource_json: fhirObservation,
            source_table: "assessment_results",
            source_id: assessment.id,
          },
        ]);

        return new Response(
          JSON.stringify({
            questionnaire: fhirQuestionnaire,
            observation: fhirObservation,
          }),
          {
            status: 200,
            headers: { "Content-Type": "application/fhir+json" },
          },
        );
      }

      case "export_all": {
        // Export all mood and assessment data as FHIR Bundle
        const { data: moods } = await supabase
          .from("moods")
          .select("*")
          .eq("user_id", user.id)
          .order("created_at", { ascending: false })
          .limit(100);

        const { data: assessments } = await supabase
          .from("assessment_results")
          .select("*")
          .eq("user_id", user.id)
          .order("completed_at", { ascending: false })
          .limit(50);

        const bundle: any = {
          resourceType: "Bundle",
          id: `mindfriend-export-${user.id}`,
          meta: {
            lastUpdated: new Date().toISOString(),
          },
          type: "collection",
          total: (moods?.length || 0) + (assessments?.length || 0),
          entry: [],
        };

        // Add mood observations
        for (const mood of moods || []) {
          bundle.entry.push({
            fullUrl: `urn:uuid:mood-${mood.id}`,
            resource: {
              resourceType: "Observation",
              id: `mood-${mood.id}`,
              status: "final",
              code: {
                coding: [{ system: "http://loinc.org", code: "44261-6" }],
              },
              subject: { reference: `Patient/${user.id}` },
              effectiveDateTime: mood.created_at,
              valueQuantity: {
                value: mood.mood_score,
                unit: "score",
              },
            },
          });
        }

        // Add assessment observations
        for (const assessment of assessments || []) {
          const loincCode =
            assessment.assessment_type === "phq9" ? "44249-1" : "69737-5";

          bundle.entry.push({
            fullUrl: `urn:uuid:assessment-${assessment.id}`,
            resource: {
              resourceType: "Observation",
              id: `assessment-${assessment.id}`,
              status: "final",
              code: {
                coding: [{ system: "http://loinc.org", code: loincCode }],
              },
              subject: { reference: `Patient/${user.id}` },
              effectiveDateTime: assessment.completed_at,
              valueQuantity: {
                value: assessment.total_score,
                unit: "score",
              },
            },
          });
        }

        return new Response(JSON.stringify(bundle), {
          status: 200,
          headers: {
            "Content-Type": "application/fhir+json",
            "Content-Disposition": `attachment; filename="mindfriend-fhir-export-${Date.now()}.json"`,
          },
        });
      }

      case "share_with_provider": {
        const providerToken = url.searchParams.get("provider_token");
        const dataTypes = url.searchParams.get("types")?.split(",") || [
          "moods",
          "assessments",
        ];

        if (!providerToken) {
          return new Response(
            JSON.stringify({ error: "provider_token required" }),
            {
              status: 400,
              headers: { "Content-Type": "application/json" },
            },
          );
        }

        // Generate share token for provider
        const shareToken = crypto.randomUUID();
        const expiresAt = new Date();
        expiresAt.setDate(expiresAt.getDate() + 30); // 30 day expiry

        // Store share grant
        await supabase.from("provider_shares").insert({
          user_id: user.id,
          share_token: shareToken,
          provider_token: providerToken,
          data_types: dataTypes,
          expires_at: expiresAt.toISOString(),
        });

        // Log for HIPAA compliance
        await supabase.rpc("log_audit_event", {
          p_user_id: user.id,
          p_action: "share_data_with_provider",
          p_resource_type: "provider_share",
          p_resource_id: shareToken,
          p_actor_type: "user",
          p_actor_id: user.id,
          p_details: JSON.stringify({ data_types: dataTypes }),
        });

        return new Response(
          JSON.stringify({
            share_token: shareToken,
            expires_at: expiresAt.toISOString(),
            data_types: dataTypes,
          }),
          {
            status: 200,
            headers: { "Content-Type": "application/json" },
          },
        );
      }

      default:
        return new Response(JSON.stringify({ error: "Unknown action" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
    }
  } catch (error) {
    return new Response(
      JSON.stringify({ error: "Export failed", message: String(error) }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
