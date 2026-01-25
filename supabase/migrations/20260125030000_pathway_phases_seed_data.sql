-- Migration: Pathway Phases Seed Data
-- Purpose: Populate pathway_phases table with daily themes, journal prompts, and milestones
-- Date: 2026-01-25
-- Note: Daily themes use JSON format. Exercises arrays left empty for now.

-- ==========================================
-- JOB_LOSS PATHWAY (8 weeks = 56 days)
-- ==========================================

-- Phase 1: Acknowledge (14 days, weeks 1-2)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'job_loss'),
    1,
    'Acknowledge',
    'Processing the change and initial emotions',
    14,
    ARRAY['Accept what has happened', 'Allow yourself to feel', 'Establish daily structure', 'Reach out for support'],
    '[
        {"day": 1, "title": "The First Step", "message": "Today we begin your journey through this career transition. Its okay to feel uncertain - that is completely normal.", "focus_area": "emotional_acceptance"},
        {"day": 2, "title": "Feeling It All", "message": "All emotions are valid. Anger, sadness, relief - whatever you feel is okay.", "focus_area": "emotional_processing"},
        {"day": 3, "title": "Your Worth", "message": "Your value is not defined by your job title. You are so much more.", "focus_area": "self_worth"},
        {"day": 4, "title": "The Basics", "message": "Today, focus on the fundamentals: sleep, food, movement, connection.", "focus_area": "self_care"},
        {"day": 5, "title": "Asking for Help", "message": "Reaching out for support is strength, not weakness. Who can you talk to today?", "focus_area": "support_network"},
        {"day": 6, "title": "Small Wins", "message": "Celebrate every small accomplishment. Getting out of bed counts.", "focus_area": "progress_recognition"},
        {"day": 7, "title": "One Week", "message": "You have made it through your first week. That takes courage.", "focus_area": "milestone_reflection"},
        {"day": 8, "title": "Routines Matter", "message": "Creating structure helps create stability. What routine can you start today?", "focus_area": "daily_structure"},
        {"day": 9, "title": "Financial Clarity", "message": "Take one small step toward understanding your financial situation. Knowledge reduces anxiety.", "focus_area": "practical_planning"},
        {"day": 10, "title": "Your Story", "message": "How you tell your story matters. Practice a version that feels true and empowering.", "focus_area": "narrative_building"},
        {"day": 11, "title": "Permission to Rest", "message": "Rest is productive. Your body and mind need time to process.", "focus_area": "rest_recovery"},
        {"day": 12, "title": "Future Self", "message": "Your future self will thank you for the care you are taking now.", "focus_area": "forward_thinking"},
        {"day": 13, "title": "Community", "message": "You are not alone in this. Many have walked this path before you.", "focus_area": "connection"},
        {"day": 14, "title": "Ready to Build", "message": "You have acknowledged the change. Now we begin to build your foundation.", "focus_area": "phase_transition"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'Write about your first day after the news. What did you feel? What surprised you?',
        'List three things you valued about your previous work. Now list three things you did not.',
        'Who has been supportive during this time? Write them a gratitude note.',
        'Describe your ideal work day. Do not think about job titles - think about how you want to feel.',
        'What fears are coming up for you? Name them. Sometimes naming reduces their power.',
        'Write a letter to your past self on your first day at that job. What would you say?',
        'What routines from your old job served you well? Which can you keep?',
        'If a friend were going through this, what would you tell them?',
        'What skills do you have that you are proud of? List at least 10.',
        'What does success mean to you now? Has this changed?',
        'Write about a time you overcame a challenge. What strengths did you use?',
        'What are you learning about yourself through this transition?'
    ],
    '[
        {"key": "first_week_complete", "name": "First Week Complete", "description": "You made it through the first week of transition", "criteria": "day >= 7"},
        {"key": "acknowledge_complete", "name": "Acknowledgment Phase Complete", "description": "Ready to move to building stability", "criteria": "day >= 14"}
    ]'::jsonb
);

