-- =====================================================================================================================
-- Migration: 20260221000000_therapeutic_programs_seed.sql
-- Description: Seed 15 production-grade therapeutic programs (CBT×6, DBT×4, ACT×3, MBCT×2) with clinical metadata
-- Spec: Therapeutic Programs specification v1.0
-- Date: 2026-01-20
-- =====================================================================================================================

-- =====================================================================================================================
-- MARK: - CBT Programs (6 total)
-- =====================================================================================================================

-- P01: Overcoming Anxiety with CBT (7 days, Beginner, FREE)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'cbt-anxiety-7day',
  'Overcoming Anxiety with CBT',
  'Learn evidence-based Cognitive Behavioral Therapy techniques to manage generalized anxiety and worry. This 7-day program teaches you to identify anxious thought patterns, challenge cognitive distortions, and build a practical toolkit for lasting calm.',
  7,
  'anxiety',
  'beginner',
  FALSE,
  '["Understand the cognitive model of anxiety", "Identify your personal anxiety triggers and patterns", "Master the thought record technique for challenging anxious thoughts", "Recognize and reframe cognitive distortions", "Build a personalized anxiety management toolkit"]'::jsonb,
  ARRAY['anxiety', 'cbt', 'evidence-based', 'worry', 'calm'],
  15,
  10,
  'cbt',
  'Cognitive Behavioral Therapy is the gold-standard treatment for anxiety disorders, with over 50 years of research demonstrating effectiveness. Meta-analyses show 60-70% response rates for generalized anxiety.',
  'https://pubmed.ncbi.nlm.nih.gov/16199119/',
  ARRAY['Generalized Anxiety', 'Worry', 'Nervousness', 'Anxious Thoughts'],
  TRUE,
  'gad7'
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- P02: CBT for Depression (14 days, Beginner, FREE)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'cbt-depression-14day',
  'CBT for Depression',
  'Evidence-based Cognitive Behavioral Therapy program for managing depression. Learn behavioral activation, thought challenging, and problem-solving skills to improve mood and regain motivation over 14 structured days.',
  14,
  'custom',  -- Changed from 'stress' to 'custom' since depression doesn't fit existing categories
  'beginner',
  FALSE,
  '["Understand the cognitive model of depression", "Practice behavioral activation to increase positive activities", "Challenge depressive thinking patterns", "Develop problem-solving skills", "Build a relapse prevention plan"]'::jsonb,
  ARRAY['depression', 'cbt', 'mood', 'evidence-based', 'behavioral-activation'],
  18,
  11,
  'cbt',
  'CBT for depression has the most extensive evidence base of any psychotherapy, with hundreds of RCTs demonstrating significant symptom reduction and relapse prevention effects comparable to antidepressants.',
  'https://pubmed.ncbi.nlm.nih.gov/16199119/',
  ARRAY['Depression', 'Low Mood', 'Anhedonia', 'Motivation Loss'],
  TRUE,
  'phq9'  -- Correct - PHQ-9 is the depression assessment
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- P03: Managing OCD with CBT (21 days, Intermediate, PREMIUM)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'cbt-ocd-21day',
  'Managing OCD with CBT',
  'Intensive CBT program using Exposure and Response Prevention (ERP) for obsessive-compulsive disorder. Learn to face intrusive thoughts and compulsions with evidence-based techniques over 21 structured days.',
  21,
  'anxiety',
  'intermediate',
  TRUE,
  '["Understand the OCD cycle", "Learn Exposure and Response Prevention (ERP)", "Create an exposure hierarchy", "Practice response prevention strategies", "Build long-term OCD management skills"]'::jsonb,
  ARRAY['ocd', 'cbt', 'erp', 'intrusive-thoughts', 'compulsions'],
  20,
  12,
  'cbt',
  'ERP is the most effective psychological treatment for OCD, with 60-85% of patients achieving significant symptom reduction. Meta-analyses show large effect sizes maintained at follow-up.',
  'https://pubmed.ncbi.nlm.nih.gov/23504697/',
  ARRAY['OCD', 'Obsessions', 'Compulsions', 'Intrusive Thoughts'],
  FALSE,  -- Changed from TRUE - no appropriate assessment available yet
  NULL    -- Changed from 'phq9' to NULL
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- P04: Panic Disorder Relief (10 days, Intermediate, PREMIUM)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'cbt-panic-10day',
  'Panic Disorder Relief',
  'Specialized CBT program for panic attacks and panic disorder. Learn interoceptive exposure, cognitive restructuring of catastrophic thoughts, and strategies to break the panic cycle in 10 focused days.',
  10,
  'anxiety',
  'intermediate',
  TRUE,
  '["Understand panic attacks and the panic cycle", "Practice interoceptive exposure", "Challenge catastrophic thinking", "Eliminate safety behaviors", "Build confidence in managing panic"]'::jsonb,
  ARRAY['panic', 'cbt', 'panic-attacks', 'interoceptive-exposure'],
  17,
  13,
  'cbt',
  'CBT for panic disorder (including interoceptive exposure) shows 70-90% response rates in controlled trials, with most patients panic-free at follow-up.',
  'https://pubmed.ncbi.nlm.nih.gov/12002350/',
  ARRAY['Panic Attacks', 'Panic Disorder', 'Agoraphobia'],
  TRUE,
  'gad7'
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- P05: Social Anxiety Mastery (14 days, Intermediate, PREMIUM)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'cbt-social-anxiety-14day',
  'Social Anxiety Mastery',
  'Evidence-based CBT program for social anxiety and performance fears. Learn attention training, cognitive restructuring, and graduated exposure to social situations over 14 supportive days.',
  14,
  'anxiety',
  'intermediate',
  TRUE,
  '["Understand social anxiety patterns", "Identify safety behaviors", "Practice attention redirection", "Challenge social threat beliefs", "Conduct behavioral experiments in social settings"]'::jsonb,
  ARRAY['social-anxiety', 'cbt', 'performance-anxiety', 'exposure'],
  16,
  14,
  'cbt',
  'CBT for social anxiety (including cognitive restructuring and exposure) is highly effective, with 75-80% of patients achieving clinically significant improvement sustained over years.',
  'https://pubmed.ncbi.nlm.nih.gov/11936120/',
  ARRAY['Social Anxiety', 'Performance Anxiety', 'Public Speaking Fear'],
  TRUE,
  'gad7'
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- P06: Insomnia Solutions (CBT-I) (10 days, Beginner, PREMIUM)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'cbt-insomnia-10day',
  'Insomnia Solutions (CBT-I)',
  'Cognitive Behavioral Therapy for Insomnia (CBT-I) program. Learn sleep restriction, stimulus control, and cognitive techniques to overcome chronic insomnia in 10 structured nights.',
  10,
  'sleep',
  'beginner',
  TRUE,
  '["Understand sleep architecture and insomnia", "Practice sleep restriction therapy", "Apply stimulus control techniques", "Challenge sleep-interfering thoughts", "Build healthy sleep habits"]'::jsonb,
  ARRAY['insomnia', 'sleep', 'cbt-i', 'sleep-hygiene'],
  12,
  15,
  'cbt',
  'CBT-I is the first-line treatment for chronic insomnia recommended by medical guidelines. Meta-analyses show 70-80% of patients achieve significant improvement without medication.',
  'https://pubmed.ncbi.nlm.nih.gov/26135274/',
  ARRAY['Insomnia', 'Sleep Problems', 'Sleep Onset Difficulty'],
  FALSE,
  NULL
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- =====================================================================================================================
-- MARK: - DBT Programs (4 total)
-- =====================================================================================================================

