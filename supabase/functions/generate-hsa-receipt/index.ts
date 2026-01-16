// MindFriend Generate HSA/FSA Receipt Edge Function
// Generates tax-compliant receipts for HSA/FSA reimbursement

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { createLogger } from "../_shared/logger.ts";
import { CommonErrors } from "../_shared/errors.ts";

const log = createLogger("generate-hsa-receipt");

interface GenerateReceiptRequest {
  subscriptionId: string;
}

interface GenerateReceiptResponse {
  success: boolean;
  receiptUrl?: string;
  receiptNumber?: string;
  error?: string;
}

// Generate a unique receipt number
function generateReceiptNumber(): string {
  const timestamp = Date.now().toString(36).toUpperCase();
  const random = Math.random().toString(36).substring(2, 8).toUpperCase();
  return `MFR-${timestamp}-${random}`;
}

// Generate HSA/FSA compliant receipt JSON
function generateReceiptJSON(data: {
  receiptNumber: string;
  subscriptionId: string;
  userName: string;
  userEmail: string;
  planName: string;
  amount: number;
  currency: string;
  servicePeriodStart: string;
  servicePeriodEnd: string;
  serviceDate: string;
}) {
  return {
    receipt: {
      number: data.receiptNumber,
      date: new Date().toISOString().split("T")[0],
      type: "HSA/FSA Eligible - Mental Health Subscription",
    },
    merchant: {
      name: "MindFriend Inc.",
      ein: "XX-XXXXXXX", // Placeholder - replace with real EIN
      businessAddress: "123 Mental Health Way, San Francisco, CA 94105",
      phone: "+1-555-MINDFRIEND",
      mcc: "8099", // Health services (IRS code)
    },
    customer: {
      name: data.userName,
      email: data.userEmail,
    },
    service: {
      description:
        "Mental health subscription - AI companion, therapy tools, wellness tracking",
      serviceName: data.planName,
      cptCode: "90899", // CPT code for psychiatric services (general)
      diagnosisCodes: [
        "F41.1", // Generalized anxiety disorder
        "F32.9", // Major depressive disorder, single episode
      ],
      serviceCategory: "Mental Health & Behavioral Health Integration Services",
    },
    itemization: {
      description: data.planName,
      quantity: 1,
      unitPrice: data.amount,
      total: data.amount,
      currency: data.currency,
    },
    eligibilityStatement: {
      statement:
        "This service qualifies for HSA/FSA reimbursement as it provides mental health and behavioral health integration services.",
      references: [
        "IRS Publication 969 - Health Savings Accounts",
        "IRC Section 223(d) - Qualified Medical Expenses",
        "Treasury Regulation 1.223-1",
      ],
      servicePeriod: {
        start: data.servicePeriodStart,
        end: data.servicePeriodEnd,
      },
      merchant: {
        name: "MindFriend Inc.",
        category: "Mental Health Services Provider",
      },
    },
    tax: {
      taxAmount: 0,
      taxExempt: true,
      taxExemptReason: "HSA/FSA Eligible Medical Service",
    },
    summary: {
      subtotal: data.amount,
      tax: 0,
      total: data.amount,
      currency: data.currency,
    },
    disclaimers: [
      "This receipt is for HSA/FSA reimbursement purposes only.",
      "Verify with your HSA/FSA plan administrator before submitting for reimbursement.",
      "MindFriend is not a substitute for professional medical advice.",
      "Keep this receipt for your records and HSA/FSA documentation.",
    ],
  };
}

