-- Migration: Seed remaining pathway phases (breakup, grief, new_parent, relocation, health_diagnosis)
-- Created: 2026-01-25
-- Description: Adds 20 phases (4 per pathway) with daily themes, prompts, and milestones

-- ============================================================================
-- BREAKUP PATHWAY (70 days total)
-- Phase 1: Accept (21 days) - Processing the end
-- Phase 2: Release (21 days) - Letting go
-- Phase 3: Rediscover (14 days) - Finding yourself again
-- Phase 4: Rebuild (14 days) - Moving forward
-- ============================================================================

-- Phase 1: Accept (21 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'breakup'),
    1,
    'Accept',
    'Acknowledging the relationship has ended and processing initial emotions',
    21,
    ARRAY['Accept what happened', 'Allow yourself to grieve', 'Resist the urge to contact them', 'Lean on your support system'],
    '[
        {"day": 1, "title": "The End of a Chapter", "message": "Today marks the beginning of your healing journey. Its normal to feel overwhelmed.", "focus_area": "emotional_acceptance"},
        {"day": 2, "title": "Feeling Everything", "message": "Allow yourself to feel the full spectrum of emotions without judgment.", "focus_area": "emotional_processing"},
        {"day": 3, "title": "No Contact Strength", "message": "Resisting contact is one of the hardest but most important steps in healing.", "focus_area": "boundaries"},
        {"day": 4, "title": "Your Support Circle", "message": "Reach out to friends and family. You do not have to go through this alone.", "focus_area": "social_connection"},
        {"day": 5, "title": "Self-Compassion", "message": "Be as kind to yourself as you would be to a close friend going through this.", "focus_area": "self_care"},
        {"day": 6, "title": "Processing Memories", "message": "Memories will surface. Acknowledge them without dwelling or romanticizing.", "focus_area": "emotional_processing"},
        {"day": 7, "title": "First Week Complete", "message": "You made it through the hardest week. That takes real strength.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Understanding Grief", "message": "Grief is not linear. Some days will feel harder than others, and that is okay.", "focus_area": "emotional_acceptance"},
        {"day": 9, "title": "Resisting Idealization", "message": "Our minds can romanticize the past. Try to see the relationship clearly.", "focus_area": "cognitive_reframing"},
        {"day": 10, "title": "Physical Self-Care", "message": "Your body holds stress. Movement, rest, and nourishment matter now more than ever.", "focus_area": "self_care"},
        {"day": 11, "title": "What You Learned", "message": "Every relationship teaches us something about ourselves and what we need.", "focus_area": "reflection"},
        {"day": 12, "title": "Avoiding Rebounds", "message": "Resist the urge to fill the void with someone new. Healing comes first.", "focus_area": "boundaries"},
        {"day": 13, "title": "Your Identity", "message": "You are whole on your own. Rediscover who you are outside the relationship.", "focus_area": "self_discovery"},
        {"day": 14, "title": "Two Weeks Strong", "message": "Every day without contact is a day closer to healing. Keep going.", "focus_area": "milestone_celebration"},
        {"day": 15, "title": "Future Self", "message": "Imagine who you will be six months from now. Stronger, wiser, and whole.", "focus_area": "future_focus"},
        {"day": 16, "title": "Feeling Lonely", "message": "Loneliness is temporary. Being alone and being lonely are different things.", "focus_area": "emotional_processing"},
        {"day": 17, "title": "Digital Boundaries", "message": "Consider unfollowing or muting them on social media to protect your peace.", "focus_area": "boundaries"},
        {"day": 18, "title": "Gratitude Practice", "message": "Even in pain, there are things to be grateful for. Start small.", "focus_area": "cognitive_reframing"},
        {"day": 19, "title": "Your Worth", "message": "Your worth is not determined by whether someone chose to stay or go.", "focus_area": "self_compassion"},
        {"day": 20, "title": "Almost Three Weeks", "message": "You are building new neural pathways. Each day gets a little easier.", "focus_area": "milestone_celebration"},
        {"day": 21, "title": "Phase One Complete", "message": "You have accepted what happened. Now you are ready to start letting go.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'Write about how you are feeling right now without filtering or censoring yourself',
        'What do you miss most? What do you not miss?',
        'List three things you are grateful for today, even if they are small',
        'What have you learned about yourself from this relationship?',
        'Write a letter to your ex that you will never send, saying everything you need to say',
        'Describe your ideal future relationship. What will be different?',
        'What boundaries do you need to set for yourself right now?',
        'Write about a moment when you felt truly yourself, independent of the relationship',
        'What fears are coming up for you? Name them without judgment',
        'List five things you can do this week to take care of yourself',
        'What patterns from this relationship do you want to break?',
        'Write about who you want to become on the other side of this'
    ],
    '[
        {"key": "first_week_no_contact", "name": "7 Days Strong", "criteria": "day >= 7"},
        {"key": "two_weeks_no_contact", "name": "14 Days of Healing", "criteria": "day >= 14"},
        {"key": "phase_one_complete", "name": "Acceptance Phase Complete", "criteria": "day >= 21"}
    ]'::jsonb
);

-- Phase 2: Release (21 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'breakup'),
    2,
    'Release',
    'Actively letting go of the relationship and what could have been',
    21,
    ARRAY['Process anger and resentment', 'Release expectations and fantasies', 'Forgive yourself and them', 'Create new routines'],
    '[
        {"day": 1, "title": "Beginning Release", "message": "Letting go is an active choice you make every day, not a one-time event.", "focus_area": "emotional_processing"},
        {"day": 2, "title": "Anger is Valid", "message": "Anger is a natural part of grief. Allow yourself to feel it safely.", "focus_area": "emotional_acceptance"},
        {"day": 3, "title": "What Could Have Been", "message": "Grieve the future you imagined, then release it. It was never guaranteed.", "focus_area": "cognitive_reframing"},
        {"day": 4, "title": "Forgiveness Begins", "message": "Forgiveness is for you, not them. It releases you from carrying the weight.", "focus_area": "emotional_processing"},
        {"day": 5, "title": "New Morning Routine", "message": "Build a new morning that does not revolve around them or checking your phone.", "focus_area": "behavior_change"},
        {"day": 6, "title": "Releasing Blame", "message": "Whether it was your fault, their fault, or both - you can release the blame now.", "focus_area": "self_compassion"},
        {"day": 7, "title": "One Month Milestone", "message": "One month of healing. You are stronger than you realize.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Clearing Space", "message": "Consider putting away photos and mementos that keep you stuck in the past.", "focus_area": "environment"},
        {"day": 9, "title": "Rewriting the Story", "message": "The story of your breakup does not have to be one of failure. It can be one of growth.", "focus_area": "cognitive_reframing"},
        {"day": 10, "title": "Resentment Release", "message": "Holding resentment is like drinking poison and expecting them to suffer.", "focus_area": "emotional_processing"},
        {"day": 11, "title": "Your Own Life", "message": "Start investing energy into your own life, dreams, and goals again.", "focus_area": "future_focus"},
        {"day": 12, "title": "Feeling Lighter", "message": "Notice the small moments when you feel lighter, freer, or at peace.", "focus_area": "mindfulness"},
        {"day": 13, "title": "Forgiving Yourself", "message": "Forgive yourself for any mistakes you made. You did the best you could.", "focus_area": "self_compassion"},
        {"day": 14, "title": "Six Weeks Strong", "message": "Six weeks of choosing yourself. That is something to be proud of.", "focus_area": "milestone_celebration"},
        {"day": 15, "title": "Letting Go Ritual", "message": "Consider a symbolic ritual to mark letting go - burning a letter, releasing balloons, planting something new.", "focus_area": "emotional_processing"},
        {"day": 16, "title": "No Longer Defined", "message": "You are no longer defined by this relationship or its ending.", "focus_area": "identity"},
        {"day": 17, "title": "Creating Joy", "message": "Joy is not something you wait for. Start creating small moments of it.", "focus_area": "behavior_change"},
        {"day": 18, "title": "Choosing Peace", "message": "In moments of anger or sadness, actively choose peace instead.", "focus_area": "emotional_regulation"},
        {"day": 19, "title": "Future You Thanks You", "message": "The person you are becoming is grateful for the work you are doing now.", "focus_area": "future_focus"},
        {"day": 20, "title": "Almost There", "message": "You are almost through the release phase. Feel how far you have come.", "focus_area": "milestone_celebration"},
        {"day": 21, "title": "Release Complete", "message": "You have let go of what was. Now you are ready to rediscover who you are.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What am I still holding onto that I need to release?',
        'Write about the anger you feel. Let it out on paper',
        'What does forgiveness mean to me? Am I ready for it?',
        'Describe the future I imagined with them, then consciously let it go',
        'What new routines or habits do I want to build?',
        'Write a forgiveness letter to yourself',
        'What have I learned about my needs and boundaries?',
        'List everything I am releasing today - resentment, blame, what-ifs',
        'How has my perspective shifted in the past month?',
        'What parts of myself did I lose in the relationship that I want back?',
        'Write about a moment this week when I felt at peace',
        'Who am I without this relationship? Who do I want to be?'
    ],
    '[
        {"key": "one_month_healing", "name": "30 Days of Healing", "criteria": "day >= 7"},
        {"key": "six_weeks_strong", "name": "Six Weeks of Growth", "criteria": "day >= 14"},
        {"key": "release_phase_complete", "name": "Release Phase Complete", "criteria": "day >= 21"}
    ]'::jsonb
);

