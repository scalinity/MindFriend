-- Store decoded ciphertext bytes from the typed encryption result.
CREATE OR REPLACE FUNCTION sanitize_mentorship_message()
RETURNS TRIGGER AS $$
BEGIN
    -- Sanitize by encoding HTML entities instead of regex filtering (more secure)
    NEW.content := replace(NEW.content, '&', '&amp;');
    NEW.content := replace(NEW.content, '<', '&lt;');
    NEW.content := replace(NEW.content, '>', '&gt;');
    NEW.content := replace(NEW.content, '"', '&quot;');
    NEW.content := replace(NEW.content, '''', '&#x27;');

    -- Trim and limit length
    NEW.content := trim(NEW.content);
    IF length(NEW.content) > 2000 THEN
        NEW.content := substring(NEW.content FROM 1 FOR 2000);
    END IF;

    -- Empty messages not allowed
    IF NEW.content = '' THEN
        RAISE EXCEPTION 'Message content cannot be empty';
    END IF;

    -- Encrypt content
    SELECT decode(encrypted.v_encrypted, 'base64'), encrypted.v_key_id
    INTO NEW.encrypted_content, NEW.encryption_key_id
    FROM public.encrypt_message_content(NEW.content) AS encrypted;
    NEW.iv := NULL;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public, extensions, pg_temp;
