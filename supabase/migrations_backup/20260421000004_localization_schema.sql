-- =============================================================================
-- Migration: Multi-Language Localization Infrastructure
-- Date: 2026-01-19
-- Phase: 1 (Infrastructure)
-- Description: Database schema for multi-language support (Spanish, Portuguese)
-- =============================================================================

-- =============================================================================
-- ENUMS: Content Type for Translations
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'content_type_enum') THEN
    CREATE TYPE content_type_enum AS ENUM (
      'exercise',
      'quest',
      'quest_template',
      'badge',
      'journal_prompt'
    );
  END IF;
END $$;

-- =============================================================================
-- TABLE: supported_languages
-- Purpose: Stores metadata for all supported languages
-- =============================================================================

CREATE TABLE IF NOT EXISTS supported_languages (
    code TEXT PRIMARY KEY CHECK (length(code) >= 2 AND length(code) <= 10),
    name TEXT NOT NULL,
    native_name TEXT NOT NULL,
    direction TEXT NOT NULL DEFAULT 'ltr' CHECK (direction IN ('ltr', 'rtl')),
    is_active BOOLEAN NOT NULL DEFAULT false,
    translation_coverage NUMERIC(5,2) NOT NULL DEFAULT 0.00 CHECK (translation_coverage >= 0 AND translation_coverage <= 100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- TABLE: ui_translations
-- Purpose: Stores translated UI strings (buttons, labels, messages)
-- =============================================================================

CREATE TABLE IF NOT EXISTS ui_translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    string_key TEXT NOT NULL,
    language_code TEXT NOT NULL REFERENCES supported_languages(code) ON DELETE CASCADE,
    translation TEXT NOT NULL,
    context TEXT,
    is_verified BOOLEAN NOT NULL DEFAULT false,
    verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(string_key, language_code)
);

-- =============================================================================
-- TABLE: content_translations
-- Purpose: Stores translated content (exercises, quests, badges, etc.)
-- =============================================================================

CREATE TABLE IF NOT EXISTS content_translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_type content_type_enum NOT NULL,
    content_id UUID NOT NULL,
    language_code TEXT NOT NULL REFERENCES supported_languages(code) ON DELETE CASCADE,

    -- Translated fields
    title TEXT,
    description TEXT,
    content TEXT,
    instructions JSONB,

    -- Verification
    is_verified BOOLEAN NOT NULL DEFAULT false,
    verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    translation_notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(content_type, content_id, language_code)
);

-- =============================================================================
-- TABLE: localized_audio
-- Purpose: Placeholder for future localized audio content (meditation, etc.)
-- =============================================================================

CREATE TABLE IF NOT EXISTS localized_audio (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_audio_id UUID NOT NULL,
    language_code TEXT NOT NULL REFERENCES supported_languages(code) ON DELETE CASCADE,
    audio_url TEXT NOT NULL,
    duration_seconds INTEGER,
    voice_artist TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(original_audio_id, language_code)
);

-- =============================================================================
-- TABLE: localized_crisis_resources
-- Purpose: Country/language-specific crisis resources and hotlines
-- =============================================================================

CREATE TABLE IF NOT EXISTS localized_crisis_resources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    country_code TEXT NOT NULL,
    language_code TEXT NOT NULL REFERENCES supported_languages(code) ON DELETE CASCADE,

    -- Crisis contact information
    emergency_number TEXT NOT NULL,
    crisis_hotline TEXT,
    crisis_hotline_name TEXT,
    crisis_text_line TEXT,
    crisis_website TEXT,
    intro_message TEXT NOT NULL,

    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(country_code, language_code)
);

-- =============================================================================
-- INDEXES: Performance optimization for lookups
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_ui_translations_key ON ui_translations(string_key);
CREATE INDEX IF NOT EXISTS idx_ui_translations_lang ON ui_translations(language_code);
CREATE INDEX IF NOT EXISTS idx_content_translations_type_id ON content_translations(content_type, content_id);
CREATE INDEX IF NOT EXISTS idx_content_translations_lang ON content_translations(language_code);
CREATE INDEX IF NOT EXISTS idx_content_translations_verified ON content_translations(is_verified) WHERE is_verified = true;
CREATE INDEX IF NOT EXISTS idx_crisis_resources_country_lang ON localized_crisis_resources(country_code, language_code);