-- Phase 3: Rediscover (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'breakup'),
    3,
    'Rediscover',
    'Reconnecting with yourself and what brings you joy',
    14,
    ARRAY['Explore your interests', 'Rebuild confidence', 'Reconnect with passions', 'Strengthen other relationships'],
    '[
        {"day": 1, "title": "Who Are You?", "message": "Outside of being someones partner, who are you? Lets find out.", "focus_area": "self_discovery"},
        {"day": 2, "title": "Old Passions", "message": "What did you love before the relationship? Its time to reconnect with those things.", "focus_area": "identity"},
        {"day": 3, "title": "Solo Adventures", "message": "Do something alone that you would have done together. Reclaim those experiences.", "focus_area": "behavior_change"},
        {"day": 4, "title": "Your People", "message": "Strengthen bonds with friends and family. These relationships matter deeply.", "focus_area": "social_connection"},
        {"day": 5, "title": "Confidence Building", "message": "Notice the things you do well. You are capable and worthy.", "focus_area": "self_compassion"},
        {"day": 6, "title": "New Experiences", "message": "Try something you have always wanted to do but never did.", "focus_area": "behavior_change"},
        {"day": 7, "title": "Two Months Milestone", "message": "Two months of healing and growth. Look how far you have come.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Your Values", "message": "What matters most to you? Make sure your life reflects your values.", "focus_area": "identity"},
        {"day": 9, "title": "Creative Expression", "message": "Express yourself creatively - write, paint, dance, create something.", "focus_area": "self_discovery"},
        {"day": 10, "title": "Physical Strength", "message": "Your body is capable of amazing things. Move it, challenge it, celebrate it.", "focus_area": "self_care"},
        {"day": 11, "title": "Authentic Self", "message": "You do not have to compromise or shrink yourself for anyone anymore.", "focus_area": "identity"},
        {"day": 12, "title": "Future Vision", "message": "What kind of life do you want to build? Start taking small steps toward it.", "focus_area": "future_focus"},
        {"day": 13, "title": "Feeling Whole", "message": "Notice the moments when you feel complete on your own.", "focus_area": "mindfulness"},
        {"day": 14, "title": "Rediscovery Complete", "message": "You have reconnected with yourself. You are ready to move forward.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What activities or hobbies did I give up or neglect? Which do I want to restart?',
        'Describe myself without mentioning my relationship status or romantic life',
        'What makes me feel most alive and authentic?',
        'List 10 things I love about myself',
        'What new skill or experience do I want to explore?',
        'Write about the friendships I want to invest more energy in',
        'What does my ideal day look like?',
        'How have I grown since the breakup?',
        'What boundaries do I need in my next relationship?',
        'List everything I want to do in the next six months',
        'Who do I admire and why? What qualities do I want to embody?',
        'Write a letter to my future self one year from now'
    ],
    '[
        {"key": "two_months_healing", "name": "60 Days of Transformation", "criteria": "day >= 7"},
        {"key": "rediscovery_complete", "name": "Rediscovery Phase Complete", "criteria": "day >= 14"}
    ]'::jsonb
);

-- Phase 4: Rebuild (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'breakup'),
    4,
    'Rebuild',
    'Building a new life and opening to future possibilities',
    14,
    ARRAY['Set new goals', 'Build healthy habits', 'Open to connection', 'Trust the process'],
    '[
        {"day": 1, "title": "Fresh Start", "message": "You are not starting over. You are starting better, with wisdom and strength.", "focus_area": "future_focus"},
        {"day": 2, "title": "Goal Setting", "message": "What do you want to achieve in the next 3 months? 6 months? Year?", "focus_area": "planning"},
        {"day": 3, "title": "Healthy Routines", "message": "Build routines that support the person you are becoming.", "focus_area": "behavior_change"},
        {"day": 4, "title": "Opening Your Heart", "message": "You do not have to date yet, but practice opening your heart to possibility.", "focus_area": "emotional_readiness"},
        {"day": 5, "title": "Trust Yourself", "message": "You can trust yourself to make good choices and protect your own heart.", "focus_area": "self_compassion"},
        {"day": 6, "title": "New Connections", "message": "Meeting new people (platonically or romantically) can be energizing and fun.", "focus_area": "social_connection"},
        {"day": 7, "title": "Ten Weeks Strong", "message": "Ten weeks of choosing growth over stagnation. You should be proud.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Lessons Learned", "message": "Carry the lessons forward, but leave the pain behind.", "focus_area": "reflection"},
        {"day": 9, "title": "Your Support System", "message": "You have built or strengthened a support system that will sustain you.", "focus_area": "social_connection"},
        {"day": 10, "title": "Excitement for Life", "message": "Notice when you feel genuine excitement about your life and your future.", "focus_area": "mindfulness"},
        {"day": 11, "title": "Ready for Love", "message": "When you are ready, you will be able to love from a place of wholeness, not need.", "focus_area": "emotional_readiness"},
        {"day": 12, "title": "Celebrating Growth", "message": "Celebrate how much you have grown, healed, and evolved through this journey.", "focus_area": "milestone_celebration"},
        {"day": 13, "title": "Trust the Timing", "message": "Everything happens when it is meant to. Trust the timing of your life.", "focus_area": "mindfulness"},
        {"day": 14, "title": "Journey Complete", "message": "You did it. You healed, grew, and built a new life. You are ready.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What are my top 3 goals for the next 3 months?',
        'What healthy habits do I want to build or maintain?',
        'What qualities am I looking for in a future partner?',
        'Write about the biggest lessons from this experience',
        'How do I want to show up in my next relationship?',
        'What am I most excited about in my life right now?',
        'List 10 ways I have grown through this experience',
        'What does a fulfilling life look like for me?',
        'Write about a moment recently when I felt truly happy',
        'What boundaries will I maintain in future relationships?',
        'Describe the person I have become through this journey',
        'Write a gratitude letter to myself for doing this work'
    ],
    '[
        {"key": "ten_weeks_milestone", "name": "70 Days of Transformation", "criteria": "day >= 7"},
        {"key": "pathway_complete", "name": "Breakup Healing Complete", "criteria": "day >= 14"}
    ]'::jsonb
);

-- ============================================================================
-- GRIEF PATHWAY (84 days total)
-- Phase 1: Shock and Denial (21 days)
-- Phase 2: Processing Grief (28 days)
-- Phase 3: Finding Meaning (21 days)
-- Phase 4: Continuing Bonds (14 days)
-- ============================================================================

-- Phase 1: Shock and Denial (21 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'grief'),
    1,
    'Shock and Denial',
    'Navigating the initial impact of loss and allowing reality to settle',
    21,
    ARRAY['Acknowledge the loss', 'Allow yourself to feel numb', 'Accept support from others', 'Handle practical matters with care'],
    '[
        {"day": 1, "title": "The Unthinkable", "message": "This loss may feel surreal. Shock is your mind protecting you from overwhelming pain.", "focus_area": "emotional_acceptance"},
        {"day": 2, "title": "Waves of Reality", "message": "Reality will come in waves. Some moments it hits, others it feels distant.", "focus_area": "emotional_processing"},
        {"day": 3, "title": "Its Okay to Not Be Okay", "message": "You do not need to hold it together. Fall apart if you need to.", "focus_area": "self_compassion"},
        {"day": 4, "title": "Accepting Help", "message": "Let people help you with practical things. You do not have to do this alone.", "focus_area": "social_connection"},
        {"day": 5, "title": "Numb is Normal", "message": "Feeling numb or disconnected is a natural response to overwhelming loss.", "focus_area": "emotional_acceptance"},
        {"day": 6, "title": "One Day at a Time", "message": "You only need to survive today. Tomorrow can wait.", "focus_area": "mindfulness"},
        {"day": 7, "title": "First Week Survived", "message": "You made it through the first week. That took everything you had.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Moments of Forgetting", "message": "You may forget for a moment, then remember again. This is part of processing loss.", "focus_area": "emotional_processing"},
        {"day": 9, "title": "The Why Question", "message": "Why questions may never have answers. Its okay to sit with the mystery.", "focus_area": "cognitive_reframing"},
        {"day": 10, "title": "Your Body Grieves Too", "message": "Grief lives in your body. Exhaustion, aches, and heaviness are normal.", "focus_area": "self_care"},
        {"day": 11, "title": "Talking About Them", "message": "Saying their name and sharing memories keeps their spirit alive.", "focus_area": "emotional_processing"},
        {"day": 12, "title": "Its Not Fair", "message": "You are right. It is not fair. Your anger at the injustice is valid.", "focus_area": "emotional_acceptance"},
        {"day": 13, "title": "Rituals Matter", "message": "Funerals, memorials, and rituals help us begin to process loss.", "focus_area": "meaning_making"},
        {"day": 14, "title": "Two Weeks", "message": "Two weeks without them. The world keeps turning, but yours has stopped.", "focus_area": "milestone_celebration"},
        {"day": 15, "title": "Bargaining", "message": "If only, what if - your mind is trying to undo the undoable.", "focus_area": "emotional_processing"},
        {"day": 16, "title": "Breathe", "message": "When the weight feels unbearable, just breathe. In and out. You are still here.", "focus_area": "mindfulness"},
        {"day": 17, "title": "Support Circle", "message": "Notice who shows up. Those are your people. Let them in.", "focus_area": "social_connection"},
        {"day": 18, "title": "Guilt Creeps In", "message": "Survivor guilt and should-have-done-differently thoughts are common. Be gentle with yourself.", "focus_area": "self_compassion"},
        {"day": 19, "title": "Special Objects", "message": "Items that belonged to them can be comforting. Hold them when you need to.", "focus_area": "emotional_processing"},
        {"day": 20, "title": "Almost Three Weeks", "message": "You are still standing. That is enough.", "focus_area": "milestone_celebration"},
        {"day": 21, "title": "Accepting Reality", "message": "Reality is starting to sink in. The shock is lifting, and deeper grief awaits.", "focus_area": "emotional_acceptance"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'Write about the moment you found out. Get it out of your body and onto paper',
        'What do you wish you could say to them one more time?',
        'Describe your favorite memory together',
        'What feels hardest right now?',
        'Write a letter to them telling them everything you need them to know',
        'What support do you need that you are not getting?',
        'List the practical things that need to be handled',
        'What are you feeling in your body right now?',
        'Write about what you miss most',
        'What guilt are you carrying? Can you release any of it?',
        'Describe their laugh, their voice, their presence',
        'What do you need today to get through?'
    ],
    '[
        {"key": "first_week_survived", "name": "First Week Survived", "criteria": "day >= 7"},
        {"key": "two_weeks_grief", "name": "14 Days of Grief", "criteria": "day >= 14"},
        {"key": "shock_phase_complete", "name": "Shock Phase Complete", "criteria": "day >= 21"}
    ]'::jsonb
);

