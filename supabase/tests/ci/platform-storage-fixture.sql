-- Synthetic subset of platform-owned Storage schema. Not an application migration.
-- Column/role basis: https://github.com/supabase/storage/blob/master/migrations/tenant/0002-storage-schema.sql
-- Current column basis: https://supabase.com/docs/guides/storage/schema/design
-- Intentionally does not simulate Storage service/API behavior.
CREATE TABLE storage.buckets (
 id text PRIMARY KEY, name text NOT NULL UNIQUE, owner uuid, owner_id text,
 public boolean NOT NULL DEFAULT false, file_size_limit bigint, allowed_mime_types text[],
 created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now()
);
CREATE TABLE storage.objects (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bucket_id text REFERENCES storage.buckets(id),
 name text, owner uuid, owner_id text, metadata jsonb, version text,
 created_at timestamptz DEFAULT now(),updated_at timestamptz DEFAULT now(),last_accessed_at timestamptz DEFAULT now(),
 UNIQUE(bucket_id,name)
);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION storage.foldername(name text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
 SELECT (string_to_array(name,'/'))[1:cardinality(string_to_array(name,'/'))-1];
$$;
CREATE FUNCTION storage.filename(name text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
 SELECT (string_to_array(name,'/'))[cardinality(string_to_array(name,'/'))];
$$;
CREATE FUNCTION storage.extension(name text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
 SELECT reverse(split_part(reverse(storage.filename(name)),'.',1));
$$;
GRANT USAGE ON SCHEMA storage TO postgres,anon,authenticated,service_role;
GRANT ALL ON storage.buckets,storage.objects TO postgres,anon,authenticated,service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA storage TO postgres,anon,authenticated,service_role;
