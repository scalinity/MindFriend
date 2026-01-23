-- Ensure family_members has timestamps required by add_family_member RPC

ALTER TABLE family_members ADD COLUMN IF NOT EXISTS joined_at TIMESTAMPTZ;
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
