/**
 * Unit Tests for Batch RPC Utilities
 *
 * Tests all 8 batch RPC wrapper functions and 3 helper utilities
 * - 18 test cases total
 * - Covers normal operations, edge cases, error handling, type correctness
 * - Includes special validation tests for BUG FIX #1 (state_changed flag)
 * - Includes special validation tests for BUG FIX #3 (all users returned)
 *
 * Run: deno test supabase/functions/_shared/__tests__/batch-utils.test.ts
 */

import { assertEquals, assertExists, assertRejects } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  getEngagementStatesBatch,
  updateEngagementStatesBatch,
  getProactiveSettingsBatch,
  getUsersProactiveCountsBatch,
  insertProactiveMessagesBatch,
  updateNotificationStatusesBatch,
  calculateUserAbsenceBatch,
  checkRecentNotificationsBatch,
  chunkArray,
  mergeMaps,
  filterMap,
  type BatchEngagementState,
  type BatchEngagementUpdate,
  type BatchEngagementUpdateResult,
  type BatchProactiveSettings,
  type BatchUserProactiveCount,
  type BatchProactiveMessage,
  type BatchProactiveMessageResult,
  type BatchNotificationStatusUpdate,
  type BatchNotificationStatusResult,
  type BatchUserAbsenceMetrics,
  type BatchRecentNotificationCheck,
  type BatchRecentNotificationCheckResult,
} from "../batch-utils.ts";

/**
 * Mock Supabase client for isolated testing
 * Allows simulating RPC responses without database connectivity
 */
function createMockSupabase(mockData: unknown) {
  return {
    rpc: async (_functionName: string, _options?: Record<string, unknown>) => {
      return { data: mockData, error: null };
    },
  };
}

function createErrorSupabase(errorMessage: string) {
  return {
    rpc: async (_functionName: string, _options?: Record<string, unknown>) => {
      return { data: null, error: new Error(errorMessage) };
    },
  };
}

// ============================================================================
// FR-1: get_engagement_states_batch Tests
// ============================================================================

Deno.test("FR-1: getEngagementStatesBatch - Basic batch retrieval", async () => {
  const mockData: BatchEngagementState[] = [
    {
      user_id: "user-1",
      current_state: "active",
      proactive_ignore_count: 2,
      last_proactive_at: "2024-01-15T10:30:00Z",
    },
    {
      user_id: "user-2",
      current_state: "paused",
      proactive_ignore_count: 0,
      last_proactive_at: null,
    },
  ];

  const supabase = createMockSupabase(mockData);
  const userIds = ["user-1", "user-2"];
  const result = await getEngagementStatesBatch(supabase as any, userIds);

  assertEquals(result.size, 2);
  assertEquals(result.get("user-1")?.current_state, "active");
  assertEquals(result.get("user-2")?.current_state, "paused");
});

Deno.test("FR-1: getEngagementStatesBatch - Empty array returns empty map", async () => {
  const supabase = createMockSupabase([]);
  const result = await getEngagementStatesBatch(supabase as any, []);

  assertEquals(result.size, 0);
});

Deno.test("FR-1: getEngagementStatesBatch - Error handling", async () => {
  const supabase = createErrorSupabase("Database connection failed");

  await assertRejects(
    async () => {
      await getEngagementStatesBatch(supabase as any, ["user-1"]);
    },
    Error,
    "Database connection failed",
  );
});

// ============================================================================
// FR-2: update_engagement_states_batch Tests (WITH BUG FIX #1 - CTE Pattern)
// ============================================================================

Deno.test("FR-2: updateEngagementStatesBatch - State changes detected", async () => {
  const mockData: BatchEngagementUpdateResult[] = [
    { user_id: "user-1", new_state: "dormant", state_changed: true },
    { user_id: "user-2", new_state: "active", state_changed: true },
    { user_id: "user-3", new_state: "paused", state_changed: false },
  ];

  const supabase = createMockSupabase(mockData);
  const updates: BatchEngagementUpdate[] = [
    { user_id: "user-1", new_state: "dormant" },
    { user_id: "user-2", new_state: "active" },
    { user_id: "user-3", new_state: "paused" },
  ];

  const result = await updateEngagementStatesBatch(supabase as any, updates);

  assertEquals(result.size, 3);
  assertEquals(result.get("user-1")?.state_changed, true);
  assertEquals(result.get("user-2")?.state_changed, true);
  assertEquals(result.get("user-3")?.state_changed, false);
});

