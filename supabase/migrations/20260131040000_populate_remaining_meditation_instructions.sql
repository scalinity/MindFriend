-- Populate meditation instructions for the 9 remaining exercises
-- These will be used for TTS audio generation with Google Cloud Chirp 3 HD voices

-- 1. Loving Kindness
UPDATE exercises SET instructions = '{
  "type": "meditation",
  "data": {
    "segments": [
      {"timestamp_seconds": 0, "text": "Find a comfortable seated position. Close your eyes and take three slow, deep breaths.", "segment_type": "intro"},
      {"timestamp_seconds": 30, "text": "Bring your attention to your heart center. Imagine a warm, glowing light there.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 60, "text": "Now, silently repeat these phrases to yourself: May I be happy. May I be healthy. May I be safe. May I live with ease.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 120, "text": "Feel the warmth of these wishes for yourself. You deserve kindness and love.", "segment_type": "encouragement"},
      {"timestamp_seconds": 150, "text": "Now think of someone you love. Picture them clearly and send them these same wishes: May you be happy. May you be healthy. May you be safe.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 210, "text": "Expand this circle of loving kindness to include all beings everywhere. May all beings be happy. May all beings be free from suffering.", "segment_type": "integration"},
      {"timestamp_seconds": 270, "text": "Rest in this feeling of boundless love and compassion. Let it fill your entire being.", "segment_type": "encouragement"},
      {"timestamp_seconds": 300, "text": "Gently bring your awareness back to your breath. When you are ready, slowly open your eyes.", "segment_type": "closing"}
    ]
  }
}'::jsonb
WHERE id = 'ecd91710-1daf-4f06-8282-d00299690265';

-- 2. Walking Meditation
UPDATE exercises SET instructions = '{
  "type": "meditation",
  "data": {
    "segments": [
      {"timestamp_seconds": 0, "text": "Stand still with your feet hip-width apart. Feel the ground beneath you. Take a few deep breaths.", "segment_type": "intro"},
      {"timestamp_seconds": 30, "text": "Bring all your attention to your feet. Notice the sensations where they meet the floor.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 60, "text": "Very slowly, shift your weight to your left foot. Notice how this feels.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 90, "text": "Lift your right foot slowly. Feel the heel leave the ground, then the toes. Move it forward and place it down mindfully.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 120, "text": "Continue walking slowly, one step at a time. Lifting, moving, placing. Each step a meditation.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 180, "text": "If your mind wanders, simply return your attention to the sensations in your feet.", "segment_type": "encouragement"},
      {"timestamp_seconds": 240, "text": "Notice your surroundings without losing awareness of each step. You are fully present in this moment.", "segment_type": "integration"},
      {"timestamp_seconds": 300, "text": "Gradually come to a stop. Stand still for a moment, feeling grounded and calm.", "segment_type": "closing"}
    ]
  }
}'::jsonb
WHERE id = 'e1494309-ef98-41c0-ac38-1c8a2a74d332';

-- 3. Morning Intention
UPDATE exercises SET instructions = '{
  "type": "meditation",
  "data": {
    "segments": [
      {"timestamp_seconds": 0, "text": "Good morning. Before the day begins, take this moment to arrive fully in the present.", "segment_type": "intro"},
      {"timestamp_seconds": 30, "text": "Take three deep breaths. With each exhale, let go of any lingering drowsiness.", "segment_type": "breathingGuide"},
      {"timestamp_seconds": 60, "text": "Notice how it feels to be alive in this moment. Your body is awake. Your mind is becoming clear.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 90, "text": "Think of one thing you are grateful for today. Let that gratitude warm your heart.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 120, "text": "Now set an intention for today. What quality do you want to bring into your day? Perhaps patience, kindness, or focus.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 180, "text": "Visualize yourself moving through the day embodying this intention. See yourself responding to challenges with this quality.", "segment_type": "visualization"},
      {"timestamp_seconds": 240, "text": "Take one more deep breath and affirm: Today, I choose this intention. I am ready for whatever comes.", "segment_type": "encouragement"},
      {"timestamp_seconds": 270, "text": "Slowly open your eyes. Carry this intention with you as you begin your day.", "segment_type": "closing"}
    ]
  }
}'::jsonb
WHERE id = '9166ec5a-9c10-4c29-a33a-fef6eb90f470';