-- =============================================================================
-- TRIGGERS: Auto-update timestamps
-- =============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to ui_translations
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'update_ui_translations_updated_at'
  ) THEN
    CREATE TRIGGER update_ui_translations_updated_at
      BEFORE UPDATE ON ui_translations
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

-- Apply trigger to content_translations
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'update_content_translations_updated_at'
  ) THEN
    CREATE TRIGGER update_content_translations_updated_at
      BEFORE UPDATE ON content_translations
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

-- =============================================================================
-- ROW LEVEL SECURITY: Enable RLS on all tables
-- =============================================================================

ALTER TABLE supported_languages ENABLE ROW LEVEL SECURITY;
ALTER TABLE ui_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE localized_audio ENABLE ROW LEVEL SECURITY;
ALTER TABLE localized_crisis_resources ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- RLS POLICIES: supported_languages
-- =============================================================================

DO $$
BEGIN
  -- SELECT: Authenticated users can read active languages
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'supported_languages'
    AND policyname = 'Active languages readable by authenticated users'
  ) THEN
    CREATE POLICY "Active languages readable by authenticated users"
      ON supported_languages FOR SELECT
      USING (is_active = true);
  END IF;

  -- INSERT/UPDATE/DELETE: Blocked for all clients (service role only)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'supported_languages'
    AND policyname = 'Block client writes to supported_languages'
  ) THEN
    CREATE POLICY "Block client writes to supported_languages"
      ON supported_languages FOR ALL
      USING (false);
  END IF;
END $$;

-- =============================================================================
-- RLS POLICIES: ui_translations
-- =============================================================================

DO $$
BEGIN
  -- SELECT: All authenticated users can read all translations
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'ui_translations'
    AND policyname = 'Translations readable by authenticated users'
  ) THEN
    CREATE POLICY "Translations readable by authenticated users"
      ON ui_translations FOR SELECT
      USING (auth.role() = 'authenticated');
  END IF;

  -- INSERT/UPDATE/DELETE: Blocked for all clients (service role only)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'ui_translations'
    AND policyname = 'Block client writes to ui_translations'
  ) THEN
    CREATE POLICY "Block client writes to ui_translations"
      ON ui_translations FOR ALL
      USING (false);
  END IF;
END $$;

-- =============================================================================
-- RLS POLICIES: content_translations
-- =============================================================================

DO $$
BEGIN
  -- SELECT: Only verified translations visible to authenticated users
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'content_translations'
    AND policyname = 'Verified content translations readable'
  ) THEN
    CREATE POLICY "Verified content translations readable"
      ON content_translations FOR SELECT
      USING (auth.role() = 'authenticated' AND is_verified = true);
  END IF;

  -- INSERT/UPDATE/DELETE: Blocked for all clients (service role only)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'content_translations'
    AND policyname = 'Block client writes to content_translations'
  ) THEN
    CREATE POLICY "Block client writes to content_translations"
      ON content_translations FOR ALL
      USING (false);
  END IF;
END $$;

-- =============================================================================
-- RLS POLICIES: localized_audio
-- =============================================================================

DO $$
BEGIN
  -- SELECT: Only active audio visible
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'localized_audio'
    AND policyname = 'Active audio readable by authenticated users'
  ) THEN
    CREATE POLICY "Active audio readable by authenticated users"
      ON localized_audio FOR SELECT
      USING (auth.role() = 'authenticated' AND is_active = true);
  END IF;

  -- INSERT/UPDATE/DELETE: Blocked for all clients (service role only)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'localized_audio'
    AND policyname = 'Block client writes to localized_audio'
  ) THEN
    CREATE POLICY "Block client writes to localized_audio"
      ON localized_audio FOR ALL
      USING (false);
  END IF;
END $$;

-- =============================================================================
-- RLS POLICIES: localized_crisis_resources
-- =============================================================================

