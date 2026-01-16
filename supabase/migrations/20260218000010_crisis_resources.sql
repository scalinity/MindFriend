-- Crisis resources for safety features
-- Referenced by iOS SupabaseDataService.getCrisisResources()
-- Issue #006: Missing crisis_resources table in canonical migrations

CREATE TABLE IF NOT EXISTS public.crisis_resources (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  country_code TEXT NOT NULL,
  name TEXT NOT NULL,
  phone TEXT,
  text_line TEXT,
  website TEXT,
  description TEXT,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT crisis_resources_country_code_len CHECK (char_length(country_code) BETWEEN 2 AND 3)
);

CREATE INDEX IF NOT EXISTS idx_crisis_resources_country ON public.crisis_resources(country_code);
CREATE INDEX IF NOT EXISTS idx_crisis_resources_default ON public.crisis_resources(is_default);

ALTER TABLE public.crisis_resources ENABLE ROW LEVEL SECURITY;

-- Crisis resources are public safety info - readable by all authenticated users
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'crisis_resources' AND policyname = 'Crisis resources readable'
  ) THEN
    CREATE POLICY "Crisis resources readable" ON public.crisis_resources
      FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;

-- Seed default crisis resources
INSERT INTO public.crisis_resources (country_code, name, phone, text_line, website, is_default, description)
VALUES
  ('US', '988 Suicide & Crisis Lifeline', '988', '988', 'https://988lifeline.org', true,
   'Free, confidential support for people in distress, 24/7'),
  ('US', 'Crisis Text Line', NULL, 'HOME to 741741', 'https://www.crisistextline.org', false,
   'Text-based crisis support, 24/7'),
  ('US', 'SAMHSA National Helpline', '1-800-662-4357', NULL, 'https://www.samhsa.gov/find-help/national-helpline', false,
   'Free, confidential treatment referral and information service'),
  ('CA', 'Canada Suicide Prevention Service', '1-833-456-4566', '45645', 'https://www.crisisservicescanada.ca', true,
   'Available 24/7/365'),
  ('GB', 'Samaritans', '116 123', NULL, 'https://www.samaritans.org', true,
   'Free emotional support 24/7'),
  ('AU', 'Lifeline Australia', '13 11 14', NULL, 'https://www.lifeline.org.au', true,
   'Crisis support and suicide prevention services')
ON CONFLICT DO NOTHING;