-- P07: DBT Distress Tolerance (10 days, Beginner, FREE)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'dbt-distress-tolerance-10day',
  'DBT Distress Tolerance',
  'Learn Dialectical Behavior Therapy skills to survive emotional crises without making things worse. Master STOP, TIPP, ACCEPTS, and radical acceptance techniques in 10 focused days.',
  10,
  'stress',
  'beginner',
  FALSE,
  '["Understand dialectical thinking", "Master crisis survival skills (STOP, TIPP, ACCEPTS)", "Practice radical acceptance", "Build distress tolerance without destructive behaviors", "Create a personalized crisis survival kit"]'::jsonb,
  ARRAY['dbt', 'distress-tolerance', 'crisis-skills', 'emotion-regulation'],
  15,
  20,
  'dbt',
  'DBT distress tolerance skills significantly reduce self-destructive behaviors and emotional dysregulation. Research shows sustained improvements in crisis management and impulsivity reduction.',
  'https://www.guilford.com/books/DBT-Skills-Training-Manual/Marsha-Linehan/9781462516995',
  ARRAY['Emotional Overwhelm', 'Crisis Management', 'Distress', 'Impulsivity'],
  TRUE,
  'phq9'
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- P08: Emotion Regulation Skills (DBT) (14 days, Intermediate, PREMIUM)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'dbt-emotion-regulation-14day',
  'Emotion Regulation Skills',
  'Comprehensive DBT program for managing intense emotions. Learn to identify, understand, and regulate emotions using ABC PLEASE, opposite action, and check the facts skills over 14 days.',
  14,
  'stress',
  'intermediate',
  TRUE,
  '["Understand emotion myths and functions", "Practice ABC PLEASE vulnerability reduction", "Use opposite action effectively", "Apply check the facts technique", "Build positive emotional experiences"]'::jsonb,
  ARRAY['dbt', 'emotion-regulation', 'mood-swings', 'emotional-intensity'],
  18,
  21,
  'dbt',
  'DBT emotion regulation module significantly reduces emotional instability, mood swings, and interpersonal conflicts. Research demonstrates sustained improvements in affect regulation.',
  'https://pubmed.ncbi.nlm.nih.gov/16938084/',
  ARRAY['Emotional Instability', 'Mood Swings', 'Intense Emotions'],
  TRUE,
  'phq9'
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- P09: Interpersonal Effectiveness (DBT) (10 days, Intermediate, PREMIUM)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'dbt-interpersonal-10day',
  'Interpersonal Effectiveness',
  'Master DBT skills for healthy relationships. Learn DEAR MAN (assertiveness), GIVE (relationship maintenance), and FAST (self-respect) techniques for effective communication in 10 days.',
  10,
  'stress',
  'intermediate',
  TRUE,
  '["Master DEAR MAN assertiveness skills", "Practice GIVE relationship maintenance", "Apply FAST self-respect techniques", "Navigate difficult conversations", "Balance priorities in relationships"]'::jsonb,
  ARRAY['dbt', 'relationships', 'communication', 'assertiveness', 'boundaries'],
  16,
  22,
  'dbt',
  'DBT interpersonal effectiveness skills improve relationship satisfaction, reduce conflicts, and enhance assertiveness while maintaining respect and connection.',
  'https://www.guilford.com/books/DBT-Skills-Training-Manual/Marsha-Linehan/9781462516995',
  ARRAY['Relationship Conflicts', 'Communication Issues', 'Boundary Problems'],
  FALSE,
  NULL
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- P10: Radical Acceptance (DBT) (7 days, Advanced, PREMIUM)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'dbt-radical-acceptance-7day',
  'Radical Acceptance',
  'Intensive DBT program on radical acceptance for painful realities. Learn to fully accept what cannot be changed and reduce suffering through willingness and acceptance practices over 7 days.',
  7,
  'stress',
  'advanced',
  TRUE,
  '["Understand radical acceptance concept", "Practice turning the mind", "Develop willingness vs. willfulness awareness", "Use half-smiling and willing hands", "Accept reality without approval"]'::jsonb,
  ARRAY['dbt', 'acceptance', 'suffering', 'pain', 'willingness'],
  15,
  23,
  'dbt',
  'Radical acceptance is a core DBT skill for reducing suffering when facing unchangeable painful realities. Research shows it significantly decreases distress and increases quality of life.',
  'https://www.guilford.com/books/DBT-Skills-Training-Manual/Marsha-Linehan/9781462516995',
  ARRAY['Chronic Pain', 'Loss', 'Suffering', 'Painful Realities'],
  FALSE,
  NULL
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- =====================================================================================================================
-- MARK: - ACT Programs (3 total)
-- =====================================================================================================================

