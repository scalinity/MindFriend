# Claude Code Implementation Prompts

> **Version:** 3.0.0 (Reordered by Implementation Priority)
> **Last Updated:** 2026-01-22
> **Total Features:** 27

This file contains implementation prompts for all features, ordered by implementation priority. Novel differentiators are marked with ⭐.

**Usage:**

1. Copy the prompt for the feature you want to implement
2. Run `/dev-pipeline` in Claude Code
3. Paste the prompt when asked for the task

---

## Implementation Order Quick Reference

| #   | Feature                                 | Type     | Phase       |
| --- | --------------------------------------- | -------- | ----------- |
| 001 | Nervous System State Engine             | ⭐ NOVEL | Foundation  |
| 002 | Circadian Vulnerability Shield          | ⭐ NOVEL | Foundation  |
| 003 | Dynamic Difficulty Adjustment           | Standard | Foundation  |
| 004 | Daily Wellness Score                    | Standard | Foundation  |
| 005 | Predictive Mood Intelligence            | MOONSHOT | Foundation  |
| 006 | Cognitive Distortion Detector           | ⭐ NOVEL | Enhancement |
| 007 | Social Vitality Index                   | ⭐ NOVEL | Enhancement |
| 008 | Progress Narrative                      | Standard | Engagement  |
| 009 | Streak Shields Enhancement              | Standard | Engagement  |
| 010 | Achievement Milestones                  | Standard | Engagement  |
| 011 | Personalized Daily Briefing             | Standard | Engagement  |
| 012 | Wellness Time Capsule                   | Standard | Engagement  |
| 013 | Intervention Efficacy Engine            | ⭐ NOVEL | Advanced    |
| 014 | Wellbeing Debt Calculator               | ⭐ NOVEL | Advanced    |
| 015 | Sleep Optimization System               | Standard | Content     |
| 016 | AI-Generated Exercises                  | Standard | Content     |
| 017 | Contextual Micro-Interventions          | Standard | Content     |
| 018 | Life Transition Pathways                | Standard | Life        |
| 019 | Mentorship Matching                     | MOONSHOT | Social      |
| 020 | Community Wisdom Engine                 | MOONSHOT | Social      |
| 021 | Ambient Wellness Presence               | MOONSHOT | Platform    |
| 022 | AR Grounding Exercises                  | MOONSHOT | Platform    |
| 023 | Biofeedback Adaptation                  | MOONSHOT | Platform    |
| 024 | Autonomous Wellness Agent               | MOONSHOT | Autonomous  |
| 025 | Generative Wellness Experiences         | MOONSHOT | Autonomous  |
| 026 | Stress Signature Fingerprint            | ⭐ NOVEL | Synthesis   |
| 027 | Longitudinal Mental Health Intelligence | MOONSHOT | Synthesis   |

---

# PHASE 1: FOUNDATION (001-005)

Build core sensing and prediction capabilities.

---

## Prompt 001: Nervous System State Engine ⭐

```
Implement the Nervous System State Engine as specified in claude-specs/001-nervous-system-state-engine.md.

OVERVIEW:
This feature provides real-time detection of the user's autonomic nervous system state using Polyvagal Theory. It combines voice biomarkers (from existing EmotionAnalyzer), HRV from HealthKit, and behavioral signals to classify users into Ventral Vagal (safe), Sympathetic (fight/flight), or Dorsal Vagal (freeze) states. No consumer app has implemented this.

LEVERAGING EXISTING INFRASTRUCTURE:
- EmotionAnalyzer service (extend for polyvagal features)
- HealthKitService (add HRV queries)
- SmartNotificationService (state-aware notification timing)
- Biometric Correlation Engine (already implemented)

DATABASE REQUIREMENTS:
1. Create migration for nervous_system_states table:
   - id, user_id, state (enum), confidence, source
   - voice_score, hrv_score, behavioral_score (signal contributions)
   - session_id (optional), created_at

2. Create migration for state_interventions catalog:
   - Target state, intervention type, name, description
   - Duration, audio_url, instructions (JSONB), efficacy_score

3. RLS policies for user-only access

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/nervous-system-classify/index.ts:
   - Accept voice, HRV, behavioral features
   - Calculate composite score using weighted fusion
   - Return state classification with confidence

2. Create supabase/functions/get-state-history/index.ts:
   - Return state timeline for visualization

iOS REQUIREMENTS:
1. Create Core/Services/NervousSystemStateEngine.swift:
   - Main classification engine
   - Periodic sampling (10s during voice, 5min passive)
   - State change debouncing (30s)

2. Create Core/Services/VoicePolyvagalExtractor.swift:
   - Extend EmotionAnalyzer output
   - Extract: pitch variability, speech rate, pause duration, prosody contour

3. Create Core/Services/HRVPolyvagalExtractor.swift:
   - Query HealthKit for HRV
   - Calculate RMSSD, SDNN, LF/HF ratio
   - Handle graceful degradation (no Apple Watch)

4. Create Core/Services/BehavioralPolyvagalTracker.swift:
   - Track response latency, message length, session engagement

5. Create Core/Models/NervousSystemModels.swift:
   - NervousSystemState enum (ventralVagal, sympathetic, dorsalVagal, transitioning, unknown)
   - StateClassification struct

6. Create Features/NervousSystem/NervousSystemIndicatorView.swift:
   - Traffic light visual (green/yellow/red)
   - State name and explanation
   - Recommended intervention button

7. Create Features/NervousSystem/StateHistoryView.swift:
   - Timeline chart showing state over day/week
   - Filter by state type

8. Create Features/NervousSystem/InterventionView.swift:
   - State-specific exercise player
   - Vagal toning for sympathetic
   - Gentle activation for dorsal vagal

9. Update Features/Home/HomeView.swift:
   - Add NervousSystemIndicatorView widget
   - Real-time state display

TESTING:
1. Test classification with sample audio files (RAVDESS)
2. Test HRV integration
3. Test graceful degradation without HRV
4. Test state-specific intervention selection

ACCEPTANCE CRITERIA:
- Classification updates every 10s during voice session
- State indicator visible on home screen
- Interventions matched to current state
- Classification confidence > 75% target
- On-device processing (no raw biometrics transmitted)
```

---

## Prompt 002: Circadian Vulnerability Shield ⭐

```
Implement the Circadian Vulnerability Shield as specified in claude-specs/002-circadian-vulnerability-shield.md.

OVERVIEW:
This feature identifies each user's chronotype, maps their daily rhythm, and predicts 2-4 "vulnerable windows" when they're most susceptible to mood crashes. During these windows, it delivers "armor interventions" proactively. No mental health app does chronotype-aware preventive intervention.

LEVERAGING EXISTING INFRASTRUCTURE:
- HealthKitService (sleep data)
- SmartNotificationService (intervention delivery)
- Mood logging (for vulnerability correlation)
- Exercise sessions (for armor interventions)

DATABASE REQUIREMENTS:
1. Create migration for circadian_profiles table:
   - id, user_id (unique), chronotype (enum)
   - natural_wake_time, natural_sleep_time (seconds from midnight)
   - social_jet_lag_minutes, vulnerable_windows (JSONB)
   - peak_performance_window (JSONB), updated_at

2. Create migration for vulnerable_windows table:
   - id, user_id, date, start_time, end_time
   - severity (low/moderate/high), confidence
   - predicted_triggers (JSONB), armor_delivered, armor_completed
   - mood_during_window, crash_occurred

3. Create migration for armor_interventions catalog:
   - Seed with 12+ interventions (breathing, grounding, activation)
   - Duration 2-5 minutes each

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/calculate-chronotype/index.ts:
   - Analyze 7+ days of sleep data
   - Calculate MSFsc (mid-sleep on free days, corrected)
   - Return chronotype with confidence

2. Create supabase/functions/predict-vulnerable-windows/index.ts:
   - Accept chronotype profile, mood history, calendar (optional)
   - Predict windows for next 24-48 hours
   - Return windows with severity and recommended armor

iOS REQUIREMENTS:
1. Create Core/Services/CircadianVulnerabilityEngine.swift:
   - Main engine coordinating chronotype and predictions

2. Create Core/Services/ChronotypeClassifier.swift:
   - Calculate from HealthKit sleep data
   - 5 chronotypes: extreme morning to extreme evening

3. Create Core/Services/VulnerabilityPredictor.swift:
   - Predict circadian trough
   - Detect social jet lag
   - Integrate calendar for stress events (optional)

4. Create Core/Services/ArmorScheduler.swift:
   - Schedule notifications 15-30 min before windows
   - Select interventions based on severity

5. Create Core/Models/CircadianModels.swift:
   - Chronotype enum, CircadianProfile, VulnerableWindow structs

6. Create Features/Circadian/CircadianDashboardView.swift:
   - Chronotype display with explanation
   - Today's rhythm visualization
   - Upcoming vulnerable windows

7. Create Features/Circadian/VulnerabilityTimelineView.swift:
   - 24-hour view with window overlays
   - Current position indicator

8. Create Features/Circadian/ArmorInterventionView.swift:
   - Quick intervention player
   - Progress tracking

9. Create Features/Circadian/RhythmReportView.swift:
   - Weekly report showing alignment
   - Crash correlation

TESTING:
1. Test chronotype classification with mock sleep data
2. Test window prediction accuracy
3. Test notification scheduling
4. Test armor intervention flow

ACCEPTANCE CRITERIA:
- Chronotype determined within 7 days of use
- 2-4 vulnerable windows predicted daily
- Armor notifications delivered on time
- 70%+ prediction accuracy target
```

---

## Prompt 003: Dynamic Difficulty Adjustment