-- Phase 2: Processing Grief (28 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'grief'),
    2,
    'Processing Grief',
    'Moving through the deep pain of loss and all its emotions',
    28,
    ARRAY['Feel all emotions without judgment', 'Express grief in healthy ways', 'Practice self-care during pain', 'Connect with others who understand'],
    '[
        {"day": 1, "title": "The Deep Dive", "message": "The shock has worn off. Now comes the hard work of truly feeling the loss.", "focus_area": "emotional_processing"},
        {"day": 2, "title": "Anger Has a Place", "message": "Anger at them for leaving, at yourself, at life - all of it is valid.", "focus_area": "emotional_acceptance"},
        {"day": 3, "title": "Depression is Not Weakness", "message": "The weight of grief can feel crushing. This is not weakness. This is love.", "focus_area": "self_compassion"},
        {"day": 4, "title": "Physical Grief", "message": "Grief hurts physically. Aches, exhaustion, loss of appetite - all normal.", "focus_area": "self_care"},
        {"day": 5, "title": "Crying Heals", "message": "Tears are how the body releases grief. Cry when you need to.", "focus_area": "emotional_processing"},
        {"day": 6, "title": "Good Days and Bad", "message": "Some days you will feel okay. Then guilt for feeling okay. Both are normal.", "focus_area": "emotional_acceptance"},
        {"day": 7, "title": "One Month Mark", "message": "One month without them. The world moves on but you are still learning to breathe.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Triggers Everywhere", "message": "Songs, places, smells - triggers are everywhere. Be gentle with yourself.", "focus_area": "mindfulness"},
        {"day": 9, "title": "The Empty Chair", "message": "Their absence is a presence. The space they left is palpable.", "focus_area": "emotional_processing"},
        {"day": 10, "title": "Comparison Trap", "message": "Others may seem to move on faster. Your grief timeline is your own.", "focus_area": "self_compassion"},
        {"day": 11, "title": "Finding Your People", "message": "Grief can feel isolating. Find others who truly understand loss.", "focus_area": "social_connection"},
        {"day": 12, "title": "What They Left Behind", "message": "The impact they had, the love they gave, the memories you shared - these remain.", "focus_area": "meaning_making"},
        {"day": 13, "title": "Permission to Laugh", "message": "Laughing does not mean you have forgotten or stopped loving them.", "focus_area": "emotional_acceptance"},
        {"day": 14, "title": "Six Weeks", "message": "Six weeks of carrying this weight. You are stronger than you know.", "focus_area": "milestone_celebration"},
        {"day": 15, "title": "Regrets Surface", "message": "Things unsaid, time not spent - regrets are part of grief. Practice forgiveness.", "focus_area": "emotional_processing"},
        {"day": 16, "title": "Honoring Their Memory", "message": "Find ways to honor them that feel meaningful to you.", "focus_area": "meaning_making"},
        {"day": 17, "title": "The Before and After", "message": "Life is now divided into before and after. This is the new reality.", "focus_area": "cognitive_reframing"},
        {"day": 18, "title": "Self-Care is Not Selfish", "message": "Taking care of yourself honors their love for you.", "focus_area": "self_care"},
        {"day": 19, "title": "Dreams and Visitations", "message": "Dreams of them can feel like visits. Take comfort in these moments.", "focus_area": "emotional_processing"},
        {"day": 20, "title": "Two Months", "message": "Two months of learning to live with loss. Each day is an achievement.", "focus_area": "milestone_celebration"},
        {"day": 21, "title": "Firsts Without Them", "message": "First birthday, holiday, anniversary without them. These will be hard.", "focus_area": "emotional_acceptance"},
        {"day": 22, "title": "Gratitude and Grief", "message": "Gratitude for having known them and grief for losing them coexist.", "focus_area": "meaning_making"},
        {"day": 23, "title": "Energy Returns", "message": "You may notice small bursts of energy returning. This is healing.", "focus_area": "mindfulness"},
        {"day": 24, "title": "Their Legacy", "message": "How they lived shapes how you live. Carry forward what they taught you.", "focus_area": "meaning_making"},
        {"day": 25, "title": "Complicated Feelings", "message": "If your relationship was complicated, your grief will be too. All feelings are valid.", "focus_area": "emotional_acceptance"},
        {"day": 26, "title": "Writing to Them", "message": "Continue conversations with them through writing. They are still with you.", "focus_area": "emotional_processing"},
        {"day": 27, "title": "Almost Through", "message": "You have processed so much pain. You are transforming.", "focus_area": "milestone_celebration"},
        {"day": 28, "title": "Deep Work Done", "message": "The deepest grief has been felt. Now you begin finding meaning.", "focus_area": "emotional_processing"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What emotion is strongest today? Write about it without holding back',
        'Describe a perfect day you shared together',
        'What do you wish you had said or done?',
        'Write about your angriest moment since they left',
        'What are you learning about yourself through this grief?',
        'List all the ways they changed your life for the better',
        'What do you miss that you did not expect to miss?',
        'Write about a trigger you encountered and how it felt',
        'If they could see you now, what would they want you to know?',
        'Describe how you want to honor their memory',
        'What has surprised you most about grief?',
        'Write a letter forgiving yourself for any regrets',
        'What would they be proud of you for?',
        'Describe the person you are becoming through this loss'
    ],
    '[
        {"key": "one_month_grief", "name": "One Month Survived", "criteria": "day >= 7"},
        {"key": "six_weeks_grief", "name": "Six Weeks of Grief", "criteria": "day >= 14"},
        {"key": "two_months_grief", "name": "Two Months of Healing", "criteria": "day >= 20"},
        {"key": "processing_complete", "name": "Processing Phase Complete", "criteria": "day >= 28"}
    ]'::jsonb
);

