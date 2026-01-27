// MindFriend Enterprise Inquiry Edge Function
// Receives enterprise sales inquiry from iOS app, saves to database, sends email notification

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getCorsHeaders } from "../_shared/cors.ts";
import { escapeHtml, isValidEmail, sanitizeEmail } from "../_shared/utils.ts";

interface EnterpriseInquiryRequest {
  name: string;
  email: string;
  companyName: string;
  employeeCount: string;
  message?: string;
}

interface EnterpriseInquiryResponse {
  success: boolean;
  inquiryId?: string;
  message?: string;
  error?: string;
}

const VALID_EMPLOYEE_COUNTS = ["1-10", "11-50", "51-200", "201-500", "500+"];
const MAX_NAME_LENGTH = 100;
const MAX_COMPANY_LENGTH = 200;
const MAX_MESSAGE_LENGTH = 2000;
const DUPLICATE_WINDOW_MINUTES = 5;
const MAX_INQUIRIES_PER_DAY = 10;

serve(async (req) => {
  const origin = req.headers.get("Origin");
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Unauthorized", code: "UNAUTHORIZED" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid token", code: "INVALID_TOKEN" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate Content-Type
    const contentType = req.headers.get("Content-Type");
    if (!contentType || !contentType.includes("application/json")) {
      return new Response(
        JSON.stringify({
          error: "Content-Type must be application/json",
          code: "INVALID_CONTENT_TYPE",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Global rate limiting: max 10 inquiries per user per 24 hours
    const oneDayAgo = new Date();
    oneDayAgo.setHours(oneDayAgo.getHours() - 24);

    const { count: dailyCount } = await supabaseAdmin
      .from("enterprise_inquiries")
      .select("*", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", oneDayAgo.toISOString());

    if (dailyCount && dailyCount >= MAX_INQUIRIES_PER_DAY) {
      return new Response(
        JSON.stringify({
          error: "Rate limit exceeded",
          message: "Maximum 10 inquiries per 24 hours. Please try again later.",
          code: "RATE_LIMIT_EXCEEDED",
        }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Parse and validate request body
    const body: EnterpriseInquiryRequest = await req.json();
    const { name, email: rawEmail, companyName, employeeCount, message } = body;

    // Validate required fields
    const validationErrors: Record<string, string> = {};

    if (!name || name.trim().length === 0) {
      validationErrors.name = "Name is required";
    } else if (name.trim().length > MAX_NAME_LENGTH) {
      validationErrors.name = `Name must be ${MAX_NAME_LENGTH} characters or less`;
    }

    if (!rawEmail || rawEmail.trim().length === 0) {
      validationErrors.email = "Email is required";
    } else if (!isValidEmail(rawEmail)) {
      validationErrors.email = "Please enter a valid email address";
    }

    if (!companyName || companyName.trim().length === 0) {
      validationErrors.companyName = "Company name is required";
    } else if (companyName.trim().length > MAX_COMPANY_LENGTH) {
      validationErrors.companyName = `Company name must be ${MAX_COMPANY_LENGTH} characters or less`;
    }

    if (!employeeCount || !VALID_EMPLOYEE_COUNTS.includes(employeeCount)) {
      validationErrors.employeeCount = "Please select a valid employee count";
    }

    if (message && message.length > MAX_MESSAGE_LENGTH) {
      validationErrors.message = `Message must be ${MAX_MESSAGE_LENGTH} characters or less`;
    }

    if (Object.keys(validationErrors).length > 0) {
      return new Response(
        JSON.stringify({
          error: "Validation failed",
          details: validationErrors,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Sanitize inputs
    const sanitizedName = name.trim();
    const sanitizedEmail = sanitizeEmail(rawEmail);
    const sanitizedCompany = companyName.trim();
    const sanitizedMessage = message ? message.trim() : null;

    // Check for duplicate submission within 5-minute window
    const duplicateWindowStart = new Date();
    duplicateWindowStart.setMinutes(
      duplicateWindowStart.getMinutes() - DUPLICATE_WINDOW_MINUTES,
    );

    const { data: existingInquiry } = await supabaseAdmin
      .from("enterprise_inquiries")
      .select("id")
      .eq("user_id", user.id)
      .eq("email", sanitizedEmail.toLowerCase())
      .eq("company_name", sanitizedCompany)
      .gte("created_at", duplicateWindowStart.toISOString())
      .limit(1)
      .single();

    if (existingInquiry) {
      return new Response(
        JSON.stringify({
          error: "Duplicate submission",
          message:
            "You've already submitted an inquiry recently. We'll get back to you soon.",
          code: "DUPLICATE_SUBMISSION",
        }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Insert inquiry into database
    const { data: inquiry, error: insertError } = await supabaseAdmin
      .from("enterprise_inquiries")
      .insert({
        user_id: user.id,
        name: sanitizedName,
        email: sanitizedEmail.toLowerCase(),
        company_name: sanitizedCompany,
        employee_count: employeeCount,
        message: sanitizedMessage,
        email_sent: false,
      })
      .select("id")
      .single();

    if (insertError) {
      console.error("Error inserting enterprise inquiry:", insertError);
      return new Response(
        JSON.stringify({
          error: "Failed to save inquiry",
          code: "DATABASE_ERROR",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Send email notification to sales team via Resend
    let emailSent = false;
    const resendApiKey = Deno.env.get("RESEND_API_KEY");

    if (resendApiKey) {
      try {
        // Escape user content to prevent XSS in email
        const safeName = escapeHtml(sanitizedName);
        const safeCompany = escapeHtml(sanitizedCompany);
        const safeEmployeeCount = escapeHtml(employeeCount);
        const safeMessage = sanitizedMessage
          ? escapeHtml(sanitizedMessage)
          : "(not provided)";

        // Sanitize email for use in headers (prevent CRLF injection)
        const safeReplyTo = sanitizedEmail.replace(/[\r\n]/g, "").trim();

        const emailResponse = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${resendApiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from: "MindFriend Inquiries <inquiries@getmindfriend.app>",
            to: ["support@getmindfriend.app"],
            reply_to: safeReplyTo,
            subject: `Enterprise Inquiry: ${safeCompany}`,
            html: `
              <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
                <h1 style="color: #6366f1; margin-bottom: 24px;">New Enterprise Inquiry</h1>

                <table style="width: 100%; border-collapse: collapse; margin-bottom: 24px;">
                  <tr>
                    <td style="padding: 12px; border-bottom: 1px solid #e5e7eb; color: #6b7280; font-weight: 500; width: 140px;">Contact Name</td>
                    <td style="padding: 12px; border-bottom: 1px solid #e5e7eb; color: #111827;">${safeName}</td>
                  </tr>
                  <tr>
                    <td style="padding: 12px; border-bottom: 1px solid #e5e7eb; color: #6b7280; font-weight: 500;">Email</td>
                    <td style="padding: 12px; border-bottom: 1px solid #e5e7eb; color: #111827;">
                      <a href="mailto:${sanitizedEmail}" style="color: #6366f1;">${sanitizedEmail}</a>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding: 12px; border-bottom: 1px solid #e5e7eb; color: #6b7280; font-weight: 500;">Company</td>
                    <td style="padding: 12px; border-bottom: 1px solid #e5e7eb; color: #111827;">${safeCompany}</td>
                  </tr>
                  <tr>
                    <td style="padding: 12px; border-bottom: 1px solid #e5e7eb; color: #6b7280; font-weight: 500;">Employee Count</td>
                    <td style="padding: 12px; border-bottom: 1px solid #e5e7eb; color: #111827;">${safeEmployeeCount}</td>
                  </tr>
                </table>

                <div style="background: #f9fafb; border-radius: 8px; padding: 16px; margin-bottom: 24px;">
                  <p style="font-size: 14px; color: #6b7280; margin: 0 0 8px 0; font-weight: 500;">Message</p>
                  <p style="font-size: 16px; color: #374151; margin: 0; line-height: 1.6; white-space: pre-wrap;">${safeMessage}</p>
                </div>

                <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 24px 0;" />

                <p style="font-size: 12px; color: #9ca3af;">
                  Submitted: ${new Date().toISOString()}<br/>
                  User ID: ${user.id}<br/>
                  Inquiry ID: ${inquiry.id}
                </p>
              </div>
            `,
            text: `
New Enterprise Inquiry

Contact Name: ${sanitizedName}
Email: ${sanitizedEmail}
Company: ${sanitizedCompany}
Employee Count: ${employeeCount}

Message:
${sanitizedMessage || "(not provided)"}

---
Submitted: ${new Date().toISOString()}
User ID: ${user.id}
Inquiry ID: ${inquiry.id}
            `.trim(),
          }),
        });

        if (emailResponse.ok) {
          emailSent = true;
          // Update inquiry to mark email as sent
          await supabaseAdmin
            .from("enterprise_inquiries")
            .update({ email_sent: true })
            .eq("id", inquiry.id);
        } else {
          const errorText = await emailResponse.text();
          console.error("Resend API error:", errorText);
        }
      } catch (emailError) {
        console.error("Error sending email notification:", emailError);
        // Don't fail the request - inquiry is already saved
      }
    } else {
      console.log("RESEND_API_KEY not configured, skipping email notification");
    }

    const response: EnterpriseInquiryResponse = {
      success: true,
      inquiryId: inquiry.id,
      message:
        "Thank you for your inquiry. Our team will contact you within 24 hours.",
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Enterprise inquiry error:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        code: "INTERNAL_ERROR",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
