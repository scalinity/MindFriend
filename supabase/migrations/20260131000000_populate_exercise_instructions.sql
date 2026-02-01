-- Migration: Populate exercise instructions for immersive players
-- This adds structured instructions to existing exercises for type-specific players

-- =============================================================================
-- BREATHING EXERCISES
-- =============================================================================

-- Box Breathing (4-4-4-4)
UPDATE exercises
SET instructions = '{
  "type": "breathing",
  "data": {
    "pattern": {
      "inhaleSeconds": 4,
      "holdInSeconds": 4,
      "exhaleSeconds": 4,
      "holdOutSeconds": 4,
      "name": "Box Breathing"
    },
    "cycles": 8,
    "introText": "Find a comfortable seated position. Close your eyes or soften your gaze. We will breathe in a box pattern - inhale, hold, exhale, hold - each for 4 seconds.",
    "outroText": "Slowly return to normal breathing. Notice how you feel. Take a moment before continuing with your day."
  }
}'::jsonb
WHERE type = 'breathing' AND title ILIKE '%box%';

-- 4-7-8 Breathing
UPDATE exercises
SET instructions = '{
  "type": "breathing",
  "data": {
    "pattern": {
      "inhaleSeconds": 4,
      "holdInSeconds": 7,
      "exhaleSeconds": 8,
      "holdOutSeconds": 0,
      "name": "4-7-8 Breathing"
    },
    "cycles": 4,
    "introText": "This technique is deeply calming. Breathe in through your nose for 4 seconds, hold for 7, then exhale slowly through your mouth for 8 seconds.",
    "outroText": "Well done. This practice becomes more effective with regular use. Notice any sense of calm in your body."
  }
}'::jsonb
WHERE type = 'breathing' AND (title ILIKE '%4-7-8%' OR title ILIKE '%relaxation%' OR title ILIKE '%sleep%');

-- Default breathing pattern for others
UPDATE exercises
SET instructions = '{
  "type": "breathing",
  "data": {
    "pattern": {
      "inhaleSeconds": 4,
      "holdInSeconds": 2,
      "exhaleSeconds": 6,
      "holdOutSeconds": 0,
      "name": "Calming Breath"
    },
    "cycles": 6,
    "introText": "Settle into a comfortable position. We will practice slow, deep breaths to activate your relaxation response.",
    "outroText": "Return to natural breathing. Carry this sense of calm with you."
  }
}'::jsonb
WHERE type = 'breathing' AND instructions IS NULL;

-- =============================================================================
-- MEDITATION EXERCISES
-- =============================================================================

-- Body Scan Meditation
UPDATE exercises
SET instructions = '{
  "type": "meditation",
  "data": {
    "segments": [
      {"timestamp_seconds": 0, "text": "Find a comfortable position, either sitting or lying down. Close your eyes and take three deep breaths.", "segment_type": "intro"},
      {"timestamp_seconds": 30, "text": "Bring your attention to the top of your head. Notice any sensations there - warmth, tingling, or tension.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 60, "text": "Move your awareness down to your forehead and face. Let the muscles around your eyes and jaw soften.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 90, "text": "Notice your neck and shoulders. These often hold tension. Simply observe without trying to change anything.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 120, "text": "Bring attention to your arms and hands. Feel the weight of your arms, the sensation in your fingertips.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 150, "text": "Move your awareness to your chest and heart area. Notice your breath expanding this space.", "segment_type": "breathingGuide"},
      {"timestamp_seconds": 180, "text": "Scan down through your abdomen. Feel it rise and fall gently with each breath.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 210, "text": "Bring awareness to your hips and pelvis, then down through your thighs.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 240, "text": "Notice your knees, lower legs, and finally your feet. Feel the connection to the ground.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 270, "text": "Now expand your awareness to your whole body. Feel it as one integrated whole, breathing and alive.", "segment_type": "integration"},
      {"timestamp_seconds": 300, "text": "Take a few more breaths here. When you are ready, slowly begin to move your fingers and toes.", "segment_type": "closing"}
    ]
  }
}'::jsonb
WHERE type = 'meditation' AND title ILIKE '%body scan%';

