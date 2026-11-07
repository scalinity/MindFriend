import { assertEquals, assertExists } from "jsr:@std/assert@1.0.19";
import { handleEnterpriseInquiry } from "./index.ts";

Deno.test("enterprise inquiry encodes the address in the actual email template", async () => {
  const originalFetch = globalThis.fetch;
  const environment = {
    SUPABASE_URL: "https://inquiry.invalid",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-key",
    RESEND_API_KEY: "synthetic-email-key",
  };
  const previous = new Map(Object.keys(environment).map((key) => [key, Deno.env.get(key)]));
  for (const [key, value] of Object.entries(environment)) Deno.env.set(key, value);

  const emails: { html: string; reply_to: string }[] = [];
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    if (url.hostname === "inquiry.invalid" && url.pathname === "/auth/v1/user") {
      return Response.json({ id: "11111111-1111-4111-8111-111111111111" });
    }
    if (url.hostname === "inquiry.invalid" && url.pathname === "/rest/v1/enterprise_inquiries") {
      if (request.method === "HEAD") return new Response(null, { headers: { "content-range": "*/0" } });
      if (request.method === "GET") return Response.json(null);
      if (request.method === "POST") return Response.json({ id: "22222222-2222-4222-8222-222222222222" });
      if (request.method === "PATCH") return new Response(null, { status: 204 });
    }
    if (url.href === "https://api.resend.com/emails") {
      emails.push(await request.json());
      return Response.json({ id: "synthetic-delivery" });
    }
    throw new Error(`Unexpected request: ${request.method} ${url.pathname}`);
  };

  try {
    for (const address of ['"<b>urgent</b>"@example.com', 'x&y+tag?subject=spoof@example.com', 'o\'neil@example.com']) {
      const response = await handleEnterpriseInquiry(new Request("https://function.invalid", {
        method: "POST",
        headers: { Authorization: "Bearer synthetic-user-token", "Content-Type": "application/json" },
        body: JSON.stringify({ name: "Test", email: address, companyName: "Test", employeeCount: "1-10" }),
      }));
      assertEquals(response.status, 200);
      assertEquals((await response.json()).success, true);
      const email = emails.at(-1);
      assertExists(email);
      const link = email.html.match(/<a href="([^"]+)" style="color: #6366f1;">([^<]*)<\/a>/);
      assertExists(link);
      const mailto = link[1].replaceAll("&#039;", "'");
      assertEquals(decodeURIComponent(mailto.slice("mailto:".length)), address);
      assertEquals(link[1].includes("?"), false);
      assertEquals(mailto.includes("&"), false);
      assertEquals(email.html.includes("<b>urgent</b>"), false);
      assertEquals(link[2].includes('"'), false);
      assertEquals(email.reply_to, address);
    }
    assertEquals(emails.length, 3);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of previous) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
});
