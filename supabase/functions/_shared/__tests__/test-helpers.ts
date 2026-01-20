/**
 * Test helpers for ritual Edge Functions
 */

import { isValidUUID } from "./ritual-validation.ts";

/**
 * Create a valid UUID for testing
 */
export function createTestUUID(): string {
  return "550e8400-e29b-41d4-a716-446655440000";
}

/**
 * Create a mock user ID for testing
 */
export function createTestUserId(): string {
  return "660e8400-e29b-41d4-a716-446655440001";
}

/**
 * Create a future date string
 */
export function futureDate(minutesFromNow: number): string {
  return new Date(Date.now() + minutesFromNow * 60000).toISOString();
}

/**
 * Create a past date string
 */
export function pastDate(minutesAgo: number): string {
  return new Date(Date.now() - minutesAgo * 60000).toISOString();
}

/**
 * Create a mock CreateRitualInput
 */
export function createRitualInput(
  overrides: Partial<{
    circleId: string;
    title: string;
    ritualType: string;
    startOption: "now" | "scheduled";
    scheduledFor?: string;
  }> = {},
): {
  circleId: string;
  title: string;
  ritualType: string;
  startOption: "now" | "scheduled";
  scheduledFor?: string;
} {
  return {
    circleId: createTestUUID(),
    title: "Test Ritual",
    ritualType: "gratitude",
    startOption: "now",
    scheduledFor: undefined,
    ...overrides,
  };
}

/**
 * Check if a value is a valid UUID
 */
export function isValidTestUUID(value: string): boolean {
  return isValidUUID(value);
}

/**
 * Create mock circle members response
 */
export function createMockMembers(count: number): Array<{
  user_id: string;
  profiles: { id: string; display_name: string };
}> {
  const members = [];
  for (let i = 0; i < count; i++) {
    const uuid = `770e8400-e29b-41d4-a716-44665544000${i + 2}`;
    members.push({
      user_id: uuid,
      profiles: {
        id: uuid,
        display_name: `Test User ${i + 1}`,
      },
    });
  }
  return members;
}

/**
 * Create mock ritual data
 */
export function createMockRitual(
  overrides: Partial<{
    id: string;
    circle_id: string;
    created_by: string;
    title: string;
    ritual_type: string;
    scheduled_for: string;
    duration_seconds: number;
    status: string;
  }> = {},
): Record<string, unknown> {
  return {
    id: createTestUUID(),
    circle_id: createTestUUID(),
    created_by: createTestUserId(),
    title: "Test Ritual",
    ritual_type: "gratitude",
    scheduled_for: new Date().toISOString(),
    duration_seconds: 180,
    status: "active",
    ...overrides,
  };
}

/**
 * Create mock attendee data
 */
export function createMockAttendee(
  overrides: Partial<{
    id: string;
    ritual_id: string;
    user_id: string;
    joined_at: string;
  }> = {},
): Record<string, unknown> {
  return {
    id: createTestUUID(),
    ritual_id: createTestUUID(),
    user_id: createTestUserId(),
    joined_at: new Date().toISOString(),
    left_at: null,
    ...overrides,
  };
}
