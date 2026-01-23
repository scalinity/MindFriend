-- Spec 14: Accessibility Indexes Migration
-- Add missing composite indexes for query optimization

-- Index for accessibility_preferences lookups by user_id
CREATE INDEX IF NOT EXISTS idx_accessibility_preferences_user_id
ON accessibility_preferences(user_id);

-- Index for audio_captions lookups (language fallback pattern)
CREATE INDEX IF NOT EXISTS idx_audio_captions_content_language
ON audio_captions(content_type, content_id, language);

-- Index for audio_captions fallback lookups (exact match then language)
CREATE INDEX IF NOT EXISTS idx_audio_captions_language
ON audio_captions(language);

-- Index for localized_strings lookups by language and region
CREATE INDEX IF NOT EXISTS idx_localized_strings_lang_region
ON localized_strings(language, region);

-- Index for localized_strings by language only (for fallback)
CREATE INDEX IF NOT EXISTS idx_localized_strings_language
ON localized_strings(language);

-- Index for sign_language_videos lookups
CREATE INDEX IF NOT EXISTS idx_sign_language_videos_content
ON sign_language_videos(content_type, content_id);

-- Index for sign_language_videos by language
CREATE INDEX IF NOT EXISTS idx_sign_language_videos_language
ON sign_language_videos(sign_language);

-- Index for accessibility_feedback by user_id and category
CREATE INDEX IF NOT EXISTS idx_accessibility_feedback_user_category
ON accessibility_feedback(user_id, category);

-- Index for accessibility_feedback by issue type (for reporting)
CREATE INDEX IF NOT EXISTS idx_accessibility_feedback_issue_type
ON accessibility_feedback(issue_type);

-- Index for accessibility_feedback by created_at (for recent feedback)
CREATE INDEX IF NOT EXISTS idx_accessibility_feedback_created_at
ON accessibility_feedback(created_at DESC);

-- ANALYZE to update statistics
ANALYZE;