-- 4. Gratitude Meditation
UPDATE exercises SET instructions = '{
  "type": "meditation",
  "data": {
    "segments": [
      {"timestamp_seconds": 0, "text": "Settle into a comfortable position and close your eyes. Let your breath become slow and natural.", "segment_type": "intro"},
      {"timestamp_seconds": 30, "text": "Begin by noticing your body. Feel gratitude for your breath, your heartbeat, the gift of being alive.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 60, "text": "Think of one small thing you are grateful for today. Perhaps a warm cup of coffee, a kind word, or a moment of quiet.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 90, "text": "Let this feeling of appreciation grow in your chest. Notice how gratitude feels in your body.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 120, "text": "Now think of a person you are grateful for. Picture their face and silently thank them.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 180, "text": "Expand your gratitude to include your life circumstances. Even challenges can teach us something valuable.", "segment_type": "integration"},
      {"timestamp_seconds": 240, "text": "Let this sense of abundance and thankfulness fill your entire being. You have so much to appreciate.", "segment_type": "encouragement"},
      {"timestamp_seconds": 300, "text": "Carry this gratitude with you. When you are ready, gently open your eyes.", "segment_type": "closing"}
    ]
  }
}'::jsonb
WHERE id = 'bad034b7-e0fa-4f46-a985-35a315f85497';

-- 5. Self-Compassion
UPDATE exercises SET instructions = '{
  "type": "meditation",
  "data": {
    "segments": [
      {"timestamp_seconds": 0, "text": "Find a comfortable position. Close your eyes and bring a gentle awareness to how you are feeling.", "segment_type": "intro"},
      {"timestamp_seconds": 30, "text": "Place your hand over your heart. Feel its warmth and the gentle rhythm of your heartbeat.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 60, "text": "Think of a difficulty you are facing. Acknowledge it without judgment. This is a moment of struggle.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 90, "text": "Remind yourself: Struggle is part of being human. Everyone experiences pain and difficulty.", "segment_type": "encouragement"},
      {"timestamp_seconds": 120, "text": "Now offer yourself the same kindness you would give a good friend. What would you say to them?", "segment_type": "mindfulness"},
      {"timestamp_seconds": 180, "text": "Repeat silently: May I be kind to myself. May I give myself the compassion I need.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 240, "text": "Feel yourself held in compassion. You are doing the best you can. That is enough.", "segment_type": "encouragement"},
      {"timestamp_seconds": 300, "text": "Take a deep breath and release your hand. Carry this self-compassion with you.", "segment_type": "closing"}
    ]
  }
}'::jsonb
WHERE id = '9db2cd7d-1a2b-4686-a22b-62d0b9f6a2e9';

-- 6. Visualization Journey
UPDATE exercises SET instructions = '{
  "type": "meditation",
  "data": {
    "segments": [
      {"timestamp_seconds": 0, "text": "Close your eyes and take several deep breaths. Allow your body to relax completely.", "segment_type": "intro"},
      {"timestamp_seconds": 30, "text": "Imagine yourself in a peaceful natural place. Perhaps a quiet beach, a sunlit forest, or a mountain meadow.", "segment_type": "visualization"},
      {"timestamp_seconds": 60, "text": "Look around this place. Notice the colors, the shapes, the light. Make it vivid in your mind.", "segment_type": "visualization"},
      {"timestamp_seconds": 90, "text": "Now notice the sounds. Perhaps gentle waves, rustling leaves, or birdsong. Let these sounds soothe you.", "segment_type": "visualization"},
      {"timestamp_seconds": 120, "text": "Feel the temperature on your skin. Notice any scents in the air. Engage all your senses.", "segment_type": "visualization"},
      {"timestamp_seconds": 180, "text": "Find a comfortable spot in this peaceful place and sit down. You are completely safe here.", "segment_type": "visualization"},
      {"timestamp_seconds": 240, "text": "Absorb the calm and beauty of this place. Let it fill you with peace and tranquility.", "segment_type": "integration"},
      {"timestamp_seconds": 300, "text": "Slowly begin to return. Know that you can visit this place anytime. Gently open your eyes.", "segment_type": "closing"}
    ]
  }
}'::jsonb
WHERE id = '5d31c6f3-90b7-4baa-ac70-0ce6232365c4';