-- Phase 3: Finding Meaning (21 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'grief'),
    3,
    'Finding Meaning',
    'Discovering purpose and growth through loss',
    21,
    ARRAY['Find meaning in the loss', 'Identify personal growth', 'Connect to purpose', 'Honor their impact'],
    '[
        {"day": 1, "title": "Why Am I Here?", "message": "If they are gone, why are you still here? There is purpose in that question.", "focus_area": "meaning_making"},
        {"day": 2, "title": "Grief Changed You", "message": "You are not who you were before. Explore who you are becoming.", "focus_area": "identity"},
        {"day": 3, "title": "Living for Both", "message": "You get to live the life they no longer can. What will you do with that?", "focus_area": "future_focus"},
        {"day": 4, "title": "Post-Traumatic Growth", "message": "Trauma can lead to growth. You may be stronger, wiser, more compassionate.", "focus_area": "cognitive_reframing"},
        {"day": 5, "title": "What Matters Now", "message": "Loss clarifies what truly matters. What has become clear to you?", "focus_area": "meaning_making"},
        {"day": 6, "title": "Helping Others", "message": "Your experience can help others navigate loss. This is powerful.", "focus_area": "purpose"},
        {"day": 7, "title": "Ten Weeks", "message": "Ten weeks of transformation through pain. Notice how far you have come.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Values Realignment", "message": "Does your life reflect what matters most to you now?", "focus_area": "identity"},
        {"day": 9, "title": "Their Wisdom Lives", "message": "The lessons they taught you continue to guide you.", "focus_area": "meaning_making"},
        {"day": 10, "title": "Purpose Through Pain", "message": "Some people find their life purpose through their greatest pain.", "focus_area": "purpose"},
        {"day": 11, "title": "Compassion Deepened", "message": "You likely have deeper compassion for others suffering. This is a gift.", "focus_area": "cognitive_reframing"},
        {"day": 12, "title": "Life is Precious", "message": "Loss teaches us that life is both fragile and precious.", "focus_area": "mindfulness"},
        {"day": 13, "title": "Making Them Proud", "message": "Living well honors them. What would make them proud?", "focus_area": "meaning_making"},
        {"day": 14, "title": "Three Months", "message": "Three months of living with loss. You are still here. That matters.", "focus_area": "milestone_celebration"},
        {"day": 15, "title": "Creating Beauty", "message": "From ashes, beauty can grow. What beauty are you creating?", "focus_area": "purpose"},
        {"day": 16, "title": "Strength You Did Not Know", "message": "You have survived what you thought would destroy you. Notice that strength.", "focus_area": "self_compassion"},
        {"day": 17, "title": "Connection to Others", "message": "Shared loss creates deep connection. You are part of a community.", "focus_area": "social_connection"},
        {"day": 18, "title": "Appreciating Life", "message": "Do you notice the small moments more? Appreciate them differently?", "focus_area": "mindfulness"},
        {"day": 19, "title": "Their Story Continues", "message": "As long as you remember them and share their story, they live on.", "focus_area": "meaning_making"},
        {"day": 20, "title": "Integration", "message": "Grief is becoming integrated into your life rather than consuming it.", "focus_area": "emotional_processing"},
        {"day": 21, "title": "Meaning Found", "message": "You have found meaning in this loss. You carry them forward with purpose.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What has this loss taught you about life?',
        'How have you grown as a person through grief?',
        'What purpose or meaning have you found in this experience?',
        'Describe how you want to honor their legacy',
        'What would you tell someone just beginning this grief journey?',
        'List the ways they influenced who you are today',
        'What values have become more important to you?',
        'How do you want to live differently because of this loss?',
        'Write about a moment when you felt their presence or guidance',
        'What beauty or good has emerged from this pain?',
        'Describe the person you are becoming',
        'What do you want to create or accomplish in their honor?'
    ],
    '[
        {"key": "ten_weeks_grief", "name": "Ten Weeks of Integration", "criteria": "day >= 7"},
        {"key": "three_months_grief", "name": "Three Months Milestone", "criteria": "day >= 14"},
        {"key": "meaning_phase_complete", "name": "Meaning Phase Complete", "criteria": "day >= 21"}
    ]'::jsonb
);

-- Phase 4: Continuing Bonds (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'grief'),
    4,
    'Continuing Bonds',
    'Maintaining connection while moving forward with life',
    14,
    ARRAY['Maintain healthy connection', 'Move forward without guilt', 'Create rituals of remembrance', 'Embrace joy again'],
    '[
        {"day": 1, "title": "Moving Forward", "message": "Moving forward with life does not mean leaving them behind.", "focus_area": "cognitive_reframing"},
        {"day": 2, "title": "They Go With You", "message": "They are woven into who you are. They come with you into your future.", "focus_area": "meaning_making"},
        {"day": 3, "title": "Permission to Be Happy", "message": "Being happy again is not betrayal. They would want your joy.", "focus_area": "emotional_acceptance"},
        {"day": 4, "title": "Rituals of Connection", "message": "Create rituals that keep you connected - visiting places, annual tributes, traditions.", "focus_area": "behavior_change"},
        {"day": 5, "title": "Talking to Them", "message": "You can still talk to them. The conversation continues in your heart.", "focus_area": "emotional_processing"},
        {"day": 6, "title": "Signs and Symbols", "message": "Many find comfort in signs - butterflies, songs, synchronicities.", "focus_area": "meaning_making"},
        {"day": 7, "title": "Fifteen Weeks", "message": "Fifteen weeks of integrating loss into life. You are learning to carry it.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Living Your Life", "message": "Live the fullest life possible. That honors their memory best.", "focus_area": "future_focus"},
        {"day": 9, "title": "Sharing Memories", "message": "Share stories about them. Keep their memory alive through words.", "focus_area": "social_connection"},
        {"day": 10, "title": "Grief Ebbs and Flows", "message": "Grief never fully goes away. It ebbs and flows like waves. This is normal.", "focus_area": "emotional_acceptance"},
        {"day": 11, "title": "You Are Not Alone", "message": "Millions walk this path of loss. You are never alone in this.", "focus_area": "social_connection"},
        {"day": 12, "title": "Both And", "message": "You can be sad and happy. Grieving and thriving. Both are true.", "focus_area": "cognitive_reframing"},
        {"day": 13, "title": "Ready to Live", "message": "You are ready to fully engage with life again while carrying love for them.", "focus_area": "future_focus"},
        {"day": 14, "title": "Journey Complete", "message": "Your grief journey continues, but you have the tools to carry love and loss together.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'How do you stay connected to them now?',
        'What rituals or traditions do you want to create to honor them?',
        'Describe how they are still present in your life',
        'What brings you joy now? Is there guilt? Explore it',
        'How has your relationship with them evolved since their death?',
        'Describe the ways they live on through you',
        'What do you want to tell them about your life now?',
        'List the ways you are moving forward while keeping them close',
        'Write about a recent moment of happiness and how it felt',
        'What advice would they give you about your life right now?',
        'How will you continue honoring them in the years to come?',
        'Write a letter of gratitude for the time you had together'
    ],
    '[
        {"key": "fifteen_weeks_grief", "name": "Fifteen Weeks of Integration", "criteria": "day >= 7"},
        {"key": "grief_pathway_complete", "name": "Grief Pathway Complete", "criteria": "day >= 14"}
    ]'::jsonb
);

-- ============================================================================
-- NEW PARENT PATHWAY (84 days total)
-- Phase 1: Survival Mode (21 days)
-- Phase 2: Finding Rhythm (28 days)
-- Phase 3: Identity Integration (21 days)
-- Phase 4: Embracing Parenthood (14 days)
-- ============================================================================

-- Phase 1: Survival Mode (21 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'new_parent'),
    1,
    'Survival Mode',
    'Navigating the overwhelming first weeks of parenthood',
    21,
    ARRAY['Accept help from others', 'Rest when possible', 'Lower expectations', 'Trust your instincts'],
    '[
        {"day": 1, "title": "Welcome to Parenthood", "message": "Everything just changed. Its okay to feel overwhelmed, overjoyed, and terrified all at once.", "focus_area": "emotional_acceptance"},
        {"day": 2, "title": "Sleep When Baby Sleeps", "message": "Easier said than done, but rest is critical. Lower all other expectations.", "focus_area": "self_care"},
        {"day": 3, "title": "You Are Enough", "message": "You do not need to be perfect. You just need to be present and loving.", "focus_area": "self_compassion"},
        {"day": 4, "title": "Accept All Help", "message": "Say yes to help with meals, laundry, dishes. Focus your energy on baby and rest.", "focus_area": "support_acceptance"},
        {"day": 5, "title": "Trust Your Instincts", "message": "You will get a million opinions. Your instincts about your baby matter most.", "focus_area": "confidence"},
        {"day": 6, "title": "The Learning Curve", "message": "You are both learning each other. Give yourself grace for not knowing everything.", "focus_area": "self_compassion"},
        {"day": 7, "title": "First Week Survived", "message": "You made it through the first week. That is an accomplishment.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Its Okay to Not Love Every Moment", "message": "Parenting is hard. Acknowledging that does not make you a bad parent.", "focus_area": "emotional_acceptance"},
        {"day": 9, "title": "Your Body Needs Time", "message": "Birth is intense. Your body needs weeks or months to heal. Be patient.", "focus_area": "self_care"},
        {"day": 10, "title": "Partner Connection", "message": "Check in with your partner. You are in this together, even when exhausted.", "focus_area": "relationship"},
        {"day": 11, "title": "Hormones Are Real", "message": "Postpartum hormones affect everything. Mood swings and tears are normal.", "focus_area": "emotional_acceptance"},
        {"day": 12, "title": "Comparison is Poison", "message": "Every baby is different. Avoid comparing to others babies or timelines.", "focus_area": "mindfulness"},
        {"day": 13, "title": "Small Victories", "message": "Celebrate small wins - a shower, a walk, five minutes of quiet. They matter.", "focus_area": "mindfulness"},
        {"day": 14, "title": "Two Weeks In", "message": "Two weeks of being responsible for a tiny human. You are doing it.", "focus_area": "milestone_celebration"},
        {"day": 15, "title": "Ask for What You Need", "message": "People want to help but do not know how. Be specific about what would help most.", "focus_area": "communication"},
        {"day": 16, "title": "Its Not Supposed to Be Easy", "message": "The hardest moments do not mean you are failing. This is just hard.", "focus_area": "reality_check"},
        {"day": 17, "title": "Bonding Takes Time", "message": "If you do not feel instant overwhelming love, that is normal. Bonding is a process.", "focus_area": "emotional_acceptance"},
        {"day": 18, "title": "You Are Learning", "message": "Every parent was once where you are now - overwhelmed and figuring it out.", "focus_area": "perspective"},
        {"day": 19, "title": "Protect Your Energy", "message": "Limit visitors if you need to. Your energy is for baby and yourself right now.", "focus_area": "boundaries"},
        {"day": 20, "title": "Almost Three Weeks", "message": "You are getting through each day. That is exactly what you need to do.", "focus_area": "mindfulness"},
        {"day": 21, "title": "Survival Mode Complete", "message": "The hardest weeks are behind you. A rhythm is starting to emerge.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What has surprised you most about becoming a parent?',
        'Describe a moment today when you felt overwhelmed',
        'What support do I need that I am not getting?',
        'Write about my fears as a new parent',
        'What do I want to remember about these early days?',
        'How are I feeling in my body?',
        'List three things that went well today, even if small',
        'What advice would I give to my pre-parent self?',
        'Describe a tender moment with my baby',
        'What am I learning about myself?',
        'Write about my relationship with my partner right now',
        'What do I need to let go of or lower expectations about?'
    ],
    '[
        {"key": "first_week_parent", "name": "First Week Complete", "criteria": "day >= 7"},
        {"key": "two_weeks_parent", "name": "Two Weeks Survived", "criteria": "day >= 14"},
        {"key": "survival_mode_complete", "name": "Survival Mode Complete", "criteria": "day >= 21"}
    ]'::jsonb
);