-- Mindfulness Meditation
UPDATE exercises
SET instructions = '{
  "type": "meditation",
  "data": {
    "segments": [
      {"timestamp_seconds": 0, "text": "Settle into a comfortable position. Let your eyes close gently.", "segment_type": "intro"},
      {"timestamp_seconds": 20, "text": "Begin by noticing your breath. Do not try to change it, just observe its natural rhythm.", "segment_type": "breathingGuide"},
      {"timestamp_seconds": 60, "text": "When your mind wanders - and it will - simply notice that, and gently return to the breath.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 120, "text": "Each time you notice your mind has wandered and bring it back, you are strengthening your mindfulness.", "segment_type": "encouragement"},
      {"timestamp_seconds": 180, "text": "There is no perfect way to do this. Simply be present with whatever arises.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 240, "text": "Continue observing your breath. In... and out... in... and out.", "segment_type": "breathingGuide"},
      {"timestamp_seconds": 300, "text": "Gently begin to widen your awareness. Notice sounds around you, the feeling of your body.", "segment_type": "closing"}
    ]
  }
}'::jsonb
WHERE type = 'meditation' AND (title ILIKE '%mindful%' OR title ILIKE '%awareness%');

-- Default meditation instructions
UPDATE exercises
SET instructions = '{
  "type": "meditation",
  "data": {
    "segments": [
      {"timestamp_seconds": 0, "text": "Find a quiet, comfortable place. Close your eyes and take a few deep breaths.", "segment_type": "intro"},
      {"timestamp_seconds": 30, "text": "Allow your breathing to return to its natural rhythm. Simply observe each inhale and exhale.", "segment_type": "breathingGuide"},
      {"timestamp_seconds": 90, "text": "If thoughts arise, acknowledge them without judgment and return your focus to your breath.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 150, "text": "Continue this gentle practice of noticing and returning.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 240, "text": "Begin to deepen your breath. Slowly bring your awareness back to the room.", "segment_type": "closing"}
    ]
  }
}'::jsonb
WHERE type = 'meditation' AND instructions IS NULL;

-- =============================================================================
-- GROUNDING EXERCISES
-- =============================================================================

-- 5-4-3-2-1 Grounding
UPDATE exercises
SET instructions = '{
  "type": "grounding",
  "data": {
    "technique": "5-4-3-2-1",
    "prompts": [
      {"sense": "sight", "text": "Look around and name 5 things you can see. Notice colors, shapes, and details.", "count": 5},
      {"sense": "touch", "text": "Notice 4 things you can physically feel. The texture of your clothes, the surface beneath you.", "count": 4},
      {"sense": "hearing", "text": "Listen carefully for 3 sounds you can hear. Near or far, loud or soft.", "count": 3},
      {"sense": "smell", "text": "Identify 2 things you can smell. If needed, move closer to something or recall a familiar scent.", "count": 2},
      {"sense": "taste", "text": "Notice 1 thing you can taste. Perhaps the lingering taste in your mouth or take a sip of water.", "count": 1}
    ]
  }
}'::jsonb
WHERE type = 'grounding' AND (title ILIKE '%5-4-3-2-1%' OR title ILIKE '%senses%' OR title ILIKE '%sensory%');

-- Default grounding instructions
UPDATE exercises
SET instructions = '{
  "type": "grounding",
  "data": {
    "technique": "present_moment",
    "prompts": [
      {"sense": "touch", "text": "Feel your feet firmly on the ground. Press them down and notice the sensation.", "count": null},
      {"sense": "sight", "text": "Look around slowly. Name three objects you see.", "count": 3},
      {"sense": "hearing", "text": "What sounds can you hear right now? Just notice without judgment.", "count": null},
      {"sense": "touch", "text": "Feel your hands. Rub them together slowly. Notice the warmth.", "count": null}
    ]
  }
}'::jsonb
WHERE type = 'grounding' AND instructions IS NULL;