-- 7. Deep Relaxation
UPDATE exercises SET instructions = '{
  "type": "meditation",
  "data": {
    "segments": [
      {"timestamp_seconds": 0, "text": "Lie down on your back with your arms at your sides. Close your eyes and take three deep breaths.", "segment_type": "intro"},
      {"timestamp_seconds": 30, "text": "Bring your attention to your feet. Curl your toes tightly for five seconds, then release. Feel the relaxation.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 60, "text": "Move to your calves and thighs. Tense these muscles, hold, and release. Let them become heavy and relaxed.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 90, "text": "Tighten your stomach and lower back. Hold the tension, then release with a sigh. Feel your body sinking into the surface beneath you.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 120, "text": "Make fists with your hands and tense your arms. Hold, and release. Let your arms feel heavy and warm.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 150, "text": "Raise your shoulders toward your ears. Hold this tension, then let them drop. Feel the release in your neck and shoulders.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 180, "text": "Scrunch up your face tightly. Hold, and release. Let all the small muscles of your face soften and relax.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 210, "text": "Now scan your entire body. Notice the deep relaxation in every muscle. You are completely at ease.", "segment_type": "integration"},
      {"timestamp_seconds": 270, "text": "Rest here for a few more breaths. When you are ready, slowly begin to move your fingers and toes.", "segment_type": "closing"}
    ]
  }
}'::jsonb
WHERE id = '9ecbc163-6279-46f7-bd57-f160ba8562d1';

-- 8. Focus Meditation
UPDATE exercises SET instructions = '{
  "type": "meditation",
  "data": {
    "segments": [
      {"timestamp_seconds": 0, "text": "Sit in a comfortable but alert position. Close your eyes and take a few settling breaths.", "segment_type": "intro"},
      {"timestamp_seconds": 30, "text": "Choose a single point of focus. This could be your breath at the nostrils, or a simple word like calm or peace.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 60, "text": "Bring all your attention to this focus point. Notice every subtle detail of it.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 90, "text": "When your mind wanders - and it will - simply notice this without judgment. Gently return to your focus.", "segment_type": "encouragement"},
      {"timestamp_seconds": 120, "text": "Each time you return your attention, you are strengthening your ability to concentrate. This is the practice.", "segment_type": "encouragement"},
      {"timestamp_seconds": 180, "text": "Continue focusing. Let everything else fade into the background. There is only this one point of attention.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 240, "text": "Notice the quality of your attention now. It may feel sharper, more stable. This is your mind becoming focused.", "segment_type": "integration"},
      {"timestamp_seconds": 300, "text": "Slowly release your focus. Take a deep breath and open your eyes, carrying this clarity with you.", "segment_type": "closing"}
    ]
  }
}'::jsonb
WHERE id = '9083ea18-e310-4ccf-8220-57ebc1ba3cdc';

-- 9. Evening Wind Down
UPDATE exercises SET instructions = '{
  "type": "meditation",
  "data": {
    "segments": [
      {"timestamp_seconds": 0, "text": "The day is complete. Find a comfortable position and close your eyes. Let your body begin to unwind.", "segment_type": "intro"},
      {"timestamp_seconds": 30, "text": "Take three slow, deep breaths. With each exhale, release any remaining tension from the day.", "segment_type": "breathingGuide"},
      {"timestamp_seconds": 60, "text": "Without judgment, briefly review your day. Acknowledge what you accomplished and what you learned.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 90, "text": "If any worries arise about tomorrow, gently set them aside. Tomorrow will take care of itself.", "segment_type": "mindfulness"},
      {"timestamp_seconds": 120, "text": "Scan your body from head to toe. Notice any places holding tension and consciously relax them.", "segment_type": "bodyAwareness"},
      {"timestamp_seconds": 180, "text": "Let your breath become slow and natural. Feel your body becoming heavier and more relaxed.", "segment_type": "breathingGuide"},
      {"timestamp_seconds": 240, "text": "Imagine all the stress and activity of the day draining away, leaving you peaceful and still.", "segment_type": "visualization"},
      {"timestamp_seconds": 300, "text": "You have done enough today. Rest now. Allow yourself to drift toward peaceful sleep.", "segment_type": "closing"}
    ]
  }
}'::jsonb
WHERE id = 'd175d71b-5db3-44c5-be62-9849a97b7db6';