-- Phase 2: Finding Rhythm (28 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'new_parent'),
    2,
    'Finding Rhythm',
    'Establishing patterns and building confidence',
    28,
    ARRAY['Create sustainable routines', 'Build confidence', 'Connect with other parents', 'Practice self-compassion'],
    '[
        {"day": 1, "title": "Rhythm Emerges", "message": "Patterns are starting to form. You are learning your baby language.", "focus_area": "observation"},
        {"day": 2, "title": "Its Not Linear", "message": "Just when you think you have a routine, it changes. This is normal.", "focus_area": "flexibility"},
        {"day": 3, "title": "You Know Your Baby", "message": "Trust the knowledge you have gained. You are the expert on your child.", "focus_area": "confidence"},
        {"day": 4, "title": "Partner Teamwork", "message": "Divide and conquer. Communication about needs and schedules prevents resentment.", "focus_area": "relationship"},
        {"day": 5, "title": "One Month Milestone", "message": "One month of keeping a tiny human alive and loved. You are doing it.", "focus_area": "milestone_celebration"},
        {"day": 6, "title": "Sleep Training Decisions", "message": "Everyone has opinions. Research options and choose what feels right for your family.", "focus_area": "decision_making"},
        {"day": 7, "title": "Your Mental Health", "message": "Check in with yourself. Postpartum depression and anxiety are real and treatable.", "focus_area": "mental_health"},
        {"day": 8, "title": "Connect with Others", "message": "Other new parents get it. Find your people through groups or classes.", "focus_area": "social_connection"},
        {"day": 9, "title": "Imperfect is Perfect", "message": "The messy house, the unwashed hair - none of it matters. Baby is thriving.", "focus_area": "perspective"},
        {"day": 10, "title": "Feeding Journey", "message": "However you feed your baby - breast, bottle, combo - fed is best. Release guilt.", "focus_area": "self_compassion"},
        {"day": 11, "title": "Developmental Milestones", "message": "Babies develop at their own pace. Comparison steals joy.", "focus_area": "mindfulness"},
        {"day": 12, "title": "Identity Shift", "message": "You are still you, even though everything has changed. Both are true.", "focus_area": "identity"},
        {"day": 13, "title": "Making Time for Partner", "message": "Even 15 minutes of connection matters. Schedule it like an appointment.", "focus_area": "relationship"},
        {"day": 14, "title": "Six Weeks Postpartum", "message": "Your body is healing. Be patient and kind with yourself.", "focus_area": "self_care"},
        {"day": 15, "title": "Learning to Read Cues", "message": "Hungry, tired, overstimulated - you are getting better at reading the signs.", "focus_area": "skill_building"},
        {"day": 16, "title": "Its Okay to Need a Break", "message": "Needing time away does not make you a bad parent. It makes you human.", "focus_area": "boundaries"},
        {"day": 17, "title": "Celebrating Small Wins", "message": "Successful outing, good nap, happy baby - celebrate it all.", "focus_area": "gratitude"},
        {"day": 18, "title": "Asking for Help", "message": "Strength is knowing when you need support and asking for it.", "focus_area": "vulnerability"},
        {"day": 19, "title": "Two Months", "message": "Two months of parenthood. You have learned so much.", "focus_area": "milestone_celebration"},
        {"day": 20, "title": "Routines Evolve", "message": "What worked last week may not work this week. Stay flexible.", "focus_area": "adaptation"},
        {"day": 21, "title": "You Are Enough", "message": "On the hard days when you doubt yourself - you are exactly what your baby needs.", "focus_area": "self_compassion"},
        {"day": 22, "title": "Protecting Sleep", "message": "Your sleep matters too. Tag team with partner or ask for help.", "focus_area": "self_care"},
        {"day": 23, "title": "Baby Personality", "message": "Their little personality is emerging. Notice and delight in it.", "focus_area": "connection"},
        {"day": 24, "title": "Letting Go of Control", "message": "Parenthood is surrendering control. Practice acceptance and presence.", "focus_area": "mindfulness"},
        {"day": 25, "title": "Finding Joy", "message": "In the chaos, look for moments of pure joy. They are there.", "focus_area": "gratitude"},
        {"day": 26, "title": "You Have Come So Far", "message": "Remember those first terrifying days? Look how confident you are now.", "focus_area": "perspective"},
        {"day": 27, "title": "Sustainable Pace", "message": "This is a marathon. Find a pace you can sustain for the long run.", "focus_area": "balance"},
        {"day": 28, "title": "Rhythm Established", "message": "You have found your rhythm. It will keep evolving, and you will keep adapting.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What routines are working for us? What needs adjustment?',
        'Describe a moment this week when I felt confident as a parent',
        'What am I learning about my baby personality?',
        'Write about how my relationship with my partner is evolving',
        'What do I need more of? Less of?',
        'How am I taking care of myself emotionally?',
        'List three small victories from this week',
        'What surprised me about parenthood this month?',
        'Describe a tender moment between me and baby',
        'What am I still struggling with? What help do I need?',
        'How have I grown in the past month?',
        'What do I want to remember about this phase?'
    ],
    '[
        {"key": "one_month_parent", "name": "One Month of Parenthood", "criteria": "day >= 5"},
        {"key": "six_weeks_postpartum", "name": "Six Weeks Postpartum", "criteria": "day >= 14"},
        {"key": "two_months_parent", "name": "Two Months Milestone", "criteria": "day >= 19"},
        {"key": "rhythm_phase_complete", "name": "Finding Rhythm Complete", "criteria": "day >= 28"}
    ]'::jsonb
);

-- Phase 3: Identity Integration (21 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'new_parent'),
    3,
    'Identity Integration',
    'Integrating parent identity with who you were before',
    21,
    ARRAY['Honor your pre-parent self', 'Create space for your needs', 'Define your parenting values', 'Build sustainable balance'],
    '[
        {"day": 1, "title": "The Before and After", "message": "You are not just your diagnosis. Remember the other parts of who you are.", "focus_area": "identity"},
        {"day": 2, "title": "Your Interests Matter", "message": "You can be a parent AND have interests, hobbies, and goals. Make time for them.", "focus_area": "self_care"},
        {"day": 3, "title": "Parenting Philosophy", "message": "What kind of parent do you want to be? Define your values.", "focus_area": "values"},
        {"day": 4, "title": "Letting Go of Guilt", "message": "Mom guilt, dad guilt - it serves no one. Do your best and let the rest go.", "focus_area": "self_compassion"},
        {"day": 5, "title": "Your Career Identity", "message": "If returning to work, this is a transition. Give yourself grace.", "focus_area": "work_life_integration"},
        {"day": 6, "title": "Three Months", "message": "Three months of being a parent. You have come so far.", "focus_area": "milestone_celebration"},
        {"day": 7, "title": "Making Time for You", "message": "Schedule time for yourself like you schedule everything else.", "focus_area": "boundaries"},
        {"day": 8, "title": "Relationship with Partner", "message": "You are co-parents now. Keep nurturing the partnership.", "focus_area": "relationship"},
        {"day": 9, "title": "Friend Relationships", "message": "Friendships may have changed. Some will adapt, some will fade. This is okay.", "focus_area": "social_connection"},
        {"day": 10, "title": "Your Body Now", "message": "Your body did something incredible. Honor it as it is.", "focus_area": "body_image"},
        {"day": 11, "title": "Permission to Want More", "message": "Its okay to want time alone, to miss your old life sometimes. These feelings coexist with love.", "focus_area": "emotional_acceptance"},
        {"day": 12, "title": "Parenting Disagreements", "message": "You and your partner will disagree. Have the hard conversations with respect.", "focus_area": "communication"},
        {"day": 13, "title": "Letting Go of Perfection", "message": "Good enough is actually good enough. Perfectionism serves no one.", "focus_area": "perspective"},
        {"day": 14, "title": "Who You Are Now", "message": "Take stock of who you have become. There is strength and beauty there.", "focus_area": "identity"},
        {"day": 15, "title": "Setting Boundaries", "message": "With family, friends, and yourself. Boundaries protect your energy.", "focus_area": "boundaries"},
        {"day": 16, "title": "Your Support System", "message": "Who can you call? Who shows up? Nurture those relationships.", "focus_area": "social_connection"},
        {"day": 17, "title": "Career and Identity", "message": "Whether staying home or working, you are enough. Your choice is valid.", "focus_area": "validation"},
        {"day": 18, "title": "Comparison Trap", "message": "Social media shows highlights. Every family is struggling behind the scenes.", "focus_area": "reality_check"},
        {"day": 19, "title": "Integrating All Parts", "message": "Parent, partner, professional, friend, self - all are part of who you are.", "focus_area": "wholeness"},
        {"day": 20, "title": "Future Vision", "message": "What kind of life do you want to build for your family? Start small.", "focus_area": "goal_setting"},
        {"day": 21, "title": "Integration Complete", "message": "You have integrated parenthood into your identity. You are whole.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'Who was I before becoming a parent? What do I miss?',
        'Who am I now? What has changed for the better?',
        'What kind of parent do I want to be? What values guide me?',
        'What boundaries do I need to set to protect my energy?',
        'How is my relationship with my partner? What does it need?',
        'What brings me joy outside of being a parent?',
        'Write about a moment when I felt like myself again',
        'What guilt am I carrying that I can release?',
        'How do I want to live going forward?',
        'Write about the relationship with my body now',
        'What wisdom have I gained?',
        'If I could tell someone newly diagnosed one thing, what would it be?',
        'Describe a moment of beauty or joy this week',
        'What gives me hope?',
        'How do I define health now?'
    ],
    '[
        {"key": "three_months_parent", "name": "Three Months of Parenting", "criteria": "day >= 6"},
        {"key": "identity_integrated", "name": "Identity Integration", "criteria": "day >= 14"},
        {"key": "integration_phase_complete", "name": "Integration Phase Complete", "criteria": "day >= 21"}
    ]'::jsonb
);

