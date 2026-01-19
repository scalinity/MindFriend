# MindFriend Codebase Overview

**Last Updated:** January 17, 2026
**Project:** MindFriend - iOS Mental Wellness App + Supabase Backend
**Status:** Active Development (Multiple feature specs in progress)

---

## 🎯 Project Overview

MindFriend is a consumer iOS app providing an AI "wellness buddy" companion alongside daily habits, mood tracking, and private friend circles. The tech stack is **iOS (SwiftUI) + Supabase Backend (PostgreSQL + Edge Functions)**.

### Core Features (MVP + Extended)

- Sign in with Apple/Google/Email via Supabase Auth
- AI chat companion with safety guardrails
- Daily quest assignment + streaks + badges
- Mood logging + analytics/insights
- Private invite-only circles + daily check-ins
- 45-exercise guided library (5 types: breathing, meditation, grounding, journaling, movement)
- Push notifications (quest reminder, inactivity nudge)
- Crisis resources + self-harm escalation flow
- StoreKit 2 subscription + entitlement gating
- Extended features: voice journal, biometric analysis, creative expression, peer support, etc.

---

## 📁 Repository Structure

```
mindfriend/
├── apps/
│   └── ios/
│       ├── MindFriendApp/               # Main iOS app source code
│       ├── MindFriendApp.xcodeproj      # Xcode project file
│       ├── MindFriendAppTests/          # Unit & integration tests
│       ├── MindFriendAppUITests/        # UI tests
│       ├── MindFriendWatch/             # WatchOS app (future)
│       ├── MindFriendWidgets/           # iOS widgets
│       └── Supabase/                    # Supabase iOS SDK
├── supabase/
│   ├── functions/                       # Edge Functions (40+ functions)
│   ├── migrations/                      # Database schema migrations
│   └── config.toml                      # Supabase project config
├── docs/
│   ├── PROGRESS.md                      # Feature implementation progress log
│   ├── decisions.md                     # Architecture decision log
│   ├── AUDIT_REPORT.md                  # Security audit findings
│   ├── SECURITY_AUDIT_FOLLOWUP.md       # Post-audit improvements
│   └── specs/                           # Feature specification docs
├── specs/                               # Feature requirement specs (15+ specs)
├── landing-page/                        # Marketing website (getmindfriend.app)
├── infra/                               # Infrastructure configuration
└── CLAUDE.md                            # AI agent operating guidelines
```

---

## 🏗️ Architecture & Tech Stack

### iOS Frontend

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI
- **State Management:** Swift Concurrency (async/await) + @Observable + @StateObject
- **Networking:** URLSession + Codable (via Supabase Swift SDK)
- **Local Persistence:** CoreData / SQLite
- **Secure Storage:** Keychain (tokens, secrets)
- **Auth:** Supabase Auth (Apple Sign In, Google Sign In)
- **In-App Purchases:** StoreKit 2
- **Push Notifications:** APNs + Supabase Realtime
- **Analytics:** Firebase Analytics + Crashlytics
- **Accessibility:** Dynamic Type, VoiceOver support

### Backend Stack

- **Platform:** Supabase (managed PostgreSQL + services)
  - **Auth:** Supabase Auth (Apple, Google, Email/Password)
  - **Database:** PostgreSQL with Row Level Security (RLS)
  - **Edge Functions:** Deno/TypeScript (40+ serverless functions)
  - **Realtime:** Supabase Realtime for live circle updates
  - **Storage:** Supabase Storage for audio/media assets
- **AI Provider:** xAI (Grok) - called only via Edge Functions
- **CI/CD:** GitHub Actions
- **Infrastructure:** Supabase Cloud (auto-scaling, managed backups)

---

## 📱 iOS App Directory Structure