```
Implement Dynamic Difficulty Adjustment as specified in claude-specs/003-dynamic-difficulty-adjustment.md.

OBJECTIVE: Automatically adjust quest difficulty, exercise duration, and challenge intensity based on user's current capacity, recent performance, and emotional state.

CURRENT STATE: Zero infrastructure exists. This is a new feature.

DATABASE REQUIREMENTS:
1. Create migration file: supabase/migrations/YYYYMMDD_dynamic_difficulty.sql
2. Create tables with RLS policies:
   - user_capacity (user_id, current_level, energy_estimate, stress_level, capacity_factors, last_calculated)
   - difficulty_settings (user_id, base_difficulty, auto_adjust_enabled, sensitivity, min_difficulty, max_difficulty)
   - difficulty_history (user_id, content_type, content_id, assigned_difficulty, completion_status, time_spent, user_rating)
3. Add difficulty_level column to quests table

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/calculate-capacity/index.ts:
   - Gather signals:
     * Recent mood entries (last 24h average)
     * Sleep quality (last night)
     * Activity level (steps, active minutes)
     * Recent completion rates
     * Streak status
     * Time of day patterns
   - Calculate composite capacity score (0-100)
   - Store in user_capacity
   - Return capacity assessment

2. Update supabase/functions/assign-quest/index.ts:
   - Call calculate-capacity first
   - Select quest matching capacity level
   - Adjust parameters: duration, complexity
   - Store in difficulty_history

3. Create supabase/functions/adjust-difficulty/index.ts:
   - Called after content completion
   - Analyze: completed? time spent? rating?
   - Update difficulty model:
     * Success → slightly increase
     * Struggle → decrease
     * Abandonment → significantly decrease
   - Apply smoothing to prevent oscillation

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Core/Models/DifficultyModels.swift:
   - UserCapacity struct (level, energy, stress, factors)
   - DifficultySettings struct
   - DifficultyLevel enum (gentle, easy, moderate, challenging, intense)

2. Update quest views to show difficulty indicator

3. Create Apps/ios/MindFriendApp/Features/Settings/DifficultySettingsView.swift:
   - Toggle auto-adjustment
   - Set sensitivity
   - Set bounds (min/max difficulty)

TESTING:
1. Unit tests for capacity calculation
2. Unit tests for adjustment algorithm
3. Test oscillation prevention

ACCEPTANCE CRITERIA:
- Capacity calculated in under 500ms
- Difficulty adjusts within 1-2 sessions
- User never feels punished
- Manual override always available
```

---

## Prompt 004: Daily Wellness Score

```
Complete the Daily Wellness Score feature as specified in claude-specs/004-daily-wellness-score.md.

CURRENT STATE:
- Table `daily_signals` exists with aggregated daily signals
- Database function `aggregate_daily_signals()` creates daily data
- Score calculation logic exists in backend
- NO UI component displays the score on Home screen
- NO user-facing score breakdown or trends

OBJECTIVE: Add the missing UI layer and expose the existing score calculation to users.

WHAT EXISTS (DO NOT REBUILD):
- daily_signals table with user_id, signal_date, aggregated data
- aggregate_daily_signals() database function
- Basic score calculation logic in Edge Functions

WHAT'S MISSING (IMPLEMENT THIS):

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Features/Home/Components/WellnessScoreCard.swift:
   - Circular progress indicator showing overall score (0-100)
   - Color coding: green (80+), yellow (60-79), orange (40-59), red (<40)
   - Animated score reveal on load
   - Trend indicator (up/down/stable arrow)
   - Tap to expand component breakdown

2. Create Apps/ios/MindFriendApp/Features/Home/Components/ScoreBreakdownView.swift:
   - Four mini progress bars (mood, sleep, activity, engagement)
   - Show weighted contributions
   - Highlight lowest component as improvement opportunity

3. Create Apps/ios/MindFriendApp/Features/Insights/ScoreHistoryView.swift:
   - Line chart showing score over time (7/30/90 days)
   - Component overlay option
   - Personal bests highlighted

4. Update Apps/ios/MindFriendApp/Features/Home/HomeView.swift:
   - Add WellnessScoreCard at top of home screen
   - Fetch today's score via existing API
   - Handle loading and empty states

EDGE FUNCTION (if needed):
- Create supabase/functions/get-daily-score/index.ts if no endpoint exists
- Query daily_signals for user
- Return formatted score with components

TESTING:
1. Unit tests for score display logic
2. UI tests for card interactions
3. Test empty state (no data yet)

ACCEPTANCE CRITERIA:
- Score visible on home screen within 2 seconds
- Breakdown accessible via tap
- History shows at least 7 days when available
- Trend indicator accurate based on 7-day comparison
```

---

## Prompt 005: Predictive Mood Intelligence [MOONSHOT]

```
Complete the Predictive Mood Intelligence feature as specified in claude-specs/005-predictive-mood-intelligence.md.

CURRENT STATE:
- Table `mood_biometric_correlations` stores historical correlations
- Edge Function `pattern-detector` with signature-builder.ts exists
- Database function `calculate_mood_trend()` provides trend analysis (up/down/stable)
- Trend detection works, but FUTURE PREDICTION does not
- No ML model for actual mood prediction
- No preemptive intervention triggering

OBJECTIVE: Add ML-based mood prediction and preemptive intervention system.

WHAT EXISTS (DO NOT REBUILD):
- mood_biometric_correlations table
- calculate_mood_trend() function
- pattern-detector Edge Function (trend analysis)
- Mood logging infrastructure

WHAT'S MISSING (IMPLEMENT THIS):

DATABASE REQUIREMENTS:
1. Create migration for prediction tables:
   - mood_predictions (user_id, predicted_for, predicted_mood, confidence, factors_json, actual_mood, prediction_accuracy)
   - prediction_models (user_id, model_version, feature_weights, accuracy_score, last_trained_at)
   - preemptive_interventions (user_id, prediction_id, intervention_type, content, delivered_at, user_response)

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/predict-mood/index.ts:
   - Called morning (6-7 AM local time)
   - Gather features: hour, day_of_week, sleep_hours, steps_yesterday, previous_mood
   - Use simple weighted regression (or call xAI for prediction)
   - Calculate confidence based on data availability
   - Store prediction in mood_predictions
   - If predicted_mood < 3 with confidence > 0.6, trigger intervention
   - Return prediction with explanation

2. Create supabase/functions/suggest-intervention/index.ts:
   - Analyze contributing factors from prediction
   - Select intervention type based on cause:
     * Low sleep → suggest rest
     * Low activity → suggest walk
     * Pattern-based → suggest specific exercise
   - Queue notification via send-notification

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Features/Home/Components/MoodPredictionCard.swift:
   - Show predicted mood for today
   - Confidence indicator
   - Contributing factors list
   - Tap for detailed explanation

2. Create Apps/ios/MindFriendApp/Features/Interventions/PreemptiveInterventionView.swift:
   - Show when low mood predicted
   - Context message ("Based on your sleep...")
   - Suggested action with one-tap start
   - Dismiss with feedback

3. Update mood logging to record actual_mood and calculate prediction_accuracy

TESTING:
1. Unit tests for prediction calculation
2. Test intervention triggering logic
3. Test accuracy tracking after mood logged

ACCEPTANCE CRITERIA:
- Predictions generated by 7 AM daily
- Interventions trigger for high-confidence low predictions
- Accuracy improves over time (track and display)
- Users can see prediction factors
```

---

# PHASE 2: ENHANCEMENT (006-007)

Add intelligence to existing features.

---

## Prompt 006: Cognitive Distortion Detector ⭐

```
Implement the Cognitive Distortion Detector as specified in claude-specs/006-cognitive-distortion-detector.md.

OVERVIEW:
This brings automated CBT to voice journaling. As users speak, the system detects cognitive distortions (catastrophizing, overgeneralization, etc.) in real-time and provides gentle micro-prompts for reframing. No consumer app does real-time CBT pattern detection during voice.

LEVERAGING EXISTING INFRASTRUCTURE:
- Voice journaling with speech-to-text (existing)
- Grok API integration (for LLM enhancement)
- Mood logging (for distortion-mood correlation)

DATABASE REQUIREMENTS:
1. Create migration for cognitive_distortions table:
   - id, user_id, session_id, distortion_type (enum)
   - trigger_phrase, full_context, confidence
   - prompt_delivered, prompt_dismissed, user_engaged
   - user_feedback (accurate/not_distorted/unclear)

2. Create migration for distortion_daily_stats table:
   - User, date, distortion_type, count
   - avg_confidence, mood_correlation

3. Seed 10 distortion types with patterns

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/analyze-distortions/index.ts:
   - Accept transcript text
   - Run pattern matching
   - Return detected distortions with confidence

2. Create supabase/functions/get-distortion-trends/index.ts:
   - Aggregate distortion history
   - Calculate trends and mood correlations

iOS REQUIREMENTS:
1. Create Core/Services/CognitiveDistortionEngine.swift:
   - Main detection engine
   - Real-time processing during voice journal

2. Create Core/Services/DistortionPatternMatcher.swift:
   - Regex patterns for each distortion type
   - Keyword sets and context rules
   - Confidence calculation

3. Create Core/Services/LLMDistortionAnalyzer.swift:
   - Grok API integration for ambiguous cases
   - Only called when confidence 0.5-0.75

4. Create Core/Models/CognitiveDistortionModels.swift:
   - CognitiveDistortionType enum (10 types)
   - DetectedDistortion struct
   - Include displayName, explanation, reframingPrompt for each type

5. Create Features/CognitiveDistortion/DistortionPromptView.swift:
   - Non-intrusive overlay during voice journal
   - Gentle language ("Thought Pattern Noticed")
   - Reframing question display
   - Skip/Explore buttons

6. Create Features/CognitiveDistortion/ThoughtPatternReportView.swift:
   - Weekly trends by distortion type
   - Correlation with low mood days
   - Progress tracking (are distortions decreasing?)

7. Create Features/CognitiveDistortion/DistortionHistoryView.swift:
   - List of detected distortions
   - User feedback mechanism
   - Search and filter

8. Integrate with VoiceJournalView:
   - Hook into transcript stream
   - Show overlay when distortion detected
   - Rate limit prompts (max 3 per 5-min session)

TESTING:
1. Test pattern detection with labeled sentences
2. Test LLM enhancement for edge cases
3. Test UI overlay timing and dismissal
4. Test feedback collection

ACCEPTANCE CRITERIA:
- Detection within 5 seconds of utterance
- > 75% precision target
- < 3 prompts per 5-min session
- Trend reports show weekly patterns
```