-- P11: Living by Your Values (ACT) (10 days, Beginner, FREE)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'act-values-10day',
  'Living by Your Values',
  'Acceptance and Commitment Therapy program for values clarification and committed action. Discover what truly matters to you and start living a values-aligned life in 10 meaningful days.',
  10,
  'mindfulness',
  'beginner',
  FALSE,
  '["Clarify your core values across life domains", "Distinguish values from goals", "Identify barriers to valued living", "Practice committed action", "Build psychological flexibility"]'::jsonb,
  ARRAY['act', 'values', 'meaning', 'purpose', 'psychological-flexibility'],
  15,
  30,
  'act',
  'ACT values work is central to building psychological flexibility and life satisfaction. Research shows values-based living correlates with reduced depression, anxiety, and increased well-being.',
  'https://pubmed.ncbi.nlm.nih.gov/22545738/',
  ARRAY['Lack of Direction', 'Meaninglessness', 'Purpose Questions'],
  FALSE,
  NULL
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- P12: ACT for Anxiety (14 days, Intermediate, PREMIUM)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'act-anxiety-14day',
  'ACT for Anxiety',
  'Acceptance and Commitment Therapy for anxiety. Learn to accept anxious thoughts and feelings while committing to values-based action. Transform your relationship with anxiety in 14 days.',
  14,
  'anxiety',
  'intermediate',
  TRUE,
  '["Understand creative hopelessness", "Practice cognitive defusion", "Accept anxiety instead of controlling it", "Connect with present moment", "Take committed action with anxiety present"]'::jsonb,
  ARRAY['act', 'anxiety', 'acceptance', 'defusion', 'values'],
  18,
  31,
  'act',
  'ACT for anxiety is as effective as CBT with unique benefits for psychological flexibility. Meta-analyses show moderate to large effect sizes sustained over time.',
  'https://pubmed.ncbi.nlm.nih.gov/22369640/',
  ARRAY['Generalized Anxiety', 'Worry', 'Avoidance', 'Anxiety Control'],
  TRUE,
  'gad7'
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- P13: Psychological Flexibility (ACT) (10 days, Advanced, PREMIUM)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'act-flexibility-10day',
  'Psychological Flexibility',
  'Advanced ACT program integrating all six core processes: acceptance, defusion, present moment, self-as-context, values, and committed action. Build comprehensive psychological flexibility in 10 days.',
  10,
  'mindfulness',
  'advanced',
  TRUE,
  '["Integrate all six ACT processes", "Deepen defusion and acceptance practices", "Strengthen observer self", "Align actions with values consistently", "Navigate difficult experiences with flexibility"]'::jsonb,
  ARRAY['act', 'psychological-flexibility', 'advanced', 'integration'],
  20,
  32,
  'act',
  'Psychological flexibility is the core outcome of ACT therapy, predicting better mental health, resilience, and quality of life across diverse populations and conditions.',
  'https://pubmed.ncbi.nlm.nih.gov/25830558/',
  ARRAY['Rigidity', 'Experiential Avoidance', 'Psychological Inflexibility'],
  FALSE,
  NULL
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- =====================================================================================================================
-- MARK: - MBCT Programs (2 total)
-- =====================================================================================================================

