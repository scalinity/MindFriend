// MindFriend Enterprise Provision Edge Function
// Handles bulk employee provisioning for enterprise accounts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { createLogger } from "../_shared/logger.ts";
import { CommonErrors } from "../_shared/errors.ts";

const log = createLogger("enterprise-provision");

interface Employee {
  email: string;
  employeeId?: string;
  department?: string;
}

interface ProvisionRequest {
  enterpriseAccountId: string;
  employees: Employee[];
}

interface ProvisionResult {
  email: string;
  status: "success" | "error";
  invitationCode?: string;
  error?: string;
}

interface ProvisionResponse {
  success: boolean;
  results?: ProvisionResult[];
  seatsUsed?: number;
  seatsTotal?: number;
  error?: string;
}

// Generate invitation code for employee onboarding
function generateInvitationCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";

  for (let i = 0; i < 16; i++) {
    const randomByte = new Uint8Array(1);
    crypto.getRandomValues(randomByte);
    code += chars.charAt(randomByte[0] % chars.length);
  }

  return code;
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

    const requestBody: ProvisionRequest = await req.json();
    const { enterpriseAccountId, employees } = requestBody;

    // Validate required fields
    if (!enterpriseAccountId || !employees || !Array.isArray(employees)) {
      return CommonErrors.badRequest(
        corsHeaders,
        "Missing required fields: enterpriseAccountId, employees (array)",
      );
    }

    if (employees.length === 0) {
      return CommonErrors.badRequest(
        corsHeaders,
        "Employees array cannot be empty",
      );
    }

    // Get enterprise account
    const { data: enterprise, error: enterpriseError } = await supabaseAdmin
      .from("enterprise_accounts")
      .select("*")
      .eq("id", enterpriseAccountId)
      .single();

    if (enterpriseError || !enterprise) {
      log.error("Enterprise account not found", {
        enterpriseId: enterpriseAccountId,
        error: enterpriseError?.message,
      });
      return CommonErrors.notFound(corsHeaders, "Enterprise account");
    }

    // Verify caller is enterprise admin
    const { data: authUser } = await supabaseAdmin.auth.admin.getUserById(
      user.id,
    );
    const callerEmail = authUser?.user?.email;

    if (callerEmail !== enterprise.admin_email) {
      log.warn("Unauthorized enterprise provision attempt", {
        enterpriseId: enterpriseAccountId,
        callerEmail,
        adminEmail: enterprise.admin_email,
      });
      return CommonErrors.forbidden(
        corsHeaders,
        "Only enterprise admin can provision employees",
      );
    }

    // Count current active/invited employees
    const { data: currentEmployees, error: countError } = await supabaseAdmin
      .from("enterprise_employees")
      .select("id")
      .eq("enterprise_account_id", enterpriseAccountId)
      .in("status", ["invited", "active"]);

    if (countError) {
      log.error("Failed to count employees", { error: countError.message });
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to check seat availability",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const currentSeatsUsed = currentEmployees?.length || 0;
    const seatsAvailable = enterprise.seat_count - currentSeatsUsed;

    // Check if enough seats available
    if (employees.length > seatsAvailable) {
      log.warn("Insufficient seats for employee provisioning", {
        enterpriseId: enterpriseAccountId,
        requested: employees.length,
        available: seatsAvailable,
      });
      return new Response(
        JSON.stringify({
          success: false,
          error: `Insufficient seats. Requested: ${employees.length}, Available: ${seatsAvailable}`,
          seatsUsed: currentSeatsUsed,
          seatsTotal: enterprise.seat_count,
        }),
        {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate email format for all employees
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    for (const emp of employees) {
      if (!emailRegex.test(emp.email)) {
        return CommonErrors.badRequest(
          corsHeaders,
          `Invalid email format: ${emp.email}`,
        );
      }
    }

    // Bulk insert employees
    const employeeRecords = employees.map((emp) => ({
      enterprise_account_id: enterpriseAccountId,
      email: emp.email,
      employee_id: emp.employeeId || null,
      department: emp.department || null,
      status: "invited" as const,
    }));

    const { data: insertedEmployees, error: insertError } = await supabaseAdmin
      .from("enterprise_employees")
      .upsert(employeeRecords, {
        onConflict: "enterprise_account_id,email",
      })
      .select();

    if (insertError) {
      log.error("Failed to insert employees", { error: insertError.message });
      return new Response(
        JSON.stringify({
          success: false,
          error: "Failed to provision employees",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate invitation codes for each employee
    const results: ProvisionResult[] = (insertedEmployees || []).map((emp) => ({
      email: emp.email,
      status: "success",
      invitationCode: generateInvitationCode(),
    }));

    // Log provision event
    log.info("Enterprise employees provisioned", {
      enterpriseId: enterpriseAccountId,
      employeeCount: results.length,
      adminEmail: enterprise.admin_email,
    });

    const response: ProvisionResponse = {
      success: true,
      results,
      seatsUsed: currentSeatsUsed + results.length,
      seatsTotal: enterprise.seat_count,
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    log.error("Enterprise provision error", { error: String(error) });
    return CommonErrors.internalError(corsHeaders);
  }
});