-- Phase 2: Stabilize (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'job_loss'),
    2,
    'Stabilize',
    'Creating routine and self-care foundation',
    14,
    ARRAY['Build consistent daily routines', 'Strengthen support network', 'Clarify financial situation', 'Practice self-compassion'],
    '[
        {"day": 1, "title": "Morning Anchor", "message": "What is one morning ritual that makes you feel grounded? Start there.", "focus_area": "routine_building"},
        {"day": 2, "title": "Energy Mapping", "message": "Notice when your energy is highest. Use that time wisely.", "focus_area": "self_awareness"},
        {"day": 3, "title": "Support Check", "message": "Schedule time with someone who lifts you up. Put it in your calendar.", "focus_area": "social_connection"},
        {"day": 4, "title": "Financial Foundation", "message": "Review your budget. One step at a time builds clarity.", "focus_area": "financial_planning"},
        {"day": 5, "title": "Skills Inventory", "message": "Make a list of all your skills - hard and soft. You have more than you think.", "focus_area": "skill_recognition"},
        {"day": 6, "title": "Learning Mode", "message": "Is there a skill you have wanted to develop? Now might be the time.", "focus_area": "growth_mindset"},
        {"day": 7, "title": "Halfway Mark", "message": "You are halfway through this phase. Notice how far you have come.", "focus_area": "progress_check"},
        {"day": 8, "title": "Boundary Practice", "message": "It is okay to say no. Protect your energy.", "focus_area": "boundaries"},
        {"day": 9, "title": "Resume Refresh", "message": "Update your resume to reflect your accomplishments. See your value on paper.", "focus_area": "professional_preparation"},
        {"day": 10, "title": "Network Gently", "message": "Reach out to one former colleague. Just to say hello.", "focus_area": "networking"},
        {"day": 11, "title": "Self-Care Audit", "message": "Rate your sleep, nutrition, movement, and social connection. Where can you improve?", "focus_area": "holistic_health"},
        {"day": 12, "title": "Gratitude Practice", "message": "Even in difficulty, there are gifts. What are you unexpectedly grateful for?", "focus_area": "gratitude"},
        {"day": 13, "title": "Confidence Building", "message": "Recall a professional win. Let yourself feel proud.", "focus_area": "confidence"},
        {"day": 14, "title": "Ready to Reflect", "message": "You have built your foundation. Now we explore what you truly want.", "focus_area": "phase_transition"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'What does your ideal daily routine look like? Be specific about times and activities.',
        'Write about a time at work when you felt most alive. What were you doing?',
        'Who in your network could you reconnect with? Make a list of 5 people.',
        'What are your non-negotiables for your next role?',
        'Describe your relationship with money and work. How do you want it to change?',
        'What would you do if you knew you could not fail?',
        'List 5 accomplishments you are proud of. Include evidence of impact.',
        'What feedback have you received that affirmed your strengths?',
        'If you could design your perfect workday from scratch, what would it include?',
        'What lessons has this transition taught you?',
        'Write a brag sheet - all your wins, big and small.',
        'What support do you need that you are not asking for?'
    ],
    '[
        {"key": "three_week_streak", "name": "Three Weeks Strong", "description": "Maintained engagement for three weeks", "criteria": "day >= 21"},
        {"key": "stabilize_complete", "name": "Stability Phase Complete", "description": "Ready to reflect deeply on your path", "criteria": "day >= 28"}
    ]'::jsonb
);

-- Phase 3: Reflect (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'job_loss'),
    3,
    'Reflect',
    'Understanding what you want next',
    14,
    ARRAY['Identify core values', 'Clarify career goals', 'Explore new possibilities', 'Build job search strategy'],
    '[
        {"day": 1, "title": "Values Clarity", "message": "What matters most to you in your work? Identify your top 5 values.", "focus_area": "values_exploration"},
        {"day": 2, "title": "Pattern Recognition", "message": "Look at your career history. What patterns do you notice?", "focus_area": "self_discovery"},
        {"day": 3, "title": "Strengths Focus", "message": "What do people regularly ask for your help with? That is a clue to your gifts.", "focus_area": "strength_identification"},
        {"day": 4, "title": "Dream Job Vision", "message": "If you could design your ideal role, what would it look like?", "focus_area": "visioning"},
        {"day": 5, "title": "Industry Exploration", "message": "Research an industry you are curious about. What excites you?", "focus_area": "exploration"},
        {"day": 6, "title": "Informational Interviews", "message": "Reach out to someone doing work you admire. Ask for 20 minutes to learn.", "focus_area": "research"},
        {"day": 7, "title": "Reflection Checkpoint", "message": "What insights have emerged this week? Write them down.", "focus_area": "integration"},
        {"day": 8, "title": "Skills Gap Analysis", "message": "What skills do you need to develop for your desired direction?", "focus_area": "learning_needs"},
        {"day": 9, "title": "Company Culture", "message": "What type of culture brings out your best? Define it clearly.", "focus_area": "environment_fit"},
        {"day": 10, "title": "Compensation Clarity", "message": "Research salary ranges for roles you are targeting. Know your worth.", "focus_area": "market_research"},
        {"day": 11, "title": "Plan Draft", "message": "Sketch out a 3-month action plan. It does not have to be perfect.", "focus_area": "planning"},
        {"day": 12, "title": "Confidence Check", "message": "How does your vision feel? Exciting? Scary? Both is good.", "focus_area": "emotional_check"},
        {"day": 13, "title": "Support Update", "message": "Share your emerging direction with a trusted friend. Speaking it makes it real.", "focus_area": "accountability"},
        {"day": 14, "title": "Ready to Rebuild", "message": "You know what you want. Now we take action to make it happen.", "focus_area": "phase_transition"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'Write your personal mission statement. What impact do you want to have through your work?',
        'Describe your ideal work environment in detail. Remote? Collaborative? Quiet?',
        'What would you tell someone considering the career path you are exploring?',
        'List 10 companies or organizations whose mission resonates with you.',
        'What are you willing to sacrifice for? What is non-negotiable?',
        'Write about a mentor or role model. What qualities do they embody?',
        'If money were not a factor, what work would you do?',
        'What does meaningful work mean to you?',
        'Describe your career in 5 years. Where are you? What are you doing?',
        'What strengths do you want to develop further?',
        'Write a job description for your dream role.',
        'What limiting beliefs about your career need to be released?'
    ],
    '[
        {"key": "one_month_milestone", "name": "One Month Journey", "description": "Sustained engagement for a full month", "criteria": "day >= 30"},
        {"key": "reflect_complete", "name": "Reflection Phase Complete", "description": "Ready to take action on your vision", "criteria": "day >= 42"}
    ]'::jsonb
);