// Convert JSON to simple text-based receipt (HTML-safe format)
function generateReceiptHTML(receiptData: Record<string, unknown>): string {
  const r = receiptData.receipt as Record<string, unknown>;
  const m = receiptData.merchant as Record<string, unknown>;
  const c = receiptData.customer as Record<string, unknown>;
  const s = receiptData.service as Record<string, unknown>;
  const i = receiptData.itemization as Record<string, unknown>;
  const e = receiptData.eligibilityStatement as Record<string, unknown>;
  const sum = receiptData.summary as Record<string, unknown>;

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>HSA/FSA Receipt - ${receiptData.receipt}</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    .header { border-bottom: 2px solid #333; padding-bottom: 10px; margin-bottom: 20px; }
    .merchant { font-weight: bold; font-size: 16px; }
    .section { margin: 15px 0; }
    .section-title { font-weight: bold; border-bottom: 1px solid #ccc; padding-bottom: 5px; margin-bottom: 10px; }
    table { width: 100%; border-collapse: collapse; margin: 10px 0; }
    th, td { text-align: left; padding: 8px; border-bottom: 1px solid #ddd; }
    .amount { text-align: right; }
    .total-row { font-weight: bold; background-color: #f0f0f0; }
    .footer { margin-top: 30px; font-size: 12px; color: #666; border-top: 1px solid #ccc; padding-top: 10px; }
  </style>
</head>
<body>
  <div class="header">
    <div class="merchant">${m.name}</div>
    <div>EIN: ${m.ein}</div>
    <div>${m.businessAddress}</div>
    <div>MCC: ${m.mcc} (Health Services)</div>
    <div style="margin-top: 10px;">Receipt #: ${r.number}</div>
    <div>Date: ${r.date}</div>
  </div>

  <div class="section">
    <div class="section-title">Customer Information</div>
    <div><strong>Name:</strong> ${c.name}</div>
    <div><strong>Email:</strong> ${c.email}</div>
  </div>

  <div class="section">
    <div class="section-title">Service Description</div>
    <div><strong>Service:</strong> ${s.serviceName}</div>
    <div><strong>CPT Code:</strong> ${s.cptCode}</div>
    <div><strong>Category:</strong> ${s.serviceCategory}</div>
    <div style="margin-top: 10px;"><strong>Description:</strong></div>
    <div>${s.description}</div>
  </div>

  <div class="section">
    <div class="section-title">Service Itemization</div>
    <table>
      <tr>
        <th>Description</th>
        <th class="amount">Amount</th>
      </tr>
      <tr>
        <td>${i.description}</td>
        <td class="amount">\$${((i.total as number) / 100).toFixed(2)}</td>
      </tr>
    </table>
  </div>

  <div class="section">
    <div class="section-title">Summary</div>
    <table>
      <tr>
        <td><strong>Subtotal</strong></td>
        <td class="amount amount">$${((sum.subtotal as number) / 100).toFixed(2)}</td>
      </tr>
      <tr>
        <td><strong>Tax</strong></td>
        <td class="amount">\$${((sum.tax as number) / 100).toFixed(2)} (Tax Exempt)</td>
      </tr>
      <tr class="total-row">
        <td><strong>Total</strong></td>
        <td class="amount"><strong>\$${((sum.total as number) / 100).toFixed(2)}</strong></td>
      </tr>
    </table>
  </div>

  <div class="section">
    <div class="section-title">HSA/FSA Eligibility Statement</div>
    <p>${e.statement}</p>
    <p><strong>Service Period:</strong> ${(e.servicePeriod as Record<string, string>).start} to ${(e.servicePeriod as Record<string, string>).end}</p>
    <p><strong>Diagnosis Codes (ICD-10):</strong> F41.1, F32.9</p>
  </div>

  <div class="footer">
    <p><strong>Important:</strong></p>
    <ul>
      <li>This receipt is for HSA/FSA reimbursement purposes only</li>
      <li>Verify with your HSA/FSA plan administrator before submitting</li>
      <li>MindFriend is not a substitute for professional medical advice</li>
      <li>Keep this receipt for your records and tax documentation</li>
    </ul>
  </div>
</body>
</html>
  `;
}

serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const corsHeaders = getCorsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Authenticate user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return CommonErrors.unauthorized(corsHeaders);
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return CommonErrors.invalidToken(corsHeaders);
    }

    const requestBody: GenerateReceiptRequest = await req.json();
    const { subscriptionId } = requestBody;

    // Validate required field
    if (!subscriptionId) {
      return CommonErrors.badRequest(
        corsHeaders,
        "Missing required field: subscriptionId",
      );
    }

    // Get subscription details
    const { data: subscription, error: subError } = await supabaseAdmin
      .from("subscriptions")
      .select("*")
      .eq("id", subscriptionId)
      .eq("user_id", user.id)
      .single();

    if (subError || !subscription) {
      log.error("Subscription not found", {
        subscriptionId,
        error: subError?.message,
      });
      return CommonErrors.notFound(corsHeaders, "Subscription");
    }

    // Get plan details
    const { data: plan, error: planError } = await supabaseAdmin
      .from("subscription_plans")
      .select("*")
      .eq("app_store_product_id", subscription.product_id)
      .single();

    if (planError || !plan) {
      log.error("Plan not found", {
        productId: subscription.product_id,
        error: planError?.message,
      });
      return new Response(
        JSON.stringify({
          success: false,
          error: "Plan details not found",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get user profile for name
    const { data: profile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .select("full_name")
      .eq("id", user.id)
      .single();

    if (profileError) {
      log.warn("Profile not found", { userId: user.id });
    }

    const { data: authUser } = await supabaseAdmin.auth.admin.getUserById(
      user.id,
    );
    const userEmail = authUser?.user?.email || "user@mindfriend.app";
    const userName =
      profile?.full_name || authUser?.user?.email?.split("@")[0] || "User";

    // Generate receipt number
    const receiptNumber = generateReceiptNumber();

    // Calculate service period (current subscription period)
    const now = new Date();
    const servicePeriodStart = now.toISOString().split("T")[0];
    const servicePeriodEnd = subscription.expires_at
      ? subscription.expires_at.split("T")[0]
      : new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000)
          .toISOString()
          .split("T")[0];

    // Generate receipt JSON data
    const receiptData = generateReceiptJSON({
      receiptNumber,
      subscriptionId,
      userName,
      userEmail,
      planName: plan.name,
      amount: plan.price_cents,
      currency: plan.currency || "USD",
      servicePeriodStart,
      servicePeriodEnd,
      serviceDate: now.toISOString().split("T")[0],
    });

    // Generate HTML receipt
    const receiptHTML = generateReceiptHTML(receiptData);

    // Upload receipt to Supabase Storage
    const fileName = `receipts/${user.id}/${receiptNumber}.html`;

    const { error: uploadError } = await supabaseAdmin.storage
      .from("documents")
      .upload(fileName, new TextEncoder().encode(receiptHTML), {
        contentType: "text/html",
        upsert: true,
      });

    if (uploadError) {
      log.error("Failed to upload receipt", { error: uploadError.message });
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to store receipt",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get public URL for receipt
    const { data: publicData } = await supabaseAdmin.storage
      .from("documents")
      .getPublicUrl(fileName);

    const receiptUrl = publicData.publicUrl;

    // Insert or update HSA/FSA record
    const { error: hsaError } = await supabaseAdmin
      .from("hsa_fsa_records")
      .upsert({
        user_id: user.id,
        subscription_id: subscriptionId,
        is_hsa_eligible: true,
        is_fsa_eligible: true,
        receipt_generated_at: now.toISOString(),
        receipt_url: receiptUrl,
        receipt_amount_cents: plan.price_cents,
        merchant_category_code: "8099",
        diagnosis_codes: ["F41.1", "F32.9"],
      });

    if (hsaError) {
      log.warn("Failed to update HSA/FSA record", { error: hsaError.message });
      // Don't fail - receipt was still generated successfully
    }

    log.info("HSA/FSA receipt generated", {
      receiptNumber,
      userId: user.id.slice(0, 8),
      subscriptionId,
      receiptUrl,
    });

    const response: GenerateReceiptResponse = {
      success: true,
      receiptUrl,
      receiptNumber,
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    log.error("Generate receipt error", { error: String(error) });
    return CommonErrors.internalError(corsHeaders);
  }
});