-- =============================================================================
-- JOURNALING EXERCISES
-- =============================================================================

-- Gratitude Journal
UPDATE exercises
SET instructions = '{
  "type": "journaling",
  "data": {
    "prompts": [
      {"text": "What are three things you are grateful for today, no matter how small?", "category": "gratitude"},
      {"text": "Describe one person who made a positive difference in your life recently.", "category": "relationships"},
      {"text": "What is one thing about yourself that you appreciate?", "category": "self-compassion"}
    ],
    "reflection_questions": [
      "How did writing these things down affect how you feel?",
      "Is there anything you can do to express gratitude to someone today?"
    ]
  }
}'::jsonb
WHERE type = 'journaling' AND title ILIKE '%gratitude%';

-- Mood Reflection Journal
UPDATE exercises
SET instructions = '{
  "type": "journaling",
  "data": {
    "prompts": [
      {"text": "How are you feeling right now? Describe your emotions without judgment.", "category": "emotions"},
      {"text": "What might be contributing to how you feel today?", "category": "awareness"},
      {"text": "What is one small thing you could do to take care of yourself right now?", "category": "self-care"}
    ],
    "reflection_questions": [
      "What patterns do you notice in your emotions over time?",
      "How might naming your feelings help you process them?"
    ]
  }
}'::jsonb
WHERE type = 'journaling' AND (title ILIKE '%mood%' OR title ILIKE '%emotion%' OR title ILIKE '%feeling%');

-- Default journaling instructions
UPDATE exercises
SET instructions = '{
  "type": "journaling",
  "data": {
    "prompts": [
      {"text": "What is on your mind right now? Write freely without censoring yourself.", "category": "freewrite"},
      {"text": "What would you like to let go of today?", "category": "release"},
      {"text": "What is one intention you can set for the rest of your day?", "category": "intention"}
    ],
    "reflection_questions": [
      "Did anything surprise you as you wrote?",
      "How do you feel now compared to when you started?"
    ]
  }
}'::jsonb
WHERE type = 'journaling' AND instructions IS NULL;

-- =============================================================================
-- MOVEMENT EXERCISES
-- =============================================================================

-- Morning Stretch
UPDATE exercises
SET instructions = '{
  "type": "movement",
  "data": {
    "movements": [
      {"name": "Neck Rolls", "description": "Slowly roll your head in a circle, 3 times clockwise, then 3 times counterclockwise. Move gently and stop if you feel any pain.", "duration_seconds": 30, "is_rest_period": false, "image_url": null},
      {"name": "Shoulder Shrugs", "description": "Raise both shoulders up toward your ears. Hold for 3 seconds, then release. Repeat 5 times.", "duration_seconds": 25, "is_rest_period": false, "image_url": null},
      {"name": "Brief Pause", "description": "Take two deep breaths before the next movement.", "duration_seconds": 10, "is_rest_period": true, "image_url": null},
      {"name": "Side Stretch", "description": "Reach your right arm up and over, stretching to the left. Hold for 15 seconds. Repeat on the other side.", "duration_seconds": 35, "is_rest_period": false, "image_url": null},
      {"name": "Forward Fold", "description": "Slowly bend forward from the hips, letting your arms hang. Keep knees slightly bent. Hold and breathe.", "duration_seconds": 30, "is_rest_period": false, "image_url": null},
      {"name": "Gentle Twist", "description": "Standing or seated, gently twist your torso to the right, then to the left. Hold each side for 10 seconds.", "duration_seconds": 25, "is_rest_period": false, "image_url": null},
      {"name": "Rest", "description": "Stand or sit quietly. Notice how your body feels after these stretches.", "duration_seconds": 15, "is_rest_period": true, "image_url": null}
    ]
  }
}'::jsonb
WHERE type = 'movement' AND (title ILIKE '%stretch%' OR title ILIKE '%morning%');