-- Phase 4: Rebuild (14 days)
INSERT INTO pathway_phases (pathway_id, phase_number, name, description, duration_days, objectives, daily_themes, exercises, journal_prompts, milestones)
VALUES (
    (SELECT id FROM transition_pathways WHERE key = 'job_loss'),
    4,
    'Rebuild',
    'Taking action toward your goals',
    14,
    ARRAY['Execute job search strategy', 'Build interview confidence', 'Expand professional network', 'Negotiate effectively'],
    '[
        {"day": 1, "title": "Action Mode", "message": "Today you transition from planning to doing. One application. One connection. Begin.", "focus_area": "activation"},
        {"day": 2, "title": "Application Strategy", "message": "Quality over quantity. Tailor each application to show you understand the role.", "focus_area": "strategic_action"},
        {"day": 3, "title": "LinkedIn Optimization", "message": "Update your profile to reflect where you are going, not just where you have been.", "focus_area": "online_presence"},
        {"day": 4, "title": "Interview Prep", "message": "Practice telling your story. Record yourself. Listen back.", "focus_area": "preparation"},
        {"day": 5, "title": "Network Activation", "message": "Let your network know you are looking. Most opportunities come from connections.", "focus_area": "networking"},
        {"day": 6, "title": "Rejection Resilience", "message": "Every no gets you closer to yes. Do not take it personally.", "focus_area": "resilience"},
        {"day": 7, "title": "Progress Check", "message": "Reflect on your efforts this week. What is working? What needs adjustment?", "focus_area": "iteration"},
        {"day": 8, "title": "Portfolio Building", "message": "Create tangible evidence of your capabilities. Projects, writing, whatever showcases your skills.", "focus_area": "credibility"},
        {"day": 9, "title": "Interview Follow-Up", "message": "Send thoughtful thank-you notes after every conversation. It matters.", "focus_area": "professionalism"},
        {"day": 10, "title": "Salary Negotiation", "message": "Know your worth. Practice saying your number out loud until it feels comfortable.", "focus_area": "negotiation"},
        {"day": 11, "title": "Offer Evaluation", "message": "When offers come, evaluate the whole package: culture, growth, compensation, values alignment.", "focus_area": "decision_making"},
        {"day": 12, "title": "Confidence Boost", "message": "You have come so far. You are capable. You are ready.", "focus_area": "self_belief"},
        {"day": 13, "title": "Future Vision", "message": "Imagine your first day at your new role. How does it feel?", "focus_area": "manifestation"},
        {"day": 14, "title": "Journey Complete", "message": "Whether you have landed a role or are still searching, you have grown immensely. Celebrate that.", "focus_area": "completion"}
    ]'::jsonb,
    ARRAY[]::text[],
    ARRAY[
        'Write your why statement. Why are you the right fit for the roles you are pursuing?',
        'Practice answering Tell me about yourself in writing. Then say it out loud.',
        'What makes you unique as a candidate? List 5 specific qualities.',
        'Write about a challenge you overcame at work. Use the STAR method.',
        'What questions will you ask in interviews to evaluate culture fit?',
        'Draft your negotiation talking points. What do you bring to the table?',
        'Reflect on an interview that went well. What did you do right?',
        'What would you do in your first 90 days in a new role?',
        'Write a thank-you note template you can customize after interviews.',
        'What support do you need during this active search phase?',
        'Describe your ideal onboarding experience.',
        'What has this entire transition taught you about yourself?'
    ],
    '[
        {"key": "first_application", "name": "First Application Sent", "description": "Took action toward your next opportunity", "criteria": "check_ins >= 1"},
        {"key": "pathway_complete", "name": "Career Transition Journey Complete", "description": "Completed the full 8-week pathway", "criteria": "day >= 56"}
    ]'::jsonb
);

-- Note: Remaining pathway phases (breakup, grief, new_parent, relocation, health_diagnosis)
-- will be added in subsequent migrations to keep file sizes manageable.
-- Each pathway will have 4 complete phases with daily themes, journal prompts, and milestones.