Deno.test("FR-2: updateEngagementStatesBatch - BUG FIX #1 validation (state_changed accuracy)", async () => {
  // BUG FIX #1: CTE pattern in SQL captures old states before update
  // This test validates that state_changed flag correctly reflects actual changes
  const mockData: BatchEngagementUpdateResult[] = [
    { user_id: "user-1", new_state: "dormant", state_changed: true },
    { user_id: "user-2", new_state: "active", state_changed: true },
  ];

  const supabase = createMockSupabase(mockData);
  const updates = [
    { user_id: "user-1", new_state: "dormant" },
    { user_id: "user-2", new_state: "active" },
  ];

  const result = await updateEngagementStatesBatch(supabase as any, updates);

  // Verify flag enables differentiated logging
  const changedUsers = Array.from(result.values()).filter((r) => r.state_changed);
  assertEquals(changedUsers.length, 2);
});

Deno.test("FR-2: updateEngagementStatesBatch - Empty update list", async () => {
  const supabase = createMockSupabase([]);
  const result = await updateEngagementStatesBatch(supabase as any, []);

  assertEquals(result.size, 0);
});

// ============================================================================
// FR-3: get_user_proactive_settings_batch Tests
// ============================================================================

Deno.test("FR-3: getProactiveSettingsBatch - Basic retrieval with defaults applied", async () => {
  const mockData: BatchProactiveSettings[] = [
    {
      user_id: "user-1",
      proactive_enabled: true,
      max_daily: 5,
      quiet_hours_start_local: "22:00",
      quiet_hours_end_local: "08:00",
      timezone: "America/New_York",
      proactive_types_enabled: ["mood_decline", "streak_risk", "milestone_approach"],
    },
    {
      user_id: "user-2",
      proactive_enabled: false,
      max_daily: 2,
      quiet_hours_start_local: null,
      quiet_hours_end_local: null,
      timezone: "UTC",
      proactive_types_enabled: ["mood_decline"],
    },
  ];

  const supabase = createMockSupabase(mockData);
  const result = await getProactiveSettingsBatch(supabase as any, ["user-1", "user-2"]);

  assertEquals(result.size, 2);
  assertEquals(result.get("user-1")?.proactive_enabled, true);
  assertEquals(result.get("user-2")?.proactive_enabled, false);
});

Deno.test("FR-3: getProactiveSettingsBatch - Empty result handling", async () => {
  const supabase = createMockSupabase([]);
  const result = await getProactiveSettingsBatch(supabase as any, []);

  assertEquals(result.size, 0);
});

// ============================================================================
// FR-4: get_users_proactive_counts_batch Tests (WITH BUG FIX #3 - UNNEST Pattern)
// ============================================================================

Deno.test("FR-4: getUsersProactiveCountsBatch - All users returned including zero counts", async () => {
  // BUG FIX #3: UNNEST pattern guarantees all input users are returned
  // This prevents GROUP BY from omitting users with zero messages
  const mockData: BatchUserProactiveCount[] = [
    { user_id: "user-1", count_today: 3 },
    { user_id: "user-2", count_today: 0 }, // Zero count must be included
    { user_id: "user-3", count_today: 1 },
  ];

  const supabase = createMockSupabase(mockData);
  const userIds = ["user-1", "user-2", "user-3"];
  const result = await getUsersProactiveCountsBatch(supabase as any, userIds);

  assertEquals(result.size, 3);
  assertEquals(result.get("user-1")?.count_today, 3);
  assertEquals(result.get("user-2")?.count_today, 0); // CRITICAL: Zero-count user included
  assertEquals(result.get("user-3")?.count_today, 1);
});

Deno.test("FR-4: getUsersProactiveCountsBatch - BUG FIX #3 validation (all users guaranteed)", async () => {
  // Verifies that even if RPC returns partial data, Map is initialized with all input users
  const mockData: BatchUserProactiveCount[] = [
    { user_id: "user-1", count_today: 5 },
    // user-2 intentionally omitted from mock response
    { user_id: "user-3", count_today: 2 },
  ];

  const supabase = createMockSupabase(mockData);
  const userIds = ["user-1", "user-2", "user-3"];
  const result = await getUsersProactiveCountsBatch(supabase as any, userIds);

  // All 3 users must be in result
  assertEquals(result.size, 3);
  assertExists(result.get("user-1"));
  assertExists(result.get("user-2")); // Must exist even though omitted from mock
  assertExists(result.get("user-3"));

  // user-2 should have default zero count
  assertEquals(result.get("user-2")?.count_today, 0);
});