-- Phase 4: Embracing Parenthood (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'new_parent'),
    4,
    'Embracing Parenthood',
    'Fully stepping into your role with confidence and joy',
    14,
    ARRAY['Trust your parenting', 'Find your community', 'Embrace the journey', 'Look to the future'],
    '[
        {"day": 1, "title": "You Are a Parent", "message": "Not becoming, not learning to be - you ARE a parent. Own it.", "focus_area": "identity"},
        {"day": 2, "title": "Your Parenting Style", "message": "You have developed your own way. Trust it over any book or advice.", "focus_area": "confidence"},
        {"day": 3, "title": "The Hard and the Beautiful", "message": "Both exist at once. This is the paradox of parenthood.", "focus_area": "acceptance"},
        {"day": 4, "title": "Your Village", "message": "You have built or are building your support system. Lean on them.", "focus_area": "community"},
        {"day": 5, "title": "Milestones to Come", "message": "So many firsts await. Anticipate them with joy rather than anxiety.", "focus_area": "future_focus"},
        {"day": 6, "title": "Trusting Yourself", "message": "When in doubt, tune into your gut. You know your baby best.", "focus_area": "intuition"},
        {"day": 7, "title": "Halfway Through", "message": "You are transforming beautifully into this role. Keep going.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Joy in the Mundane", "message": "Diaper changes, feeding, rocking - these mundane moments are actually sacred.", "focus_area": "mindfulness"},
        {"day": 9, "title": "It Goes So Fast", "message": "Everyone says it. You are living it. Savor what you can.", "focus_area": "presence"},
        {"day": 10, "title": "You Are Enough", "message": "On the hard days, remember - your love and presence are enough.", "focus_area": "self_compassion"},
        {"day": 11, "title": "Looking Forward", "message": "What are you excited about in the next phase? Name it.", "focus_area": "anticipation"},
        {"day": 12, "title": "Celebrating Growth", "message": "Both yours and your baby. You have both grown so much.", "focus_area": "gratitude"},
        {"day": 13, "title": "The Journey Ahead", "message": "Parenthood is a lifelong journey. You are ready for it.", "focus_area": "readiness"},
        {"day": 14, "title": "Pathway Complete", "message": "You have navigated this transition with grace. You are a parent. You are ready.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What do I love most about being a parent?',
        'Describe my parenting style in three words',
        'What has been the hardest part? The most beautiful?',
        'Write about a moment that made it all worth it',
        'What am I most looking forward to in the next phase?',
        'How have I surprised myself as a parent?',
        'What would I tell my pre-parent self now?',
        'Describe my relationship with my baby',
        'What values do I want to pass on?',
        'How has this journey changed me?',
        'Write a letter to my baby about this time',
        'What am I grateful for about this experience?'
    ],
    '[
        {"key": "halfway_through_phase", "name": "Embracing Parenthood", "criteria": "day >= 7"},
        {"key": "new_parent_pathway_complete", "name": "New Parent Pathway Complete", "criteria": "day >= 14"}
    ]'::jsonb
);

-- ============================================================================
-- RELOCATION PATHWAY (42 days total)
-- Phase 1: Goodbye and Transition (14 days)
-- Phase 2: Arrival and Adjustment (14 days)
-- Phase 3: Building New Roots (7 days)
-- Phase 4: Home (7 days)
-- ============================================================================

-- Phase 1: Goodbye and Transition (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'relocation'),
    1,
    'Goodbye and Transition',
    'Honoring what you are leaving while preparing for what comes next',
    14,
    ARRAY['Grieve what you are leaving', 'Stay connected to people', 'Prepare emotionally', 'Honor the ending'],
    '[
        {"day": 1, "title": "The Countdown Begins", "message": "Moving is one of life most stressful transitions. Your feelings are valid.", "focus_area": "emotional_acceptance"},
        {"day": 2, "title": "Grief is Okay", "message": "Even if this move is wanted, grieving what you are leaving is normal.", "focus_area": "emotional_processing"},
        {"day": 3, "title": "Saying Goodbye", "message": "Make time for goodbye rituals with people and places. They matter.", "focus_area": "closure"},
        {"day": 4, "title": "The Stress of Change", "message": "Moving logistics are overwhelming. One task at a time.", "focus_area": "stress_management"},
        {"day": 5, "title": "Staying Connected", "message": "True friendships survive distance. Make plans to stay in touch.", "focus_area": "relationships"},
        {"day": 6, "title": "What You Take With You", "message": "Memories, lessons, growth - these come with you. Place is just a backdrop.", "focus_area": "perspective"},
        {"day": 7, "title": "One Week to Go", "message": "The final week. Let yourself feel everything.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Favorite Places", "message": "Visit your favorite spots one last time. Take mental photos.", "focus_area": "nostalgia"},
        {"day": 9, "title": "Anxiety About Unknown", "message": "The new place is unknown. Anxiety is your brain trying to prepare you.", "focus_area": "self_compassion"},
        {"day": 10, "title": "Identity and Place", "message": "This place shaped who you are. You carry that with you.", "focus_area": "identity"},
        {"day": 11, "title": "Almost Time", "message": "In a few days, everything changes. Breathe through it.", "focus_area": "mindfulness"},
        {"day": 12, "title": "What You Will Miss", "message": "Name what you will miss. Honor it. Then release it.", "focus_area": "closure"},
        {"day": 13, "title": "Excitement and Fear", "message": "Both can coexist. You can be excited and terrified at once.", "focus_area": "emotional_acceptance"},
        {"day": 14, "title": "Goodbye Day", "message": "This chapter is closing. Thank it for what it gave you.", "focus_area": "gratitude"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What am I leaving behind that I will miss most?',
        'Write about my favorite memories in this place',
        'What fears do I have about the move?',
        'Who has shaped my experience here? How do I thank them?',
        'What have I learned from living in this place?',
        'Describe my perfect last day here',
        'What am I most excited about in the new place?',
        'Write a love letter to this place',
        'What parts of my life here do I want to recreate there?',
        'How do I want to stay connected to people here?',
        'What does home mean to me?',
        'Write about who I have become while living here'
    ],
    '[
        {"key": "one_week_to_move", "name": "One Week to Move", "criteria": "day >= 7"},
        {"key": "goodbye_phase_complete", "name": "Goodbye Phase Complete", "criteria": "day >= 14"}
    ]'::jsonb
);

