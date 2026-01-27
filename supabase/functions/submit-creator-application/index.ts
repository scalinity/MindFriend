import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

interface ApplicationRequest {
  fullName: string;
  email: string;
  location?: string;
  professionalBackground: string;
  teachingPhilosophy?: string;
  experienceYears?: number;
  credentials: Array<{
    type: string;
    name: string;
    issuer: string;
    year?: number;
  }>;
  portfolioLinks?: string[];
  sampleContentUrls?: string[];
}

function validateApplicationInput(req: ApplicationRequest): string | null {
  if (!req.fullName || typeof req.fullName !== "string") {
    return "Full name is required";
  }

  if (req.fullName.length < 2 || req.fullName.length > 100) {
    return "Full name must be between 2 and 100 characters";
  }

  if (!req.email || typeof req.email !== "string") {
    return "Email is required";
  }

  // Basic email validation
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(req.email)) {
    return "Invalid email format";
  }

  if (
    !req.professionalBackground ||
    typeof req.professionalBackground !== "string"
  ) {
    return "Professional background is required";
  }

  if (
    req.professionalBackground.length < 10 ||
    req.professionalBackground.length > 2000
  ) {
    return "Professional background must be between 10 and 2000 characters";
  }

  // Validate portfolio links if provided
  if (req.portfolioLinks && Array.isArray(req.portfolioLinks)) {
    for (const link of req.portfolioLinks) {
      try {
        new URL(link);
      } catch {
        return `Invalid portfolio URL: ${link}`;
      }
    }
  }

  return null;
}

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization")!;
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
    });
  }

  const application: ApplicationRequest = await req.json();

  // Validate input
  const validationError = validateApplicationInput(application);
  if (validationError) {
    return new Response(JSON.stringify({ error: validationError }), {
      status: 400,
    });
  }

  try {
    // Check for existing pending application
    const { data: existing } = await supabase
      .from("creator_applications")
      .select("id, status")
      .eq("user_id", user.id)
      .in("status", ["pending", "under_review"])
      .single();

    if (existing) {
      return new Response(
        JSON.stringify({ error: "You already have a pending application" }),
        { status: 400 },
      );
    }

    // Check if already a creator
    const { data: existingCreator } = await supabase
      .from("creators")
      .select("id")
      .eq("user_id", user.id)
      .single();

    if (existingCreator) {
      return new Response(
        JSON.stringify({ error: "You are already a creator" }),
        { status: 400 },
      );
    }

    // Create application
    const { data: newApplication, error: insertError } = await supabase
      .from("creator_applications")
      .insert({
        user_id: user.id,
        full_name: application.fullName,
        email: application.email,
        location: application.location,
        professional_background: application.professionalBackground,
        teaching_philosophy: application.teachingPhilosophy,
        experience_years: application.experienceYears,
        credentials: application.credentials,
        portfolio_links: application.portfolioLinks,
        sample_content_urls: application.sampleContentUrls,
        status: "pending",
      })
      .select()
      .single();

    if (insertError) throw insertError;

    // Log to admin notifications
    console.log(
      `Creator application submitted: ${newApplication.id} by ${user.id}`,
    );

    return new Response(
      JSON.stringify({
        success: true,
        applicationId: newApplication.id,
        message:
          "Application submitted successfully. We'll review it within 7 business days.",
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Application submission error:", error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
    });
  }
});