---

## Prompt 007: Social Vitality Index ⭐

```
Implement the Social Vitality Index as specified in claude-specs/007-social-vitality-index.md.

OVERVIEW:
This models each user's "social health" (0-100) based on circle activity. It detects social withdrawal patterns as early warning signs and enables opt-in peer support notifications. No app models social dynamics predictively for mental health.

LEVERAGING EXISTING INFRASTRUCTURE:
- Circles feature (already implemented)
- Mood logging (for correlation)
- Push notifications (for peer alerts)

DATABASE REQUIREMENTS:
1. Create migration for social_vitality_scores table:
   - id, user_id, date (unique per user/date)
   - overall_score (0-100), trend
   - Component scores: frequency, depth, reciprocity, diversity

2. Create migration for interaction_metrics table:
   - User pairs, circle, date
   - messages_sent, messages_received
   - avg_response_time, avg_message_length
   - reciprocity_ratio, engagement_score

3. Create migration for relationship_correlations table:
   - User pairs, mood_correlation
   - Classification (support_pillar/neutral/draining)

4. Create migration for peer_alert_preferences table:
   - enabled, alert_threshold, designated_supporters[]

5. Create migration for peer_alerts table:
   - Sent alerts tracking

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/calculate-social-vitality/index.ts:
   - Calculate daily score from interactions
   - Update relationship correlations

2. Create supabase/functions/detect-withdrawal/index.ts:
   - Analyze 14-day score pattern
   - Return withdrawal status and severity

3. Create supabase/functions/send-peer-alert/index.ts:
   - Notify designated supporters
   - Log alert sent

iOS REQUIREMENTS:
1. Create Core/Services/SocialVitalityEngine.swift:
   - Main engine coordinating scoring

2. Create Core/Services/SocialVitalityCalculator.swift:
   - Score calculation algorithm
   - Frequency, depth, reciprocity, diversity scoring

3. Create Core/Services/WithdrawalDetector.swift:
   - Pattern detection (declining over 5+ days)
   - Severity classification

4. Create Core/Services/PeerAlertService.swift:
   - Preference management
   - Alert delivery

5. Create Core/Models/SocialVitalityModels.swift:
   - SocialVitalityScore, InteractionMetric
   - RelationshipCorrelation, PeerAlertPreferences

6. Create Features/SocialVitality/SocialHealthDashboardView.swift:
   - Current score with trend
   - Component breakdown
   - Top supporters list
   - Insights/suggestions

7. Create Features/SocialVitality/RelationshipInsightsView.swift:
   - Relationship list with correlation scores
   - Support pillars highlighted
   - Draining relationships flagged (sensitively)

8. Create Features/SocialVitality/PeerAlertSettingsView.swift:
   - Enable/disable toggle
   - Select designated supporters
   - Choose alert threshold

TESTING:
1. Test score calculation with mock data
2. Test withdrawal detection patterns
3. Test peer alert flow
4. Test privacy/consent handling

ACCEPTANCE CRITERIA:
- Score calculated daily
- Withdrawal detected with > 80% sensitivity
- Peer alerts require explicit consent
- Dashboard shows actionable insights
```

---

# PHASE 3: ENGAGEMENT (008-012)

Deepen user engagement and retention.

---

## Prompt 008: Progress Narrative

```
Complete the Progress Narrative feature as specified in claude-specs/008-progress-narrative.md.

CURRENT STATE:
- Table `weekly_stories` stores AI-generated narratives
- Edge Function `generate-weekly-story` exists
- Weekly summaries generated
- NO journey narrative UI visible to users
- NO personalized narrative preferences

OBJECTIVE: Add user-facing UI and personalization for progress narratives.

WHAT EXISTS (DO NOT REBUILD):
- weekly_stories table
- generate-weekly-story Edge Function
- Weekly summary generation logic

WHAT'S MISSING (IMPLEMENT THIS):

DATABASE REQUIREMENTS:
1. Add to existing tables or create:
   - narrative_preferences (user_id, preferred_tone, preferred_length, include_metrics, generation_frequency)
   - Add user_rating, is_favorite columns to weekly_stories if missing

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Features/Journey/NarrativeListView.swift:
   - List past narratives chronologically
   - Filter by type (weekly/monthly)
   - Show favorites section
   - Pull to refresh / generate new

2. Create Apps/ios/MindFriendApp/Features/Journey/NarrativeDetailView.swift:
   - Display full narrative with nice typography
   - Show metrics sidebar if included
   - Rate narrative (thumbs up/down)
   - Mark as favorite
   - Share option

3. Create Apps/ios/MindFriendApp/Features/Journey/NarrativePreferencesView.swift:
   - Tone selector (warm, professional, playful)
   - Length preference (brief, standard, detailed)
   - Toggle metric inclusion

4. Add narrative section to Profile or Insights tab

EDGE FUNCTION (update if needed):
- Update generate-weekly-story to use narrative_preferences
- Apply tone and length preferences to generation prompt

TESTING:
1. Test narrative display
2. Test preference application
3. Test rating/favorite functionality

ACCEPTANCE CRITERIA:
- Users can view all past narratives
- Preferences affect generation
- Favorites are easily accessible
- Narratives can be shared
```

---

## Prompt 009: Streak Shields Enhancement

```
Complete the Streak Shields Enhancement feature as specified in claude-specs/009-streak-shields-enhancement.md.

CURRENT STATE:
- Table `streak_shield_events` tracks shield usage
- Database function `reset_shields()` exists
- 26 references to streak shields in codebase
- Basic shield mechanics exist
- Vacation mode NOT fully implemented
- Shield earning/consumption UI incomplete

OBJECTIVE: Complete vacation mode and polish shield UI/mechanics.

WHAT EXISTS (DO NOT REBUILD):
- streak_shield_events table
- reset_shields() function
- Basic shield tracking

WHAT'S MISSING (IMPLEMENT THIS):

DATABASE REQUIREMENTS:
1. Create or update tables:
   - vacation_mode (user_id, is_active, start_date, end_date, reason, streak_at_start)
   - streak_shields (user_id, shields_available, shields_max, last_earned_at)
   - shield_transactions (user_id, transaction_type, amount, reason, created_at)

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/toggle-vacation/index.ts:
   - Accept action (start/end), dates, reason
   - If starting: store current streak, activate vacation mode
   - If ending: restore streak, deactivate, award "Welcome Back" bonus
   - Return vacation status

2. Update quest assignment to skip users in vacation mode

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Features/Streaks/VacationModeView.swift:
   - Date picker for vacation duration (max 14 days)
   - Optional reason field
   - Show streak being protected
   - Confirm activation with animation
   - Active vacation countdown display

2. Update Apps/ios/MindFriendApp/Features/Home/Components/StreakCard.swift:
   - Show shield count alongside streak
   - Vacation mode indicator if active
   - "Protected!" badge when shield used today
   - Animate shield consumption

3. Create Apps/ios/MindFriendApp/Features/Streaks/ShieldHistoryView.swift:
   - List shield transactions (earned/used)
   - Show how each shield was earned
   - Total shields used all-time

TESTING:
1. Test vacation mode activation/deactivation
2. Test streak preservation during vacation
3. Test shield earning triggers
4. Test auto-consumption on missed day

ACCEPTANCE CRITERIA:
- Vacation mode completely pauses streak requirements
- Shields auto-consumed (if enabled) to protect streaks
- Shield count visible on home screen
- Transaction history accessible
```

---

## Prompt 010: Achievement Milestones

```
Complete the Achievement Milestones feature as specified in claude-specs/010-achievement-milestones.md.

CURRENT STATE:
- Tables: badges, badges_v2, user_badges, user_badges_v2, level_thresholds, xp_transactions
- Service: AchievementService.swift
- Views: AchievementsView.swift, BadgeEarnedView.swift
- Database functions: check_badge_progress(), award_xp()
- XP system and badge earning WORKS
- Tiered badges partially implemented
- Celebration/milestone narratives INCOMPLETE

OBJECTIVE: Complete tiered badge progression and milestone celebrations.

WHAT EXISTS (DO NOT REBUILD):
- Badge definitions and user_badges tracking
- XP transactions and level thresholds
- AchievementService and basic views
- award_xp() and check_badge_progress()

WHAT'S MISSING (IMPLEMENT THIS):

DATABASE REQUIREMENTS:
1. Create or update:
   - badge_tiers (badge_id, tier, tier_name, requirement_value, xp_reward, icon_variant)
   - user_badge_progress (user_id, badge_id, current_tier, current_value, next_tier_requirement)
   - milestone_celebrations (user_id, milestone_type, milestone_value, celebrated_at, celebration_content)

iOS REQUIREMENTS:
1. Update Apps/ios/MindFriendApp/Features/Achievements/BadgeDetailView.swift:
   - Show current tier prominently
   - Progress bar to next tier
   - Tier history (when each tier earned)
   - How to progress tips

2. Create Apps/ios/MindFriendApp/Features/Achievements/LevelUpCelebrationView.swift:
   - Full-screen celebration modal
   - Animated level number with effects
   - Summary of what unlocked
   - Share option
   - Auto-dismiss after 5 seconds or tap

3. Create Apps/ios/MindFriendApp/Features/Achievements/MilestoneNarrativeView.swift:
   - AI-generated milestone story
   - Journey reflection
   - Shareable card

4. Update HomeView to show XP progress bar subtly

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/generate-milestone-narrative/index.ts:
   - Accept milestone_type (level_up, badge_tier, streak_milestone)
   - Generate personalized celebration message
   - Create shareable graphic data
   - Store in milestone_celebrations

TESTING:
1. Test tier advancement
2. Test celebration triggering
3. Test milestone narrative generation
4. UI tests for animations

ACCEPTANCE CRITERIA:
- Tiered badges show clear progression
- Level up triggers celebration immediately
- Milestone narratives are personalized
- XP visible throughout app
```

---