-- Phase 2: Arrival and Adjustment (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'relocation'),
    2,
    'Arrival and Adjustment',
    'Settling in and navigating the disorientation of newness',
    14,
    ARRAY['Unpack physically and emotionally', 'Explore your new area', 'Practice patience', 'Start building routine'],
    '[
        {"day": 1, "title": "You Are Here", "message": "You made it. Take a breath. Everything is new and that is overwhelming.", "focus_area": "arrival"},
        {"day": 2, "title": "Disorientation is Normal", "message": "Not knowing where anything is, feeling lost - this passes.", "focus_area": "normalization"},
        {"day": 3, "title": "Unpack Mindfully", "message": "Create spaces that feel like home. Start with your favorite things.", "focus_area": "nesting"},
        {"day": 4, "title": "Explore With Curiosity", "message": "Where is the coffee shop, the park, the grocery store? Make it an adventure.", "focus_area": "exploration"},
        {"day": 5, "title": "Its Okay to Miss Home", "message": "Missing your old place does not mean this was a mistake.", "focus_area": "emotional_acceptance"},
        {"day": 6, "title": "First Impressions", "message": "Your first impressions will evolve. Give this place a chance.", "focus_area": "openness"},
        {"day": 7, "title": "First Week Complete", "message": "One week in your new place. You are doing it.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Building Routine", "message": "Routines create comfort. Find your morning coffee spot, your walking route.", "focus_area": "routine"},
        {"day": 9, "title": "The Loneliness", "message": "Not having friends nearby yet is hard. It takes time to build community.", "focus_area": "patience"},
        {"day": 10, "title": "Comparison to Before", "message": "This place is different. Different is not bad, just different.", "focus_area": "acceptance"},
        {"day": 11, "title": "Small Discoveries", "message": "Notice the small things you like. A view, a restaurant, a quiet street.", "focus_area": "gratitude"},
        {"day": 12, "title": "Reaching Out", "message": "Start introducing yourself. Join a group. Make one small connection.", "focus_area": "social_connection"},
        {"day": 13, "title": "Almost Two Weeks", "message": "You are adjusting. It does not feel like home yet, but it will.", "focus_area": "trust"},
        {"day": 14, "title": "Adjustment Phase Done", "message": "Two weeks in. You have started to settle. Keep going.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What has surprised me about this new place?',
        'Describe how I am feeling in this transition',
        'What do I like so far? What is challenging?',
        'Write about a moment of homesickness',
        'What routines am I building here?',
        'Who do I want to become in this new place?',
        'List three things I discovered this week',
        'How am I making this space feel like home?',
        'What opportunities exist here that did not before?',
        'Write about a small victory this week',
        'What am I learning about myself through this move?',
        'What do I need more of right now?'
    ],
    '[
        {"key": "first_week_new_place", "name": "First Week in New Place", "criteria": "day >= 7"},
        {"key": "two_weeks_relocated", "name": "Two Weeks Relocated", "criteria": "day >= 14"}
    ]'::jsonb
);

-- Phase 3: Building New Roots (7 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'relocation'),
    3,
    'Building New Roots',
    'Actively creating community and belonging',
    7,
    ARRAY['Make connections', 'Get involved', 'Create meaning', 'Find your places'],
    '[
        {"day": 1, "title": "Planting Seeds", "message": "Roots take time to grow. Start planting seeds of connection.", "focus_area": "intentionality"},
        {"day": 2, "title": "Join Something", "message": "A class, a group, a volunteer opportunity - show up somewhere regularly.", "focus_area": "community"},
        {"day": 3, "title": "Your New Favorites", "message": "Which coffee shop feels right? Which park? Claim your spots.", "focus_area": "belonging"},
        {"day": 4, "title": "One Month Here", "message": "One month in. Notice how much has already shifted.", "focus_area": "milestone_celebration"},
        {"day": 5, "title": "Making Friends", "message": "Adult friendships take time. Be patient and keep showing up.", "focus_area": "relationships"},
        {"day": 6, "title": "Creating Traditions", "message": "Start new traditions here. Sunday farmers market, Friday pizza spot, Saturday hike.", "focus_area": "meaning_making"},
        {"day": 7, "title": "Roots Growing", "message": "You are no longer brand new. You are building a life here.", "focus_area": "progress"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What groups or activities am I joining?',
        'Describe someone new I have connected with',
        'What are my new favorite spots?',
        'How am I creating belonging here?',
        'What traditions do I want to start?',
        'Write about a moment when this place started feeling less foreign',
        'What is working well? What needs more attention?'
    ],
    '[
        {"key": "one_month_relocated", "name": "One Month in New Place", "criteria": "day >= 4"},
        {"key": "roots_growing", "name": "Building Roots", "criteria": "day >= 7"}
    ]'::jsonb
);

-- Phase 4: Home (7 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'relocation'),
    4,
    'Home',
    'Recognizing this new place as home',
    7,
    ARRAY['Accept this as home', 'Appreciate the journey', 'Look forward', 'Celebrate adaptation'],
    '[
        {"day": 1, "title": "It Feels Like Home", "message": "That moment when you realize - this is home now. You made it.", "focus_area": "arrival"},
        {"day": 2, "title": "You Adapted", "message": "Look how much you have adapted and grown through this transition.", "focus_area": "pride"},
        {"day": 3, "title": "Gratitude for Both", "message": "Grateful for where you were and where you are now.", "focus_area": "gratitude"},
        {"day": 4, "title": "You Belong Here", "message": "You have created belonging. This is your place now.", "focus_area": "belonging"},
        {"day": 5, "title": "Looking Forward", "message": "What do you want to create and experience in this new chapter?", "focus_area": "future_focus"},
        {"day": 6, "title": "Resilience Gained", "message": "You proved to yourself you can adapt to major change. Remember this.", "focus_area": "self_knowledge"},
        {"day": 7, "title": "Welcome Home", "message": "You are home. You built a life here. This is your place.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'When did this place start feeling like home?',
        'What do I love about living here now?',
        'How have I grown through this relocation?',
        'Write about the life I am building here',
        'What surprised me about this transition?',
        'Who am I in this new place?',
        'Write a letter to myself from six weeks ago'
    ],
    '[
        {"key": "relocation_pathway_complete", "name": "Relocation Complete - Welcome Home", "criteria": "day >= 7"}
    ]'::jsonb
);

-- ============================================================================
-- HEALTH DIAGNOSIS PATHWAY (56 days total)
-- Phase 1: Shock and Information (14 days)
-- Phase 2: Processing and Planning (14 days)
-- Phase 3: Action and Adjustment (14 days)
-- Phase 4: Living Forward (14 days)
-- ============================================================================

-- Phase 1: Shock and Information (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'health_diagnosis'),
    1,
    'Shock and Information',
    'Processing the initial shock and gathering information',
    14,
    ARRAY['Process the shock', 'Gather information', 'Build your medical team', 'Allow yourself to feel'],
    '[
        {"day": 1, "title": "The Day Everything Changed", "message": "A diagnosis divides life into before and after. Your shock is understandable.", "focus_area": "emotional_acceptance"},
        {"day": 2, "title": "Information Overload", "message": "Medical information is overwhelming. Take it one piece at a time.", "focus_area": "pacing"},
        {"day": 3, "title": "Its Okay to Fall Apart", "message": "You do not have to be strong every moment. Falling apart is processing.", "focus_area": "self_compassion"},
        {"day": 4, "title": "Your Medical Team", "message": "Build a team you trust. You are the CEO of your health.", "focus_area": "empowerment"},
        {"day": 5, "title": "Questions to Ask", "message": "Write down questions. Bring someone to appointments to help you hear the answers.", "focus_area": "advocacy"},
        {"day": 6, "title": "Telling Others", "message": "You get to choose who knows, when, and how much. This is your story to tell.", "focus_area": "boundaries"},
        {"day": 7, "title": "First Week Survived", "message": "You made it through the hardest week. One day at a time.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "The Why Question", "message": "Why me is a natural question that may have no answer. Sit with the unfairness.", "focus_area": "acceptance"},
        {"day": 9, "title": "Your Support System", "message": "Notice who shows up. Let them help in concrete ways.", "focus_area": "social_connection"},
        {"day": 10, "title": "Second Opinions", "message": "Getting another medical opinion is wise, not disloyal. Do your research.", "focus_area": "due_diligence"},
        {"day": 11, "title": "Fear of the Future", "message": "Uncertainty is terrifying. Practice staying in today as much as you can.", "focus_area": "mindfulness"},
        {"day": 12, "title": "Learning the Language", "message": "Medical terminology becomes a second language. Be patient with the learning curve.", "focus_area": "education"},
        {"day": 13, "title": "Almost Two Weeks", "message": "The shock is starting to lift. Reality is setting in. Keep breathing.", "focus_area": "presence"},
        {"day": 14, "title": "Information Gathered", "message": "You have learned so much in two weeks. You are more equipped now.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'Write about the moment you got the news',
        'What are you feeling right now? All of it, without filtering',
        'What information do you still need?',
        'Who are your people through this? Who shows up?',
        'What fears are loudest right now?',
        'List your questions for your medical team',
        'What do you need that you are not getting?',
        'Write about what has helped you get through this first week',
        'How has your perspective shifted since the diagnosis?',
        'What gives you hope or comfort right now?',
        'Describe your biggest fear about this diagnosis',
        'What are you learning about yourself?'
    ],
    '[
        {"key": "first_week_diagnosis", "name": "First Week Post-Diagnosis", "criteria": "day >= 7"},
        {"key": "two_weeks_diagnosis", "name": "Two Weeks of Processing", "criteria": "day >= 14"}
    ]'::jsonb
);