```
MindFriendApp/
├── App/                          # App entry point & dependency injection
│   ├── MindFriendApp.swift       # @main entry point
│   ├── DependencyContainer.swift # Service locator pattern
│   └── AppDelegate.swift         # App lifecycle, push notification setup
│
├── Core/                         # Shared utilities & base services
│   ├── Models/                   # Data models (User, Quest, Mood, etc.)
│   ├── Services/                 # Core services (Auth, Data, Notifications)
│   ├── Accessibility/            # Accessibility models & service
│   ├── Observability/            # Logging, analytics, crash reporting
│   ├── Extensions/               # Swift extensions (Foundation, SwiftUI)
│   └── Utilities/                # Helper functions, constants
│
├── Networking/                   # API & Supabase integration
│   ├── SupabaseClient.swift      # Supabase SDK wrapper
│   └── Services/
│       ├── LiveService.swift     # Realtime subscriptions
│       └── ... (other API services)
│
├── Features/                     # Feature modules (one per feature)
│   ├── Auth/                     # Sign in, registration, password reset
│   ├── Home/                     # Main dashboard view
│   ├── Chat/                     # AI conversation + history
│   ├── Mood/                     # Mood logging & history
│   ├── Quests/                   # Quest display, completion
│   ├── Circles/                  # Private friend circles
│   ├── Achievements/             # Badges & streak display
│   ├── Exercises/                # Exercise library + playback
│   ├── Crisis/                   # Crisis resources & escalation
│   ├── Subscription/             # Paywall & entitlement gating
│   ├── Programs/                 # Multi-week programs
│   ├── Buddy/                    # Onboarding buddy
│   ├── Family/                   # Family features
│   ├── Personalization/          # User preferences & settings
│   ├── Insights/                 # Weekly/monthly analytics
│   ├── Creator/                  # Content creator tools
│   ├── Biometrics/               # Heart rate, sleep data
│   ├── MicroMoments/             # Quick wellness activities
│   └── ... (15+ feature modules)
│
└── Resources/
    ├── Assets.xcassets/          # Images, app icons, colors
    └── Localizable.strings       # i18n strings
```

### Key iOS Components

| Module           | Purpose                                   | Key Files                                                             |
| ---------------- | ----------------------------------------- | --------------------------------------------------------------------- |
| **Auth**         | Sign in, registration, session management | `SignInView.swift`, `SupabaseAuthService.swift`                       |
| **Home**         | Dashboard with quest, mood, circles, chat | `HomeView.swift`, `HomeViewModel.swift`                               |
| **Chat**         | AI conversation interface + history       | `ChatView.swift`, `ChatViewModel.swift`, `ConversationListView.swift` |
| **Mood**         | Mood entry + history visualization        | `MoodView.swift`, `MoodHistoryView.swift`                             |
| **Quests**       | Daily quest display + completion tracking | `QuestView.swift`, `QuestDetailView.swift`                            |
| **Circles**      | Friend circle creation, joining, posts    | `CirclesView.swift`, `CircleDetailView.swift`                         |
| **Exercises**    | Exercise library browse + playback        | `ExerciseListView.swift`, `ExerciseDetailView.swift`                  |
| **Achievements** | Badges, streaks, milestones               | `AchievementsView.swift`                                              |
| **Crisis**       | Crisis resources, self-harm escalation    | `CrisisView.swift`, `ResourcesView.swift`                             |
| **Subscription** | Premium paywall, entitlement checking     | `PaywallView.swift`, `SubscriptionManager.swift`                      |

---

## 🗄️ Backend Architecture

### Edge Functions (40+ deployed)

| Function                           | Purpose                                | Trigger          | Notes                                    |
| ---------------------------------- | -------------------------------------- | ---------------- | ---------------------------------------- |
| **chat**                           | AI conversation with safety moderation | HTTP POST        | Streams response, logs crisis events     |
| **assign-quest**                   | Daily quest assignment                 | Cron (daily)     | Selects template, ensures 1 per user/day |
| **send-notification**              | Push notification delivery             | HTTP POST        | Uses APNS, respects quiet hours          |
| **verify-purchase**                | StoreKit transaction validation        | HTTP POST        | Updates subscription status              |
| **create-gift**                    | Create virtual gifts for circles       | HTTP POST        | Peer-to-peer recognition                 |
| **generate-weekly-summary**        | Weekly insights email/push             | Cron             | Mood trends, quest streaks               |
| **check-streak-risk**              | Identify at-risk streaks               | Cron             | Send re-engagement notifications         |
| **award-xp**                       | Award experience points                | Database trigger | Based on quest, mood, exercise           |
| **check-badge-progress**           | Check badge completion                 | Database trigger | Milestone tracking                       |
| **analyze-voice-journal**          | Transcribe + summarize audio           | HTTP POST        | Voice journal analysis                   |
| **analyze-biometrics**             | Process health data                    | HTTP POST        | HealthKit integration                    |
| **delete-account**                 | GDPR-compliant data erasure            | HTTP POST        | Secure user data deletion                |
| ... and 25+ more feature functions |

