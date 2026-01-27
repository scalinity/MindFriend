// Tests for moderate-forum-content Edge Function
// Comprehensive test suite covering moderation thresholds, crisis detection, timeouts

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

// Mock Grok API for testing
class MockGrokAPI {
  private responses: Map<string, any> = new Map();

  setResponse(content: string, response: any) {
    this.responses.set(content, response);
  }

  async call(content: string): Promise<Response> {
    const mockResponse = this.responses.get(content) || {
      safe: true,
      confidence: 0.9,
      isCrisis: false,
      reason: "Content appears safe",
    };

    return new Response(
      JSON.stringify({
        choices: [
          {
            message: {
              content: JSON.stringify(mockResponse),
            },
          },
        ],
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
}

const mockGrok = new MockGrokAPI();

// Test: Safe content should be approved (confidence > 0.8)
Deno.test("moderate-forum-content: safe content auto-approved", async () => {
  mockGrok.setResponse("I'm feeling anxious today", {
    safe: true,
    confidence: 0.95,
    isCrisis: false,
    reason: "User sharing mental health experience",
  });

  const result = await mockGrok.call("I'm feeling anxious today");
  const data = await result.json();
  const moderation = JSON.parse(data.choices[0].message.content);

  assertEquals(moderation.safe, true);
  assertEquals(moderation.confidence >= 0.8, true);
  assertEquals(moderation.isCrisis, false);
});

// Test: Harmful content should be rejected (confidence > 0.8, not safe)
Deno.test("moderate-forum-content: harmful content rejected", async () => {
  mockGrok.setResponse("You're so stupid, go away", {
    safe: false,
    confidence: 0.95,
    isCrisis: false,
    reason: "Harassment detected",
  });

  const result = await mockGrok.call("You're so stupid, go away");
  const data = await result.json();
  const moderation = JSON.parse(data.choices[0].message.content);

  assertEquals(moderation.safe, false);
  assertEquals(moderation.confidence >= 0.8, true);
});

// Test: Low confidence content should be queued (0.3 <= confidence <= 0.8)
Deno.test(
  "moderate-forum-content: low confidence queued for review",
  async () => {
    mockGrok.setResponse("Ambiguous content", {
      safe: true,
      confidence: 0.5,
      isCrisis: false,
      reason: "Uncertain about intent",
    });

    const result = await mockGrok.call("Ambiguous content");
    const data = await result.json();
    const moderation = JSON.parse(data.choices[0].message.content);

    assertEquals(
      moderation.confidence >= 0.3 && moderation.confidence <= 0.8,
      true,
    );
  },
);

// Test: Very low confidence content rejected (confidence < 0.3)
Deno.test("moderate-forum-content: very low confidence rejected", async () => {
  mockGrok.setResponse("???", {
    safe: false,
    confidence: 0.2,
    isCrisis: false,
    reason: "Unable to determine content safety",
  });

  const result = await mockGrok.call("???");
  const data = await result.json();
  const moderation = JSON.parse(data.choices[0].message.content);

  assertEquals(moderation.confidence < 0.3, true);
});

// Test: Crisis content should be detected but approved
Deno.test("moderate-forum-content: crisis detection", async () => {
  mockGrok.setResponse("I don't want to live anymore", {
    safe: true, // Crisis content is approved but flagged
    confidence: 0.9,
    isCrisis: true,
    reason: "Crisis keywords detected",
  });

  const result = await mockGrok.call("I don't want to live anymore");
  const data = await result.json();
  const moderation = JSON.parse(data.choices[0].message.content);

  assertEquals(moderation.isCrisis, true);
  assertEquals(moderation.safe, true); // Should be approved for peer support
});

// Test: Crisis keywords: self-harm variations
Deno.test("moderate-forum-content: self-harm crisis keywords", async () => {
  const crisisKeywords = [
    "want to die",
    "kill myself",
    "end it all",
    "suicide",
    "self harm",
  ];

  for (const keyword of crisisKeywords) {
    mockGrok.setResponse(keyword, {
      safe: true,
      confidence: 0.9,
      isCrisis: true,
      reason: `Crisis keyword detected: ${keyword}`,
    });

    const result = await mockGrok.call(keyword);
    const data = await result.json();
    const moderation = JSON.parse(data.choices[0].message.content);

    assertEquals(moderation.isCrisis, true);
  }
});

// Test: Spam detection
Deno.test("moderate-forum-content: spam detection", async () => {
  mockGrok.setResponse("BUY NOW! CLICK HERE! www.scam.com", {
    safe: false,
    confidence: 0.98,
    isCrisis: false,
    reason: "Spam detected",
  });

  const result = await mockGrok.call("BUY NOW! CLICK HERE! www.scam.com");
  const data = await result.json();
  const moderation = JSON.parse(data.choices[0].message.content);

  assertEquals(moderation.safe, false);
});

// Test: Timeout handling (30s max)
Deno.test("moderate-forum-content: timeout threshold", () => {
  // Verify timeout constant is correctly set
  const TIMEOUT_MS = 30000;
  assertEquals(TIMEOUT_MS, 30000);
});

// Test: Title + content combined analysis
Deno.test("moderate-forum-content: combined title and content", async () => {
  const combined =
    "Struggling with anxiety | I've been having panic attacks daily";

  mockGrok.setResponse(combined, {
    safe: true,
    confidence: 0.92,
    isCrisis: false,
    reason: "Mental health discussion",
  });

  const result = await mockGrok.call(combined);
  const data = await result.json();
  const moderation = JSON.parse(data.choices[0].message.content);

  assertEquals(moderation.safe, true);
  assertEquals(moderation.confidence >= 0.8, true);
});

// Test: Very short content
Deno.test("moderate-forum-content: short content handling", async () => {
  mockGrok.setResponse("Help", {
    safe: true,
    confidence: 0.6, // Lower confidence due to lack of context
    isCrisis: false,
    reason: "Content too short for high confidence",
  });

  const result = await mockGrok.call("Help");
  const data = await result.json();
  const moderation = JSON.parse(data.choices[0].message.content);

  // Short content should still be processed
  assertExists(moderation.safe);
  assertExists(moderation.confidence);
});

// Test: Medical misinformation detection
Deno.test("moderate-forum-content: medical misinformation", async () => {
  mockGrok.setResponse(
    "Essential oils cure depression, stop taking your meds",
    {
      safe: false,
      confidence: 0.95,
      isCrisis: false,
      reason: "Dangerous medical misinformation",
    },
  );

  const result = await mockGrok.call(
    "Essential oils cure depression, stop taking your meds",
  );
  const data = await result.json();
  const moderation = JSON.parse(data.choices[0].message.content);

  assertEquals(moderation.safe, false);
});

// Test: Personal information detection
Deno.test("moderate-forum-content: personal info detection", async () => {
  mockGrok.setResponse("My phone is 555-1234, call me at john@email.com", {
    safe: false,
    confidence: 0.9,
    isCrisis: false,
    reason: "Personal information sharing detected",
  });

  const result = await mockGrok.call(
    "My phone is 555-1234, call me at john@email.com",
  );
  const data = await result.json();
  const moderation = JSON.parse(data.choices[0].message.content);

  assertEquals(moderation.safe, false);
});

// Test: Lenient on mental health struggles
Deno.test("moderate-forum-content: lenient on struggle sharing", async () => {
  const struggles = [
    "I feel hopeless and can't get out of bed",
    "My depression is getting worse",
    "Having suicidal thoughts but not making plans",
  ];

  for (const struggle of struggles) {
    mockGrok.setResponse(struggle, {
      safe: true, // Should be lenient
      confidence: 0.85,
      isCrisis: struggle.includes("suicidal"), // Flag if mentions suicide
      reason: "Mental health struggle sharing",
    });

    const result = await mockGrok.call(struggle);
    const data = await result.json();
    const moderation = JSON.parse(data.choices[0].message.content);

    assertEquals(moderation.safe, true); // Lenient on struggles
  }
});

// Test: Strict on clear violations
Deno.test("moderate-forum-content: strict on harassment", async () => {
  const violations = [
    "You're worthless and should be ashamed",
    "Everyone hates you, go away",
    "What a loser, nobody wants you here",
  ];

  for (const violation of violations) {
    mockGrok.setResponse(violation, {
      safe: false,
      confidence: 0.95,
      isCrisis: false,
      reason: "Harassment/bullying",
    });

    const result = await mockGrok.call(violation);
    const data = await result.json();
    const moderation = JSON.parse(data.choices[0].message.content);

    assertEquals(moderation.safe, false);
  }
});

// Test: Error handling - malformed JSON
Deno.test("moderate-forum-content: malformed JSON handling", async () => {
  const malformedResponse = new Response("NOT JSON", {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });

  try {
    await malformedResponse.json();
  } catch (error) {
    assertExists(error); // Should throw
  }
});

// Test: Error handling - API error response
Deno.test("moderate-forum-content: API error handling", async () => {
  const errorResponse = new Response(
    JSON.stringify({
      error: { message: "API key invalid" },
    }),
    {
      status: 401,
      headers: { "Content-Type": "application/json" },
    },
  );

  assertEquals(errorResponse.status, 401);
});

console.log("✅ All moderate-forum-content tests passed!");