-- Tension Release
UPDATE exercises
SET instructions = '{
  "type": "movement",
  "data": {
    "movements": [
      {"name": "Shoulder Release", "description": "Tense your shoulders up to your ears. Hold for 5 seconds. Then release completely. Notice the difference.", "duration_seconds": 20, "is_rest_period": false, "image_url": null},
      {"name": "Fist Clench", "description": "Make tight fists with both hands. Squeeze for 5 seconds. Then release and spread your fingers wide.", "duration_seconds": 15, "is_rest_period": false, "image_url": null},
      {"name": "Leg Tense", "description": "Tense your leg muscles by pressing your feet into the floor. Hold for 5 seconds. Release.", "duration_seconds": 15, "is_rest_period": false, "image_url": null},
      {"name": "Pause", "description": "Breathe naturally and notice any changes in your body.", "duration_seconds": 15, "is_rest_period": true, "image_url": null},
      {"name": "Full Body Tense", "description": "Tense every muscle you can - face, shoulders, arms, core, legs. Hold for 5 seconds. Then release everything at once.", "duration_seconds": 20, "is_rest_period": false, "image_url": null},
      {"name": "Final Rest", "description": "Let your whole body relax. Breathe deeply and enjoy the feeling of release.", "duration_seconds": 30, "is_rest_period": true, "image_url": null}
    ]
  }
}'::jsonb
WHERE type = 'movement' AND (title ILIKE '%tension%' OR title ILIKE '%release%' OR title ILIKE '%relax%');

-- Default movement instructions
UPDATE exercises
SET instructions = '{
  "type": "movement",
  "data": {
    "movements": [
      {"name": "Deep Breathing", "description": "Stand or sit comfortably. Take 5 slow, deep breaths to center yourself.", "duration_seconds": 30, "is_rest_period": false, "image_url": null},
      {"name": "Gentle Movement", "description": "Follow along with the exercise. Move at your own pace and listen to your body.", "duration_seconds": 120, "is_rest_period": false, "image_url": null},
      {"name": "Cool Down", "description": "Slow your movements and return to stillness. Take a few final deep breaths.", "duration_seconds": 30, "is_rest_period": true, "image_url": null}
    ]
  }
}'::jsonb
WHERE type = 'movement' AND instructions IS NULL;

-- =============================================================================
-- VERIFICATION
-- =============================================================================

-- Log the number of exercises updated per type
DO $$
DECLARE
    breathing_count INT;
    meditation_count INT;
    grounding_count INT;
    journaling_count INT;
    movement_count INT;
BEGIN
    SELECT COUNT(*) INTO breathing_count FROM exercises WHERE type = 'breathing' AND instructions IS NOT NULL;
    SELECT COUNT(*) INTO meditation_count FROM exercises WHERE type = 'meditation' AND instructions IS NOT NULL;
    SELECT COUNT(*) INTO grounding_count FROM exercises WHERE type = 'grounding' AND instructions IS NOT NULL;
    SELECT COUNT(*) INTO journaling_count FROM exercises WHERE type = 'journaling' AND instructions IS NOT NULL;
    SELECT COUNT(*) INTO movement_count FROM exercises WHERE type = 'movement' AND instructions IS NOT NULL;

    RAISE NOTICE 'Exercise instructions populated:';
    RAISE NOTICE '  Breathing: % exercises', breathing_count;
    RAISE NOTICE '  Meditation: % exercises', meditation_count;
    RAISE NOTICE '  Grounding: % exercises', grounding_count;
    RAISE NOTICE '  Journaling: % exercises', journaling_count;
    RAISE NOTICE '  Movement: % exercises', movement_count;
END $$;