**Shared utilities** (`_shared/`):

- `cors.ts` - CORS middleware
- `validation.ts` - Input validation helpers
- `auth.ts` - JWT validation
- `errors.ts` - Error handling patterns

### Database Schema (20+ tables)

| Table                         | Purpose                      | Key Columns                                                     |
| ----------------------------- | ---------------------------- | --------------------------------------------------------------- |
| **profiles**                  | User profile data            | id, user_id, name, avatar, bio, age                             |
| **user_settings**             | User preferences             | user_id, theme, quiet_hours, notifications_enabled              |
| **quests**                    | Daily quests                 | id, user_id, template_id, completed_at, streak_count            |
| **quest_templates**           | Quest definitions (100+)     | id, title, description, category, difficulty                    |
| **moods**                     | Mood log entries             | id, user_id, mood_score, notes, created_at                      |
| **conversations**             | Chat session metadata        | id, user_id, title, created_at                                  |
| **messages**                  | Chat messages                | id, conversation_id, user_id, content, role (user/assistant)    |
| **circles**                   | Friend circles               | id, creator_id, name, invite_code                               |
| **circle_members**            | Circle membership            | circle_id, user_id, joined_at                                   |
| **circle_posts**              | Daily check-ins              | id, circle_id, user_id, content, reactions                      |
| **exercises**                 | Exercise library (45 items)  | id, title, type (breathing/meditation/etc), duration, audio_url |
| **exercise_sessions**         | Completed exercises          | id, user_id, exercise_id, completed_at, duration                |
| **badges**                    | Badge definitions (29 items) | id, name, category, icon_url, unlock_condition                  |
| **user_badges**               | Earned badges                | user_id, badge_id, unlocked_at                                  |
| **subscriptions**             | Premium subscriptions        | user_id, tier, expires_at, is_active                            |
| **crisis_events**             | Safety escalation logs       | id, user_id, trigger_keyword, timestamp, action_taken           |
| **voice_journals**            | Audio journal entries        | id, user_id, audio_url, transcription, created_at               |
| **accessibility_preferences** | A11y settings                | user_id, font_size, high_contrast, voiceover_enabled            |
| **live_experiences**          | Scheduled group activities   | id, title, start_time, max_participants                         |
| **family_members**            | Family connections           | id, user_id, relative_user_id, relationship                     |

**All tables have:**

- Row Level Security (RLS) policies
- Created/updated timestamps
- Proper foreign key constraints
- Appropriate indexes for query performance

### Database Migrations (20+ files)

Recent migrations (in `supabase/migrations/`):

- `20260307000000_peer_support.sql` - Peer support system (circles, reactions)
- `20260309000000_audio_content_library.sql` - Audio exercises + voice journals
- `20260310000000_smart_personalization.sql` - Personalization engine
- `20260311000000_achievement_system_v2.sql` - Badge system improvements
- `20260312000000_content_creators.sql` - Creator tools & rewards
- `20260314000000_create_accessibility_tables.sql` - Accessibility settings
- `20260316000000_code_quality_improvements.sql` - Performance & fixes
- `20260317000000_security_audit_*.sql` - Security hardening (multiple)
- `20260320000000_spec15_business_model_innovation.sql` - Business model features
- `20260321000000_optimize_family_rls.sql` - Family feature RLS optimization

---

## 🔐 Security Model

### Authentication

- **Primary:** Supabase Auth (Apple Sign In, Google Sign In, Email/Password)
- **Session Management:** JWT tokens stored securely in Keychain
- **Multi-factor Auth:** Optional via Supabase Auth

### Authorization (Row Level Security)

