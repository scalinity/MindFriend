# Retained routes for support sessions

Source inventory at `bba67bb6e059e32fe60765f0ed0c77697d71bc7b`; canonical map: SUPPORT_SESSION_SPEC.md §4.2. This is source evidence, not runtime acceptance. All 26 `DeepLinkRoute` cases (25 functional plus unknown) are recorded below. Parser aliases, request identity, ownership, entitlement and unavailable handling remain contracts.

| Existing case | Retained destination | Baseline qualification |
|---|---|---|
| home | Today | Existing Home |
| chat(conversationId:) | Chat | Owned conversation lookup |
| circles(circleId:) | Explore, direct Circles row | Membership validated |
| profile | You | Existing More/Profile |
| settings | You → Settings | Previously same Profile root |
| mood | Optional Today check-in | Existing mood entry |
| moodHistory | You → History/Progress | Existing history |
| quest(questId:) | Today chosen work; You → Progress → Daily quests | Exact/current quest, unavailable if absent |
| streak | You → Progress → Streaks and shields | ShieldHistoryView |
| progress | You → Progress | Activation hold must be removed |
| breathing | Explore → Practices | QuickBreathingView |
| meditation | Explore → Practices | Existing general library behavior |
| exercise(exerciseId:) | Explore → Practices | Exact catalog ID |
| exerciseLibrary | Explore → Practices | Existing library |
| programs | Explore → Programs and Pathways | Activation hold must be removed |
| therapeuticPrograms | Explore → Programs and Pathways | Activation hold must be removed |
| program(programId:) | Explore → Programs and Pathways | Exact program; remove activation hold |
| journal | Explore → Practices → Journal → Text | Existing journal |
| microMoments(templateId:) | Explore → Practices | Exact template and paid gate |
| sleep(contentId:) | Explore → Practices → Sleep | Exact content, paid gate, no autoplay |
| quote | Explore → Practices → Quotes | Pre-existing route selects Home only |
| assessment(code:) | You → Progress → Assessments; Explore shortcut | Validated code; remove activation hold |
| buddy(code:) | Explore → People and Circles | App-level invitation parsing |
| insights | You → Progress/History | WeeklyInsightsView |
| achievements | You → Progress | AchievementsView |
| unknown | Native unavailable screen | Previously error alert |

Aliases: circle, breathe, meditate, exercise/meditation, exercise with no ID, exercises, program with no ID, micro-moments. Preserve UUID validation, assessment uppercasing, buddy-code format, rejection of extra path segments, and fresh request UUIDs for repeated links.

## Production entrypoints to retain

| Source | Named destinations | New home |
|---|---|---|
| HomeView composition | Mood, daily quest, difficulty/capacity, streak/shields/recovery quest, habits, daily briefing, active action plan, quest arcs, buddy invitations/encouragement, weekly insights, sensory toolkit, progress stories, Insight Lab, transition pathways, seasonal participation | Compact chosen Today work; named Explore/You routes for the rest |
| Home measurement links | WellbeingDebtDashboardView, SleepDashboardView | You → Measurements |
| Home QuickActionsSection | LiveSessionsView, CreativeHubView, ExerciseLibraryView, MoodHistoryView, GenerativeHomeView, BadgesView, TherapistDiscoveryView, WarningSignsDashboardView, SOS, SafetyPlanView | Explore Practices/Tools/People, You Progress/Measurements, independent Help |
| Home sheets | RecoveryQuestView, buddy invitation, QuestArcCatalogView, PreemptiveInterventionView, PathwaySelectionView, PathwayDashboardView | Corresponding named capability |
| Profile progress | Achievements, certificates, NarrativeListView (My Stories), LongitudinalDashboardView (Your Journey) | You → Progress/History |
| Profile Features/Social | Circles, SleepTabView, ForYouView, mentorship, peer support, partner mode, family | Direct Explore entries |
| Profile professional | TherapistApplicationView | You → Settings/professional |
| Profile settings | Biometrics, notifications, AI preferences, interventions, vacation, shields, privacy, app lock, Private Vault, generated/curated memories, appearance, language, proactive check-ins, Wellness Agent, SOS, Recovery Mode, Our Approach | You settings/memory/measurements; Private Vault remains separate/device-only |
| Profile data/support | Export/delete account, crisis resources, contact support, Terms/Privacy, edit profile, subscription | You |
| ChatListView/ChatView | New/current chat, owned link, conversation-bound voice | Chat |
| CreativeHubView/CreativeGalleryView | Voice journal recorder and saved analysis; creative tools | Explore → Practices → Journal → Voice; creative tools separately retained |
| GenerativeHomeView | Voice preferences, story/meditation, soundscape, history/favorites | Explore Tools/Practices; distinct from For You |
| ForYouView | Personalized catalog exercise/insights | Explore → For You |
| HabitCompletionCard | Habit library/create/detail | You → Progress → Habits |
| SensoryToolkitCard | SensoryHomeView | Explore → Practices |
| InsightLabHomeCard | InsightLabView | Explore → Tools and Experiments |
| ActionPlanHomeCard/ActionPlanSheet | Existing plan/item mutation/regeneration | You → Progress → Plans; distinct from Saved steps |

Primary source paths: `Features/Home/{MainTabView,HomeView}.swift`, `Features/Profile/ProfileView.swift`, `Core/DeepLinkRouter.swift`, `App/AppState.swift`, `Features/Chat/{ChatListView,ChatView}.swift`. All under `apps/ios/MindFriendApp/`.

## Pre-existing scaffolds, not verified reachable features

- ActionCardStackView and its contained cards: no production callsite.
- RewriteOptionsView and RewriteFeedbackView: previews only.
- AICoachingView and CopingKitsView roots: previews only; descendant views do not establish entry.
- Creator Studio: Profile entry commented out.
- ActionPlanService.generatePlan: regeneration caller exists; initial-generation entry not found.
- Quote route: Home only, no quote-specific destination.
- MainTab circles/mentorship/sleep/personalization cases exist but are not rendered tabs.

## First-run boundary

Original MindFriend-spec.md §6.1 requires birth year, under-13 block, server computation, nonclinical disclaimer, skippable personalization. Baseline SignInView links are plain text; OnboardingFlow has no age/consent check; SupabaseDataService completion writes only focus/time. Direct sign-ins call setAuthenticated without checking needsOnboarding, unlike cold restore. These are source-confirmed gaps.

Read-only HTTP checks returned 200 for `https://getmindfriend.app/terms/` and `/privacy/`; served processor disclosure parity remains unverified. Existing completed accounts are retained without claiming historical age verification. New completion must acknowledge the new server contract before proceeding.
