-- Fix orphaned media cleanup
-- BUG: When capsule is soft-deleted, media records are not marked for deletion
-- BUG: Storage files remain orphaned, causing storage quota leaks

-- Trigger to cascade soft-delete from time_capsules to capsule_media
CREATE OR REPLACE FUNCTION cascade_capsule_soft_delete()
RETURNS TRIGGER AS $$
BEGIN
    -- When a capsule is soft-deleted, also soft-delete its media
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        UPDATE capsule_media
        SET deleted_at = NEW.deleted_at
        WHERE capsule_id = NEW.id
          AND deleted_at IS NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS cascade_capsule_soft_delete_trigger ON time_capsules;

-- Create trigger that runs after update
CREATE TRIGGER cascade_capsule_soft_delete_trigger
    AFTER UPDATE OF deleted_at ON time_capsules
    FOR EACH ROW
    WHEN (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)
    EXECUTE FUNCTION cascade_capsule_soft_delete();

COMMENT ON FUNCTION cascade_capsule_soft_delete() IS
'Cascades soft-delete from time_capsules to capsule_media. When a capsule is soft-deleted, all its media records are also soft-deleted to prevent orphaned records.';

-- Note: Actual Storage file cleanup requires an Edge Function (storage.remove API)
-- A separate cron job should periodically scan capsule_media with deleted_at NOT NULL
-- and remove the corresponding Storage files, then hard-delete the records.
COMMENT ON TABLE capsule_media IS
'Time capsule media files (photos, audio). When deleted_at is set, the record is soft-deleted but Storage files remain until cleanup cron runs.';