```sql
-- Example: Users can only see their own moods
CREATE POLICY "Users read own moods" ON moods
  FOR SELECT USING (auth.uid() = user_id);

-- Example: Circle members can only see circle data
CREATE POLICY "Circle members view posts" ON circle_posts
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM circle_members
            WHERE circle_members.circle_id = circle_posts.circle_id
            AND circle_members.user_id = auth.uid())
  );
```

### Data Privacy

- **Keychain:** Auth tokens, refresh tokens, device IDs
- **CoreData:** Local cache (quest, mood history - non-sensitive)
- **Encryption:** TLS 1.3 for all network communication
- **GDPR:** Delete account flow with complete data erasure

### Safety & Crisis Management

- **Input Moderation:** Edge Function screens for self-harm keywords
- **Crisis Template:** Special response + logged to `crisis_events` table
- **Crisis Resources:** Emergency contacts, hotline numbers, escalation procedures
- **Logging:** All crisis events logged with timestamp & user context (HIPAA-compliant)

---

## 📊 Data Flows

### 1. Sign In Flow

```
iOS App → Sign in with Apple/Google
        → Supabase Auth validates
        → Session token created
        → Database trigger creates user profile
        → iOS stores session in Keychain
        → HomeView displayed
```

### 2. Daily Quest Flow

```
iOS App → Query quests table for today
        → No quest found?
           → Call assign-quest Edge Function
           → Selects random template
           → Creates quest_instance
           → Returns quest to iOS
        → User completes quest
           → iOS updates quest_instance (completed_at)
           → Database trigger fires:
              - Updates user streak
              - Awards XP
              - Checks badge unlock conditions
              - Updates achievement stats
```

### 3. AI Chat Flow

```
iOS App → User sends message
        → Call chat Edge Function
           → Validate JWT
           → Input moderation (check for crisis keywords)
           → If crisis detected: log to crisis_events, return crisis template
           → Compose prompt with user context (mood history, streak, etc.)
           → Call xAI (Grok) API
           → Stream response back to iOS
           → Output moderation (safety checks)
           → Store message + response in database
           → Update conversation timestamp
        → iOS displays response in real-time
```

### 4. Circle Check-In Flow

```
iOS App → User posts daily check-in to circle
        → Supabase client inserts to circle_posts
        → RLS policy validates circle membership
        → Realtime subscription broadcasts to other members
        → Members see new post in real-time
        → Optional: reactions (gift) triggers create-gift function
```

### 5. Subscription Flow

```
iOS App → User initiates StoreKit 2 purchase
        → StoreKit 2 handles transaction
        → iOS calls verify-purchase Edge Function
           → Validates transaction with App Store Server API
           → Updates subscriptions table
           → Returns entitlements
        → RLS policies gate premium features based on subscription status
```

---

## 🎯 Feature Status & Implementation Specs

### Implemented (MVP + Extended)

- ✅ Authentication (Apple/Google/Email)
- ✅ Home dashboard
- ✅ AI chat with safety guardrails
- ✅ Daily quests + streaks + badges (29 badges)
- ✅ Mood logging + history
- ✅ Private circles + check-ins
- ✅ 45 exercises (breathing, meditation, grounding, journaling, movement)
- ✅ Push notifications
- ✅ Crisis resources + self-harm escalation
- ✅ StoreKit 2 subscription + paywall
- ✅ Accessibility features (Dynamic Type, VoiceOver)
- ✅ Profile settings + preferences

### Extended Features (Implemented)

- ✅ Voice journal (audio transcription + analysis)
- ✅ Biometric analysis (heart rate, sleep)
- ✅ Creative expression (drawing, mood boards)
- ✅ Peer support (gifts, circle reactions)
- ✅ Weekly insights & analytics
- ✅ Family features (family members, alerts)
- ✅ Onboarding buddy (interactive guide)
- ✅ Micro-moments (quick wellness activities)
- ✅ Programs (multi-week structured plans)
- ✅ Content creator tools

### In Development (Feature Specs)

Specs are in `specs/` directory:

