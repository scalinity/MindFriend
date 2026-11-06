-- Companion ingestion uses an empty search path. Trigger lookups must not depend on its caller.
CREATE OR REPLACE FUNCTION public.update_challenge_progress_on_mood()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    UPDATE public.challenge_participants
    SET current_progress = (
        SELECT COUNT(DISTINCT DATE(created_at))
        FROM public.moods
        WHERE user_id = NEW.user_id
          AND created_at > NOW() - INTERVAL '7 days'
    )
    WHERE challenge_id IN (
        SELECT id FROM public.challenges
        WHERE challenge_type = 'mood' AND ends_at > NOW()
    )
      AND user_id = NEW.user_id;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_challenge_progress_on_quest()
RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        UPDATE public.challenge_participants
        SET current_progress = CASE
            WHEN c.challenge_type = 'quest' THEN 1
            WHEN c.challenge_type = 'streak' THEN (
                SELECT COUNT(DISTINCT DATE(completed_at))
                FROM public.quests
                WHERE user_id = NEW.user_id
                  AND status = 'completed'
                  AND completed_at > NOW() - INTERVAL '7 days'
            )
            ELSE current_progress
        END
        FROM public.challenges c
        WHERE challenge_participants.challenge_id = c.id
          AND challenge_participants.user_id = NEW.user_id
          AND c.challenge_type IN ('quest', 'streak')
          AND c.ends_at > NOW();
    END IF;
    RETURN NEW;
END;
$$;
