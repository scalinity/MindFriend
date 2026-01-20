-- Test if the updated function exists and works
-- Get your user ID
SELECT id, email FROM auth.users WHERE email LIKE '%danny%' OR email LIKE '%@gmail.com' LIMIT 5;

-- Check if profile exists for your user
-- Replace with your actual user ID from above
-- SELECT * FROM profiles WHERE id = 'YOUR_USER_ID_HERE';

-- Test the function exists
SELECT proname, prosrc
FROM pg_proc
WHERE proname = 'check_and_increment_ai_quota';

-- Check if ensure_profile_exists function was created
SELECT proname, prosrc
FROM pg_proc
WHERE proname = 'ensure_profile_exists';