- **Spec 01:** AI Memory (conversation context persistence)
- **Spec 02:** Onboarding flows
- **Spec 03:** Circle virality (invite mechanics)
- **Spec 04:** Smart notifications (timing, frequency)
- **Spec 05:** Progression system (XP, levels, ranks)
- **Spec 06:** Weekly insights (trends, recommendations)
- **Spec 07:** Credibility signals (expert verification badges)
- **Spec 08:** Monetization (premium tiers, rewards)
- **Spec 09:** Voice mode (voice input/output)
- **Spec 10:** Streak recovery (second-chance mechanics)
- **Spec 11:** Re-engagement flows (lapsed user recovery)
- **Spec 12:** Quest choice (user selects from 3 options)
- **Spec 13:** Mood-adaptive home (dynamic UI based on mood)
- **Spec 14:** Celebration & sharing (achievement sharing)
- **Spec 15:** Business model innovation (enterprise, B2B)

---

## 🧪 Testing

### iOS Tests

- **Unit Tests:** `MindFriendAppTests/`
  - `SupabaseAuthServiceTests.swift` - Auth flow testing
  - `QuestViewModelTests.swift` - Quest logic, streak updates
  - `ChatViewModelTests.swift` - Chat, entitlement gating
  - `MoodViewModelTests.swift` - Mood persistence
  - `BusinessModelsTests.swift` - Data model validation
  - `ModelsTests.swift` - Model serialization
- **UI Tests:** `MindFriendAppUITests/`
  - Authentication flow
  - Quest completion
  - Chat interaction

### Edge Function Tests

- Deno test files in `supabase/functions/`
- Test files: `join-family/test.ts`, `_shared/validation.test.ts`
- Run with: `deno test supabase/functions/*/test.ts`

### Test Requirements (from CLAUDE.md)

- Supabase auth flow tests
- Quest completion → streak update
- Entitlement gating (quota exceeded → paywall)
- Mood entry persistence
- Offline cache fallback
- RLS policies verified for all tables

---

## 📚 Documentation

### Core Documents

- **CLAUDE.md** - AI agent operating guidelines, architectural decisions
- **MindFriend-spec.md** - Complete technical specification
- **docs/PROGRESS.md** - Feature implementation progress log (detailed)
- **docs/decisions.md** - Architecture decision log
- **docs/AUDIT_REPORT.md** - Security audit findings
- **docs/SECURITY_AUDIT_FOLLOWUP.md** - Post-audit improvements

### Feature Specifications

Each spec includes:

- User stories
- Technical requirements
- Database schema changes
- API endpoints / Edge Functions
- Testing approach
- Acceptance criteria

### Key Files for Understanding the Codebase

| Purpose                    | File Path                                                |
| -------------------------- | -------------------------------------------------------- |
| App entry                  | `apps/ios/MindFriendApp/App/MindFriendApp.swift`         |
| Dependency injection       | `apps/ios/MindFriendApp/App/DependencyContainer.swift`   |
| Core models                | `apps/ios/MindFriendApp/Core/Models/`                    |
| Supabase client            | `apps/ios/MindFriendApp/Networking/SupabaseClient.swift` |
| Home view                  | `apps/ios/MindFriendApp/Features/Home/HomeView.swift`    |
| Chat feature               | `apps/ios/MindFriendApp/Features/Chat/`                  |
| Auth service               | `apps/ios/MindFriendApp/Networking/Services/`            |
| Database schema            | `supabase/migrations/`                                   |
| Chat function              | `supabase/functions/chat/`                               |
| Edge function shared utils | `supabase/functions/_shared/`                            |

---

## 🚀 Development Workflow

### Local Setup

```bash
# Start Supabase local development
supabase start

# Apply migrations to local DB
supabase db push

# Open iOS app
cd apps/ios
open MindFriendApp.xcodeproj

# Run tests
xcodebuild test -scheme MindFriendApp -destination 'platform=iOS Simulator,name=iPhone 15'

# Serve Edge Functions locally
supabase functions serve
```

### Git Workflow

- **Main branch:** Production-ready code
- **Feature branches:** Not typically used (direct main commits post-review)
- **Commit format:** Conventional commits (feat:, fix:, docs:, etc.)
- **Migration discipline:** ALWAYS run `supabase db push` immediately after creating migrations

### Key Commands

```bash
# Create new migration
supabase migration new <name>

# Apply migrations
supabase db push

# Deploy Edge Functions
supabase functions deploy

# View function logs
supabase functions logs <function-name>

# Reset local database (destructive)
supabase db reset
```

