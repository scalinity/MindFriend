-- Seed micro_moment_templates with starter content
-- These templates power the contextual micro-interventions feature
-- Source: restored from archived migration 20260307000000_micro_moments.sql

INSERT INTO micro_moment_templates (name, slug, type, title, description, duration_seconds, instructions, animation_type, suggested_contexts, energy_effect, is_premium, sort_order)
VALUES
    -- Breathing Exercises
    ('3-breath-reset', '3-breath-reset', 'breathing', '3 Deep Breaths', 'Quick calming reset in 15 seconds', 15,
     '[{"id":"1","step":1,"text":"Breathe in slowly...","duration_seconds":4,"action":"inhale"},{"id":"2","step":2,"text":"Breathe out...","duration_seconds":4,"action":"exhale"},{"id":"3","step":3,"text":"Breathe in...","duration_seconds":4,"action":"inhale"},{"id":"4","step":4,"text":"And out... Great job!","duration_seconds":3,"action":"exhale"}]'::JSONB,
     'breathing_circle', ARRAY['stress', 'morning', 'pre_meeting'], 'calming', false, 1),

    ('box-breath-30', 'box-breath-30', 'breathing', 'Box Breathing', '4-count pattern: inhale-hold-exhale-hold', 30,
     '[{"id":"1","step":1,"text":"Inhale 1...2...3...4","duration_seconds":4,"action":"inhale"},{"id":"2","step":2,"text":"Hold 1...2...3...4","duration_seconds":4,"action":"hold"},{"id":"3","step":3,"text":"Exhale 1...2...3...4","duration_seconds":4,"action":"exhale"},{"id":"4","step":4,"text":"Hold 1...2...3...4","duration_seconds":4,"action":"hold"},{"id":"5","step":5,"text":"Inhale 1...2...3...4","duration_seconds":4,"action":"inhale"},{"id":"6","step":6,"text":"Hold 1...2...3...4","duration_seconds":4,"action":"hold"},{"id":"7","step":7,"text":"Exhale and relax...","duration_seconds":6,"action":"exhale"}]'::JSONB,
     'breathing_circle', ARRAY['stress', 'anxiety', 'pre_meeting'], 'calming', false, 2),

    ('calm-minute', 'calm-minute', 'breathing', 'One Minute Calm', 'Extended breathing with visual guide', 60,
     '[{"id":"1","step":1,"text":"Find a comfortable position","duration_seconds":5,"action":"observe"},{"id":"2","step":2,"text":"Breathe in deeply...","duration_seconds":5,"action":"inhale"},{"id":"3","step":3,"text":"And slowly release...","duration_seconds":5,"action":"exhale"},{"id":"4","step":4,"text":"Again, breathe in...","duration_seconds":5,"action":"inhale"},{"id":"5","step":5,"text":"Let it go...","duration_seconds":5,"action":"exhale"},{"id":"6","step":6,"text":"Breathe in peace...","duration_seconds":5,"action":"inhale"},{"id":"7","step":7,"text":"Release tension...","duration_seconds":5,"action":"exhale"},{"id":"8","step":8,"text":"One more deep breath in...","duration_seconds":5,"action":"inhale"},{"id":"9","step":9,"text":"Exhale completely...","duration_seconds":5,"action":"exhale"},{"id":"10","step":10,"text":"Return to your day, refreshed","duration_seconds":10,"action":"observe"}]'::JSONB,
     'breathing_circle', ARRAY['evening', 'stress', 'break'], 'calming', false, 3),

    ('energize-breath', 'energize-breath', 'breathing', 'Energizing Breath', 'Quick breath to boost energy', 20,
     '[{"id":"1","step":1,"text":"Inhale quickly!","duration_seconds":2,"action":"inhale"},{"id":"2","step":2,"text":"Exhale sharply!","duration_seconds":2,"action":"exhale"},{"id":"3","step":3,"text":"Inhale!","duration_seconds":2,"action":"inhale"},{"id":"4","step":4,"text":"Exhale!","duration_seconds":2,"action":"exhale"},{"id":"5","step":5,"text":"Inhale!","duration_seconds":2,"action":"inhale"},{"id":"6","step":6,"text":"Exhale!","duration_seconds":2,"action":"exhale"},{"id":"7","step":7,"text":"Deep breath in...","duration_seconds":4,"action":"inhale"},{"id":"8","step":8,"text":"Slow release...","duration_seconds":4,"action":"exhale"}]'::JSONB,
     'pulse', ARRAY['morning', 'afternoon', 'energy'], 'energizing', true, 4),

    -- Grounding Exercises
    ('5-4-3-2-1-express', '5-4-3-2-1-express', 'grounding', '5-4-3-2-1 Express', 'Quick sensory grounding technique', 30,
     '[{"id":"1","step":1,"text":"Name 5 things you can see","duration_seconds":6,"action":"observe"},{"id":"2","step":2,"text":"Name 4 things you can touch","duration_seconds":6,"action":"observe"},{"id":"3","step":3,"text":"Name 3 things you can hear","duration_seconds":6,"action":"observe"},{"id":"4","step":4,"text":"Name 2 things you can smell","duration_seconds":6,"action":"observe"},{"id":"5","step":5,"text":"Name 1 thing you can taste","duration_seconds":6,"action":"observe"}]'::JSONB,
     'countdown', ARRAY['anxiety', 'stress', 'grounding'], 'calming', false, 10),

    ('name-3-things', 'name-3-things', 'grounding', 'Name 3 Things', 'Quick cognitive reset', 15,
     '[{"id":"1","step":1,"text":"Name 3 blue things around you","duration_seconds":5,"action":"observe"},{"id":"2","step":2,"text":"Name 3 sounds you hear","duration_seconds":5,"action":"observe"},{"id":"3","step":3,"text":"Take a breath. You''re here.","duration_seconds":5,"action":"inhale"}]'::JSONB,
     'countdown', ARRAY['anxiety', 'stress', 'break'], 'calming', false, 11),

    ('body-scan-flash', 'body-scan-flash', 'grounding', 'Body Scan Flash', '15-second body awareness', 15,
     '[{"id":"1","step":1,"text":"Notice your feet on the ground","duration_seconds":5,"action":"observe"},{"id":"2","step":2,"text":"Relax your shoulders","duration_seconds":5,"action":"observe"},{"id":"3","step":3,"text":"Soften your jaw","duration_seconds":5,"action":"observe"}]'::JSONB,
     'body_scan', ARRAY['stress', 'tension', 'break'], 'calming', false, 12),

    -- Movement Micro-Breaks
    ('desk-stretch', 'desk-stretch', 'movement', 'Desk Stretch', '30-second shoulder and neck release', 30,
     '[{"id":"1","step":1,"text":"Roll shoulders back 3 times","duration_seconds":8,"action":"move"},{"id":"2","step":2,"text":"Roll shoulders forward 3 times","duration_seconds":8,"action":"move"},{"id":"3","step":3,"text":"Gently tilt head left","duration_seconds":7,"action":"move"},{"id":"4","step":4,"text":"Gently tilt head right","duration_seconds":7,"action":"move"}]'::JSONB,
     NULL, ARRAY['break', 'afternoon', 'tension'], 'neutral', false, 20),

    ('posture-reset', 'posture-reset', 'movement', 'Posture Reset', '15-second spinal alignment', 15,
     '[{"id":"1","step":1,"text":"Sit up tall, crown toward ceiling","duration_seconds":5,"action":"move"},{"id":"2","step":2,"text":"Pull shoulders back and down","duration_seconds":5,"action":"move"},{"id":"3","step":3,"text":"Breathe and hold this posture","duration_seconds":5,"action":"inhale"}]'::JSONB,
     NULL, ARRAY['break', 'work', 'posture'], 'neutral', false, 21),

    ('hand-massage', 'hand-massage', 'movement', 'Hand Massage', '20-second tension release', 20,
     '[{"id":"1","step":1,"text":"Press thumb into opposite palm","duration_seconds":5,"action":"move"},{"id":"2","step":2,"text":"Massage in circles","duration_seconds":5,"action":"move"},{"id":"3","step":3,"text":"Switch hands","duration_seconds":5,"action":"move"},{"id":"4","step":4,"text":"Shake both hands gently","duration_seconds":5,"action":"move"}]'::JSONB,
     NULL, ARRAY['break', 'tension', 'stress'], 'calming', false, 22),

    -- Transition Rituals
    ('work-home-shift', 'work-home-shift', 'transition', 'Work → Home', '60-second mental shift exercise', 60,
     '[{"id":"1","step":1,"text":"Close your eyes. Work is done.","duration_seconds":10,"action":"observe"},{"id":"2","step":2,"text":"Take 3 deep breaths...","duration_seconds":15,"action":"inhale"},{"id":"3","step":3,"text":"Think of one good thing from today","duration_seconds":10,"action":"observe"},{"id":"4","step":4,"text":"Set one intention for your evening","duration_seconds":15,"action":"observe"},{"id":"5","step":5,"text":"Open your eyes. Welcome home.","duration_seconds":10,"action":"observe"}]'::JSONB,
     'breathing_circle', ARRAY['evening', 'transition', 'work'], 'calming', false, 30),

    ('meeting-prep', 'meeting-prep', 'transition', 'Meeting Prep', '30-second centering before calls', 30,
     '[{"id":"1","step":1,"text":"Take a centering breath","duration_seconds":8,"action":"inhale"},{"id":"2","step":2,"text":"Set your intention: Be present","duration_seconds":7,"action":"observe"},{"id":"3","step":3,"text":"Release any tension","duration_seconds":8,"action":"exhale"},{"id":"4","step":4,"text":"You''re ready. Let''s go.","duration_seconds":7,"action":"observe"}]'::JSONB,
     'pulse', ARRAY['pre_meeting', 'work', 'focus'], 'neutral', false, 31),

    ('sleep-wind-down', 'sleep-wind-down', 'transition', 'Sleep Wind-Down', '45-second pre-sleep relaxation', 45,
     '[{"id":"1","step":1,"text":"Close your eyes","duration_seconds":5,"action":"observe"},{"id":"2","step":2,"text":"Breathe in peace...","duration_seconds":8,"action":"inhale"},{"id":"3","step":3,"text":"Release the day...","duration_seconds":8,"action":"exhale"},{"id":"4","step":4,"text":"Let your body sink into the bed","duration_seconds":8,"action":"observe"},{"id":"5","step":5,"text":"Breathe in calm...","duration_seconds":8,"action":"inhale"},{"id":"6","step":6,"text":"Sleep well...","duration_seconds":8,"action":"exhale"}]'::JSONB,
     'breathing_circle', ARRAY['evening', 'sleep', 'transition'], 'calming', false, 32),

    -- Gratitude Moments
    ('gratitude-moment', 'gratitude-moment', 'gratitude', 'Gratitude Moment', 'Quick appreciation practice', 20,
     '[{"id":"1","step":1,"text":"Think of one thing you''re grateful for","duration_seconds":10,"action":"observe"},{"id":"2","step":2,"text":"Feel that gratitude in your heart","duration_seconds":5,"action":"observe"},{"id":"3","step":3,"text":"Smile. Carry this with you.","duration_seconds":5,"action":"observe"}]'::JSONB,
     'pulse', ARRAY['morning', 'evening', 'gratitude'], 'energizing', false, 40)

ON CONFLICT (slug) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    duration_seconds = EXCLUDED.duration_seconds,
    instructions = EXCLUDED.instructions,
    animation_type = EXCLUDED.animation_type,
    suggested_contexts = EXCLUDED.suggested_contexts,
    energy_effect = EXCLUDED.energy_effect,
    is_premium = EXCLUDED.is_premium,
    sort_order = EXCLUDED.sort_order,
    updated_at = NOW();