DO $$
BEGIN
  -- SELECT: Only active resources visible
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'localized_crisis_resources'
    AND policyname = 'Active crisis resources readable'
  ) THEN
    CREATE POLICY "Active crisis resources readable"
      ON localized_crisis_resources FOR SELECT
      USING (auth.role() = 'authenticated' AND is_active = true);
  END IF;

  -- INSERT/UPDATE/DELETE: Blocked for all clients (service role only)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'localized_crisis_resources'
    AND policyname = 'Block client writes to crisis resources'
  ) THEN
    CREATE POLICY "Block client writes to crisis resources"
      ON localized_crisis_resources FOR ALL
      USING (false);
  END IF;
END $$;

-- =============================================================================
-- SEED DATA: Supported Languages
-- =============================================================================

INSERT INTO supported_languages (code, name, native_name, direction, is_active, translation_coverage) VALUES
('en', 'English', 'English', 'ltr', true, 100.00),
('es', 'Spanish', 'Español', 'ltr', true, 0.00),
('pt-BR', 'Portuguese (Brazil)', 'Português (Brasil)', 'ltr', true, 0.00),
('fr', 'French', 'Français', 'ltr', false, 0.00),
('de', 'German', 'Deutsch', 'ltr', false, 0.00),
('it', 'Italian', 'Italiano', 'ltr', false, 0.00),
('nl', 'Dutch', 'Nederlands', 'ltr', false, 0.00),
('pl', 'Polish', 'Polski', 'ltr', false, 0.00),
('ja', 'Japanese', '日本語', 'ltr', false, 0.00),
('ko', 'Korean', '한국어', 'ltr', false, 0.00),
('zh-CN', 'Chinese (Simplified)', '简体中文', 'ltr', false, 0.00),
('ar', 'Arabic', 'العربية', 'rtl', false, 0.00),
('he', 'Hebrew', 'עברית', 'rtl', false, 0.00)
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- SEED DATA: Crisis Resources
-- =============================================================================

INSERT INTO localized_crisis_resources (
  country_code,
  language_code,
  emergency_number,
  crisis_hotline,
  crisis_hotline_name,
  crisis_text_line,
  crisis_website,
  intro_message,
  is_active
) VALUES
-- United States (English)
(
  'US',
  'en',
  '911',
  '988',
  'Suicide & Crisis Lifeline',
  'Text HOME to 741741',
  'https://988lifeline.org',
  'If you''re in crisis, help is available 24/7.',
  true
),
-- Spain (Spanish)
(
  'ES',
  'es',
  '112',
  '024',
  'Línea de Atención a la Conducta Suicida',
  NULL,
  'https://www.sanidad.gob.es/linea024',
  'Si estás en crisis, hay ayuda disponible 24/7.',
  true
),
-- Brazil (Portuguese)
(
  'BR',
  'pt-BR',
  '190',
  '188',
  'CVV - Centro de Valorização da Vida',
  NULL,
  'https://www.cvv.org.br',
  'Se você está em crise, há ajuda disponível 24h.',
  true
)
ON CONFLICT (country_code, language_code) DO NOTHING;

-- =============================================================================
-- ALTER: Add preferred_language to profiles table (AFTER seed data)
-- =============================================================================

-- Step 1: Add column without constraint (safe for existing data)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles'
    AND column_name = 'preferred_language'
  ) THEN
    ALTER TABLE profiles ADD COLUMN preferred_language TEXT DEFAULT 'en';
  END IF;
END $$;

-- Step 2: Update existing rows to ensure no NULLs
UPDATE profiles SET preferred_language = 'en' WHERE preferred_language IS NULL;

-- Step 3: Add foreign key constraint (after languages table is populated)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_profiles_preferred_language'
  ) THEN
    ALTER TABLE profiles
    ADD CONSTRAINT fk_profiles_preferred_language
    FOREIGN KEY (preferred_language)
    REFERENCES supported_languages(code)
    ON DELETE SET DEFAULT;
  END IF;
END $$;

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================

-- Verify tables exist
DO $$
DECLARE
  table_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO table_count
  FROM information_schema.tables
  WHERE table_name IN (
    'supported_languages',
    'ui_translations',
    'content_translations',
    'localized_audio',
    'localized_crisis_resources'
  );

  IF table_count = 5 THEN
    RAISE NOTICE 'Localization migration completed successfully: 5/5 tables created';
  ELSE
    RAISE EXCEPTION 'Localization migration incomplete: only % tables created', table_count;
  END IF;
END $$;