---

## 🔍 Code Quality & Standards

### Swift Conventions

- **Naming:** camelCase for properties/methods, PascalCase for types
- **Access control:** private/fileprivate for internals, public only when needed
- **Error handling:** Using Swift's Result type where appropriate
- **Async/await:** Modern concurrency, not callbacks/promises
- **Testing:** XCTest framework, async test methods with @MainActor

### Database Conventions

- **Column naming:** snake_case
- **Foreign keys:** Always defined with ON DELETE CASCADE/RESTRICT
- **Timestamps:** created_at, updated_at on all tables
- **Indexes:** On frequently queried columns (user_id, created_at)
- **RLS:** All tables must have RLS enabled with explicit policies

### Documentation Standards

- **Commit messages:** Descriptive, following conventional commits
- **Code comments:** Only for non-obvious logic (self-documenting code preferred)
- **PROGRESS.md:** Updated immediately after feature completion
- **decisions.md:** Record all spec-adjacent decisions

---

## ⚠️ Common Gotchas

### Migration Management

- **Rule:** ALWAYS run `supabase db push` immediately after creating/modifying migrations
- Never leave migrations unapplied — causes schema drift
- Use `CREATE TABLE IF NOT EXISTS` for idempotency
- Wrap `CREATE POLICY` in conditional blocks to avoid duplicate policy errors
- Order matters: create tables before policies that reference them

### RLS & Security

- All tables must have RLS enabled
- Test RLS policies carefully — mistakes can expose data or block legitimate access
- Use `auth.uid()` for user context, never trust client-sent user_id
- Crisis events are sensitive — log carefully (PII considerations)

### Offline Behavior (MVP)

- Cache today's quest locally
- Cache last N mood entries
- Chat requires connectivity (show offline state)
- Sync queue for mood entries when reconnected

### StoreKit 2 & Entitlements

- Client initiates purchase, sends originalTransactionId to Edge Function
- Edge Function validates with App Store Server API
- Subscription status updated in database
- RLS gates premium features based on subscription

---

## 📞 Getting Help

### If you need to...

| Task                          | Location                           | Command                          |
| ----------------------------- | ---------------------------------- | -------------------------------- |
| Understand architecture       | `CLAUDE.md` Section 2-3            | —                                |
| Find a specific feature       | `apps/ios/MindFriendApp/Features/` | —                                |
| Check current progress        | `docs/PROGRESS.md`                 | —                                |
| Make architectural decision   | `docs/decisions.md`                | Record in same file              |
| Debug a function              | `supabase/functions/`              | `supabase functions logs <name>` |
| Reset development environment | Terminal                           | `supabase db reset`              |
| Check migration status        | Terminal                           | `supabase migration list`        |

---

## 🎓 Learning Resources

### Swift/SwiftUI

- Apple SwiftUI tutorials
- WWDC sessions (State management, Async/await)

### Supabase

- [Supabase documentation](https://supabase.com/docs)
- [Supabase Swift SDK](https://github.com/supabase/supabase-swift)
- [Edge Functions guide](https://supabase.com/docs/guides/functions)

### iOS Development

- Apple's Human Interface Guidelines
- OWASP Mobile Security Top 10

---

## 📋 Checklist for New Contributors

- [ ] Read `CLAUDE.md` (operating rules)
- [ ] Read `MindFriend-spec.md` (requirements)
- [ ] Understand repo structure (this document)
- [ ] Set up local Supabase: `supabase start && supabase db push`
- [ ] Open iOS project: `cd apps/ios && open MindFriendApp.xcodeproj`
- [ ] Run iOS tests to verify setup
- [ ] Pick a feature spec from `specs/`
- [ ] Update `docs/PROGRESS.md` after completing work
- [ ] Record architectural decisions in `docs/decisions.md`
- [ ] Get familiar with git workflow (commits, no force pushes)

---

**For more details, always refer to:**

1. `CLAUDE.md` - Authoritative operating guidelines
2. `MindFriend-spec.md` - Complete technical requirements
3. `docs/PROGRESS.md` - What's been completed
4. `docs/decisions.md` - Architectural rationale
