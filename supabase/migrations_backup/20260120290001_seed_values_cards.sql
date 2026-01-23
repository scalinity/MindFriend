-- Values Cards Library Seed Data
-- Created: 2026-01-20
-- 32 predefined values across 4 categories (8 per category)

-- =============================================================================
-- Personal Category (8 values)
-- =============================================================================
INSERT INTO values_cards (value_key, display_name, description, category, icon, questions, examples)
VALUES
    ('autonomy', 'Autonomy', 'The freedom to make your own choices and live by your own standards.', 'personal', 'figure.walk',
     ARRAY['When do you feel most in control of your life?', 'What decisions do you want more freedom in?'],
     ARRAY['Choosing your career path', 'Setting your own schedule', 'Making personal health choices']),

    ('growth', 'Growth', 'Continuous learning, self-improvement, and personal evolution.', 'personal', 'chart.line.uptrend.xyaxis',
     ARRAY['What areas of your life do you want to grow in?', 'How do you challenge yourself?'],
     ARRAY['Taking courses to learn new skills', 'Seeking feedback and acting on it', 'Stepping outside your comfort zone']),

    ('security', 'Security', 'Safety, stability, and freedom from worry about basic needs.', 'personal', 'lock.shield',
     ARRAY['What makes you feel safe and stable?', 'What would give you peace of mind?'],
     ARRAY['Having emergency savings', 'Stable employment', 'Secure housing']),

    ('freedom', 'Freedom', 'Independence and the ability to live without constraints.', 'personal', 'bird',
     ARRAY['What constraints do you want to break free from?', 'How would you spend your time if totally free?'],
     ARRAY['Location independence', 'Financial freedom', 'Freedom to travel']),

    ('creativity', 'Creativity', 'Expressing yourself through original ideas and self-expression.', 'personal', 'paintbrush',
     ARRAY['When do you feel most creative?', 'What forms of expression matter to you?'],
     ARRAY['Making art or music', 'Solving problems in novel ways', 'Decorating your space']),

    ('adventure', 'Adventure', 'Seeking new experiences, excitement, and the unknown.', 'personal', 'mountain.2',
     ARRAY['What new experiences excite you?', 'What adventures have you been putting off?'],
     ARRAY['Traveling to new places', 'Trying extreme sports', 'Starting a new venture']),

    ('stability', 'Stability', 'Consistency, predictability, and reliable routines.', 'personal', 'circle.grid.cross',
     ARRAY['What routines bring you comfort?', 'Where do you need more consistency?'],
     ARRAY['Regular sleep schedule', 'Steady income', 'Familiar environment']),

    ('achievement', 'Achievement', 'Accomplishing goals and reaching your full potential.', 'personal', 'rosette',
     ARRAY['What goals are you working toward?', 'How do you define success?'],
     ARRAY['Completing a degree', 'Getting promoted', 'Running a marathon']),

-- =============================================================================
-- Relationships Category (8 values)
-- =============================================================================
    ('connection', 'Connection', 'Deep, meaningful bonds with others; feeling understood and valued.', 'relationships', 'person.2',
     ARRAY['Who do you feel most connected to?', 'What deepens your relationships?'],
     ARRAY['Having heart-to-heart conversations', 'Spending quality time with loved ones', 'Being vulnerable with others']),

    ('love', 'Love', 'Giving and receiving affection, care, and romantic connection.', 'relationships', 'heart',
     ARRAY['How do you express love?', 'What makes you feel loved?'],
     ARRAY['Physical affection', 'Saying "I love you"', 'Acts of service for partners']),

    ('kindness', 'Kindness', 'Being compassionate, considerate, and gentle with others.', 'relationships', 'leaf',
     ARRAY['When are you most kind to others?', 'Who deserves more kindness from you?'],
     ARRAY['Helping a stranger', 'Forgiving someone', 'Listening without judgment']),

    ('support', 'Support', 'Being there for others and having people there for you.', 'relationships', 'hands.sparkles',
     ARRAY['Who do you support?', 'Who supports you?'],
     ARRAY['Being a shoulder to cry on', 'Celebrating others'' wins', 'Asking for help when needed']),

    ('trust', 'Trust', 'Reliability, honesty, and confidence in your relationships.', 'relationships', 'checkmark.seal',
     ARRAY['Who do you trust completely?', 'How do you build trust?'],
     ARRAY['Keeping promises', 'Being honest even when it''s hard', 'Respecting confidences']),

    ('belonging', 'Belonging', 'Feeling accepted and part of a group or community.', 'relationships', 'person.3',
     ARRAY['Where do you feel you belong?', 'What communities matter to you?'],
     ARRAY['Family gatherings', 'Clubs or groups', 'Workplace culture']),

    ('community', 'Community', 'Contributing to and being part of something larger than yourself.', 'relationships', 'building.2',
     ARRAY['What communities do you serve?', 'How do you contribute?'],
     ARRAY['Volunteering locally', 'Neighborhood involvement', 'Supporting local businesses']),

    ('intimacy', 'Intimacy', 'Emotional and physical closeness; being truly known by others.', 'relationships', 'heart.circle',
     ARRAY['What level of closeness feels right?', 'How do you create intimacy?'],
     ARRAY['Sharing your fears and dreams', 'Physical touch', 'Quality one-on-one time']),