## Prompt 011: Personalized Daily Briefing

```
Implement Personalized Daily Briefing as specified in claude-specs/011-personalized-daily-briefing.md.

OBJECTIVE: Generate a personalized morning briefing summarizing yesterday, previewing today, and providing context-aware recommendations.

CURRENT STATE: Zero infrastructure exists. This is a new feature.

DATABASE REQUIREMENTS:
1. Create migration: supabase/migrations/YYYYMMDD_daily_briefing.sql
2. Create tables with RLS:
   - daily_briefings (user_id, briefing_date, content_json, generated_at, delivered_at, read_at, feedback)
   - briefing_preferences (user_id, delivery_time, include_weather, tone, length, sections_enabled[])
3. Content JSON: { greeting, yesterday_summary, today_preview, recommendations, affirmation }

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/generate-briefing/index.ts:
   - Scheduled for user's preferred delivery time (default 7 AM)
   - Gather data:
     * Yesterday: mood entries, quests completed, exercises, sleep
     * Today: assigned quest, predicted mood
   - Generate sections:
     * Greeting: time-aware, personalized with name
     * Yesterday summary: achievements, challenges
     * Today preview: quest, capacity-based tips
     * Recommendations: 2-3 personalized suggestions
     * Affirmation: AI-generated based on journey
   - Apply tone and length preferences
   - Store and queue notification

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Core/Models/BriefingModels.swift:
   - DailyBriefing struct with all sections
   - BriefingPreferences struct

2. Create Apps/ios/MindFriendApp/Features/Briefing/DailyBriefingView.swift:
   - Card-based layout
   - Expandable sections
   - Time-appropriate greeting with animation
   - Quick actions from recommendations
   - Mark sections as helpful

3. Create Apps/ios/MindFriendApp/Features/Settings/BriefingPreferencesView.swift:
   - Delivery time picker
   - Toggle sections
   - Tone selector
   - Length preference

4. Handle briefing notification → open briefing view

TESTING:
1. Test briefing generation with various data states
2. Test scheduling logic
3. Test preference application

ACCEPTANCE CRITERIA:
- Briefing delivered at user's preferred time
- Content is personalized and accurate
- Graceful handling of missing data
- Loads within 3 seconds
```

---

## Prompt 012: Wellness Time Capsule

```
Implement Wellness Time Capsule as specified in claude-specs/012-wellness-time-capsule.md.

OBJECTIVE: Allow users to record messages to their future selves, delivered at specified dates.

CURRENT STATE: Zero infrastructure exists. This is a new feature.

DATABASE REQUIREMENTS:
1. Create migration: supabase/migrations/YYYYMMDD_time_capsule.sql
2. Create tables with RLS:
   - time_capsules (user_id, capsule_type, title, content, media_urls[], created_at, deliver_at, delivered_at, opened_at, is_recurring, recurrence_pattern)
   - capsule_reactions (capsule_id, user_id, reaction_type, reflection_text, created_at)
   - capsule_templates (template_type, title_template, content_prompts[], suggested_delivery)

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/create-capsule/index.ts:
   - Validate delivery date (must be future)
   - Store capsule
   - Schedule notification for delivery date
   - Return capsule details

2. Create supabase/functions/deliver-capsules/index.ts:
   - Run every hour
   - Find capsules where deliver_at <= now AND delivered_at IS NULL
   - Mark as delivered
   - Send push notification
   - If recurring, schedule next occurrence

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Core/Models/TimeCapsuleModels.swift:
   - TimeCapsule struct
   - CapsuleType enum (letter_to_self, intention, reflection, milestone_marker)
   - RecurrencePattern enum

2. Create Apps/ios/MindFriendApp/Features/TimeCapsule/TimeCapsuleListView.swift:
   - Tabs: Pending, Delivered, Opened
   - Visual envelope metaphor
   - Countdown to delivery date

3. Create Apps/ios/MindFriendApp/Features/TimeCapsule/CreateCapsuleView.swift:
   - Type selector
   - Title and content input
   - Media attachment option
   - Delivery date picker with suggestions
   - "Seal Capsule" with animation

4. Create Apps/ios/MindFriendApp/Features/TimeCapsule/OpenCapsuleView.swift:
   - Envelope opening animation
   - Message reveal (typewriter effect)
   - Show when created
   - Reaction options
   - Add reflection text

TESTING:
1. Test delivery scheduling
2. Test recurrence calculation
3. Test notification delivery
4. UI tests for create and open flows

ACCEPTANCE CRITERIA:
- Capsules sealed with confirmation
- Delivery at specified time (+/- 1 hour)
- Opening animation creates emotional impact
- Reactions and reflections stored
```

---

# PHASE 4: ADVANCED (013-017)

Build on novel foundations.

---

## Prompt 013: Intervention Efficacy Engine ⭐

```
Implement the Intervention Efficacy Engine as specified in claude-specs/013-intervention-efficacy-engine.md.

OVERVIEW:
This tracks emotional state DURING interventions (not just before/after) to measure what actually works for each user. It creates personalized efficacy profiles and detects "breakthrough moments" (rapid positive shifts). No wellness app tracks real-time emotional trajectory during exercises.

LEVERAGING EXISTING INFRASTRUCTURE:
- 001 Nervous System State Engine (for real-time state)
- EmotionAnalyzer (for emotion classification)
- Exercise sessions (existing)

DATABASE REQUIREMENTS:
1. Create migration for emotional_trajectories table:
   - session_id, user_id, exercise_id
   - start_time, end_time
   - samples (JSONB array of trajectory points)

2. Create migration for intervention_efficacy table:
   - User, exercise, session, completed_at
   - efficacy_score (0-100), net_emotional_change
   - trajectory_shape, breakthrough_detected
   - Context: starting_state, time_of_day, day_of_week

3. Create migration for user_efficacy_profiles table:
   - User, exercise (unique)
   - overall_efficacy_score, completion_count, confidence
   - Contextual breakdowns (by state, time, emotion)
   - trend (improving/stable/declining)

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/calculate-efficacy/index.ts:
   - Accept trajectory data
   - Calculate efficacy score
   - Detect breakthrough moments

2. Create supabase/functions/get-personalized-recommendations/index.ts:
   - Accept current state/emotion/time
   - Return ranked exercises by predicted efficacy

iOS REQUIREMENTS:
1. Create Core/Services/InterventionEfficacyEngine.swift:
   - Main engine coordinating tracking and calculation

2. Create Core/Services/TrajectoryTracker.swift:
   - Start/stop tracking for exercise sessions
   - Sample state every 30 seconds
   - Store trajectory points

3. Create Core/Services/EfficacyCalculator.swift:
   - Net change calculation
   - Breakthrough detection (> 0.4 shift in < 60s)
   - Efficacy score algorithm

4. Create Core/Services/EfficacyBasedRecommender.swift:
   - Score exercises by contextual efficacy
   - Generate personalized recommendations

5. Create Core/Models/InterventionEfficacyModels.swift:
   - EmotionalTrajectory, TrajectoryPoint
   - InterventionEfficacy, UserEfficacyProfile
   - ExerciseRecommendation

6. Integrate with ExercisePlayerView:
   - Hook trajectory tracking into session lifecycle
   - Display trajectory visualization on completion

7. Create Features/Efficacy/EfficacyDashboardView.swift:
   - "What Works for You" section
   - Top exercises by efficacy
   - Recent sessions with scores

8. Create Features/Efficacy/TrajectoryVisualizationView.swift:
   - Line chart of emotional journey
   - Highlight breakthrough moments
   - Compare to baseline

9. Create Features/Efficacy/BreakthroughCelebrationView.swift:
   - Celebratory overlay when breakthrough detected
   - Save breakthrough moment

TESTING:
1. Test trajectory tracking accuracy
2. Test efficacy calculation
3. Test breakthrough detection
4. Test recommendation ranking

ACCEPTANCE CRITERIA:
- Trajectory sampled every 30s during exercises
- Efficacy calculated within 5s of completion
- Recommendations prioritize high-efficacy exercises
- Breakthrough moments detected and celebrated
```

---

## Prompt 014: Wellbeing Debt Calculator ⭐

```
Implement the Wellbeing Debt Calculator as specified in claude-specs/014-wellbeing-debt-calculator.md.

OVERVIEW:
This models cumulative stress as "wellbeing debt" that accumulates from stressors and replenishes from self-care. When debt exceeds a personalized threshold, the system intervenes with a recovery program BEFORE the crash. No app models mental wellbeing as a debt system.

LEVERAGING EXISTING INFRASTRUCTURE:
- HealthKitService (sleep data)
- Exercise sessions (as deposits)
- Circles (social connection as deposits)
- Mood logging (for threshold learning)
- 002 Circadian Shield (disruption as withdrawals)

DATABASE REQUIREMENTS:
1. Create migration for wellbeing_transactions table:
   - id, user_id, date, type (deposit/withdrawal)
   - category, amount, source, description, metadata

2. Create migration for wellbeing_debt_scores table:
   - User, date (unique), daily_balance
   - rolling_debt_7day, rolling_debt_14day, rolling_debt_30day
   - trend (JSONB), threshold_status (JSONB)

3. Create migration for wellbeing_debt_profiles table:
   - User (unique), personal_threshold
   - crash_history (JSONB), top_drains, top_deposits

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/detect-transactions/index.ts:
   - Run daily to detect deposits/withdrawals
   - Sources: HealthKit, app activity, inferred

2. Create supabase/functions/calculate-debt-score/index.ts:
   - Calculate rolling totals
   - Determine trend and threshold status

3. Create supabase/functions/generate-recovery-program/index.ts:
   - Accept current debt and profile
   - Return personalized recovery actions

iOS REQUIREMENTS:
1. Create Core/Services/WellbeingDebtEngine.swift:
   - Main engine coordinating detection and calculation

2. Create Core/Services/TransactionDetector.swift:
   - Detect deposits: good sleep, exercise, social, quest completion
   - Detect withdrawals: poor sleep, isolation, circadian disruption

3. Create Core/Services/WellbeingDebtCalculator.swift:
   - Rolling totals
   - Trend calculation
   - Threshold detection

4. Create Core/Services/RecoveryProgramGenerator.swift:
   - Generate actions based on top drains/deposits
   - Set daily targets

5. Create Core/Models/WellbeingDebtModels.swift:
   - WellbeingTransaction, WellbeingDebtScore
   - WellbeingDebtProfile, RecoveryProgram

6. Create Features/WellbeingDebt/WellbeingBudgetDashboardView.swift:
   - Current debt score with visual gauge
   - Trend indicator (accumulating/recovering)
   - Days to threshold warning
   - Today's transactions

7. Create Features/WellbeingDebt/DebtBreakdownView.swift:
   - Transaction history
   - Top drains and deposits
   - Category breakdown

8. Create Features/WellbeingDebt/RecoveryProgramView.swift:
   - 7-day program display
   - Daily targets
   - Progress tracking
   - Milestone celebrations

9. Add threshold alert integration:
   - When threshold exceeded, show recovery modal
   - Push notification to start recovery

TESTING:
1. Test transaction detection
2. Test debt calculation
3. Test threshold alerts
4. Test recovery program generation

ACCEPTANCE CRITERIA:
- Daily transactions detected automatically
- Rolling debt updated daily
- Threshold triggers recovery before crash
- Recovery program actionable and trackable
```

