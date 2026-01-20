-- SQL Tests for get_stress_signature() RPC Function
-- Run with: psql -f supabase/tests/get_stress_signature.test.sql

BEGIN;

-- Setup test environment
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgtap";

-- Test 1: Authorization check - rejects unauthorized user_id
SELECT plan(1);

-- Create test user
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000001'::uuid,
  'test1@example.com',
  crypt('password', gen_salt('bf')),
  NOW(),
  NOW(),
  NOW()
);

-- Set auth context to different user
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

-- Attempt to fetch signature for another user (should fail)
SELECT throws_ok(
  $$SELECT get_stress_signature('00000000-0000-0000-0000-000000000001'::uuid)$$,
  'Unauthorized: Cannot access patterns for other users'
);

SELECT * FROM finish();
ROLLBACK;

-- Test 2: Returns empty array for new users
BEGIN;
SELECT plan(3);

-- Create test user with no patterns
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000003'::uuid,
  'test3@example.com',
  crypt('password', gen_salt('bf')),
  NOW(),
  NOW(),
  NOW()
);

INSERT INTO profiles (id, username, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000003'::uuid,
  'test3',
  NOW(),
  NOW()
);

-- Set auth context
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

-- Fetch signature
SELECT results_eq(
  $$SELECT jsonb_typeof(get_stress_signature('00000000-0000-0000-0000-000000000003'::uuid))$$,
  $$VALUES ('object'::text)$$,
  'Returns JSONB object'
);

SELECT is(
  (get_stress_signature('00000000-0000-0000-0000-000000000003'::uuid)->>'userId'),
  '00000000-0000-0000-0000-000000000003',
  'Contains correct userId'
);

SELECT is(
  (get_stress_signature('00000000-0000-0000-0000-000000000003'::uuid)->'patterns')::text,
  '[]',
  'Returns empty patterns array for new user'
);

SELECT * FROM finish();
ROLLBACK;

-- Test 3: Filters low-confidence patterns (< 0.5)
BEGIN;
SELECT plan(1);

-- Create test user with patterns
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000004'::uuid,
  'test4@example.com',
  crypt('password', gen_salt('bf')),
  NOW(),
  NOW()
);

INSERT INTO profiles (id, username, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000004'::uuid,
  'test4',
  NOW(),
  NOW()
);

-- Insert low-confidence pattern (should be filtered)
INSERT INTO user_patterns (
  user_id, pattern_type, pattern_key, pattern_data,
  confidence, evidence_count, first_detected_at, is_active
) VALUES (
  '00000000-0000-0000-0000-000000000004'::uuid,
  'signature_stress_trigger',
  'work_stress',
  '{"category": "Work Stress", "frequency": 5, "timeline": []}'::jsonb,
  0.3,  -- Below 0.5 threshold
  10,
  NOW(),
  true
);

-- Insert high-confidence pattern (should be included)
INSERT INTO user_patterns (
  user_id, pattern_type, pattern_key, pattern_data,
  confidence, evidence_count, first_detected_at, is_active
) VALUES (
  '00000000-0000-0000-0000-000000000004'::uuid,
  'signature_coping_strategy',
  'meditation',
  '{"category": "Meditation", "frequency": 3, "timeline": []}'::jsonb,
  0.8,  -- Above 0.5 threshold
  8,
  NOW(),
  true
);

-- Set auth context
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';

-- Fetch signature and verify only high-confidence pattern included
SELECT is(
  jsonb_array_length(get_stress_signature('00000000-0000-0000-0000-000000000004'::uuid)->'patterns'),
  1,
  'Filters out low-confidence patterns (< 0.5)'
);

SELECT * FROM finish();
ROLLBACK;

-- Test 4: Returns correctly formatted JSONB
BEGIN;
SELECT plan(8);

-- Create test user with signature patterns
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000005'::uuid,
  'test5@example.com',
  crypt('password', gen_salt('bf')),
  NOW(),
  NOW()
);

INSERT INTO profiles (id, username, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000005'::uuid,
  'test5',
  NOW(),
  NOW()
);

INSERT INTO user_patterns (
  id, user_id, pattern_type, pattern_key, pattern_data,
  confidence, evidence_count, first_detected_at, last_confirmed_at, is_active
) VALUES (
  '00000000-0000-0000-0000-000000000010'::uuid,
  '00000000-0000-0000-0000-000000000005'::uuid,
  'signature_stress_trigger',
  'social_anxiety',
  '{"category": "Social Situations", "frequency": 4, "timeline": []}'::jsonb,
  0.75,
  12,
  NOW() - INTERVAL '30 days',
  NOW(),
  true
);

-- Set auth context
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000005';

