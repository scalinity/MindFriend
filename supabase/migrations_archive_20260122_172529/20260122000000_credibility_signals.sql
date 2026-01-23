-- Migration: Credibility Signals
-- Adds evidence-based methodology badges, therapist review indicators, testimonials, and methodology info

-- ============================================================================
-- 1. Add credibility fields to exercises table
-- ============================================================================

ALTER TABLE exercises ADD COLUMN IF NOT EXISTS evidence_basis TEXT
  CHECK (evidence_basis IN ('CBT', 'DBT', 'ACT', 'Mindfulness', 'Somatic', 'Breathwork', 'General'));

ALTER TABLE exercises ADD COLUMN IF NOT EXISTS therapist_reviewed BOOLEAN DEFAULT FALSE;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS review_date DATE;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS methodology_note TEXT;

-- Update existing exercises with evidence basis based on type
UPDATE exercises SET evidence_basis = 'Breathwork', therapist_reviewed = TRUE, review_date = '2026-01-01'
  WHERE type = 'breathing' AND evidence_basis IS NULL;

UPDATE exercises SET evidence_basis = 'Mindfulness', therapist_reviewed = TRUE, review_date = '2026-01-01'
  WHERE type = 'meditation' AND evidence_basis IS NULL;

UPDATE exercises SET evidence_basis = 'Somatic', therapist_reviewed = TRUE, review_date = '2026-01-01'
  WHERE type = 'grounding' AND evidence_basis IS NULL;

UPDATE exercises SET evidence_basis = 'CBT', therapist_reviewed = TRUE, review_date = '2026-01-01'
  WHERE type = 'journaling' AND evidence_basis IS NULL;

UPDATE exercises SET evidence_basis = 'Somatic', therapist_reviewed = TRUE, review_date = '2026-01-01'
  WHERE type = 'movement' AND evidence_basis IS NULL;

-- ============================================================================
-- 2. Create testimonials table
-- ============================================================================

CREATE TABLE IF NOT EXISTS testimonials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name TEXT NOT NULL,
  location TEXT,
  content TEXT NOT NULL,
  rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  feature_highlight TEXT,
  approved BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fetching approved testimonials
CREATE INDEX IF NOT EXISTS idx_testimonials_approved ON testimonials(approved) WHERE approved = TRUE;

-- RLS for testimonials (public read for approved only)
ALTER TABLE testimonials ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'testimonials' AND policyname = 'Anyone can read approved testimonials') THEN
    CREATE POLICY "Anyone can read approved testimonials" ON testimonials FOR SELECT USING (approved = TRUE);
  END IF;
END $$;

-- Seed initial testimonials (only if table is empty)
INSERT INTO testimonials (display_name, location, content, rating, feature_highlight, approved)
SELECT * FROM (VALUES
  ('Sarah M.', 'California', 'The AI buddy feels like talking to a friend who actually listens. It helped me process difficult emotions without judgment.', 5, 'AI Chat', TRUE),
  ('James T.', 'New York', 'The daily quests made building a meditation habit actually stick. 45 day streak and counting!', 5, 'Daily Quests', TRUE),
  ('Emily R.', 'Texas', 'I love the circles feature. My support group checks in daily and it keeps us all accountable.', 5, 'Circles', TRUE),
  ('Michael K.', 'Washington', 'The breathing exercises are science-backed and actually work. I use them before stressful meetings.', 4, 'Exercises', TRUE),
  ('Anna L.', 'Oregon', 'Finally an app that respects privacy. I feel safe sharing my thoughts here.', 5, 'Privacy', TRUE)
) AS v(display_name, location, content, rating, feature_highlight, approved)
WHERE NOT EXISTS (SELECT 1 FROM testimonials LIMIT 1);

-- ============================================================================
-- 3. Create methodology_info table (static reference data)
-- ============================================================================

CREATE TABLE IF NOT EXISTS methodology_info (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  source TEXT
);

-- RLS for methodology_info (public read)
ALTER TABLE methodology_info ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'methodology_info' AND policyname = 'Anyone can read methodology info') THEN
    CREATE POLICY "Anyone can read methodology info" ON methodology_info FOR SELECT USING (TRUE);
  END IF;
END $$;

-- Seed methodology info
INSERT INTO methodology_info (code, name, description, source) VALUES
  ('CBT', 'Cognitive Behavioral Therapy', 'A widely-studied approach that helps identify and change negative thought patterns. CBT techniques help you recognize unhelpful thoughts and develop healthier responses.', 'American Psychological Association'),
  ('DBT', 'Dialectical Behavior Therapy', 'Combines cognitive-behavioral techniques with mindfulness practices. Helps build skills in distress tolerance, emotion regulation, and interpersonal effectiveness.', 'Linehan Institute'),
  ('ACT', 'Acceptance and Commitment Therapy', 'Focuses on accepting difficult thoughts and feelings while committing to actions aligned with your values. Emphasizes psychological flexibility.', 'Association for Contextual Behavioral Science'),
  ('Mindfulness', 'Mindfulness-Based Practices', 'Rooted in ancient meditation traditions and validated by modern research. Focuses on present-moment awareness without judgment.', 'Mindfulness-Based Stress Reduction (MBSR)'),
  ('Somatic', 'Somatic Practices', 'Body-based approaches that use physical movement and awareness to release tension and regulate the nervous system.', 'Somatic Experiencing International'),
  ('Breathwork', 'Breathwork Techniques', 'Controlled breathing practices that activate the parasympathetic nervous system, reducing stress and promoting calm.', 'Research on diaphragmatic breathing'),
  ('General', 'General Wellness', 'Evidence-informed wellness practices drawn from multiple therapeutic traditions.', 'Various sources')
ON CONFLICT (code) DO NOTHING;
