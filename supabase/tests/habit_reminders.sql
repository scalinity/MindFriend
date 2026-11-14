-- Synthetic rollback fixture: a habit with a reminder saves and reads back the way released
-- clients send and decode it. PostgREST inserts JSON through json_populate_record, so this is
-- the same cast the app's request goes through.
BEGIN;

INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
SET LOCAL statement_timeout = '20s';
INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
 ('17300000-0000-4000-8000-000000000001', 'habits@example.invalid', '{}');
INSERT INTO public.profiles(id) VALUES ('17300000-0000-4000-8000-000000000001') ON CONFLICT(id) DO NOTHING;

-- The exact body 1.0.5 sends for "8:30 AM" picked on a phone in America/New_York.
INSERT INTO public.habits
SELECT * FROM json_populate_record(NULL::public.habits, '{
  "id": "17300000-0000-4000-8000-0000000000a1",
  "user_id": "17300000-0000-4000-8000-000000000001",
  "name": "Morning breath", "anchor": "pour my coffee", "behavior": "take three breaths",
  "category": "breathing", "difficulty": "easy", "duration_seconds": 30,
  "reminder_time": "2026-11-13T13:30:00.000", "reminder_minutes_before": 5,
  "is_active": true,
  "created_at": "2026-11-13T13:29:00.000", "updated_at": "2026-11-13T13:29:00.000"
}');

DO $$ DECLARE body text; local_time time; BEGIN
 SELECT to_json(reminder_time)::text, (reminder_time AT TIME ZONE 'America/New_York')::time
   INTO body, local_time
   FROM public.habits WHERE id = '17300000-0000-4000-8000-0000000000a1';
 -- What PostgREST returns, and what the app's ISO 8601 decoder reads back as the same instant.
 IF body <> '"2026-11-13T13:30:00+00:00"' THEN RAISE EXCEPTION 'Unexpected reminder body %', body; END IF;
 IF local_time <> '08:30' THEN RAISE EXCEPTION 'Expected 08:30 local, got %', local_time; END IF;
END $$;

-- Routines take the same payload.
INSERT INTO public.routines
SELECT * FROM json_populate_record(NULL::public.routines, '{
  "id": "17300000-0000-4000-8000-0000000000b1",
  "user_id": "17300000-0000-4000-8000-000000000001",
  "name": "Morning", "type": "morning", "target_time": "2026-11-13T12:00:00.000",
  "is_active": true,
  "created_at": "2026-11-13T11:59:00.000", "updated_at": "2026-11-13T11:59:00.000"
}');

ROLLBACK;