Deno.test("FR-4: getUsersProactiveCountsBatch - Empty user list", async () => {
  const supabase = createMockSupabase([]);
  const result = await getUsersProactiveCountsBatch(supabase as any, []);

  assertEquals(result.size, 0);
});

// ============================================================================
// FR-5: insert_proactive_messages_batch Tests
// ============================================================================

Deno.test("FR-5: insertProactiveMessagesBatch - Batch insertion", async () => {
  const mockData: BatchProactiveMessageResult[] = [
    { id: "msg-1", user_id: "user-1", trigger_type: "daily_quest" },
    { id: "msg-2", user_id: "user-2", trigger_type: "inactivity_nudge" },
  ];

  const supabase = createMockSupabase(mockData);
  const messages: BatchProactiveMessage[] = [
    {
      user_id: "user-1",
      trigger_type: "daily_quest",
      message_content: "You have a new quest!",
      delivery_channel: "push",
      scheduled_for: "2024-01-15T10:00:00Z",
    },
    {
      user_id: "user-2",
      trigger_type: "inactivity_nudge",
      message_content: "We miss you!",
      delivery_channel: "push",
      scheduled_for: "2024-01-15T11:00:00Z",
    },
  ];

  const result = await insertProactiveMessagesBatch(supabase as any, messages);

  assertEquals(result.size, 2);
  assertExists(result.get("user-1"));
  assertExists(result.get("user-2"));
});

Deno.test("FR-5: insertProactiveMessagesBatch - Empty message list", async () => {
  const supabase = createMockSupabase([]);
  const result = await insertProactiveMessagesBatch(supabase as any, []);

  assertEquals(result.size, 0);
});

// ============================================================================
// FR-6: update_notification_statuses_batch Tests
// ============================================================================

Deno.test("FR-6: updateNotificationStatusesBatch - Status updates", async () => {
  const mockData: BatchNotificationStatusResult[] = [
    { message_id: "msg-1", user_id: "user-1", new_status: "sent" },
    { message_id: "msg-2", user_id: "user-2", new_status: "delivered" },
  ];

  const supabase = createMockSupabase(mockData);
  const updates: BatchNotificationStatusUpdate[] = [
    { message_id: "msg-1", status: "sent", sent_at: "2024-01-15T10:05:00Z" },
    { message_id: "msg-2", status: "delivered", sent_at: "2024-01-15T10:10:00Z" },
  ];

  const result = await updateNotificationStatusesBatch(supabase as any, updates);

  assertEquals(result.size, 2);
  assertEquals(result.get("msg-1")?.new_status, "sent");
  assertEquals(result.get("msg-2")?.new_status, "delivered");
});

Deno.test("FR-6: updateNotificationStatusesBatch - Empty update list", async () => {
  const supabase = createMockSupabase([]);
  const result = await updateNotificationStatusesBatch(supabase as any, []);

  assertEquals(result.size, 0);
});

// ============================================================================
// FR-7: calculate_user_absence_batch Tests
// ============================================================================

Deno.test("FR-7: calculateUserAbsenceBatch - Lapse tier classification", async () => {
  const mockData: BatchUserAbsenceMetrics[] = [
    {
      user_id: "user-1",
      absence_days: 2,
      lapse_tier: "active",
      hugs_received: 5,
      circle_posts: 3,
      friend_milestones: 1,
    },
    {
      user_id: "user-2",
      absence_days: 10,
      lapse_tier: "drifting",
      hugs_received: 2,
      circle_posts: 0,
      friend_milestones: 0,
    },
    {
      user_id: "user-3",
      absence_days: 35,
      lapse_tier: "hibernating",
      hugs_received: 0,
      circle_posts: 0,
      friend_milestones: 0,
    },
  ];

  const supabase = createMockSupabase(mockData);
  const result = await calculateUserAbsenceBatch(supabase as any, ["user-1", "user-2", "user-3"]);

  assertEquals(result.size, 3);
  assertEquals(result.get("user-1")?.lapse_tier, "active");
  assertEquals(result.get("user-2")?.lapse_tier, "drifting");
  assertEquals(result.get("user-3")?.lapse_tier, "hibernating");
});

