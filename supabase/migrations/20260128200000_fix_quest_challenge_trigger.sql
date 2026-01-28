-- Fix update_challenge_progress_on_quest trigger
-- Issue: Trigger references NEW.completed (boolean) but quests table uses status (text)
-- The quests table has: status TEXT CHECK (status IN ('assigned', 'completed', 'skipped'))

CREATE OR REPLACE FUNCTION "public"."update_challenge_progress_on_quest"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Fix: Changed from NEW.completed = true to NEW.status = 'completed'
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        UPDATE challenge_participants
        SET current_progress = CASE
            WHEN c.challenge_type = 'quest' THEN 1
            WHEN c.challenge_type = 'streak' THEN (
                SELECT COUNT(DISTINCT DATE(completed_at))
                FROM quests
                WHERE user_id = NEW.user_id
                -- Fix: Changed from completed = true to status = 'completed'
                AND status = 'completed'
                AND completed_at > NOW() - INTERVAL '7 days'
            )
            ELSE current_progress
        END
        FROM challenges c
        WHERE challenge_participants.challenge_id = c.id
        AND challenge_participants.user_id = NEW.user_id
        AND c.challenge_type IN ('quest', 'streak')
        AND c.ends_at > NOW();
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION "public"."update_challenge_progress_on_quest"()
IS 'Updates challenge progress when a quest is completed. Uses status column, not completed boolean.';
