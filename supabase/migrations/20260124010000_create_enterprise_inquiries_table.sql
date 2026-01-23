-- Create enterprise_inquiries table for storing sales inquiries
CREATE TABLE IF NOT EXISTS enterprise_inquiries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    company_name TEXT NOT NULL,
    employee_count TEXT NOT NULL CHECK (employee_count IN ('1-10', '11-50', '51-200', '201-500', '500+')),
    message TEXT,
    email_sent BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_enterprise_inquiries_user_id ON enterprise_inquiries(user_id);
CREATE INDEX IF NOT EXISTS idx_enterprise_inquiries_created_at ON enterprise_inquiries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_enterprise_inquiries_email_sent ON enterprise_inquiries(email_sent);

-- Enable Row Level Security
ALTER TABLE enterprise_inquiries ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Authenticated users can insert their own inquiries
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'enterprise_inquiries'
        AND policyname = 'Users can insert own enterprise inquiries'
    ) THEN
        CREATE POLICY "Users can insert own enterprise inquiries"
            ON enterprise_inquiries
            FOR INSERT
            TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Note: No SELECT/UPDATE/DELETE policies - only service role can read inquiries
-- This ensures sales team accesses data via Supabase Dashboard or admin functions
