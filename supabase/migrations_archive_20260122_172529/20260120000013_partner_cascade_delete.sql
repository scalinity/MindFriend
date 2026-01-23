-- Migration: CASCADE DELETE and auto-expire/abandon triggers
-- Purpose: Handle account deletion cascades and auto-expire pending invites
-- Status: CRITICAL PATH - Foundation

-- Trigger 1: Auto-expire pending invites older than 7 days
CREATE OR REPLACE FUNCTION auto_expire_old_invites()
RETURNS void AS $$
BEGIN
    UPDATE partner_links
    SET 
        status = 'expired',
        updated_at = now()
    WHERE 
        status = 'pending' 
        AND expires_at < now()
        AND user_id_2 IS NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger 2: Auto-abandon old exercise sessions (24+ hours without completion)
CREATE OR REPLACE FUNCTION auto_abandon_old_sessions()
RETURNS void AS $$
BEGIN
    UPDATE couples_exercise_sessions
    SET 
        status = 'abandoned',
        updated_at = now()
    WHERE 
        status IN ('pending', 'in_progress', 'paused')
        AND (now() - started_at) > interval '24 hours';
END;
$$ LANGUAGE plpgsql;

-- Trigger 3: When user is deleted, end all their active partnerships (soft delete)
CREATE OR REPLACE FUNCTION end_partnerships_on_user_delete()
RETURNS TRIGGER AS $$
BEGIN
    -- Update any partner links where this user is user_id_1 or user_id_2
    UPDATE partner_links
    SET 
        status = 'ended',
        ended_at = now(),
        updated_at = now()
    WHERE 
        (user_id_1 = OLD.id OR user_id_2 = OLD.id)
        AND status IN ('pending', 'active');
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Trigger 4: Attachment trigger for user deletion
CREATE TRIGGER trigger_end_partnerships_on_user_delete
BEFORE DELETE ON auth.users
FOR EACH ROW
EXECUTE FUNCTION end_partnerships_on_user_delete();

-- Note: CASCADE DELETE is handled by ON DELETE CASCADE in foreign keys:
--   - partner_links.user_id_1 REFERENCES auth.users(id) ON DELETE CASCADE
--   - partner_links.user_id_2 REFERENCES auth.users(id) ON DELETE CASCADE
--   - couples_exercise_sessions.user_id_1 REFERENCES auth.users(id) ON DELETE CASCADE
--   - couples_exercise_sessions.user_id_2 REFERENCES auth.users(id) ON DELETE CASCADE
--   - appreciation_messages.from_user_id REFERENCES auth.users(id) ON DELETE CASCADE
--   - appreciation_messages.to_user_id REFERENCES auth.users(id) ON DELETE CASCADE
--   - partner_links.created_by REFERENCES auth.users(id) ON DELETE CASCADE

-- When a partnership is ended, also end any in-progress sessions with that partner
CREATE OR REPLACE FUNCTION abandon_sessions_on_partnership_end()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'ended' AND OLD.status IN ('pending', 'active') THEN
        UPDATE couples_exercise_sessions
        SET 
            status = 'abandoned',
            updated_at = now()
        WHERE 
            partner_link_id = NEW.id
            AND status IN ('pending', 'in_progress', 'paused');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger 5: Abandon sessions when partnership ends
CREATE TRIGGER trigger_abandon_sessions_on_partnership_end
AFTER UPDATE ON partner_links
FOR EACH ROW
EXECUTE FUNCTION abandon_sessions_on_partnership_end();

-- Index for trigger performance (finding partnerships by user)
CREATE INDEX IF NOT EXISTS idx_partner_links_user_id_1 ON partner_links(user_id_1);
CREATE INDEX IF NOT EXISTS idx_partner_links_user_id_2 ON partner_links(user_id_2) WHERE user_id_2 IS NOT NULL;

-- Index for trigger performance (finding sessions by partner link)
CREATE INDEX IF NOT EXISTS idx_couples_exercise_sessions_partner_link_status 
  ON couples_exercise_sessions(partner_link_id, status) 
  WHERE status IN ('pending', 'in_progress', 'paused');

-- Table: appreciation_messages
-- Purpose: Messages sent between partners as appreciation
CREATE TABLE IF NOT EXISTS appreciation_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_link_id UUID NOT NULL REFERENCES partner_links(id) ON DELETE CASCADE,
    from_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    to_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    message TEXT NOT NULL CHECK (char_length(message) >= 10 AND char_length(message) <= 500),
    read_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT valid_users CHECK (from_user_id != to_user_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_appreciation_messages_to_user ON appreciation_messages(to_user_id, read_at DESC);
CREATE INDEX IF NOT EXISTS idx_appreciation_messages_partner_link ON appreciation_messages(partner_link_id);
CREATE INDEX IF NOT EXISTS idx_appreciation_messages_created_at ON appreciation_messages(created_at DESC);

-- RLS
ALTER TABLE appreciation_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view messages from their partner"
    ON appreciation_messages FOR SELECT
    USING (auth.uid() = to_user_id OR auth.uid() = from_user_id);

CREATE POLICY "Users can send messages to their partner"
    ON appreciation_messages FOR INSERT
    WITH CHECK (auth.uid() = from_user_id);

CREATE POLICY "Recipients can mark read"
    ON appreciation_messages FOR UPDATE
    USING (auth.uid() = to_user_id);