---

## Prompt 015: Sleep Optimization System

```
Complete the Sleep Optimization System as specified in claude-specs/015-sleep-optimization-system.md.

CURRENT STATE:
- Tables: sleep_sessions, sleep_content
- Biometric integration: sleep duration in biometric_daily_summaries
- Sleep tracking WORKS
- Bedtime routines NOT implemented
- Sleep hygiene recommendations NOT implemented
- Sleep insights/optimization MISSING

OBJECTIVE: Add bedtime routines and sleep optimization recommendations.

WHAT EXISTS (DO NOT REBUILD):
- sleep_sessions table
- Sleep duration tracking via HealthKit
- Sleep content library

WHAT'S MISSING (IMPLEMENT THIS):

DATABASE REQUIREMENTS:
1. Create tables:
   - sleep_goals (user_id, target_bedtime, target_wake_time, target_duration, wind_down_minutes)
   - sleep_routines (user_id, routine_name, activities[], is_active, times_completed)
   - sleep_routine_logs (routine_id, user_id, started_at, completed_at, mood_before, mood_after)
   - sleep_insights (user_id, insight_type, content, factors[], created_at)

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/generate-sleep-insights/index.ts:
   - Analyze last 7-14 days of sleep data
   - Detect patterns: consistency, duration trends, quality correlation
   - Generate personalized insights
   - Store in sleep_insights

2. Create supabase/functions/bedtime-reminder/index.ts:
   - Scheduled based on user's target_bedtime
   - Send notification X minutes before (wind_down_minutes)
   - Include tonight's routine suggestion

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Features/Sleep/SleepDashboardView.swift:
   - Last night's sleep summary
   - Quality score with explanation
   - Weekly trend visualization
   - Quick access to tonight's routine

2. Create Apps/ios/MindFriendApp/Features/Sleep/SleepRoutineView.swift:
   - List of wind-down activities
   - Timer for wind-down period
   - Check off activities as completed
   - Mood check before/after

3. Create Apps/ios/MindFriendApp/Features/Sleep/SleepGoalsView.swift:
   - Set target bedtime and wake time
   - Set target duration
   - Enable/disable bedtime reminders

4. Create Apps/ios/MindFriendApp/Features/Sleep/SleepInsightsView.swift:
   - List of AI-generated insights
   - Actionable recommendations
   - Mark insights as helpful

TESTING:
1. Test insight generation logic
2. Test bedtime reminder scheduling
3. Test routine completion tracking

ACCEPTANCE CRITERIA:
- Users can set sleep goals
- Bedtime reminders sent at configured time
- Routines trackable with mood correlation
- Insights generated weekly minimum
```

---

## Prompt 016: AI-Generated Exercises

```
Complete the AI-Generated Exercises feature as specified in claude-specs/016-ai-generated-exercises.md.

CURRENT STATE:
- Tables: creative_exercises, creative_exercise_completions, creative_quota_usage
- Models: GeneratedContentModels.swift with 8 content types
- Database function: get_creative_quota()
- Edge Function: generate-content exists
- Infrastructure present but mostly uses TEMPLATES, not dynamic generation
- Personalization level LOW

OBJECTIVE: Improve dynamic personalization and true AI generation (not just templates).

WHAT EXISTS (DO NOT REBUILD):
- creative_exercises tables
- GeneratedContentModels.swift
- generate-content Edge Function
- Quota tracking

WHAT'S MISSING (IMPLEMENT THIS):

EDGE FUNCTION REQUIREMENTS:
1. Update supabase/functions/generate-content/index.ts:
   - Add rich context gathering:
     * Current mood (if logged today)
     * Recent exercise history (avoid repetition)
     * Time of day and energy level
     * User preferences and past ratings
   - Build detailed prompt with context
   - Track themes to ensure diversity
   - Generate truly personalized content (not template fill-in)
   - Return exercise with playback-ready format

2. Create supabase/functions/rate-exercise/index.ts:
   - Accept exercise_id, rating (1-5), feedback_text
   - Store rating
   - Feed rating back into preference learning
   - Adjust future generation based on patterns

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Features/Exercises/GenerateExerciseView.swift:
   - Exercise type selector (breathing, meditation, journaling, grounding)
   - Optional target state (calm, energized, focused, sleepy)
   - Duration selector
   - "Generate for me" button with loading animation
   - Preview before starting

2. Create Apps/ios/MindFriendApp/Features/Exercises/GeneratedExercisePlayerView.swift:
   - Unified player for all generated exercise types
   - Type-specific UI (breathing animation, text for journaling, audio for meditation)
   - Progress indicator
   - Pause/resume

3. Add post-exercise rating prompt (simple, non-intrusive)

4. Create Apps/ios/MindFriendApp/Features/Exercises/SavedExercisesView.swift:
   - Library of saved/favorited generated exercises
   - Quick replay
   - Organize by type

DATABASE REQUIREMENTS:
1. Add to creative_exercises or create:
   - generation_context (what context was used)
   - user_rating column
   - is_favorite column

TESTING:
1. Test context-aware generation
2. Test rating feedback loop
3. Test diversity (no repetition)
4. Test all exercise type players

ACCEPTANCE CRITERIA:
- Exercises generated within 5 seconds
- Content is contextually relevant
- No repetition of recent themes
- Ratings influence future generations
- Saved exercises accessible offline
```

---

## Prompt 017: Contextual Micro-Interventions

```
Complete the Contextual Micro-Interventions feature as specified in claude-specs/017-contextual-micro-interventions.md.

CURRENT STATE:
- Tables: micro_moment_templates, micro_moment_completions, micro_streaks
- Views: InterventionView.swift in Features/Predictive
- Edge Functions: complete-micro-moment, get-micro-suggestions
- Database function: get_micro_suggestions()
- Templates exist and work
- OPTIMAL TIMING logic MISSING
- CONTEXT AWARENESS MISSING (just random templates)

OBJECTIVE: Add intelligent timing and context-aware intervention selection.

WHAT EXISTS (DO NOT REBUILD):
- micro_moment_templates and completions tables
- InterventionView.swift
- get_micro_suggestions() function
- Template-based interventions

WHAT'S MISSING (IMPLEMENT THIS):

DATABASE REQUIREMENTS:
1. Create or update tables:
   - intervention_triggers (user_id, trigger_type, trigger_config, is_active, priority)
   - intervention_deliveries (user_id, intervention_id, trigger_id, context_snapshot, delivered_at, completed, rating)
   - intervention_preferences (user_id, enabled, max_daily, quiet_hours_start, quiet_hours_end)

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/check-intervention-triggers/index.ts:
   - Called periodically or on context change
   - Evaluate triggers:
     * Time-based: morning (9 AM), afternoon (2 PM), evening (7 PM)
     * Biometric: elevated heart rate, low HRV
     * Pattern: historically low-mood times for this user
     * Calendar: before stressful events (if calendar connected)
   - Filter by quiet hours and daily limit
   - Select best intervention for context
   - Return intervention to deliver

2. Update supabase/functions/get-micro-suggestions/index.ts:
   - Consider current context, not just random selection
   - Weight by user's past ratings
   - Avoid recently shown interventions

iOS REQUIREMENTS:
1. Update Apps/ios/MindFriendApp/Features/Predictive/InterventionView.swift:
   - Add context indicator ("Good time for a break")
   - Quick dismiss option
   - Rating after completion (simple thumbs)

2. Create Apps/ios/MindFriendApp/Core/Services/InterventionService.swift:
   - Monitor for trigger conditions locally
   - Check biometrics if available
   - Request intervention from server when triggered
   - Handle notification delivery

3. Create Apps/ios/MindFriendApp/Features/Settings/InterventionSettingsView.swift:
   - Master toggle
   - Max daily interventions slider
   - Quiet hours configuration
   - View intervention history

TESTING:
1. Test trigger evaluation logic
2. Test quiet hours enforcement
3. Test daily limit enforcement
4. Test context-aware selection

ACCEPTANCE CRITERIA:
- Interventions delivered at contextually appropriate times
- Never during quiet hours
- Daily limit respected
- Completion and rating tracked
```

---

# PHASE 5: LIFE & SOCIAL (018-020)

Expand to life events and community.

---

## Prompt 018: Life Transition Pathways

