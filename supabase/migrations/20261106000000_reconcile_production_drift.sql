-- Reconcile production with the repository's migration history.
--
-- Production's ledger records every migration through 20261105210400, but a schema-only
-- dump taken on 8 November 2026 shows that several January migrations never took effect
-- there (20260122235900/20260123000000 wellness score, 20260123001600 predictive mood
-- intelligence, 20260124150000 mentorship security fixes, 20260127100000 progressive
-- disclosure, and others). Pending migrations depend on those objects: for example,
-- 20261106230635 installs a trigger that calls public.encrypt_message_content(), which
-- production does not have, so every mentorship message insert would fail.
--
-- This migration is generated from the fresh migration chain's catalog at version
-- 20261105210400 and recreates exactly what production lacks. Every statement is guarded
-- or idempotent: on a fresh chain it changes nothing; on production it fills the gaps.
-- It sorts before the other pending migrations so they apply on top of the reconciled
-- schema, the same way they apply on a fresh chain.
--
-- Not included, deliberately:
--   * Objects production has that the repository does not (columns and functions from the
--     disabled encrypt_mood_journal_data and pathway migrations). They are left in place.
--   * Storage policies. They stay with the separate private-media operation (issue #57).
--   * submit_pathway_checkin: production's body differs but the function is service-role
--     only and its behavior is unchanged here.
--   * calculate_timezone_overlap: handled in 20261106225731 with production's parameter names.

-- 1. Columns the fresh chain has and production lacks.
ALTER TABLE public.daily_signals ADD COLUMN IF NOT EXISTS wellness_calculated_at timestamp with time zone;
ALTER TABLE public.daily_signals ADD COLUMN IF NOT EXISTS wellness_components jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.daily_signals ADD COLUMN IF NOT EXISTS wellness_confidence integer;
ALTER TABLE public.daily_signals ADD COLUMN IF NOT EXISTS wellness_score integer;
ALTER TABLE public.mentorship_messages ADD COLUMN IF NOT EXISTS encrypted_content bytea;
ALTER TABLE public.mentorship_messages ADD COLUMN IF NOT EXISTS encryption_key_id text;
ALTER TABLE public.mentorship_messages ADD COLUMN IF NOT EXISTS iv bytea;

-- 2. Tables the fresh chain has and production lacks.
CREATE TABLE IF NOT EXISTS public.prediction_models (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    model_version character varying(32) NOT NULL,
    feature_weights jsonb DEFAULT '{"day_of_week": 0.10, "mood_avg_7d": 0.30, "sleep_hours": 0.25, "mood_trend_7d": 0.15, "steps_yesterday": 0.15, "exercise_minutes": 0.05}'::jsonb NOT NULL,
    accuracy_score numeric(3,2),
    predictions_count integer DEFAULT 0 NOT NULL,
    last_trained_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.prediction_models'::regclass AND conname = 'prediction_models_pkey') THEN ALTER TABLE public.prediction_models ADD CONSTRAINT prediction_models_pkey PRIMARY KEY (id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.prediction_models'::regclass AND conname = 'prediction_models_user_id_fkey') THEN ALTER TABLE public.prediction_models ADD CONSTRAINT prediction_models_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.prediction_models'::regclass AND conname = 'prediction_models_accuracy_score_check') THEN ALTER TABLE public.prediction_models ADD CONSTRAINT prediction_models_accuracy_score_check CHECK (((accuracy_score IS NULL) OR ((accuracy_score >= (0)::numeric) AND (accuracy_score <= (1)::numeric)))); END IF; END $$;
ALTER TABLE public.prediction_models ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.prediction_models FROM PUBLIC, anon, authenticated, service_role;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.prediction_models TO anon;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.prediction_models TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.prediction_models TO service_role;

-- 3. Functions the fresh chain has and production lacks.
CREATE OR REPLACE FUNCTION public.cleanup_old_capacity()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    -- SECURITY: Only allow service_role to execute (for pg_cron)
    IF NOT (auth.jwt()->>'role' = 'service_role') THEN
        RAISE EXCEPTION 'Unauthorized: This function is for automated maintenance only';
    END IF;

    DELETE FROM user_capacity
    WHERE calculated_at < now() - INTERVAL '30 days';
END;
$function$;
REVOKE ALL ON FUNCTION public.cleanup_old_capacity() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_old_capacity() TO service_role;
CREATE OR REPLACE FUNCTION public.decrypt_message_content(p_encrypted bytea, p_key_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_key TEXT;
    v_decrypted bytea;
BEGIN
    SELECT encode(key_material, 'hex') INTO v_key
    FROM mentorship_encryption_keys
    WHERE id = p_key_id AND revoked_at IS NULL;
    
    IF v_key IS NULL THEN
        RAISE EXCEPTION 'Encryption key not found or revoked: %', p_key_id;
    END IF;
    
    -- pgp_sym_decrypt automatically verifies HMAC - errors if authentication fails
    v_decrypted := pgp_sym_decrypt(p_encrypted, v_key)::bytea;
    
    RETURN convert_from(v_decrypted, 'utf8');
END;
$function$;
REVOKE ALL ON FUNCTION public.decrypt_message_content(bytea,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.decrypt_message_content(bytea,text) TO service_role;
CREATE OR REPLACE FUNCTION public.decrypt_messages_batch(p_message_ids uuid[])
 RETURNS TABLE(message_id uuid, decryption_success boolean, decrypted_content text, error_message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_msg_id UUID;
    v_encrypted bytea;
    v_key_id TEXT;
    v_decrypted TEXT;
    v_error TEXT;
BEGIN
    FOREACH v_msg_id IN ARRAY p_message_ids
    LOOP
        BEGIN
            -- Fetch encrypted content and key for this message
            SELECT m.encrypted_content, m.encryption_key_id
            INTO v_encrypted, v_key_id
            FROM mentorship_messages m
            WHERE m.id = v_msg_id
            AND EXISTS (
                -- Verify user has access via RLS
                SELECT 1 FROM mentorship_matches
                WHERE id = m.match_id
                AND (mentor_id = auth.uid() OR mentee_id = auth.uid())
            );

            IF v_encrypted IS NULL THEN
                -- Message not found or access denied
                RETURN QUERY SELECT v_msg_id, false, NULL::TEXT, 'Message not found or access denied'::TEXT;
            ELSE
                -- Decrypt the content
                v_decrypted := decrypt_message_content(v_encrypted, v_key_id);
                RETURN QUERY SELECT v_msg_id, true, v_decrypted, NULL::TEXT;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Decryption failed - return generic error without exposing internal details
            v_error := CASE 
                WHEN SQLERRM LIKE '%encryption%' THEN 'Encryption key unavailable'
                WHEN SQLERRM LIKE '%access%' THEN 'Access denied'
                ELSE 'Decryption failed'
            END;
            RETURN QUERY SELECT v_msg_id, false, NULL::TEXT, v_error::TEXT;
        END;
    END LOOP;
END;
$function$;
REVOKE ALL ON FUNCTION public.decrypt_messages_batch(uuid[]) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.decrypt_messages_batch(uuid[]) TO service_role;
CREATE OR REPLACE FUNCTION public.delete_mentorship_message(p_message_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_affected_rows INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Delete message only if user is the sender
    DELETE FROM mentorship_messages
    WHERE id = p_message_id
    AND sender_id = v_user_id;

    GET DIAGNOSTICS v_affected_rows = ROW_COUNT;

    IF v_affected_rows = 0 THEN
        RAISE EXCEPTION 'Message not found or you do not have permission to delete it';
    END IF;

    RETURN true;
END;
$function$;
REVOKE ALL ON FUNCTION public.delete_mentorship_message(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_mentorship_message(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_mentorship_message(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.delete_mentorship_message(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_mentorship_message(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.encrypt_message_content(p_content text)
 RETURNS TABLE(v_key_id text, v_encrypted text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_key_id TEXT;
    v_key TEXT;
    v_encrypted bytea;
BEGIN
    v_key_id := get_active_encryption_key();
    
    SELECT encode(key_material, 'hex') INTO v_key
    FROM mentorship_encryption_keys
    WHERE id = v_key_id;
    
    -- Encrypt using pgp_sym_encrypt: provides AES-256 + HMAC-SHA512 authentication
    v_encrypted := pgp_sym_encrypt(
        p_content,
        v_key,
        'cipher-algo=aes256'
    );
    
    -- Return base64-encoded bytea for JSON-safe transmission to iOS client
    RETURN QUERY SELECT v_key_id, encode(v_encrypted, 'base64');
END;
$function$;
REVOKE ALL ON FUNCTION public.encrypt_message_content(text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.encrypt_message_content(text) TO service_role;
-- sanitize_mentorship_message() runs as the inserting user and encrypts each new message.
GRANT EXECUTE ON FUNCTION public.encrypt_message_content(text) TO authenticated;
CREATE OR REPLACE FUNCTION public.flag_mentorship_message(p_message_id uuid, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_match_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) = 0 THEN
        RAISE EXCEPTION 'Reason is required';
    END IF;

    -- Get match_id to verify user is participant
    SELECT match_id INTO v_match_id
    FROM mentorship_messages
    WHERE id = p_message_id;

    IF v_match_id IS NULL THEN
        RAISE EXCEPTION 'Message not found';
    END IF;

    -- Verify user is a participant
    IF NOT EXISTS (
        SELECT 1 FROM mentorship_matches
        WHERE id = v_match_id
        AND (mentor_id = v_user_id OR mentee_id = v_user_id)
    ) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    -- Flag the message
    UPDATE mentorship_messages
    SET flagged = true,
        flag_reason = p_reason,
        reviewed = false
    WHERE id = p_message_id;

    RETURN true;
END;
$function$;
REVOKE ALL ON FUNCTION public.flag_mentorship_message(uuid,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.flag_mentorship_message(uuid,text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.flag_mentorship_message(uuid,text) TO anon;
GRANT EXECUTE ON FUNCTION public.flag_mentorship_message(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.flag_mentorship_message(uuid,text) TO service_role;
CREATE OR REPLACE FUNCTION public.get_prediction_eligible_users(p_target_hour integer DEFAULT 6, p_hour_window integer DEFAULT 2)
 RETURNS TABLE(user_id uuid, timezone text, mood_count bigint, last_mood_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        m.user_id,
        COALESCE(us.timezone, 'UTC') as timezone,
        COUNT(m.id) as mood_count,
        MAX(m.created_at) as last_mood_at
    FROM moods m
    LEFT JOIN user_settings us ON us.user_id = m.user_id
    WHERE m.created_at >= NOW() - INTERVAL '90 days'
    GROUP BY m.user_id, us.timezone
    HAVING COUNT(m.id) >= 14
    -- Filter by local time (users whose local hour is within target window)
    AND EXTRACT(HOUR FROM NOW() AT TIME ZONE COALESCE(us.timezone, 'UTC'))
        BETWEEN p_target_hour AND p_target_hour + p_hour_window;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_prediction_eligible_users(integer,integer) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_prediction_eligible_users(integer,integer) TO service_role;
CREATE OR REPLACE FUNCTION public.get_prediction_features(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_features JSONB := '{}'::jsonb;
    v_mood_avg_7d DECIMAL;
    v_mood_avg_14d DECIMAL;
    v_mood_trend_7d DECIMAL;
    v_prev_mood INT;
    v_sleep_hours DECIMAL;
    v_steps_yesterday INT;
    v_exercise_minutes INT;
    v_day_of_week INT;
    v_hour_of_day INT;
    v_streak_days INT;
    v_timezone TEXT;
BEGIN
    -- Get user timezone
    SELECT COALESCE(timezone, 'UTC') INTO v_timezone
    FROM user_settings
    WHERE user_settings.user_id = p_user_id;

    -- 7-day mood average (moods are 1-5, we'll normalize later)
    SELECT AVG(mood_score) INTO v_mood_avg_7d
    FROM moods
    WHERE moods.user_id = p_user_id
    AND created_at >= NOW() - INTERVAL '7 days';

    -- 14-day mood average
    SELECT AVG(mood_score) INTO v_mood_avg_14d
    FROM moods
    WHERE moods.user_id = p_user_id
    AND created_at >= NOW() - INTERVAL '14 days';

    -- Mood trend (7-day slope using linear regression)
    SELECT
        COALESCE(
            regr_slope(
                mood_score::float,
                EXTRACT(EPOCH FROM created_at)::float
            ) * 86400 * 7, -- Scale to weekly change
            0
        ) INTO v_mood_trend_7d
    FROM moods
    WHERE moods.user_id = p_user_id
    AND created_at >= NOW() - INTERVAL '7 days';

    -- Previous mood (yesterday or most recent)
    SELECT mood_score INTO v_prev_mood
    FROM moods
    WHERE moods.user_id = p_user_id
    ORDER BY created_at DESC
    LIMIT 1;

    -- Sleep hours from biometric_daily_summaries (if available)
    SELECT sleep_duration_minutes / 60.0 INTO v_sleep_hours
    FROM biometric_daily_summaries
    WHERE biometric_daily_summaries.user_id = p_user_id
    AND date = ((NOW() AT TIME ZONE v_timezone) - INTERVAL '1 day')::date
    LIMIT 1;

    -- Steps yesterday from biometric_daily_summaries (if available)
    SELECT steps_count INTO v_steps_yesterday
    FROM biometric_daily_summaries
    WHERE biometric_daily_summaries.user_id = p_user_id
    AND date = ((NOW() AT TIME ZONE v_timezone) - INTERVAL '1 day')::date
    LIMIT 1;

    -- Exercise minutes in last 7 days
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (completed_at - started_at)) / 60), 0)::int INTO v_exercise_minutes
    FROM exercise_sessions
    WHERE exercise_sessions.user_id = p_user_id
    AND completed_at >= NOW() - INTERVAL '7 days';

    -- Day of week (0 = Sunday, 6 = Saturday)
    SELECT EXTRACT(DOW FROM NOW() AT TIME ZONE v_timezone)::int INTO v_day_of_week;

    -- Hour of day
    SELECT EXTRACT(HOUR FROM NOW() AT TIME ZONE v_timezone)::int INTO v_hour_of_day;

    -- Get streak from profiles
    SELECT COALESCE(current_streak_days, 0) INTO v_streak_days
    FROM profiles
    WHERE profiles.id = p_user_id;

    -- Build features JSON
    v_features := jsonb_build_object(
        'mood_avg_7d', COALESCE(v_mood_avg_7d, 3),
        'mood_avg_14d', COALESCE(v_mood_avg_14d, 3),
        'mood_trend_7d', COALESCE(v_mood_trend_7d, 0),
        'previous_mood', COALESCE(v_prev_mood, 3),
        'sleep_hours', v_sleep_hours,
        'steps_yesterday', v_steps_yesterday,
        'exercise_minutes_7d', COALESCE(v_exercise_minutes, 0),
        'day_of_week', v_day_of_week,
        'hour_of_day', v_hour_of_day,
        'streak_days', COALESCE(v_streak_days, 0),
        'has_sleep_data', v_sleep_hours IS NOT NULL,
        'has_steps_data', v_steps_yesterday IS NOT NULL,
        'timezone', v_timezone
    );

    RETURN v_features;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_prediction_features(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_prediction_features(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.mark_messages_read(p_match_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Update messages where current user is a participant in the match
    UPDATE mentorship_messages
    SET read_at = now()
    WHERE match_id = p_match_id
    AND read_at IS NULL
    AND EXISTS (
        SELECT 1 FROM mentorship_matches
        WHERE id = p_match_id
        AND (mentor_id = v_user_id OR mentee_id = v_user_id)
    );

    RETURN true;
END;
$function$;
REVOKE ALL ON FUNCTION public.mark_messages_read(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_messages_read(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_messages_read(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.mark_messages_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_messages_read(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.report_mentorship_issue(p_match_id uuid, p_reported_id uuid, p_reason text, p_description text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_report_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Validate required fields
    IF p_match_id IS NULL THEN
        RAISE EXCEPTION 'Match ID is required';
    END IF;

    IF p_reported_id IS NULL THEN
        RAISE EXCEPTION 'Reported user ID is required';
    END IF;

    IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) = 0 THEN
        RAISE EXCEPTION 'Reason is required';
    END IF;

    -- Verify reporter is a participant in the match
    IF NOT EXISTS (
        SELECT 1 FROM mentorship_matches
        WHERE id = p_match_id
        AND (mentor_id = v_user_id OR mentee_id = v_user_id)
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this mentorship';
    END IF;

    -- Verify reported user is the OTHER participant
    IF NOT EXISTS (
        SELECT 1 FROM mentorship_matches
        WHERE id = p_match_id
        AND (mentor_id = p_reported_id OR mentee_id = p_reported_id)
    ) THEN
        RAISE EXCEPTION 'Reported user is not a participant in this mentorship';
    END IF;

    -- Prevent self-reporting
    IF v_user_id = p_reported_id THEN
        RAISE EXCEPTION 'Cannot report yourself';
    END IF;

    -- Create report
    INSERT INTO mentorship_reports (
        match_id,
        reporter_id,
        reported_id,
        reason,
        description,
        status,
        created_at
    )
    VALUES (
        p_match_id,
        v_user_id,
        p_reported_id,
        p_reason,
        COALESCE(p_description, ''),
        'pending',
        now()
    )
    RETURNING id INTO v_report_id;

    RETURN v_report_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.report_mentorship_issue(uuid,uuid,text,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.report_mentorship_issue(uuid,uuid,text,text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.report_mentorship_issue(uuid,uuid,text,text) TO anon;
GRANT EXECUTE ON FUNCTION public.report_mentorship_issue(uuid,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_mentorship_issue(uuid,uuid,text,text) TO service_role;
CREATE OR REPLACE FUNCTION public.sanitize_mentorship_profile_bio()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Only sanitize if bio is being set
    IF NEW.bio IS NOT NULL THEN
        -- Sanitize by encoding HTML entities (same approach as message content)
        NEW.bio := replace(NEW.bio, '&', '&amp;');
        NEW.bio := replace(NEW.bio, '<', '&lt;');
        NEW.bio := replace(NEW.bio, '>', '&gt;');
        NEW.bio := replace(NEW.bio, '"', '&quot;');
        NEW.bio := replace(NEW.bio, '''', '&#x27;');
        
        -- Trim whitespace
        NEW.bio := trim(NEW.bio);
        
        -- Limit length to 500 characters
        IF length(NEW.bio) > 500 THEN
            NEW.bio := substring(NEW.bio FROM 1 FOR 500);
        END IF;
        
        -- Reject if bio becomes empty after sanitization
        IF NEW.bio = '' THEN
            NEW.bio := NULL;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.sanitize_mentorship_profile_bio() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sanitize_mentorship_profile_bio() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.sanitize_mentorship_profile_bio() TO anon;
GRANT EXECUTE ON FUNCTION public.sanitize_mentorship_profile_bio() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sanitize_mentorship_profile_bio() TO service_role;
CREATE OR REPLACE FUNCTION public.unflag_mentorship_message(p_message_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_match_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Get match_id to verify user is participant
    SELECT match_id INTO v_match_id
    FROM mentorship_messages
    WHERE id = p_message_id;

    IF v_match_id IS NULL THEN
        RAISE EXCEPTION 'Message not found';
    END IF;

    -- Verify user is a participant
    IF NOT EXISTS (
        SELECT 1 FROM mentorship_matches
        WHERE id = v_match_id
        AND (mentor_id = v_user_id OR mentee_id = v_user_id)
    ) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    -- Unflag the message
    UPDATE mentorship_messages
    SET flagged = false,
        flag_reason = NULL
    WHERE id = p_message_id;

    RETURN true;
END;
$function$;
REVOKE ALL ON FUNCTION public.unflag_mentorship_message(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.unflag_mentorship_message(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.unflag_mentorship_message(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.unflag_mentorship_message(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unflag_mentorship_message(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.update_prediction_accuracy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_predicted_mood DECIMAL;
    v_actual_mood_scaled DECIMAL;
    v_accuracy DECIMAL;
BEGIN
    -- Moods accept 1-10 while predictions use 1-10 for 1-5 check-ins doubled; clamp so a
    -- 6-10 score can never exceed the prediction's range.
    v_actual_mood_scaled := LEAST(NEW.mood_score * 2, 10);

    -- Find today's prediction for this user
    SELECT predicted_mood INTO v_predicted_mood
    FROM mood_predictions
    WHERE mood_predictions.user_id = NEW.user_id
    AND predicted_for = NEW.local_date
    AND actual_mood IS NULL
    LIMIT 1;

    IF v_predicted_mood IS NOT NULL THEN
        -- Calculate accuracy: 1 - (|predicted - actual| / 9)
        -- 9 is max possible error on 1-10 scale
        v_accuracy := GREATEST(0, 1 - (ABS(v_predicted_mood - v_actual_mood_scaled) / 9));

        -- Update prediction with actual mood and accuracy
        UPDATE mood_predictions
        SET
            actual_mood = v_actual_mood_scaled,
            prediction_accuracy = v_accuracy,
            updated_at = NOW()
        WHERE mood_predictions.user_id = NEW.user_id
        AND predicted_for = NEW.local_date
        AND actual_mood IS NULL;
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Accuracy bookkeeping is secondary; it must never roll back the user's mood entry.
    RAISE WARNING 'update_prediction_accuracy skipped: %', SQLERRM;
    RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.update_prediction_accuracy() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_prediction_accuracy() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_prediction_accuracy() TO anon;
GRANT EXECUTE ON FUNCTION public.update_prediction_accuracy() TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_prediction_accuracy() TO service_role;

-- 4. Triggers the fresh chain has and production lacks.
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.mentorship_profiles'::regclass AND tgname = 'trg_sanitize_mentorship_profile_bio') THEN EXECUTE $ddl$CREATE TRIGGER trg_sanitize_mentorship_profile_bio BEFORE INSERT OR UPDATE ON public.mentorship_profiles FOR EACH ROW EXECUTE FUNCTION public.sanitize_mentorship_profile_bio()$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.moods'::regclass AND tgname = 'trigger_update_prediction_accuracy') THEN EXECUTE $ddl$CREATE TRIGGER trigger_update_prediction_accuracy AFTER INSERT ON public.moods FOR EACH ROW EXECUTE FUNCTION public.update_prediction_accuracy()$ddl$; END IF; END $$;

-- 5. Constraints the fresh chain has and production lacks (enforced for new rows; existing rows are not re-checked).
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.circadian_profiles'::regclass AND conname = 'check_peak_performance_is_object_or_null') THEN ALTER TABLE public.circadian_profiles ADD CONSTRAINT check_peak_performance_is_object_or_null CHECK (((peak_performance_window IS NULL) OR (jsonb_typeof(peak_performance_window) = 'object'::text))) NOT VALID; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.circadian_profiles'::regclass AND conname = 'check_vulnerable_windows_is_array') THEN ALTER TABLE public.circadian_profiles ADD CONSTRAINT check_vulnerable_windows_is_array CHECK ((jsonb_typeof(vulnerable_windows) = 'array'::text)) NOT VALID; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.daily_signals'::regclass AND conname = 'daily_signals_wellness_confidence_check') THEN ALTER TABLE public.daily_signals ADD CONSTRAINT daily_signals_wellness_confidence_check CHECK (((wellness_confidence >= 0) AND (wellness_confidence <= 100))) NOT VALID; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.daily_signals'::regclass AND conname = 'daily_signals_wellness_score_check') THEN ALTER TABLE public.daily_signals ADD CONSTRAINT daily_signals_wellness_score_check CHECK (((wellness_score >= 0) AND (wellness_score <= 100))) NOT VALID; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.intervention_efficacy'::regclass AND conname = 'intervention_efficacy_session_id_fkey') THEN ALTER TABLE public.intervention_efficacy ADD CONSTRAINT intervention_efficacy_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.exercise_sessions(id) ON DELETE CASCADE NOT VALID; END IF; END $$;

-- 6. Indexes the fresh chain has and production lacks.
CREATE INDEX IF NOT EXISTS idx_ar_exercise_types_ar_type ON public.ar_exercise_types USING btree (ar_type);
CREATE INDEX IF NOT EXISTS idx_ar_exercise_types_premium ON public.ar_exercise_types USING btree (is_premium);
DO $$ BEGIN EXECUTE $ddl$CREATE UNIQUE INDEX IF NOT EXISTS idx_ar_scene_prefs_default ON public.ar_scene_preferences USING btree (user_id) WHERE (is_default = true)$ddl$; EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'Skipped unique index idx_ar_scene_prefs_default: existing rows conflict'; END $$;
CREATE INDEX IF NOT EXISTS idx_ar_scene_prefs_user_id ON public.ar_scene_preferences USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_ar_sessions_completed ON public.ar_exercise_sessions USING btree (user_id, completed_at) WHERE (completed_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_ar_sessions_exercise_type ON public.ar_exercise_sessions USING btree (exercise_type_id);
CREATE INDEX IF NOT EXISTS idx_ar_sessions_user_id ON public.ar_exercise_sessions USING btree (user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_capacity_overrides_user_active ON public.capacity_overrides USING btree (user_id, is_active) WHERE (is_active = true);
CREATE INDEX IF NOT EXISTS idx_daily_signals_wellness_score ON public.daily_signals USING btree (user_id, signal_date DESC) WHERE (wellness_score IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_mood_predictions_accuracy ON public.mood_predictions USING btree (user_id, prediction_accuracy) WHERE (prediction_accuracy IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_prediction_models_user ON public.prediction_models USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_quests_user_local_date ON public.quests USING btree (user_id, local_date DESC);
CREATE INDEX IF NOT EXISTS idx_sleep_sessions_user_created ON public.sleep_sessions USING btree (user_id, created_at DESC);

-- 7. Public-schema policies the fresh chain has and production lacks.
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'biofeedback_preferences' AND policyname = 'users_delete_own_biofeedback_preferences') THEN EXECUTE $ddl$CREATE POLICY "users_delete_own_biofeedback_preferences" ON public.biofeedback_preferences AS PERMISSIVE FOR DELETE TO public USING ((user_id = auth.uid()))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'capacity_overrides' AND policyname = 'Users can manage own overrides') THEN EXECUTE $ddl$CREATE POLICY "Users can manage own overrides" ON public.capacity_overrides AS PERMISSIVE FOR ALL TO public USING ((auth.uid() = user_id))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'capacity_rate_limits' AND policyname = 'Service role can manage rate limits') THEN EXECUTE $ddl$CREATE POLICY "Service role can manage rate limits" ON public.capacity_rate_limits AS PERMISSIVE FOR ALL TO public USING (((auth.jwt() ->> 'role'::text) = 'service_role'::text))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'capacity_rate_limits' AND policyname = 'Users can read own rate limits') THEN EXECUTE $ddl$CREATE POLICY "Users can read own rate limits" ON public.capacity_rate_limits AS PERMISSIVE FOR SELECT TO public USING ((auth.uid() = user_id))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'circadian_profiles' AND policyname = 'Users can delete own circadian profile') THEN EXECUTE $ddl$CREATE POLICY "Users can delete own circadian profile" ON public.circadian_profiles AS PERMISSIVE FOR DELETE TO public USING ((auth.uid() = user_id))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'circadian_profiles' AND policyname = 'Users can insert own circadian profile') THEN EXECUTE $ddl$CREATE POLICY "Users can insert own circadian profile" ON public.circadian_profiles AS PERMISSIVE FOR INSERT TO public WITH CHECK ((auth.uid() = user_id))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'circadian_profiles' AND policyname = 'Users can read own circadian profile') THEN EXECUTE $ddl$CREATE POLICY "Users can read own circadian profile" ON public.circadian_profiles AS PERMISSIVE FOR SELECT TO public USING ((auth.uid() = user_id))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'circadian_profiles' AND policyname = 'Users can update own circadian profile') THEN EXECUTE $ddl$CREATE POLICY "Users can update own circadian profile" ON public.circadian_profiles AS PERMISSIVE FOR UPDATE TO public USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id))$ddl$; END IF; END $$;
-- "Delete own match" is replaced in section 12.
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'mentorship_matches' AND policyname = 'Update own match status') THEN EXECUTE $ddl$CREATE POLICY "Update own match status" ON public.mentorship_matches AS PERMISSIVE FOR UPDATE TO public USING (((mentor_id = auth.uid()) OR (mentee_id = auth.uid()))) WITH CHECK (((mentor_id = auth.uid()) OR (mentee_id = auth.uid())))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'mentorship_matches' AND policyname = 'View own match') THEN EXECUTE $ddl$CREATE POLICY "View own match" ON public.mentorship_matches AS PERMISSIVE FOR SELECT TO public USING (((mentor_id = auth.uid()) OR (mentee_id = auth.uid())))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'mentorship_messages' AND policyname = 'Delete own message') THEN EXECUTE $ddl$CREATE POLICY "Delete own message" ON public.mentorship_messages AS PERMISSIVE FOR DELETE TO public USING ((sender_id = auth.uid()))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'mentorship_messages' AND policyname = 'Match participants can read messages') THEN EXECUTE $ddl$CREATE POLICY "Match participants can read messages" ON public.mentorship_messages AS PERMISSIVE FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM public.mentorship_matches
  WHERE ((mentorship_matches.id = mentorship_messages.match_id) AND ((mentorship_matches.mentor_id = auth.uid()) OR (mentorship_matches.mentee_id = auth.uid()))))))$ddl$; END IF; END $$;
-- "Match participants can send messages" is replaced in section 12.
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'mentorship_messages' AND policyname = 'Senders can delete own messages') THEN EXECUTE $ddl$CREATE POLICY "Senders can delete own messages" ON public.mentorship_messages AS PERMISSIVE FOR DELETE TO public USING ((auth.uid() = sender_id))$ddl$; END IF; END $$;
-- "Update message flags" is not restored; see section 12.
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'mentorship_messages' AND policyname = 'Users can decrypt own messages') THEN EXECUTE $ddl$CREATE POLICY "Users can decrypt own messages" ON public.mentorship_messages AS PERMISSIVE FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM public.mentorship_matches
  WHERE ((mentorship_matches.id = mentorship_messages.match_id) AND ((mentorship_matches.mentor_id = auth.uid()) OR (mentorship_matches.mentee_id = auth.uid()))))))$ddl$; END IF; END $$;
-- "Users can mark own messages as read" is not restored; see section 12.
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'mentorship_profiles' AND policyname = 'Create own profile') THEN EXECUTE $ddl$CREATE POLICY "Create own profile" ON public.mentorship_profiles AS PERMISSIVE FOR INSERT TO public WITH CHECK ((user_id = auth.uid()))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'mentorship_profiles' AND policyname = 'Update own profile') THEN EXECUTE $ddl$CREATE POLICY "Update own profile" ON public.mentorship_profiles AS PERMISSIVE FOR UPDATE TO public USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'mentorship_profiles' AND policyname = 'View verified mentor profiles') THEN EXECUTE $ddl$CREATE POLICY "View verified mentor profiles" ON public.mentorship_profiles AS PERMISSIVE FOR SELECT TO public USING (((verified = true) OR (user_id = auth.uid())))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'mentorship_reports' AND policyname = 'Create report') THEN EXECUTE $ddl$CREATE POLICY "Create report" ON public.mentorship_reports AS PERMISSIVE FOR INSERT TO public WITH CHECK ((reporter_id = auth.uid()))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'mentorship_reports' AND policyname = 'View report') THEN EXECUTE $ddl$CREATE POLICY "View report" ON public.mentorship_reports AS PERMISSIVE FOR SELECT TO public USING (((reporter_id = auth.uid()) OR (reported_id = auth.uid())))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'prediction_models' AND policyname = 'Service role can manage models') THEN EXECUTE $ddl$CREATE POLICY "Service role can manage models" ON public.prediction_models AS PERMISSIVE FOR ALL TO public USING ((auth.role() = 'service_role'::text))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'prediction_models' AND policyname = 'Users can read own model or global') THEN EXECUTE $ddl$CREATE POLICY "Users can read own model or global" ON public.prediction_models AS PERMISSIVE FOR SELECT TO public USING (((user_id IS NULL) OR (auth.uid() = user_id)))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'quest_difficulty_mapping' AND policyname = 'Anyone can read difficulty mappings') THEN EXECUTE $ddl$CREATE POLICY "Anyone can read difficulty mappings" ON public.quest_difficulty_mapping AS PERMISSIVE FOR SELECT TO public USING (true)$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_capacity' AND policyname = 'Service role can write capacity') THEN EXECUTE $ddl$CREATE POLICY "Service role can write capacity" ON public.user_capacity AS PERMISSIVE FOR ALL TO public USING (((auth.jwt() ->> 'role'::text) = 'service_role'::text))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_capacity' AND policyname = 'Users can read own capacity') THEN EXECUTE $ddl$CREATE POLICY "Users can read own capacity" ON public.user_capacity AS PERMISSIVE FOR SELECT TO public USING ((auth.uid() = user_id))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'vulnerable_windows' AND policyname = 'Users can delete own vulnerable windows') THEN EXECUTE $ddl$CREATE POLICY "Users can delete own vulnerable windows" ON public.vulnerable_windows AS PERMISSIVE FOR DELETE TO public USING ((auth.uid() = user_id))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'vulnerable_windows' AND policyname = 'Users can insert own vulnerable windows') THEN EXECUTE $ddl$CREATE POLICY "Users can insert own vulnerable windows" ON public.vulnerable_windows AS PERMISSIVE FOR INSERT TO public WITH CHECK ((auth.uid() = user_id))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'vulnerable_windows' AND policyname = 'Users can read own vulnerable windows') THEN EXECUTE $ddl$CREATE POLICY "Users can read own vulnerable windows" ON public.vulnerable_windows AS PERMISSIVE FOR SELECT TO public USING ((auth.uid() = user_id))$ddl$; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'vulnerable_windows' AND policyname = 'Users can update own vulnerable windows') THEN EXECUTE $ddl$CREATE POLICY "Users can update own vulnerable windows" ON public.vulnerable_windows AS PERMISSIVE FOR UPDATE TO public USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id))$ddl$; END IF; END $$;

-- 8. Functions where production kept an older definition without caller checks or a fixed search_path.
CREATE OR REPLACE FUNCTION public.check_activation_status(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_profile RECORD;
BEGIN
  -- Authorization check: caller must own this profile
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot read another user''s activation state';
  END IF;

  SELECT
    activation_completed_at,
    first_quest_completed_at,
    first_mood_logged_at,
    first_chat_message_at,
    unlocked_features
  INTO v_profile
  FROM profiles
  WHERE id = p_user_id;

  -- Check if profile exists using NOT FOUND (more idiomatic than IS NULL)
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found for user %', p_user_id;
  END IF;

  -- Already activated
  IF v_profile.activation_completed_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'activated', TRUE,
      'already_activated', TRUE,
      'unlocked_features', v_profile.unlocked_features
    );
  END IF;

  -- Check magic moment: (quest OR mood) AND chat
  IF (v_profile.first_quest_completed_at IS NOT NULL OR v_profile.first_mood_logged_at IS NOT NULL)
     AND v_profile.first_chat_message_at IS NOT NULL THEN
    -- Complete activation
    UPDATE profiles SET
      activation_completed_at = NOW(),
      unlocked_features = ARRAY['home', 'chat', 'profile', 'programs', 'outcomes']
    WHERE id = p_user_id;

    RETURN jsonb_build_object(
      'activated', TRUE,
      'just_activated', TRUE,
      'unlocked_features', ARRAY['home', 'chat', 'profile', 'programs', 'outcomes']
    );
  END IF;

  -- Not yet activated
  RETURN jsonb_build_object(
    'activated', FALSE,
    'has_quest', v_profile.first_quest_completed_at IS NOT NULL,
    'has_mood', v_profile.first_mood_logged_at IS NOT NULL,
    'has_chat', v_profile.first_chat_message_at IS NOT NULL,
    'unlocked_features', v_profile.unlocked_features
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.check_activation_status(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_activation_status(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_activation_status(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.check_activation_status(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_activation_status(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.record_first_chat_message(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Authorization check: caller must own this profile
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot modify another user''s activation state';
  END IF;

  UPDATE profiles
  SET first_chat_message_at = COALESCE(first_chat_message_at, NOW())
  WHERE id = p_user_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.record_first_chat_message(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_first_chat_message(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_first_chat_message(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.record_first_chat_message(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_first_chat_message(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.record_first_mood_log(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Authorization check: caller must own this profile
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot modify another user''s activation state';
  END IF;

  UPDATE profiles
  SET first_mood_logged_at = COALESCE(first_mood_logged_at, NOW())
  WHERE id = p_user_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.record_first_mood_log(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_first_mood_log(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_first_mood_log(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.record_first_mood_log(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_first_mood_log(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.record_first_quest_completion(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Authorization check: caller must own this profile
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot modify another user''s activation state';
  END IF;

  UPDATE profiles
  SET first_quest_completed_at = COALESCE(first_quest_completed_at, NOW())
  WHERE id = p_user_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.record_first_quest_completion(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_first_quest_completion(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_first_quest_completion(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.record_first_quest_completion(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_first_quest_completion(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.get_social_vitality_dashboard(p_user_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_result JSON;
BEGIN
    -- Only the signed-in owner may read the dashboard; an anonymous caller has no uid.
    IF auth.uid() IS NULL OR p_user_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Unauthorized: Cannot access another user''s dashboard'
            USING ERRCODE = 'PAUTH';
    END IF;

    WITH current_score AS (
        SELECT
            overall_score,
            trend,
            interaction_frequency,
            interaction_depth,
            reciprocity,
            diversity
        FROM social_vitality_scores
        WHERE user_id = p_user_id
        AND date = CURRENT_DATE
        LIMIT 1
    ),
    weekly_change AS (
        SELECT
            s_today.overall_score - s_week_ago.overall_score AS change
        FROM social_vitality_scores s_today
        LEFT JOIN social_vitality_scores s_week_ago
            ON s_week_ago.user_id = s_today.user_id
            AND s_week_ago.date = CURRENT_DATE - INTERVAL '7 days'
        WHERE s_today.user_id = p_user_id
        AND s_today.date = CURRENT_DATE
    ),
    top_supporters AS (
        SELECT json_agg(
            json_build_object(
                'id', rc.other_user_id,
                'name', COALESCE(p.full_name, p.email),
                'correlation', rc.mood_correlation
            )
            ORDER BY rc.mood_correlation DESC
        ) AS supporters
        FROM relationship_correlations rc
        JOIN profiles p ON p.id = rc.other_user_id
        WHERE rc.user_id = p_user_id
        AND rc.classification = 'support_pillar'
        LIMIT 3
    ),
    alert_status AS (
        SELECT
            COALESCE(enabled, FALSE) AS enabled,
            COALESCE(array_length(designated_supporters, 1), 0) AS supporters_configured
        FROM peer_alert_preferences
        WHERE user_id = p_user_id
    )
    SELECT json_build_object(
        'currentScore', COALESCE(cs.overall_score, 0),
        'trend', COALESCE(cs.trend, 'stable'),
        'components', json_build_object(
            'frequency', COALESCE(cs.interaction_frequency, 0),
            'depth', COALESCE(cs.interaction_depth, 0),
            'reciprocity', COALESCE(cs.reciprocity, 0),
            'diversity', COALESCE(cs.diversity, 0)
        ),
        'weeklyChange', COALESCE(wc.change, 0),
        'topSupporters', COALESCE(ts.supporters, '[]'::json),
        'alertStatus', json_build_object(
            'enabled', COALESCE(ast.enabled, FALSE),
            'supportersConfigured', COALESCE(ast.supporters_configured, 0)
        )
    ) INTO v_result
    FROM current_score cs
    LEFT JOIN weekly_change wc ON TRUE
    LEFT JOIN top_supporters ts ON TRUE
    LEFT JOIN alert_status ast ON TRUE;

    RETURN v_result;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_social_vitality_dashboard(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_social_vitality_dashboard(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_social_vitality_dashboard(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.check_message_rate_limit(p_match_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_message_count INTEGER;
    v_max_per_minute INTEGER := 5; -- Max 5 messages per minute
    v_max_per_hour INTEGER := 60; -- Max 60 messages per hour
    v_lock_key BIGINT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Use advisory lock to serialize rate limit checks for this user+match combination
    -- Prevents TOCTOU race condition where multiple concurrent requests bypass the limit
    v_lock_key := hashtext(v_user_id::TEXT || p_match_id::TEXT);
    PERFORM pg_advisory_xact_lock(v_lock_key);

    -- Check per-minute rate (now serialized by lock)
    SELECT COUNT(*) INTO v_message_count
    FROM mentorship_messages
    WHERE sender_id = v_user_id
    AND match_id = p_match_id
    AND sent_at > NOW() - INTERVAL '1 minute';

    IF v_message_count >= v_max_per_minute THEN
        RETURN FALSE;
    END IF;

    -- Check per-hour rate (now serialized by lock)
    SELECT COUNT(*) INTO v_message_count
    FROM mentorship_messages
    WHERE sender_id = v_user_id
    AND match_id = p_match_id
    AND sent_at > NOW() - INTERVAL '1 hour';

    IF v_message_count >= v_max_per_hour THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$function$;
REVOKE ALL ON FUNCTION public.check_message_rate_limit(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_message_rate_limit(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_message_rate_limit(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.check_message_rate_limit(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_message_rate_limit(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.enforce_profiles_insert_defaults()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Only apply restrictions to authenticated users creating their own profiles
  -- Service role and admin operations bypass this
  IF (SELECT COALESCE(auth.role(), 'unknown') = 'authenticated') THEN
    -- Force default values for revenue-critical columns
    -- These can only be set by Edge Functions/service role after purchase verification
    NEW.subscription_tier := 'free';
    NEW.daily_ai_quota := 5;  -- Updated from 10 to 5 for revenue optimization
    NEW.daily_ai_used := 0;
    NEW.quota_reset_at := NOW();
    NEW.premium_badge := FALSE;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.enforce_profiles_insert_defaults() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.enforce_profiles_insert_defaults() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.enforce_profiles_insert_defaults() TO anon;
GRANT EXECUTE ON FUNCTION public.enforce_profiles_insert_defaults() TO authenticated;
GRANT EXECUTE ON FUNCTION public.enforce_profiles_insert_defaults() TO service_role;

-- 3b. No client calls the prediction, decryption or capacity-cleanup functions; the predict-mood job and
-- definer-owned RPCs do. The grants above leave them service-role only. encrypt_message_content is also
-- granted to authenticated because the message trigger runs as the sender.

-- 9. Two functions where production's definition is the safer one; the fresh chain adopts it.
-- The repository version created a key on demand but ignored revoked_at; production ignored
-- revoked keys but never created one. Keep both behaviors. Only definer functions call it.
CREATE OR REPLACE FUNCTION public.get_active_encryption_key()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $function$
DECLARE
    v_key_id text;
BEGIN
    SELECT id INTO v_key_id
    FROM public.mentorship_encryption_keys
    WHERE is_active = true
      AND revoked_at IS NULL
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_key_id IS NULL THEN
        INSERT INTO public.mentorship_encryption_keys (id, key_material)
        VALUES ('key_' || to_char(now(), 'YYYYMMDD_HH24MISS'), extensions.gen_random_bytes(32))
        RETURNING id INTO v_key_id;
    END IF;

    RETURN v_key_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_active_encryption_key() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_active_encryption_key() TO service_role;

-- Production's version rejects cross-user calls and reports the actual count at the cap.
CREATE OR REPLACE FUNCTION public.increment_shield_count(p_user_id uuid)
RETURNS TABLE(shields_awarded boolean, new_shields_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_rows_updated INT;
  v_current_count INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot increment shields for another user';
  END IF;

  UPDATE user_stats
  SET
    streak_shields_remaining = streak_shields_remaining + 1,
    updated_at = NOW()
  WHERE user_id = p_user_id
    AND streak_shields_remaining < streak_shields_max;

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

  IF v_rows_updated = 0 THEN
    SELECT streak_shields_remaining INTO v_current_count
    FROM user_stats
    WHERE user_id = p_user_id;

    RETURN QUERY SELECT FALSE, COALESCE(v_current_count, 0);
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    TRUE as shields_awarded,
    streak_shields_remaining as new_shields_count
  FROM user_stats
  WHERE user_id = p_user_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.increment_shield_count(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.increment_shield_count(uuid) TO service_role;

-- 10. Direct client updates on mentorship rows. Released clients update mentorship_matches
-- directly (accept: status=active; end: status, ended_at, end_reason), so the UPDATE policies
-- above are needed. Policies cannot restrict columns, so this guard limits what an API caller
-- (anon/authenticated) may change. Definer RPCs run as their owner and are not affected.
CREATE OR REPLACE FUNCTION public.guard_mentorship_match_client_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $function$
BEGIN
    IF current_user NOT IN ('anon', 'authenticated') THEN
        RETURN NEW;
    END IF;
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.mentor_response IS DISTINCT FROM OLD.mentor_response OR NEW.started_at IS DISTINCT FROM OLD.started_at
       OR NEW.mentor_id IS DISTINCT FROM OLD.mentor_id OR NEW.mentee_id IS DISTINCT FROM OLD.mentee_id
       OR NEW.matched_at IS DISTINCT FROM OLD.matched_at OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.mentor_alias IS DISTINCT FROM OLD.mentor_alias OR NEW.mentee_alias IS DISTINCT FROM OLD.mentee_alias
       OR NEW.introduction_message IS DISTINCT FROM OLD.introduction_message
       OR NEW.match_reason IS DISTINCT FROM OLD.match_reason
       OR NEW.compatibility_score IS DISTINCT FROM OLD.compatibility_score
       OR NEW.expertise_match_score IS DISTINCT FROM OLD.expertise_match_score
       OR NEW.language_match_score IS DISTINCT FROM OLD.language_match_score
       OR NEW.timezone_match_score IS DISTINCT FROM OLD.timezone_match_score
       OR NEW.availability_match_score IS DISTINCT FROM OLD.availability_match_score
       OR NEW.duration_weeks IS DISTINCT FROM OLD.duration_weeks THEN
        RAISE EXCEPTION 'Only the match status and its end details can be changed' USING ERRCODE = '42501';
    END IF;
    IF OLD.status IN ('completed', 'declined', 'ended', 'suspended') THEN
        RAISE EXCEPTION 'This mentorship is closed' USING ERRCODE = '42501';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NEW.status IN ('accepted', 'active', 'declined') THEN
            IF auth.uid() IS DISTINCT FROM OLD.mentor_id OR OLD.status NOT IN ('pending', 'accepted') THEN
                RAISE EXCEPTION 'Only the mentor can respond to a pending request' USING ERRCODE = '42501';
            END IF;
        ELSIF NEW.status NOT IN ('completed', 'ended') THEN
            RAISE EXCEPTION 'Status change not allowed' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.guard_mentorship_match_client_update() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS guard_mentorship_match_client_update ON public.mentorship_matches;
CREATE TRIGGER guard_mentorship_match_client_update
    BEFORE UPDATE ON public.mentorship_matches
    FOR EACH ROW EXECUTE FUNCTION public.guard_mentorship_match_client_update();

-- A participant may mark a message read or flag it; content, authorship and review fields stay fixed.
CREATE OR REPLACE FUNCTION public.guard_mentorship_message_client_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $function$
BEGIN
    IF current_user NOT IN ('anon', 'authenticated') THEN
        RETURN NEW;
    END IF;
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.match_id IS DISTINCT FROM OLD.match_id OR NEW.sender_id IS DISTINCT FROM OLD.sender_id
       OR NEW.content IS DISTINCT FROM OLD.content OR NEW.sent_at IS DISTINCT FROM OLD.sent_at
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.encrypted_content IS DISTINCT FROM OLD.encrypted_content
       OR NEW.encryption_key_id IS DISTINCT FROM OLD.encryption_key_id OR NEW.iv IS DISTINCT FROM OLD.iv
       OR NEW.reviewed IS DISTINCT FROM OLD.reviewed OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at
       OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by THEN
        RAISE EXCEPTION 'Only read and flag state can be changed' USING ERRCODE = '42501';
    END IF;
    IF NEW.read_at IS DISTINCT FROM OLD.read_at AND auth.uid() IS NOT DISTINCT FROM OLD.sender_id THEN
        RAISE EXCEPTION 'Only the recipient can mark a message read' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.guard_mentorship_message_client_update() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS guard_mentorship_message_client_update ON public.mentorship_messages;
CREATE TRIGGER guard_mentorship_message_client_update
    BEFORE UPDATE ON public.mentorship_messages
    FOR EACH ROW EXECUTE FUNCTION public.guard_mentorship_message_client_update();

-- 11. Definer functions whose fixed search_path never reached production; the bodies already match.
ALTER FUNCTION public.delete_old_nervous_system_data() SET search_path = public, pg_temp;
ALTER FUNCTION public.update_intervention_efficacy() SET search_path = public, pg_temp;
-- pgcrypto lives in the extensions schema; resolve it the same way whichever role calls these.
ALTER FUNCTION public.encrypt_message_content(text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.decrypt_message_content(bytea, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.decrypt_messages_batch(uuid[]) SET search_path = public, extensions, pg_temp;

-- 12. Direct deletes and inserts. Deleting a match cascades through both participants' messages
-- and the safety escalations, so a client may delete only what the released app deletes: a
-- mentor declining a pending request. Ending an active mentorship is a status update.
DROP POLICY IF EXISTS "Delete own match" ON public.mentorship_matches;
CREATE POLICY "Delete own match" ON public.mentorship_matches
    FOR DELETE TO authenticated
    USING (mentor_id = auth.uid() AND status = 'pending');
-- Clients change read and flag state through mark_messages_read() and flag_mentorship_message(),
-- which run as their owner. The old direct UPDATE policies are not needed: one recursed into its
-- own table on every update, the other let a participant rewrite any field of any message.
DROP POLICY IF EXISTS "Users can mark own messages as read" ON public.mentorship_messages;
DROP POLICY IF EXISTS "Update message flags" ON public.mentorship_messages;
-- Permissive policies combine with OR; an unconditional insert policy would bypass the
-- rate-limited one, which stays as the only direct insert path.
DROP POLICY IF EXISTS "Match participants can send messages" ON public.mentorship_messages;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'mentorship_messages'
                   AND policyname = 'Match participants can send rate-limited messages') THEN
        RAISE EXCEPTION 'Expected the rate-limited message insert policy';
    END IF;
END $$;