-- P14: MBCT for Depression Relapse (21 days, Intermediate, FREE)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'mbct-depression-relapse-21day',
  'MBCT for Depression Relapse Prevention',
  'Mindfulness-Based Cognitive Therapy for preventing depression relapse. Learn to relate differently to depressive thoughts and develop mindful awareness practices over 21 days.',
  21,
  'mindfulness',
  'intermediate',
  FALSE,
  '["Practice mindfulness meditation", "Recognize relapse warning signs", "Relate to thoughts as mental events", "Develop decentering skills", "Create a relapse action plan"]'::jsonb,
  ARRAY['mbct', 'depression', 'relapse-prevention', 'mindfulness', 'meditation'],
  20,
  40,
  'mbct',
  'MBCT reduces depression relapse by 40-50% compared to usual care in multiple large RCTs. Particularly effective for recurrent depression with 3+ previous episodes.',
  'https://pubmed.ncbi.nlm.nih.gov/20350028/',
  ARRAY['Depression Relapse', 'Recurrent Depression', 'Rumination'],
  TRUE,
  'phq9'
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- P15: Mindfulness for Stress (MBCT) (14 days, Beginner, PREMIUM)
INSERT INTO programs (
  slug, title, description, duration_days, category, difficulty, premium_only,
  learning_objectives, tags, estimated_daily_minutes, sort_order,
  methodology, evidence_summary, evidence_url, target_conditions,
  requires_baseline_assessment, assessment_type
) VALUES (
  'mbct-stress-14day',
  'Mindfulness for Stress',
  'Mindfulness-Based Cognitive Therapy for chronic stress. Learn mindfulness meditation, body awareness, and responding vs. reacting to stress over 14 calming days.',
  14,
  'stress',
  'beginner',
  TRUE,
  '["Develop daily mindfulness practice", "Practice body scan meditation", "Respond vs. react to stress", "Work with difficult thoughts and emotions", "Build self-compassion"]'::jsonb,
  ARRAY['mbct', 'stress', 'mindfulness', 'meditation', 'burnout'],
  18,
  41,
  'mbct',
  'MBCT for stress and burnout shows significant reductions in perceived stress, anxiety, and improvements in well-being across healthcare and general populations.',
  'https://pubmed.ncbi.nlm.nih.gov/27090087/',
  ARRAY['Chronic Stress', 'Burnout', 'Work Stress'],
  FALSE,
  NULL
) ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  duration_days = EXCLUDED.duration_days,
  category = EXCLUDED.category,
  difficulty = EXCLUDED.difficulty,
  premium_only = EXCLUDED.premium_only,
  learning_objectives = EXCLUDED.learning_objectives,
  tags = EXCLUDED.tags,
  estimated_daily_minutes = EXCLUDED.estimated_daily_minutes,
  sort_order = EXCLUDED.sort_order,
  methodology = EXCLUDED.methodology,
  evidence_summary = EXCLUDED.evidence_summary,
  evidence_url = EXCLUDED.evidence_url,
  target_conditions = EXCLUDED.target_conditions,
  requires_baseline_assessment = EXCLUDED.requires_baseline_assessment,
  assessment_type = EXCLUDED.assessment_type,
  updated_at = NOW();

-- =====================================================================================================================
-- MARK: - Summary
-- =====================================================================================================================
-- Total Programs: 15
-- - CBT: 6 (Anxiety, Depression, OCD, Panic, Social Anxiety, Insomnia)
-- - DBT: 4 (Distress Tolerance, Emotion Regulation, Interpersonal Effectiveness, Radical Acceptance)
-- - ACT: 3 (Values Living, ACT Anxiety, Psychological Flexibility)
-- - MBCT: 2 (Depression Relapse, Stress)
--
-- Free Programs: 5 (P01, P02, P07, P11, P14)
-- Premium Programs: 10 (P03, P04, P05, P06, P08, P09, P10, P12, P13, P15)
--
-- Total Duration: 181 days of content
-- Assessment Requirements: 8 programs require baseline (GAD-7 or PHQ-9)
-- =====================================================================================================================