```
Implement Life Transition Pathways as specified in claude-specs/018-life-transition-pathways.md.

OBJECTIVE: Provide structured support programs for major life transitions (new job, breakup, loss, new parent, retirement).

CURRENT STATE: Zero infrastructure exists. This is a new feature.

DATABASE REQUIREMENTS:
1. Create migration: supabase/migrations/YYYYMMDD_life_transition_pathways.sql
2. Create tables with RLS:
   - pathway_templates (transition_type, title, description, phases[], duration_weeks, exercises[])
   - user_pathways (user_id, template_id, started_at, current_phase, progress_percent, paused_at, completed_at)
   - pathway_progress (pathway_id, user_id, phase_number, activities_completed[], reflections)
   - pathway_check_ins (pathway_id, user_id, check_in_date, responses_json, support_level)
3. Transition types: new_job, breakup, grief, new_parent, retirement, relocation

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/start-pathway/index.ts:
   - Accept template_id
   - Create user_pathway record
   - Initialize first phase
   - Assign initial exercises
   - Return pathway details

2. Create supabase/functions/advance-pathway/index.ts:
   - Verify current phase completed
   - Advance to next phase
   - Update progress
   - If final phase complete, trigger celebration

3. Create supabase/functions/pathway-check-in/index.ts:
   - Accept responses
   - Analyze for support level
   - Adjust pace if struggling
   - Generate encouragement

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Core/Models/PathwayModels.swift:
   - PathwayTemplate, UserPathway, PathwayPhase structs
   - TransitionType enum

2. Create Apps/ios/MindFriendApp/Features/Pathways/PathwaySelectionView.swift:
   - List transition types with descriptions
   - "Currently experiencing" selector

3. Create Apps/ios/MindFriendApp/Features/Pathways/PathwayDetailView.swift:
   - Phase progress visualization
   - Current phase activities
   - Resources
   - Pause/resume option

4. Create Apps/ios/MindFriendApp/Features/Pathways/PathwayCheckInView.swift:
   - Weekly check-in questions
   - How are you coping? scale
   - Submit for analysis

5. Add pathway section to Home if active

TESTING:
1. Test phase advancement
2. Test check-in analysis
3. Test pause/resume

ACCEPTANCE CRITERIA:
- All transition types have complete templates
- Phase progression is clear
- Check-ins provide personalized feedback
- Progress visible and encouraging
```

---

## Prompt 019: Mentorship Matching [MOONSHOT]

```
Complete the Mentorship Matching feature as specified in claude-specs/019-mentorship-matching.md.

CURRENT STATE:
- Tables: mentorships, mentorship_checkins exist
- Database function: accept_mentorship() exists
- Data structures present
- NO MATCHING ALGORITHM implemented
- Manual assignment only
- Safety systems NOT implemented

OBJECTIVE: Add intelligent matching algorithm and safety systems.

WHAT EXISTS (DO NOT REBUILD):
- mentorships table
- mentorship_checkins table
- accept_mentorship() function

WHAT'S MISSING (IMPLEMENT THIS):

DATABASE REQUIREMENTS:
1. Create or update tables:
   - mentorship_profiles (user_id, is_mentor_available, expertise_areas[], seeking_areas[], bio, availability_hours_week, languages[], verified)
   - mentorship_matches (mentor_id, mentee_id, matched_at, status, compatibility_score, match_reason)
   - mentorship_messages (match_id, sender_id, content, sent_at, read_at)
   - mentorship_reports (reporter_id, reported_id, match_id, reason, status)

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/find-mentor-matches/index.ts:
   - Accept user's seeking_areas
   - Find mentors with matching expertise
   - Calculate compatibility score:
     * Expertise match (40%)
     * Language match (20%)
     * Timezone overlap (20%)
     * Availability overlap (20%)
   - Filter by verified status
   - Return top 5 matches with reasons

2. Create supabase/functions/mentorship-safety-check/index.ts:
   - Run on messages periodically
   - Flag concerning patterns:
     * Crisis language
     * Boundary violations
     * Inappropriate requests
   - Auto-escalate if needed
   - Notify moderators

3. Create supabase/functions/request-mentorship/index.ts:
   - Accept mentor_id, introduction_message
   - Create pending match
   - Notify mentor
   - Return match status

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Features/Mentorship/MentorshipProfileView.swift:
   - Toggle mentor availability
   - Select expertise areas (if mentor)
   - Select seeking areas (if mentee)
   - Write bio

2. Create Apps/ios/MindFriendApp/Features/Mentorship/FindMentorView.swift:
   - Browse matched mentors
   - View mentor profiles
   - See compatibility score and reason
   - Request mentorship button

3. Create Apps/ios/MindFriendApp/Features/Mentorship/MentorshipChatView.swift:
   - Secure messaging interface
   - Report option (hidden but accessible)
   - End mentorship option

4. Add mentorship section to main navigation

TESTING:
1. Unit tests for matching algorithm
2. Test safety check triggers
3. Test request/accept flow
4. Test report handling

ACCEPTANCE CRITERIA:
- Matching returns relevant matches
- Safety checks run automatically
- Reports handled promptly
- Either party can end mentorship
```

---

## Prompt 020: Community Wisdom Engine [MOONSHOT]

```
Complete the Community Wisdom Engine as specified in claude-specs/020-community-wisdom-engine.md.

CURRENT STATE:
- Table: community_wisdom exists
- Only 2 references in codebase
- "People like you" recommendations NOT built
- Aggregation logic INCOMPLETE
- Privacy-preserving anonymization NOT implemented

OBJECTIVE: Build anonymous aggregation and personalized recommendations.

WHAT EXISTS (DO NOT REBUILD):
- community_wisdom table (basic structure)

WHAT'S MISSING (IMPLEMENT THIS):

DATABASE REQUIREMENTS:
1. Create or update tables:
   - wisdom_contributions (user_hash, contribution_type, context_tags[], data_json, contributed_at)
   - wisdom_insights (insight_type, context_tags[], insight_content, confidence_score, sample_size)
   - wisdom_recommendations (user_id, insight_id, content, relevance_score, shown_at, helpful)
   - wisdom_consent (user_id, contribute_anonymous_data, receive_recommendations)
   - All contributions use HASHED user_id (no PII)

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/contribute-wisdom/index.ts:
   - Check user consent first
   - Hash user ID for anonymity (SHA-256)
   - Extract context tags (goals, challenges)
   - Store contribution with NO PII
   - Return confirmation

2. Create supabase/functions/aggregate-wisdom/index.ts:
   - Run daily to aggregate contributions
   - Generate insights:
     * "Most effective exercises for anxiety"
     * "Common patterns in mood improvement"
   - Calculate confidence based on sample size (min 10 users)
   - Store/update wisdom_insights

3. Create supabase/functions/get-wisdom-recommendations/index.ts:
   - Accept user context (goals, challenges)
   - Find relevant insights
   - Personalize as recommendations
   - Score relevance
   - Track what was shown

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Features/Wisdom/WisdomFeedView.swift:
   - Personalized recommendations feed
   - "People like you found X helpful"
   - Evidence indicators (sample size, confidence)
   - Helpful/not helpful buttons

2. Create Apps/ios/MindFriendApp/Features/Settings/WisdomPrivacyView.swift:
   - Explain how wisdom works
   - Toggle anonymous contribution
   - Toggle receiving recommendations
   - See what data is contributed (anonymized preview)

3. Integrate recommendations into exercise selection and daily briefing

TESTING:
1. Unit tests for anonymization (verify no PII leaks)
2. Test consent enforcement
3. Test aggregation algorithm
4. Test relevance scoring

ACCEPTANCE CRITERIA:
- All contributions fully anonymized
- Consent required before any contribution
- Recommendations personalized to context
- Confidence scores accurate
- No way to identify users from wisdom data
```

---

# PHASE 6: PLATFORM (021-023)

Multi-platform and immersive experiences.

---

## Prompt 021: Ambient Wellness Presence [MOONSHOT]

```
Complete the Ambient Wellness Presence as specified in claude-specs/021-ambient-wellness-presence.md.

CURRENT STATE:
- Tables: soundscape_mixes, soundscape_sounds, audio_tracks, audio_collections
- 202 references to soundscapes/ambient in codebase
- Soundscapes WORK
- iOS Widgets NOT implemented
- Watch app NOT implemented
- CarPlay NOT implemented
- Dynamic backgrounds NOT implemented

OBJECTIVE: Add iOS widgets, Watch app, and ambient visual features.

WHAT EXISTS (DO NOT REBUILD):
- Soundscape tables and audio infrastructure
- Audio playback services
- Soundscape mixing

WHAT'S MISSING (IMPLEMENT THIS):

iOS WIDGET REQUIREMENTS (WidgetKit):
1. Create Apps/ios/MindFriendWidgets/ target:
   - MoodWidget: Show current mood or prompt to log
   - StreakWidget: Show current streak count
   - QuickBreathWidget: One-tap start breathing exercise
   - AffirmationWidget: Daily affirmation display
   - WellnessScoreWidget: Today's score

2. Configure widget extension with proper entitlements

3. Create shared data container for widget↔app communication

WATCH APP REQUIREMENTS (if time):
1. Create Apps/ios/MindFriendWatch/ target:
   - Complication showing streak
   - Quick mood log
   - Breathing exercise with haptic guidance
   - Heart rate during exercise display

AMBIENT VISUAL REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Features/Ambient/AmbientSettingsView.swift:
   - Theme selector with previews
   - Background style options (static, dynamic, animated)
   - Auto-adjust based on time of day toggle

2. Create Apps/ios/MindFriendApp/Features/Ambient/DynamicBackgroundView.swift:
   - Gradient backgrounds that shift based on time
   - Optional particle effects
   - Performance-optimized

3. Apply ambient themes throughout app:
   - Background colors/gradients
   - Accent colors matching theme
   - Consistent visual identity

DATABASE REQUIREMENTS:
1. Create table:
   - ambient_preferences (user_id, active_theme, background_type, auto_adjust_enabled)

TESTING:
1. Test widget data refresh
2. Test theme application across app
3. Test audio background playback
4. Performance tests for animations

ACCEPTANCE CRITERIA:
- At least 3 widgets available
- Themes apply consistently
- Ambient sounds play in background
- Auto-adjust responds to time of day
```

---

## Prompt 022: AR Grounding Exercises [MOONSHOT]