-- =============================================================================
-- Work Category (8 values)
-- =============================================================================
    ('purpose', 'Purpose', 'Doing work that feels meaningful and aligned with your values.', 'work', 'target',
     ARRAY['What gives your work meaning?', 'How does your work align with your purpose?'],
     ARRAY['Helping people improve their lives', 'Solving important problems', 'Creating something valuable']),

    ('mastery', 'Mastery', 'Becoming highly skilled and excellent at what you do.', 'work', 'medal',
     ARRAY['What skills do you want to master?', 'Where do you strive for excellence?'],
     ARRAY['Practicing your craft daily', 'Seeking expert mentorship', 'Continuous improvement']),

    ('recognition', 'Recognition', 'Being acknowledged and appreciated for your contributions.', 'work', 'star',
     ARRAY['When do you feel appreciated?', 'What recognition matters to you?'],
     ARRAY['Receiving praise from managers', 'Awards or promotions', 'Positive client feedback']),

    ('balance', 'Balance', 'Maintaining harmony between work and personal life.', 'work', 'scale.3d',
     ARRAY['What does balance look like for you?', 'Where are you out of balance?'],
     ARRAY['Leaving work at work', 'Having time for hobbies', 'Setting boundaries']),

    ('impact', 'Impact', 'Making a tangible difference through your work.', 'work', 'bolt.fill',
     ARRAY['What impact do you want to have?', 'How do you measure your impact?'],
     ARRAY['Changing lives', 'Improving systems', 'Leaving things better than you found them']),

    ('independence', 'Independence', 'Working autonomously without constant oversight.', 'work', 'arrow.up.right',
     ARRAY['When do you work best alone?', 'What decisions do you want to own?'],
     ARRAY['Managing your own projects', 'Setting your own priorities', 'Freelancing or entrepreneurship']),

    ('contribution', 'Contribution', 'Adding value and making things better for others.', 'work', 'gift',
     ARRAY['What do you contribute?', 'How do you add value?'],
     ARRAY['Sharing your expertise', 'Mentoring others', 'Innovating solutions']),

    ('excellence', 'Excellence', 'Holding yourself to high standards and producing quality work.', 'work', 'crown',
     ARRAY['Where do you demand excellence?', 'What does quality mean to you?'],
     ARRAY['Attention to detail', 'Going above and beyond', 'Never settling for "good enough"']),

-- =============================================================================
-- Growth Category (8 values)
-- =============================================================================
    ('learning', 'Learning', 'Acquiring new knowledge and skills throughout life.', 'growth', 'book',
     ARRAY['What do you want to learn?', 'How do you learn best?'],
     ARRAY['Reading books', 'Taking courses', 'Learning from experience']),

    ('wisdom', 'Wisdom', 'Seeking deep understanding and applying knowledge wisely.', 'growth', 'brain',
     ARRAY['Who do you turn to for wisdom?', 'What wisdom have you gained?'],
     ARRAY['Reflecting on life lessons', 'Seeking mentors', 'Learning from mistakes']),

    ('reflection', 'Reflection', 'Taking time to think deeply about yourself and your life.', 'growth', 'moon.stars',
     ARRAY['When do you reflect?', 'What do you learn from reflection?'],
     ARRAY['Journaling', 'Meditation', 'Long walks alone']),

    ('challenge', 'Challenge', 'Pushing yourself beyond your current limits.', 'growth', 'flag.checkered',
     ARRAY['What challenges excite you?', 'Where do you need to push harder?'],
     ARRAY['Setting ambitious goals', 'Competing', 'Taking on difficult projects']),

    ('curiosity', 'Curiosity', 'Wondering, questioning, and exploring the world around you.', 'growth', 'magnifyingglass',
     ARRAY['What are you curious about?', 'How do you satisfy your curiosity?'],
     ARRAY['Asking questions', 'Experimenting', 'Exploring new ideas']),

    ('evolution', 'Evolution', 'Becoming the best version of yourself over time.', 'growth', 'arrow.triangle.2.circlepath',
     ARRAY['How have you evolved?', 'Who are you becoming?'],
     ARRAY['Changing old habits', 'Developing new perspectives', 'Letting go of what no longer serves you']),

    ('self_awareness', 'Self-Awareness', 'Understanding your emotions, motivations, and patterns.', 'growth', 'eye',
     ARRAY['What have you learned about yourself?', 'What patterns do you notice?'],
     ARRAY['Therapy or coaching', 'Personality assessments', 'Noticing your triggers']),

    ('health', 'Health', 'Taking care of your physical, mental, and emotional well-being.', 'growth', 'heart.text.square',
     ARRAY['How do you prioritize your health?', 'What does wellness mean to you?'],
     ARRAY['Regular exercise', 'Healthy eating', 'Mental health care', 'Adequate sleep'])

ON CONFLICT (value_key) DO NOTHING;

-- =============================================================================
-- Verification Query (for testing)
-- =============================================================================

-- Uncomment below to verify seed data after migration:
-- SELECT category, COUNT(*) as count
-- FROM values_cards
-- GROUP BY category
-- ORDER BY category;
-- Expected result: 4 rows with 8 values each