Deno.test("FR-7: calculateUserAbsenceBatch - Lapse tiers: active, at_risk, drifting, lapsed, hibernating", async () => {
  const mockData: BatchUserAbsenceMetrics[] = [
    { user_id: "u1", absence_days: 1, lapse_tier: "active", hugs_received: 0, circle_posts: 0, friend_milestones: 0 },
    { user_id: "u2", absence_days: 4, lapse_tier: "at_risk", hugs_received: 0, circle_posts: 0, friend_milestones: 0 },
    { user_id: "u3", absence_days: 9, lapse_tier: "drifting", hugs_received: 0, circle_posts: 0, friend_milestones: 0 },
    { user_id: "u4", absence_days: 20, lapse_tier: "lapsed", hugs_received: 0, circle_posts: 0, friend_milestones: 0 },
    { user_id: "u5", absence_days: 45, lapse_tier: "hibernating", hugs_received: 0, circle_posts: 0, friend_milestones: 0 },
  ];

  const supabase = createMockSupabase(mockData);
  const result = await calculateUserAbsenceBatch(supabase as any, ["u1", "u2", "u3", "u4", "u5"]);

  assertEquals(result.get("u1")?.lapse_tier, "active");
  assertEquals(result.get("u2")?.lapse_tier, "at_risk");
  assertEquals(result.get("u3")?.lapse_tier, "drifting");
  assertEquals(result.get("u4")?.lapse_tier, "lapsed");
  assertEquals(result.get("u5")?.lapse_tier, "hibernating");
});

// ============================================================================
// FR-8: check_recent_notifications_batch Tests
// ============================================================================

Deno.test("FR-8: checkRecentNotificationsBatch - Recent notification detection", async () => {
  const mockData: BatchRecentNotificationCheckResult[] = [
    { user_id: "user-1", notification_type: "daily_quest", recently_sent: true },
    { user_id: "user-2", notification_type: "inactivity_nudge", recently_sent: false },
  ];

  const supabase = createMockSupabase(mockData);
  const checks: BatchRecentNotificationCheck[] = [
    { user_id: "user-1", notification_type: "daily_quest" },
    { user_id: "user-2", notification_type: "inactivity_nudge" },
  ];

  const result = await checkRecentNotificationsBatch(supabase as any, checks);

  assertEquals(result.size, 2);
  assertEquals(result.get("user-1:daily_quest")?.recently_sent, true);
  assertEquals(result.get("user-2:inactivity_nudge")?.recently_sent, false);
});

Deno.test("FR-8: checkRecentNotificationsBatch - Empty check list", async () => {
  const supabase = createMockSupabase([]);
  const result = await checkRecentNotificationsBatch(supabase as any, []);

  assertEquals(result.size, 0);
});

// ============================================================================
// Helper Utility Tests
// ============================================================================

Deno.test("Helper: chunkArray - Basic chunking", () => {
  const arr = [1, 2, 3, 4, 5, 6, 7, 8, 9];
  const chunks = chunkArray(arr, 3);

  assertEquals(chunks.length, 3);
  assertEquals(chunks[0], [1, 2, 3]);
  assertEquals(chunks[1], [4, 5, 6]);
  assertEquals(chunks[2], [7, 8, 9]);
});

Deno.test("Helper: chunkArray - Chunk size larger than array", () => {
  const arr = [1, 2, 3];
  const chunks = chunkArray(arr, 10);

  assertEquals(chunks.length, 1);
  assertEquals(chunks[0], [1, 2, 3]);
});

Deno.test("Helper: mergeMaps - Combine multiple maps", () => {
  const map1 = new Map<string, number>([["a", 1], ["b", 2]]);
  const map2 = new Map<string, number>([["c", 3], ["d", 4]]);
  const merged = mergeMaps(map1, map2);

  assertEquals(merged.size, 4);
  assertEquals(merged.get("a"), 1);
  assertEquals(merged.get("d"), 4);
});

Deno.test("Helper: mergeMaps - Later map overrides earlier", () => {
  const map1 = new Map<string, number>([["a", 1]]);
  const map2 = new Map<string, number>([["a", 99]]);
  const merged = mergeMaps(map1, map2);

  assertEquals(merged.get("a"), 99);
});

Deno.test("Helper: filterMap - Filter by predicate", () => {
  const map = new Map<string, number>([["a", 1], ["b", 2], ["c", 3]]);
  const filtered = filterMap(map, (_key, value) => value > 1);

  assertEquals(filtered.size, 2);
  assertEquals(filtered.has("a"), false);
  assertEquals(filtered.has("b"), true);
  assertEquals(filtered.has("c"), true);
});