```
Implement AR Grounding Exercises as specified in claude-specs/022-ar-grounding-exercises.md.

OBJECTIVE: Create augmented reality wellness experiences using ARKit for immersive grounding exercises.

CURRENT STATE: Zero ARKit code exists. This is a new feature.

DATABASE REQUIREMENTS:
1. Create migration: supabase/migrations/YYYYMMDD_ar_grounding.sql
2. Create tables with RLS:
   - ar_exercise_types (exercise_name, ar_type, description, duration_seconds, instructions[], required_capabilities[])
   - ar_exercise_sessions (user_id, exercise_type_id, started_at, completed_at, effectiveness_rating)
   - ar_scene_preferences (user_id, default_scene, saved_scenes[], environment_prefs)
3. AR types: breathing_orb, grounding_541, safe_space, nature_immersion

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/get-ar-exercises/index.ts:
   - Return available AR exercises
   - Include capability requirements
   - Filter by device capabilities

2. Create supabase/functions/log-ar-session/index.ts:
   - Store session record
   - Track effectiveness

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Core/Models/ARExerciseModels.swift:
   - ARExerciseType, ARSession, ARSceneConfig structs
   - ARCapabilities struct (hasARKit, hasTrueDepth, hasLiDAR)

2. Create Apps/ios/MindFriendApp/Core/Services/ARCapabilityService.swift:
   - Detect device AR capabilities
   - Provide fallbacks for unsupported devices

3. Create Apps/ios/MindFriendApp/Features/AR/ARExerciseListView.swift:
   - List available AR exercises
   - Show capability requirements
   - Indicate unavailable exercises

4. Create Apps/ios/MindFriendApp/Features/AR/ARSceneView.swift (using ARKit):
   - Initialize AR session
   - Configure scene based on exercise
   - Handle tracking state
   - Fallback for poor tracking

5. Create Apps/ios/MindFriendApp/Features/AR/BreathingOrbARView.swift:
   - 3D breathing orb in AR space
   - Orb scales with breath pattern
   - Particle effects
   - Audio guidance

6. Create Apps/ios/MindFriendApp/Features/AR/Grounding541ARView.swift:
   - AR markers for 5-4-3-2-1 exercise
   - Point device at objects to label
   - Track progress through exercise

7. Create Apps/ios/MindFriendApp/Features/AR/SafeSpaceARView.swift:
   - Place virtual elements in space
   - Customize safe space
   - Save configuration

TESTING:
1. Test capability detection
2. Test session logging
3. Manual testing on AR devices

ACCEPTANCE CRITERIA:
- AR exercises work on supported devices
- Graceful degradation on unsupported
- Smooth 60fps rendering
- Session completion tracked
```

---

## Prompt 023: Biofeedback Adaptation [MOONSHOT]

```
Implement Biofeedback Adaptation as specified in claude-specs/023-biofeedback-adaptation.md.

OBJECTIVE: Use real-time Apple Watch data to adapt exercises based on heart rate, HRV, and stress.

CURRENT STATE: Tables exist but are unused. Apple Watch integration MISSING.

DATABASE REQUIREMENTS:
1. Tables exist but verify/update:
   - biometric_baselines (user_id, metric_type, baseline_value, standard_deviation, sample_size)
   - biofeedback_sessions (user_id, exercise_id, started_at, ended_at, adaptations_count, effectiveness_score)
   - biofeedback_readings (session_id, metric_type, value, recorded_at)
   - biofeedback_adaptations (session_id, adaptation_type, trigger_metric, trigger_value, new_setting)

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/calculate-baseline/index.ts:
   - Accept historical biometric data
   - Calculate resting baselines (HR, HRV)
   - Calculate standard deviations
   - Store baselines

2. Create supabase/functions/analyze-biometrics/index.ts:
   - Accept current readings and session context
   - Compare to baselines
   - Detect states: elevated stress, relaxation, recovery
   - Suggest adaptations

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Core/Models/BiofeedbackModels.swift:
   - BiometricBaseline, BiofeedbackSession, BiofeedbackReading structs
   - PhysiologicalState enum (baseline, elevated, stressed, relaxing, recovered)

2. Create Apps/ios/MindFriendApp/Core/Services/BiofeedbackService.swift:
   - Stream heart rate from Apple Watch via WatchConnectivity
   - Calculate real-time HRV if available
   - Compare to baselines
   - Suggest adaptations

3. Create Apps/ios/MindFriendWatchApp/ target:
   - Real-time heart rate streaming
   - HRV calculation
   - Send data to iPhone

4. Create Apps/ios/MindFriendApp/Features/Biofeedback/BiofeedbackExerciseView.swift:
   - Exercise with biofeedback overlay
   - Real-time heart rate display
   - State indicator (calm, elevated)
   - Adaptation notifications

5. Create Apps/ios/MindFriendApp/Features/Biofeedback/AdaptiveBreathingView.swift:
   - Breathing with biofeedback
   - Pace adjusts based on heart rate
   - Shows effectiveness in real-time

6. Create Apps/ios/MindFriendApp/Features/Settings/BiofeedbackSettingsView.swift:
   - Enable/disable biofeedback
   - Apple Watch connection status
   - Baseline recalculation option

TESTING:
1. Test baseline calculation
2. Test Watch connectivity
3. Test adaptation triggers
4. Manual testing with Watch

ACCEPTANCE CRITERIA:
- Real-time heart rate streams during exercise
- Baselines calculated from 7+ days data
- Adaptations trigger appropriately
- Works without Watch (graceful degradation)
```

---

# PHASE 7: AUTONOMOUS (024-025)

Industry-defining autonomous features.

---

## Prompt 024: Autonomous Wellness Agent [MOONSHOT]

```
Implement Autonomous Wellness Agent as specified in claude-specs/024-autonomous-wellness-agent.md.

OBJECTIVE: Create a proactive AI agent that monitors patterns and takes autonomous action within user-defined boundaries.

CURRENT STATE: Zero agent infrastructure exists. This is a new feature.

DATABASE REQUIREMENTS:
1. Create migration: supabase/migrations/YYYYMMDD_autonomous_agent.sql
2. Create tables with RLS:
   - agent_settings (user_id, is_enabled, autonomy_level, action_permissions[], quiet_hours_start, quiet_hours_end, max_daily_actions)
   - agent_signals (user_id, signal_type, signal_value, detected_at, confidence, context)
   - agent_actions (user_id, action_type, action_content, triggered_by_signal, delivered_at, user_response, effectiveness)
   - agent_learnings (user_id, learning_type, insight, confidence, applied_count)
   - agent_decisions (user_id, decision_type, options_considered, chosen_option, rationale, outcome)
3. Autonomy levels: minimal, balanced, proactive, guardian
4. Signal types: mood_decline, activity_drop, streak_risk, inactivity, positive_momentum

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/agent-monitor/index.ts:
   - Run every 30 minutes per user (or on trigger)
   - Detect signals:
     * Mood declining over 3+ days
     * Activity dropped significantly
     * Streak at risk
     * Extended inactivity
     * Positive momentum (reinforce)
   - Store detected signals
   - If actionable, trigger agent-decide

2. Create supabase/functions/agent-decide/index.ts:
   - Check autonomy level and permissions
   - Consider: signal urgency, user state, past effectiveness, quiet hours
   - Choose action or wait
   - Log decision with rationale

3. Create supabase/functions/agent-act/index.ts:
   - Execute decided action:
     * Send supportive message
     * Suggest exercise
     * Remind of streak
     * Celebrate progress
   - Personalize based on learnings
   - Log action

4. Create supabase/functions/agent-learn/index.ts:
   - Called after user response
   - Analyze effectiveness
   - Update learnings
   - Improve future decisions

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Core/Models/AgentModels.swift:
   - AgentSettings, AgentSignal, AgentAction, AgentLearning structs
   - AutonomyLevel, SignalType, ActionType enums

2. Create Apps/ios/MindFriendApp/Features/Agent/AgentDashboardView.swift:
   - Agent status
   - Recent actions taken
   - Detected signals
   - Learnings summary

3. Create Apps/ios/MindFriendApp/Features/Agent/AgentSettingsView.swift:
   - Enable/disable agent
   - Autonomy level selector with explanations
   - Permission toggles by action type
   - Quiet hours
   - Max daily actions

4. Create Apps/ios/MindFriendApp/Features/Agent/AgentActionLogView.swift:
   - History of actions
   - Mark as helpful/not helpful
   - See decision rationale

5. Handle agent notifications with special styling

TESTING:
1. Test signal detection
2. Test decision logic
3. Test permission enforcement
4. Test quiet hours
5. Test learning updates

ACCEPTANCE CRITERIA:
- Agent detects signals accurately
- Actions respect autonomy level
- Quiet hours strictly enforced
- Learnings improve over time
- User has full transparency
```

---

## Prompt 025: Generative Wellness Experiences [MOONSHOT]