-- Phase 2: Processing and Planning (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'health_diagnosis'),
    2,
    'Processing and Planning',
    'Making treatment decisions and emotional processing',
    14,
    ARRAY['Make informed decisions', 'Process emotions', 'Prepare for treatment', 'Advocate for yourself'],
    '[
        {"day": 1, "title": "Treatment Options", "message": "Weighing treatment options is heavy. Trust yourself to make the right choice.", "focus_area": "decision_making"},
        {"day": 2, "title": "Anger Has a Place", "message": "Anger at your body, at the universe, at the unfairness - all valid.", "focus_area": "emotional_processing"},
        {"day": 3, "title": "Quality of Life", "message": "Treatment impacts quality of life. Your preferences matter in these decisions.", "focus_area": "values"},
        {"day": 4, "title": "One Month Mark", "message": "One month since the diagnosis. Notice how you have already adapted.", "focus_area": "milestone_celebration"},
        {"day": 5, "title": "Practical Preparations", "message": "Financial, logistical, work accommodations - tackle practical matters one at a time.", "focus_area": "planning"},
        {"day": 6, "title": "Your Body Betrayed You", "message": "Feeling betrayed by your body is understandable. Rebuild that relationship gently.", "focus_area": "body_relationship"},
        {"day": 7, "title": "Depression is Normal", "message": "Depression after diagnosis is common. It is not weakness. Consider professional support.", "focus_area": "mental_health"},
        {"day": 8, "title": "Hope and Realism", "message": "You can be realistic about challenges and hopeful about outcomes. Both matter.", "focus_area": "balance"},
        {"day": 9, "title": "Telling Your Story", "message": "How you tell your story to yourself shapes your experience. Choose your narrative.", "focus_area": "meaning_making"},
        {"day": 10, "title": "Support Groups", "message": "Others who have been through this get it in ways others cannot.", "focus_area": "community"},
        {"day": 11, "title": "Taking Control", "message": "In the aspects you can control - lifestyle, mindset, decisions - you have power.", "focus_area": "agency"},
        {"day": 12, "title": "Grief is Part of This", "message": "Grieving your old health, your old life, your assumptions about the future - all valid.", "focus_area": "grief"},
        {"day": 13, "title": "Treatment Plan Set", "message": "Having a plan, even a hard one, is better than uncertainty.", "focus_area": "direction"},
        {"day": 14, "title": "Ready for Action", "message": "You have processed, planned, and prepared. You are as ready as you can be.", "focus_area": "readiness"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What treatment path am I choosing and why?',
        'What am I grieving about this diagnosis?',
        'How am I taking care of my mental health?',
        'Describe the life I want on the other side of treatment',
        'What practical support do I need to arrange?',
        'Write about my relationship with my body right now',
        'Who inspires me? What stories give me hope?',
        'What am I learning to accept? What am I fighting to change?',
        'List my fears and which ones I can influence',
        'What gives me strength?',
        'How do I want to approach this treatment journey?',
        'Write a letter to my future healthy self'
    ],
    '[
        {"key": "one_month_diagnosis", "name": "One Month Post-Diagnosis", "criteria": "day >= 4"},
        {"key": "treatment_plan_set", "name": "Treatment Plan Established", "criteria": "day >= 13"},
        {"key": "processing_phase_complete", "name": "Processing Phase Complete", "criteria": "day >= 14"}
    ]'::jsonb
);

-- Phase 3: Action and Adjustment (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'health_diagnosis'),
    3,
    'Action and Adjustment',
    'Beginning treatment and adjusting to new normal',
    14,
    ARRAY['Navigate treatment', 'Manage side effects', 'Maintain hope', 'Celebrate small wins'],
    '[
        {"day": 1, "title": "Treatment Begins", "message": "This is hard and you are doing it. That takes courage.", "focus_area": "courage"},
        {"day": 2, "title": "Side Effects Are Real", "message": "Treatment is tough. Your body is working hard. Be patient and kind.", "focus_area": "self_compassion"},
        {"day": 3, "title": "One Day at a Time", "message": "Do not project too far forward. Just get through today.", "focus_area": "presence"},
        {"day": 4, "title": "Small Victories Matter", "message": "Ate a meal, took a walk, laughed once - celebrate all of it.", "focus_area": "gratitude"},
        {"day": 5, "title": "Asking for Help", "message": "You cannot do this alone. Specific requests make it easier for people to help.", "focus_area": "vulnerability"},
        {"day": 6, "title": "Identity Beyond Patient", "message": "You are not just your diagnosis. Remember the other parts of who you are.", "focus_area": "identity"},
        {"day": 7, "title": "Halfway Through Phase", "message": "You are doing hard things and still showing up. That is strength.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Bad Days Will Come", "message": "Bad days do not mean treatment is not working. Ride them out.", "focus_area": "endurance"},
        {"day": 9, "title": "Finding Joy", "message": "Joy can exist alongside struggle. Notice moments of lightness.", "focus_area": "mindfulness"},
        {"day": 10, "title": "Your Medical Advocates", "message": "Speak up about side effects, concerns, needs. You are your best advocate.", "focus_area": "self_advocacy"},
        {"day": 11, "title": "Comparison is Futile", "message": "Your journey is unique. Comparing to others timelines or experiences helps no one.", "focus_area": "acceptance"},
        {"day": 12, "title": "Moments of Normal", "message": "Crave and protect moments of normalcy. They sustain you.", "focus_area": "balance"},
        {"day": 13, "title": "You Are Resilient", "message": "Look how much you have handled. Your resilience is remarkable.", "focus_area": "self_recognition"},
        {"day": 14, "title": "Adjusting to New Normal", "message": "This is your life now and you are learning to live it well.", "focus_area": "acceptance"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'How am I coping with treatment so far?',
        'What has been harder than expected? Easier?',
        'List three small victories from this week',
        'Who or what is getting me through this?',
        'Write about a good moment this week',
        'What do I need to tell my medical team?',
        'How am I taking care of myself emotionally?',
        'Describe a moment when I felt strong',
        'What am I learning about resilience?',
        'What brings me comfort right now?',
        'How has my relationship with my body shifted?',
        'Write about who I am beyond this diagnosis'
    ],
    '[
        {"key": "treatment_started", "name": "Treatment Journey Begun", "criteria": "day >= 1"},
        {"key": "halfway_through_action", "name": "Halfway Through Action Phase", "criteria": "day >= 7"},
        {"key": "action_phase_complete", "name": "Action Phase Complete", "criteria": "day >= 14"}
    ]'::jsonb
);

-- Phase 4: Living Forward (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'health_diagnosis'),
    4,
    'Living Forward',
    'Integrating your diagnosis into your life story and moving forward',
    14,
    ARRAY['Embrace uncertainty', 'Live fully now', 'Find meaning', 'Continue healing'],
    '[
        {"day": 1, "title": "Living With Uncertainty", "message": "Medical uncertainty may always exist. Learning to live with it is the work.", "focus_area": "acceptance"},
        {"day": 2, "title": "What Matters Most", "message": "Illness clarifies what matters. Are you living according to those priorities?", "focus_area": "values"},
        {"day": 3, "title": "Post-Traumatic Growth", "message": "Trauma can lead to growth. Notice how you have changed for the better.", "focus_area": "meaning_making"},
        {"day": 4, "title": "Your New Perspective", "message": "Health challenges shift perspective. What do you see differently now?", "focus_area": "wisdom"},
        {"day": 5, "title": "Gratitude Practice", "message": "For your body fighting, for people who showed up, for moments of relief.", "focus_area": "gratitude"},
        {"day": 6, "title": "Living Fully Now", "message": "Do not wait for someday. Live the life you want to live now.", "focus_area": "presence"},
        {"day": 7, "title": "Two Months Mark", "message": "Eight weeks into this journey. Look how far you have come.", "focus_area": "milestone_celebration"},
        {"day": 8, "title": "Redefining Health", "message": "Health is not absence of disease but ability to adapt and thrive despite it.", "focus_area": "redefinition"},
        {"day": 9, "title": "Your Legacy", "message": "How do you want to live through this? What do you want others to learn from you?", "focus_area": "meaning_making"},
        {"day": 10, "title": "Advocacy and Activism", "message": "Some find purpose in advocating for others facing similar diagnoses.", "focus_area": "purpose"},
        {"day": 11, "title": "Celebrating Your Body", "message": "Your body is fighting for you every day. Thank it and honor it.", "focus_area": "body_appreciation"},
        {"day": 12, "title": "Hope Forward", "message": "Hope is not denial. It is choosing to focus on possibility.", "focus_area": "hope"},
        {"day": 13, "title": "You Are Still You", "message": "Diagnosis is part of your story now, but it does not define you.", "focus_area": "identity"},
        {"day": 14, "title": "Pathway Complete", "message": "You have navigated this transition with grace. You are living forward.", "focus_area": "milestone_celebration"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'How has this diagnosis changed my perspective on life?',
        'What matters most to me now?',
        'In what ways have I grown through this experience?',
        'What am I grateful for?',
        'How do I want to live going forward?',
        'Write about the relationship with my body now',
        'What wisdom have I gained?',
        'If I could tell someone newly diagnosed one thing, what would it be?',
        'Describe a moment of beauty or joy this week',
        'What gives me hope?',
        'How do I define health now?',
        'Write a letter to myself about this journey'
    ],
    '[
        {"key": "two_months_diagnosis", "name": "Two Months Since Diagnosis", "criteria": "day >= 7"},
        {"key": "health_diagnosis_pathway_complete", "name": "Health Diagnosis Pathway Complete", "criteria": "day >= 14"}
    ]'::jsonb
);