-- Fetch signature
WITH result AS (
  SELECT get_stress_signature('00000000-0000-0000-0000-000000000005'::uuid) AS sig
)
SELECT
  ok((sig->>'userId')::uuid = '00000000-0000-0000-0000-000000000005'::uuid, 'Contains userId field'),
  ok(sig->>'generatedAt' IS NOT NULL, 'Contains generatedAt field'),
  ok(jsonb_typeof(sig->'patterns') = 'array', 'patterns is array'),
  ok(jsonb_array_length(sig->'patterns') = 1, 'Contains 1 pattern'),
  ok((sig->'patterns'->0->>'id')::uuid = '00000000-0000-0000-0000-000000000010'::uuid, 'Pattern has id'),
  ok((sig->'patterns'->0->>'category') = 'social_anxiety', 'Pattern has category'),
  ok((sig->'patterns'->0->>'confidenceScore')::float = 0.75, 'Pattern has confidenceScore'),
  ok((sig->'patterns'->0->>'evidenceCount')::int = 12, 'Pattern has evidenceCount')
FROM result;

SELECT * FROM finish();
ROLLBACK;

-- Test 5: Creates audit log entries
BEGIN;
SELECT plan(3);

-- Create test user
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000006'::uuid,
  'test6@example.com',
  crypt('password', gen_salt('bf')),
  NOW(),
  NOW()
);

INSERT INTO profiles (id, username, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000006'::uuid,
  'test6',
  NOW(),
  NOW()
);

INSERT INTO user_patterns (
  user_id, pattern_type, pattern_key, pattern_data,
  confidence, evidence_count, first_detected_at, is_active
) VALUES (
  '00000000-0000-0000-0000-000000000006'::uuid,
  'signature_stress_trigger',
  'work_stress',
  '{"category": "Work Stress", "frequency": 5, "timeline": []}'::jsonb,
  0.85,
  15,
  NOW(),
  true
);

-- Set auth context
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000006';

-- Count audit logs before
SELECT is(
  (SELECT COUNT(*) FROM pattern_access_audit WHERE user_id = '00000000-0000-0000-0000-000000000006'::uuid),
  0::bigint,
  'No audit logs before fetch'
);

-- Fetch signature (creates audit log)
PERFORM get_stress_signature('00000000-0000-0000-0000-000000000006'::uuid);

-- Verify audit log created
SELECT is(
  (SELECT COUNT(*) FROM pattern_access_audit WHERE user_id = '00000000-0000-0000-0000-000000000006'::uuid),
  1::bigint,
  'Audit log created after fetch'
);

SELECT is(
  (SELECT access_type FROM pattern_access_audit WHERE user_id = '00000000-0000-0000-0000-000000000006'::uuid),
  'signature_fetch',
  'Audit log has correct access_type'
);

SELECT * FROM finish();
ROLLBACK;

-- Test 6: Rate limiting works (10 requests/minute)
BEGIN;
SELECT plan(2);

-- Create test user
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000007'::uuid,
  'test7@example.com',
  crypt('password', gen_salt('bf')),
  NOW(),
  NOW()
);

INSERT INTO profiles (id, username, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000007'::uuid,
  'test7',
  NOW(),
  NOW()
);

-- Set auth context
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000007';

-- Make 10 requests (should succeed)
DO $$
DECLARE
  i INT;
BEGIN
  FOR i IN 1..10 LOOP
    PERFORM get_stress_signature('00000000-0000-0000-0000-000000000007'::uuid);
  END LOOP;
END $$;

SELECT is(
  (SELECT COUNT(*) FROM pattern_access_audit WHERE user_id = '00000000-0000-0000-0000-000000000007'::uuid),
  10::bigint,
  '10 requests succeeded'
);

-- 11th request should fail (rate limit exceeded)
SELECT throws_ok(
  $$SELECT get_stress_signature('00000000-0000-0000-0000-000000000007'::uuid)$$,
  'Rate limit exceeded: Maximum 10 requests per minute'
);

SELECT * FROM finish();
ROLLBACK;

-- Test 7: Filters inactive patterns
BEGIN;
SELECT plan(1);

-- Create test user
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000008'::uuid,
  'test8@example.com',
  crypt('password', gen_salt('bf')),
  NOW(),
  NOW()
);

INSERT INTO profiles (id, username, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000008'::uuid,
  'test8',
  NOW(),
  NOW()
);

-- Insert inactive pattern (should be filtered)
INSERT INTO user_patterns (
  user_id, pattern_type, pattern_key, pattern_data,
  confidence, evidence_count, first_detected_at, is_active
) VALUES (
  '00000000-0000-0000-0000-000000000008'::uuid,
  'signature_stress_trigger',
  'work_stress',
  '{"category": "Work Stress", "frequency": 5, "timeline": []}'::jsonb,
  0.9,
  20,
  NOW(),
  false  -- Inactive
);

-- Insert active pattern (should be included)
INSERT INTO user_patterns (
  user_id, pattern_type, pattern_key, pattern_data,
  confidence, evidence_count, first_detected_at, is_active
) VALUES (
  '00000000-0000-0000-0000-000000000008'::uuid,
  'signature_coping_strategy',
  'breathing_exercises',
  '{"category": "Breathing Techniques", "frequency": 3, "timeline": []}'::jsonb,
  0.7,
  10,
  NOW(),
  true  -- Active
);

-- Set auth context
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000008';

-- Fetch signature and verify only active pattern included
SELECT is(
  jsonb_array_length(get_stress_signature('00000000-0000-0000-0000-000000000008'::uuid)->'patterns'),
  1,
  'Filters out inactive patterns (is_active = false)'
);

SELECT * FROM finish();
ROLLBACK;