```
Complete the Generative Wellness Experiences as specified in claude-specs/025-generative-wellness-experiences.md.

CURRENT STATE:
- Tables: generated_content, gen_content_requests, gen_content_series, gen_content_ratings
- Models: GeneratedContentModels.swift with 8 content types
- Edge Function: generate-content exists
- 133 references across codebase
- Generation infrastructure EXISTS
- Personalization quality UNCLEAR
- Voice synthesis NOT integrated

OBJECTIVE: Improve personalization quality and add voice synthesis.

WHAT EXISTS (DO NOT REBUILD):
- generated_content tables
- GeneratedContentModels.swift
- generate-content Edge Function
- Quota tracking

WHAT'S MISSING (IMPLEMENT THIS):

EDGE FUNCTION REQUIREMENTS:
1. Update supabase/functions/generate-content/index.ts:
   - Build rich context:
     * User's current emotional state
     * Recent challenges from companion memory
     * Preferences and past ratings
     * Time of day, season
     * Goals and themes
   - Avoid repetition (check generation_history)
   - Use detailed prompts for each content type:
     * Meditation: Include pauses, breathing cues, visualization
     * Sleep story: Calming narrative, slow pacing
     * Affirmations: Personal, present tense, believable
   - Store with generation context for learning

2. Create supabase/functions/synthesize-voice/index.ts:
   - Accept text content and voice preferences
   - Call TTS API (ElevenLabs or OpenAI TTS)
   - Apply voice styling (calm, warm, slow for meditations)
   - Store audio file in Supabase Storage
   - Return audio URL
   - Cache common phrases for speed

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Features/Generative/GenerativeHomeView.swift:
   - Quick generate buttons by type
   - Recent generations
   - Saved favorites
   - Generation preferences shortcut

2. Create Apps/ios/MindFriendApp/Features/Generative/GeneratedMeditationView.swift:
   - Audio playback with voice
   - Optional text follow-along
   - Background scene visualization
   - Progress indicator

3. Create Apps/ios/MindFriendApp/Features/Generative/GeneratedStoryView.swift:
   - Sleep story playback
   - Screen dims during play
   - Sleep timer option
   - Soothing visuals

4. Create Apps/ios/MindFriendApp/Features/Generative/VoicePreferencesView.swift:
   - Voice selection (male/female/neutral)
   - Speed preference
   - Preview voice

5. Add post-playback rating and save prompt

DATABASE REQUIREMENTS:
1. Add to generated_content or create:
   - voice_url column
   - voice_settings_used
   - generation_context_json

TESTING:
1. Test voice synthesis integration
2. Test personalization improvements
3. Test rating feedback loop
4. Performance test for generation + synthesis

ACCEPTANCE CRITERIA:
- Content generated within 10 seconds
- Voice synthesis within 5 additional seconds
- Content is highly personalized
- No repetitive themes
- Saved content accessible offline
```

---

# PHASE 8: SYNTHESIS (026-027)

Integrate all signals for ultimate prediction.

---

## Prompt 026: Stress Signature Fingerprint ⭐

```
Implement the Stress Signature Fingerprint as specified in claude-specs/026-stress-signature-fingerprint.md.

OVERVIEW:
This creates a personalized "early warning fingerprint" for each user - their unique prodromal symptoms (warning signs before crisis). By learning each user's signature through onboarding and history, the system detects approaching crises 24-72 hours in advance. No consumer app does personalized prodromal pattern learning.

LEVERAGING EXISTING INFRASTRUCTURE:
- 001 Nervous System State Engine (emotional signals)
- 006 Cognitive Distortion Detector (cognitive signals)
- 007 Social Vitality Index (social signals)
- 014 Wellbeing Debt (compound signals)
- HealthKit (sleep, activity signals)

DATABASE REQUIREMENTS:
1. Create migration for stress_signatures table:
   - User, crisis_type, components (JSONB WeightedComponent[])
   - source (user_reported/historical/hybrid), confidence

2. Create migration for pattern_alerts table:
   - User, signature_id, detected_at
   - active_components (JSONB), severity
   - predicted_time_to_event, intervention_delivered
   - user_feedback

3. Create migration for signature_signals table:
   - User, signal, value (0-1), date, source

4. Create migration for crisis_events table (if not exists):
   - User, crisis_type, occurred_at, severity
   - user_reported, analyzed

5. Seed signature component library (15 predefined components):
   - Sleep: insomnia_wired, oversleeping, early_waking
   - Social: isolation, irritability
   - Cognitive: rumination, indecision, catastrophizing
   - Emotional: numbness, tearfulness
   - Behavioral: procrastination, compulsions
   - Physical: appetite_change, tension, low_energy

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/learn-signature-from-history/index.ts:
   - Analyze signals 7 days before each crisis
   - Identify consistently elevated signals
   - Return learned signature

2. Create supabase/functions/detect-pattern-emergence/index.ts:
   - Monitor current signals against signature
   - Return alert if 2+ components active

iOS REQUIREMENTS:
1. Create Core/Services/StressSignatureEngine.swift:
   - Main engine coordinating learning and detection

2. Create Core/Services/PatternLearner.swift:
   - Learn from historical crisis data
   - Merge with user-reported

3. Create Core/Services/SignalMonitor.swift:
   - Daily signal measurement
   - Integration with other engines (001, 006, 007, 014)

4. Create Core/Services/PatternDetector.swift:
   - Compare active signals to signature
   - Severity classification
   - Time-to-event estimation

5. Create Core/Services/EarlyInterventionService.swift:
   - Generate personalized alert messages
   - Select appropriate intervention

6. Create Core/Models/StressSignatureModels.swift:
   - SignatureComponent (library of 15)
   - StressSignature, WeightedComponent
   - PatternAlert, SignatureSignal

7. Create Features/Signature/SignatureOnboardingFlow.swift:
   - Multi-step questionnaire
   - Category-by-category component selection
   - Save initial signature

8. Create Features/Signature/WarningSignsDashboardView.swift:
   - "My Warning Signs" list
   - Active signals indicator
   - Accuracy stats

9. Create Features/Signature/PatternAlertView.swift:
   - Gentle notification when pattern emerges
   - Personalized message
   - Intervention offer
   - Feedback collection (was this accurate?)

10. Integrate onboarding:
    - Add signature questionnaire after initial setup
    - 5-minute flow covering all categories

TESTING:
1. Test onboarding flow
2. Test pattern learning from history
3. Test signal monitoring accuracy
4. Test alert detection sensitivity
5. Test feedback loop for refinement

ACCEPTANCE CRITERIA:
- Signature captured during onboarding
- Pattern detected 24-72h before crisis
- > 80% true positive rate target
- Feedback refines signature weights
- Non-intrusive alert language
```

---

## Prompt 027: Longitudinal Mental Health Intelligence [MOONSHOT]

```
Implement Longitudinal Mental Health Intelligence as specified in claude-specs/027-longitudinal-mental-health-intelligence.md.

OBJECTIVE: Aggregate and analyze wellness data over months/years to identify long-term patterns and seasonal trends.

CURRENT STATE: Zero longitudinal analytics infrastructure. This is a new feature.

DATABASE REQUIREMENTS:
1. Create migration: supabase/migrations/YYYYMMDD_longitudinal_intelligence.sql
2. Create tables with RLS:
   - longitudinal_weekly_stats (user_id, week_start, avg_mood, mood_variance, active_days, exercises_completed, sleep_avg_hours)
   - longitudinal_monthly_stats (user_id, month_start, avg_mood, mood_trend, active_days_pct, notable_events[])
   - longitudinal_yearly_stats (user_id, year, quarterly_moods[], seasonal_patterns, yearly_comparison, milestones_achieved)
   - longitudinal_patterns (user_id, pattern_type, pattern_description, confidence, first_detected, occurrences)
   - longitudinal_life_events (user_id, event_type, event_date, impact_score, before_metrics, after_metrics, recovery_days)
   - longitudinal_reports (user_id, report_type, time_period, content_json, generated_at)
3. Pattern types: seasonal_mood, weekly_rhythm, event_response, improvement_trend

EDGE FUNCTION REQUIREMENTS:
1. Create supabase/functions/aggregate-weekly-stats/index.ts:
   - Run weekly (Sundays)
   - Calculate stats for completed week
   - Store in longitudinal_weekly_stats

2. Create supabase/functions/aggregate-monthly-stats/index.ts:
   - Run monthly (1st)
   - Aggregate from weekly stats
   - Calculate trends
   - Store in longitudinal_monthly_stats

3. Create supabase/functions/aggregate-yearly-stats/index.ts:
   - Run yearly (January 1)
   - Aggregate from monthly stats
   - Calculate seasonal patterns
   - Compare to previous year
   - Store in longitudinal_yearly_stats

4. Create supabase/functions/detect-patterns/index.ts:
   - Analyze longitudinal data
   - Detect: seasonal variations, weekly rhythms, event responses, improvement trends
   - Calculate confidence
   - Store patterns

5. Create supabase/functions/generate-longitudinal-report/index.ts:
   - Accept report_type (monthly, quarterly, yearly)
   - Compile data
   - Generate narrative insights
   - Store report

iOS REQUIREMENTS:
1. Create Apps/ios/MindFriendApp/Core/Models/LongitudinalModels.swift:
   - WeeklyStats, MonthlyStats, YearlyStats structs
   - LongitudinalPattern struct
   - LifeEvent struct
   - LongitudinalReport struct

2. Create Apps/ios/MindFriendApp/Features/Longitudinal/LongitudinalDashboardView.swift:
   - Year at a glance
   - Key patterns summary
   - Trend indicators
   - Generate report button

3. Create Apps/ios/MindFriendApp/Features/Longitudinal/YearlyOverviewView.swift:
   - 12-month mood chart
   - Seasonal pattern overlay
   - Year-over-year comparison
   - Milestones achieved

4. Create Apps/ios/MindFriendApp/Features/Longitudinal/PatternsView.swift:
   - Detected patterns list
   - Confidence indicators
   - Occurrence history

5. Create Apps/ios/MindFriendApp/Features/Longitudinal/LifeEventsView.swift:
   - Timeline of events
   - Impact visualization
   - Recovery tracking
   - Add new event

6. Create Apps/ios/MindFriendApp/Features/Longitudinal/ReportsView.swift:
   - Generated reports list
   - View/share/export
   - Schedule regular reports

TESTING:
1. Test aggregation calculations
2. Test pattern detection
3. Test report generation
4. Test year-over-year comparison

ACCEPTANCE CRITERIA:
- Weekly stats aggregated automatically
- Patterns detected with confidence scores
- Life events tracked with impact
- Reports generated on schedule
- Data exportable (FHIR format)
```

---

## Summary

| Phase       | Features                | Count |
| ----------- | ----------------------- | ----- |
| Foundation  | 001, 002, 003, 004, 005 | 5     |
| Enhancement | 006, 007                | 2     |
| Engagement  | 008, 009, 010, 011, 012 | 5     |
| Advanced    | 013, 014, 015, 016, 017 | 5     |
| Life/Social | 018, 019, 020           | 3     |
| Platform    | 021, 022, 023           | 3     |
| Autonomous  | 024, 025                | 2     |
| Synthesis   | 026, 027                | 2     |
| **Total**   |                         | 27    |

**Novel Differentiators (⭐):** 001, 002, 006, 007, 013, 014, 026
