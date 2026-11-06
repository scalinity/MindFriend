-- Run after the full migration chain. Synthetic rows and role changes roll back.
BEGIN;

DO $$ BEGIN
  IF (SELECT count(*) FROM storage.buckets
      WHERE id IN ('creative-works','generated-audio') AND public = false) <> 2 THEN
    RAISE EXCEPTION 'Creative and generated media buckets must both be private';
  END IF;
  IF NOT (SELECT allowed_mime_types @> ARRAY['audio/m4a','audio/x-m4a','audio/mp4','image/png']
          FROM storage.buckets WHERE id = 'creative-works') THEN
    RAISE EXCEPTION 'Creative bucket must retain drawings and accept voice journal uploads';
  END IF;
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);
INSERT INTO storage.objects(bucket_id,name) VALUES
 ('creative-works','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/drawings/test.png'),
 ('creative-works','AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA/voice-journals/test.m4a'),
 ('generated-audio','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/test.mp3'),
 ('generated-audio','AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA/test.mp3');
DO $$ BEGIN
  IF (SELECT count(*) FROM storage.objects WHERE bucket_id IN ('creative-works','generated-audio')) <> 4 THEN
    RAISE EXCEPTION 'Owner must read both UUID casings';
  END IF;
  BEGIN
    UPDATE storage.objects SET name = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/stolen.mp3'
    WHERE bucket_id = 'generated-audio' AND name = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/test.mp3';
    RAISE EXCEPTION 'Owner reassignment unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

SELECT set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}', true);
DO $$
DECLARE affected integer;
BEGIN
  IF EXISTS (SELECT FROM storage.objects WHERE bucket_id IN ('creative-works','generated-audio')) THEN
    RAISE EXCEPTION 'Other account can read private media';
  END IF;
  DELETE FROM storage.objects WHERE bucket_id IN ('creative-works','generated-audio');
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 0 THEN RAISE EXCEPTION 'Other account can delete private media'; END IF;
  BEGIN
    INSERT INTO storage.objects(bucket_id,name)
    VALUES ('creative-works','AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA/foreign.png');
    RAISE EXCEPTION 'Other account upload unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
DO $$ BEGIN
  IF EXISTS (SELECT FROM storage.objects WHERE bucket_id IN ('creative-works','generated-audio')) THEN
    RAISE EXCEPTION 'Anonymous role can read private media';
  END IF;
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);
DO $$
DECLARE affected integer;
BEGIN
  DELETE FROM storage.objects WHERE bucket_id IN ('creative-works','generated-audio');
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 4 THEN RAISE EXCEPTION 'Owner must delete both UUID casings'; END IF;
END $$;
ROLLBACK;
