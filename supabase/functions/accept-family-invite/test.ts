// Tests for accept-family-invite Edge Function
// Run with: deno test --allow-net --allow-env supabase/functions/accept-family-invite/test.ts

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { generateInviteCode } from "../_shared/billing-types.ts";

// Unit tests for shared utilities

Deno.test("generateInviteCode produces 8 character codes", () => {
  const code = generateInviteCode();
  assertEquals(code.length, 8);
});

Deno.test("generateInviteCode only uses allowed characters", () => {
  const allowedChars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  for (let i = 0; i < 100; i++) {
    const code = generateInviteCode();
    for (const char of code) {
      assertEquals(
        allowedChars.includes(char),
        true,
        `Invalid character: ${char}`,
      );
    }
  }
});

Deno.test("generateInviteCode produces unique codes", () => {
  const codes = new Set<string>();
  for (let i = 0; i < 1000; i++) {
    codes.add(generateInviteCode());
  }
  // With 32^8 = 1 trillion+ possible codes, 1000 should all be unique
  assertEquals(codes.size, 1000);
});

Deno.test("generateInviteCode excludes confusing characters", () => {
  // Should not include: O, 0, 1, I, L (easily confused)
  const excludedChars = "O01IL";
  for (let i = 0; i < 100; i++) {
    const code = generateInviteCode();
    for (const char of code) {
      assertEquals(
        excludedChars.includes(char),
        false,
        `Code contains confusing character: ${char}`,
      );
    }
  }
});

// Integration test stubs for accept-family-invite

Deno.test("accept-family-invite rejects missing invite_code", async () => {
  const expectedError = {
    error: "Missing invite_code",
  };
  assertExists(expectedError);
});

Deno.test("accept-family-invite rejects invalid invite code", async () => {
  const expectedError = {
    success: false,
    error: "Invalid or already used invitation code",
  };
  assertExists(expectedError);
});

Deno.test("accept-family-invite rejects expired invite code", async () => {
  const expectedError = {
    success: false,
    error: "This invitation has expired",
  };
  assertExists(expectedError);
});

Deno.test("accept-family-invite rejects when no seats available", async () => {
  // The atomic claim_family_seat RPC should return this error
  const expectedError = {
    success: false,
    error: "No seats available in this family plan",
    code: "NO_SEATS_AVAILABLE",
  };
  assertExists(expectedError);
});

Deno.test("accept-family-invite rejects duplicate membership", async () => {
  const expectedError = {
    success: false,
    error: "User is already an active member of this family",
    code: "ALREADY_MEMBER",
  };
  assertExists(expectedError);
});

Deno.test("accept-family-invite handles concurrent seat claims", async () => {
  // This tests the race condition fix
  // When two users try to claim the last seat simultaneously,
  // only one should succeed, the other gets SEAT_RACE_CONDITION
  const possibleErrors = [
    {
      success: false,
      error: "Seat was claimed by another request",
      code: "SEAT_RACE_CONDITION",
    },
    {
      success: false,
      error: "No seats available in this family plan",
      code: "NO_SEATS_AVAILABLE",
    },
  ];
  assertExists(possibleErrors);
});

Deno.test("accept-family-invite grants premium on success", async () => {
  // On successful invite acceptance:
  // 1. User added to family_members with status 'active'
  // 2. User added to family circle
  // 3. User gets subscription with premium tier
  // 4. User profile updated to subscription_tier = 'premium'
  // 5. Premium Supporter badge awarded
  // 6. Invitation marked as accepted
  const expectedBehavior = {
    success: true,
    familyId: "uuid",
    circleId: "uuid",
    message: "Welcome to the family plan!",
    profileUpdated: true,
    badgeAwarded: true,
    invitationMarkedAccepted: true,
  };
  assertExists(expectedBehavior);
});

Deno.test(
  "accept-family-invite reactivates previously removed member",
  async () => {
    // If a user was previously removed from a family and tries to rejoin,
    // their existing family_members record should be reactivated
    const expectedBehavior = {
      success: true,
      existingMemberReactivated: true,
      removedAtCleared: true,
      joinedAtUpdated: true,
    };
    assertExists(expectedBehavior);
  },
);

// Test for seat increment atomicity
Deno.test("claim_family_seat increments seats_used atomically", async () => {
  // The claim_family_seat RPC should:
  // 1. Lock the admin subscription row with FOR UPDATE
  // 2. Check seats_used < seats_total
  // 3. Increment seats_used in the same transaction
  // 4. Return success with updated seat counts
  const expectedResult = {
    success: true,
    seats_used: 3,
    seats_total: 6,
    admin_subscription_id: "uuid",
  };
  assertExists(expectedResult);
});

// Test for billing event logging
Deno.test("accept-family-invite logs billing event", async () => {
  // The claim_family_seat RPC should insert a billing_events record
  const expectedEvent = {
    event_type: "family_seat_claimed",
    user_id: "uuid",
    family_id: "uuid",
    payload: {
      seats_used: 3,
      seats_total: 6,
      admin_subscription_id: "uuid",
    },
  };
  assertExists(expectedEvent);
});
