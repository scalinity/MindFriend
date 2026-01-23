# CLAUDE.md — MindFriend Repo Guide (for Claude Code / AI Coding Agents)

<!-- Last updated: 2026-01-14 | Version: 2.1 | Owner: @mindfriend-team -->

This file defines the operating constraints, repo conventions, and "definition of done" for automated coding agents working on **MindFriend**.

**Source of truth:** `MindFriend-spec.md`
If a detail here conflicts with the spec, the spec wins. If the spec is ambiguous, choose the lowest-risk, most conservative interpretation, and record it in `docs/decisions.md`.

---

## 0) Project Goal

Ship an MVP of **MindFriend**: iOS (SwiftUI) + Supabase Backend (PostgreSQL + Edge Functions), matching the spec.

MVP includes:

- Sign in with Apple / Google / Email auth via Supabase Auth
- AI chat companion (guardrailed + daily quota for free tier)
- Daily quest assignment + completion (streaks, badges)
- Mood logging + history
- Invite-only circles + daily check-ins
- Exercise library + sessions (45 exercises across 5 types)
- Push notifications (daily quest + inactivity nudge) respecting quiet hours
- StoreKit 2 subscription entitlements (free quota vs premium) with server-side validation
- Crisis resources screen + safety escalation (self-harm handling)

---

## 1) Operating Rules (Non-Negotiables)

### Spec fidelity

- Do **not** invent endpoints, fields, or business logic not defined in `MindFriend-spec.md` unless:
  - required for internal implementation, **and**
  - optional/backward-compatible, **and**
  - documented in `docs/decisions.md`.

### Safety and privacy

- AI calls must go through Supabase Edge Functions (not direct from iOS client).
- Implement the self-harm escalation behavior exactly (block normal response → crisis template + `crisis_event` logging).
- Use Row Level Security (RLS) policies to enforce data access at the database level.

### Shipping discipline

- Prioritize end-to-end "happy path" MVP: auth → home → mood → quest → chat → circles → exercises → settings → paywall.
- Avoid "future enhancements" until MVP is feature-complete and tests are green.

### Change control

- Prefer small, reviewable diffs.
- If touching API contracts or data model, update:
  - Supabase migrations
  - Tests validating contract behavior

### Migration discipline

- **ALWAYS run `supabase db push` immediately after creating or modifying a migration file.**
- Never leave migrations unapplied — schema drift causes cascading errors when later migrations reference missing tables/columns.
- When creating migrations that reference other tables, verify those tables exist in the remote database first.
- Use `CREATE TABLE IF NOT EXISTS` and `ALTER TABLE ADD COLUMN IF NOT EXISTS` for idempotency.
- Wrap `CREATE POLICY` statements in conditional `DO $$ ... END $$` blocks checking `pg_policies` to avoid duplicate policy errors.
- Order matters: create tables before policies that reference them (e.g., create `family_members` before `family_groups` policy that references it).

### Progress documentation

- **After completing any feature or bug fix**, log it in `docs/PROGRESS.md` using the standard entry format.
- Write new ideas, improvements, and strategic notes to `SCRATCHPAD.md`.
- Use `SCRATCHPAD.md` for brainstorming and "what if" explorations that don't belong in code or `decisions.md`.

### Progress logging (REQUIRED)

After each feature implementation or bug fix session, create an entry in `docs/PROGRESS.md`:

```markdown
## [YYYY-MM-DD] Feature/Fix Name

**Type:** Feature | Bugfix | Refactor | Test | Docs
**Status:** Complete | In Progress | Blocked

### Summary

One-line description of what was done.

### Changes

- **File:** `path/to/file` — Description of change

### Testing

- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Manual verification done

### Notes

Any additional context, blockers, or follow-ups.
```

**Logging rules:**

- Log immediately after completing work (not days later)
- Include specific file paths and line numbers for significant changes
- Mark testing checkboxes honestly
- Use tables for multiple related changes
- Keep summaries to one line; details go in Changes section

### Decision documentation

- Record all spec-adjacent or architectural decisions in `docs/decisions.md`.
- Use `decisions.md` when:
  - Implementing something not explicitly defined in the spec
  - Choosing between multiple valid approaches
  - Making trade-offs that affect future development
  - Deviating from common patterns for a specific reason
- Follow the template format (see Section 13 or the template at the end of `decisions.md`).
- **`decisions.md` vs `SCRATCHPAD.md`:** Decisions are permanent architectural records; scratchpad is for ideas and progress notes.

### API integration and documentation

- **ALWAYS use Context7 MCP** (`mcp__context7__query-docs`) when integrating third-party APIs or libraries.
- Never rely on assumptions or outdated knowledge about API parameters, models, or supported values.
- Workflow:
  1. Use `mcp__context7__resolve-library-id` to find the correct library ID
  2. Use `mcp__context7__query-docs` to get current API documentation
  3. Verify parameter names, allowed values, and constraints from docs
  4. Document any non-obvious API requirements in code comments

**Example: OpenAI gpt-image-1-mini (2026-01-23)**

- **Supported sizes:** `1024x1024`, `1024x1536`, `1536x1024` (NOT `512x512`)
- **Quality parameter:** Not supported (standard quality only)
- **Response format:** `b64_json` or `url`
- **Note:** `512x512` only available for DALL-E 2, not GPT image models
- **Lesson learned:** Always verify API parameters via Context7 before implementation

---

## 2) Architecture Overview

### Tech Stack

| Layer         | Technology                                    |
| ------------- | --------------------------------------------- |
| iOS Client    | SwiftUI, Swift 5.9+, iOS 17+                  |
| Auth          | Supabase Auth (Apple, Google, Email/Password) |
| Database      | Supabase PostgreSQL with RLS                  |
| Backend Logic | Supabase Edge Functions (Deno/TypeScript)     |
| Storage       | Supabase Storage (audio files)                |
| Realtime      | Supabase Realtime (circle updates)            |
| Payments      | StoreKit 2 + Edge Function validation         |

### Why Supabase-Only (No Separate API Server)

- Single platform for auth, database, functions, storage, realtime
- Built-in Row Level Security eliminates most auth middleware
- Edge Functions handle complex logic (AI chat, notifications, billing)
- Simpler deployment and operations
- Native Swift SDK for iOS

---

## 3) Repository Layout

```
mindfriend/
  apps/
    ios/                      # SwiftUI iOS app (SPM only)
      MindFriendApp/
        App/                  # App entry, DependencyContainer
        Core/                 # Models, APIClient, Extensions
        Features/             # Feature modules (Auth, Home, Chat, etc.)
        Resources/            # Assets, Localizable strings
      MindFriendApp.xcodeproj
  supabase/
    functions/                # Edge Functions (Deno)
      chat/                   # AI conversation handler
      assign-quest/           # Daily quest assignment
      send-notification/      # Push notification sender
      verify-purchase/        # StoreKit validation
      _shared/                # Shared utilities
    migrations/               # SQL migrations
    config.toml               # Supabase project config
  docs/
    PROGRESS.md               # Development progress log (REQUIRED after each feature)
    decisions.md              # Architecture decision log
    runbooks.md               # Operational procedures
  .env.example
```

**Note:** iOS uses Swift Package Manager exclusively. Open `apps/ios/MindFriendApp.xcodeproj` directly (no `.xcworkspace`).

---

## 4) Local Development

### Prerequisites

- Xcode 15+ (or latest stable)
- Supabase CLI (`brew install supabase/tap/supabase`)
- Deno (for Edge Function development)
- Apple Developer account for Sign in with Apple

### 4.1 Supabase Local Development

```bash
# Start local Supabase stack
supabase start

# Apply migrations
supabase db push

# View local dashboard
open http://localhost:54323
```

Local endpoints:

- API: `http://localhost:54321`
- Auth: `http://localhost:54321/auth/v1`
- Database: `postgresql://postgres:postgres@localhost:54322/postgres`
- Dashboard: `http://localhost:54323`

### 4.2 iOS App

```bash
cd apps/ios
open MindFriendApp.xcodeproj
```

- Select iPhone Simulator, Run
- Debug builds connect to `http://localhost:54321` (configured in code)
- Use "Skip Sign In (Dev Only)" button for quick testing

### 4.3 Edge Functions

```bash
# Serve functions locally
supabase functions serve

# Test a function
curl -X POST http://localhost:54321/functions/v1/chat \
  -H "Authorization: Bearer <jwt>" \
  -H "Content-Type: application/json" \
  -d '{"conversationId": "...", "content": "Hello"}'
```

### 4.4 Running Tests

**iOS:**

```bash
cd apps/ios
xcodebuild test \
  -scheme MindFriendApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath TestResults
```

---

## 5) Environment Configuration

### Supabase Project Settings

Required environment variables for Edge Functions (set in Supabase Dashboard):

| Variable                | Purpose                      |
| ----------------------- | ---------------------------- |
| `XAI_API_KEY`           | AI chat/voice provider       |
| `APNS_KEY_ID`           | Push notifications           |
| `APNS_TEAM_ID`          | Push notifications           |
| `APNS_PRIVATE_KEY`      | Push notifications (base64)  |
| `APP_STORE_ISSUER_ID`   | StoreKit validation          |
| `APP_STORE_KEY_ID`      | StoreKit validation          |
| `APP_STORE_PRIVATE_KEY` | StoreKit validation (base64) |

### iOS Configuration

The iOS app reads Supabase credentials from:

- `SupabaseConfig.swift` - Contains `supabaseURL` and `supabaseAnonKey`
- Debug builds: Local Supabase (`localhost:54321`)
- Release builds: Production Supabase URL

Keychain storage:

- Supabase session tokens managed by `supabase-swift` SDK
- Legacy JWT tokens in `KeychainManager` (migration path)

---

## 6) Database Schema & Conventions

### Tables

| Table               | Purpose                                |
| ------------------- | -------------------------------------- |
| `profiles`          | User profile data (extends auth.users) |
| `user_settings`     | User preferences                       |
| `quests`            | Assigned daily quests                  |
| `quest_templates`   | Quest definitions                      |
| `moods`             | Mood log entries                       |
| `conversations`     | Chat conversation metadata             |
| `messages`          | Chat messages                          |
| `circles`           | Friend circles                         |
| `circle_members`    | Circle membership                      |
| `circle_posts`      | Circle check-ins                       |
| `exercises`         | Exercise library (45 entries)          |
| `exercise_sessions` | Completed exercise records             |
| `badges`            | Badge definitions (29 entries)         |
| `user_badges`       | Earned badges                          |
| `subscriptions`     | Premium subscription status            |
| `crisis_events`     | Safety escalation logs                 |

### Naming Conventions

| Layer             | Convention   | Example      |
| ----------------- | ------------ | ------------ |
| Database columns  | `snake_case` | `created_at` |
| Swift models      | `camelCase`  | `createdAt`  |
| JSON API payloads | `camelCase`  | `createdAt`  |

### Row Level Security (RLS)

All tables have RLS enabled. Policies enforce:

- Users can only read/write their own data
- Circle data visible to members only
- Exercises/badges readable by all authenticated users

Example policy:

```sql
CREATE POLICY "Users can read own profile"
  ON profiles FOR SELECT
  USING (auth.uid() = id);
```

### Migrations

```bash
# Create new migration
supabase migration new <migration_name>

# Apply migrations
supabase db push

# Reset database (destructive)
supabase db reset
```

---

## 7) iOS Architecture Conventions

### Feature Module Structure

```
Features/
  Auth/
    SignInView.swift
    EmailAuthView.swift
  Home/
    HomeView.swift
    HomeViewModel.swift
  Chat/
    ChatView.swift
    ChatViewModel.swift
    ConversationListView.swift
  Mood/
    MoodView.swift
    MoodHistoryView.swift
  Quests/
    QuestView.swift
    QuestDetailView.swift
  Circles/
    CirclesView.swift
    CircleDetailView.swift
  Exercises/
    ExerciseListView.swift
    ExerciseDetailView.swift
  Profile/
    ProfileView.swift
    SettingsView.swift
```

### Dependency Injection

`DependencyContainer` provides all services:

```swift
@MainActor
final class DependencyContainer: ObservableObject {
    // Supabase services (primary)
    lazy var supabaseAuthService: SupabaseAuthService
    lazy var supabaseDataService: SupabaseDataService

    // Legacy services (migration path)
    let apiClient: APIClient
    let keychainManager: KeychainManager
    let sessionManager: SessionManager
}
```

### Supabase Swift SDK Usage

```swift
// Auth
let user = try await supabase.auth.signInWithIdToken(...)

// Database queries
let quests: [Quest] = try await supabase
    .from("quests")
    .select()
    .eq("user_id", userId)
    .execute()
    .value

// Edge Function calls
let response = try await supabase.functions.invoke(
    "chat",
    options: .init(body: ["conversationId": id, "content": message])
)

// Realtime subscriptions
let channel = supabase.channel("circle:\(circleId)")
    .onPostgresChange(event: .insert, table: "circle_posts") { payload in
        // Handle new post
    }
await channel.subscribe()
```

### Offline Behavior (MVP)

- Cache today's quest payload locally
- Cache last N mood entries
- Chat requires connectivity; show clear offline state

### StoreKit 2 Flow

1. Client initiates purchase via StoreKit 2
2. Client sends `originalTransactionId` to `verify-purchase` Edge Function
3. Edge Function validates with App Store Server API
4. Edge Function updates `subscriptions` table
5. RLS policies gate premium features based on subscription status

### Accessibility

- Support Dynamic Type including accessibility sizes
- VoiceOver labels on all interactive elements
- Minimum touch target: 44×44 pt

---

## 7.1) Adding Files to Xcode Project (CRITICAL)

When creating new Swift files, you MUST add them to the Xcode project (`project.pbxproj`). Files on disk that aren't in the project won't compile.

### Why This Matters

- Xcode doesn't auto-discover files - the project file (`project.pbxproj`) is the source of truth
- Files must be in both the filesystem AND the project file to compile
- The GUI "Add Files..." option may be unavailable in some contexts

### Method: Use Ruby xcodeproj Gem

**Never manually edit `project.pbxproj`** - it's a complex OpenStep format that's easy to corrupt. Use Apple's official tool instead.

#### Install (one-time)

```bash
gem install xcodeproj
```

#### Add Files Script

Create and run this Ruby script from `apps/ios/`:

```ruby
#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }
test_target = project.targets.find { |t| t.name == 'MindFriendAppTests' }

# Helper to find/create group hierarchy matching filesystem
def find_or_create_group(project, file_path)
  components = Pathname.new(file_path).each_filename.to_a
  filename = components.pop

  current_group = project.main_group
  components.each do |component|
    child = current_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == component
    }
    current_group = child || current_group.new_group(component, component)
  end

  [current_group, filename]
end

# Add a file to the project
file_path = "MindFriendApp/Features/NewFeature/MyView.swift"  # EDIT THIS
is_test = file_path.include?("Tests")
target = is_test ? test_target : app_target

group, filename = find_or_create_group(project, file_path)
file_ref = group.new_reference(filename)
file_ref.source_tree = '<group>'
file_ref.last_known_file_type = 'sourcecode.swift'
target.source_build_phase.add_file_reference(file_ref)

project.save
puts "Added: #{file_path}"
```

#### Bulk Add Missing Files

To find and add all Swift files not in the project:

```ruby
#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }
test_target = project.targets.find { |t| t.name == 'MindFriendAppTests' }

def find_or_create_group(project, file_path)
  components = Pathname.new(file_path).each_filename.to_a
  filename = components.pop
  current_group = project.main_group
  components.each do |component|
    child = current_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == component
    }
    current_group = child || current_group.new_group(component, component)
  end
  [current_group, filename]
end

# Find missing files
Dir.glob("{MindFriendApp,MindFriendAppTests}/**/*.swift").each do |file_path|
  basename = File.basename(file_path)
  next if project.files.any? { |f| File.basename(f.path.to_s) == basename }

  is_test = file_path.include?("Tests")
  target = is_test ? test_target : app_target

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{file_path}"
end

project.save
```

### Key Concepts

| Term                     | Meaning                              |
| ------------------------ | ------------------------------------ |
| `PBXFileReference`       | Metadata about a file (path, type)   |
| `PBXGroup`               | Folder structure in Xcode navigator  |
| `PBXBuildFile`           | Maps file to a build phase           |
| `PBXSourcesBuildPhase`   | Compile sources for a target         |
| `sourceTree = "<group>"` | Path is relative to containing group |

### Common Pitfalls

1. **Path doubling**: Don't use full paths when `sourceTree = "<group>"` - just use the filename
2. **Missing groups**: Create the full group hierarchy matching the filesystem
3. **Wrong target**: Test files go to `MindFriendAppTests`, app files to `MindFriendApp`
4. **Validation**: Always run `xcodebuild -list` after changes to verify project is valid

### Removing Orphaned References

If a file was deleted but the reference remains:

```ruby
require 'xcodeproj'
project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')

orphan_files = ['DeletedFile.swift', 'OldView.swift']  # EDIT THIS

project.targets.each do |target|
  target.source_build_phase.files.each do |build_file|
    next unless build_file.file_ref
    if orphan_files.include?(File.basename(build_file.file_ref.path.to_s))
      build_file.remove_from_project
    end
  end
end

project.files.each do |file_ref|
  if orphan_files.include?(File.basename(file_ref.path.to_s))
    file_ref.remove_from_project
  end
end

project.save
```

---

## 8) Edge Functions

### Function Inventory

| Function            | Trigger      | Purpose                            |
| ------------------- | ------------ | ---------------------------------- |
| `chat`              | HTTP POST    | AI conversation with safety checks |
| `assign-quest`      | Cron (daily) | Assign new quest to each user      |
| `send-notification` | HTTP POST    | Send push notification via APNS    |
| `verify-purchase`   | HTTP POST    | Validate StoreKit transaction      |

### Edge Function Structure

```typescript
// supabase/functions/chat/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Get user from JWT
  const authHeader = req.headers.get("Authorization")!;
  const {
    data: { user },
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  // Business logic...

  return new Response(JSON.stringify(result), {
    headers: { "Content-Type": "application/json" },
  });
});
```

### Deployment

```bash
# Deploy all functions
supabase functions deploy

# Deploy specific function
supabase functions deploy chat

# View function logs
supabase functions logs chat
```

---

## 9) Content Data

### Exercises (45 total)

| Type       | Count | Premium |
| ---------- | ----- | ------- |
| Breathing  | 10    | 3       |
| Meditation | 12    | 5       |
| Grounding  | 8     | 1       |
| Journaling | 8     | 3       |
| Movement   | 7     | 2       |

### Badges (29 total)

| Category              | Count |
| --------------------- | ----- |
| Getting Started       | 5     |
| Quest Milestones      | 6     |
| Streak Achievements   | 7     |
| Exercise Achievements | 5     |
| Social                | 4     |
| Special               | 5     |

---

## 10) Testing Strategy

### iOS Tests Required

| Test Case                                     | File                             |
| --------------------------------------------- | -------------------------------- |
| Supabase auth flow                            | `SupabaseAuthServiceTests.swift` |
| Quest completion updates streak               | `QuestViewModelTests.swift`      |
| Entitlement gating (quota exceeded → paywall) | `ChatViewModelTests.swift`       |
| Mood entry persistence                        | `MoodViewModelTests.swift`       |
| Offline cache fallback                        | `QuestViewModelTests.swift`      |

### Edge Function Tests

```bash
# Run function tests
deno test supabase/functions/*/test.ts
```

---

## 11) Security

### Row Level Security

All tables must have RLS enabled with appropriate policies:

```sql
-- Users can only see their own moods
CREATE POLICY "Users read own moods" ON moods
  FOR SELECT USING (auth.uid() = user_id);

-- Users can only insert their own moods
CREATE POLICY "Users insert own moods" ON moods
  FOR INSERT WITH CHECK (auth.uid() = user_id);
```

### Edge Function Auth

All Edge Functions must validate the JWT:

```typescript
const {
  data: { user },
  error,
} = await supabase.auth.getUser(token);
if (error || !user) {
  return new Response("Unauthorized", { status: 401 });
}
```

### Crisis Event Handling

Self-harm detection in chat:

1. Edge Function detects crisis keywords
2. Log to `crisis_events` table
3. Return crisis template response
4. Block normal AI response

---

## 12) "Definition of Done" Checklist

You are done when:

1. ✅ `supabase start` runs local stack
2. ✅ All migrations applied successfully
3. ✅ iOS app runs in simulator and can:
   - Sign in with Apple/Google/Email
   - Fetch today's quest
   - Complete quest and see streak update
   - Log mood and view history
   - Create/join circle and post daily check-in
   - Use AI chat (quota enforced via Edge Function)
   - Trigger crisis flow and see resources
   - Purchase/restore premium and remove quota limits
4. ✅ iOS tests pass
5. ✅ Edge Function tests pass
6. ✅ RLS policies verified for all tables
7. ✅ `docs/decisions.md` documents all spec-adjacent choices

---

## 13) Engineering Decision Log

All spec-adjacent decisions must be written to `docs/decisions.md`:

```markdown
## YYYY-MM-DD: [Decision Title]

**Decision:** What was decided.

**Rationale:** Why this choice was made.

**Alternatives considered:**

- Option A: Why rejected
- Option B: Why rejected

**Implications:** What this affects going forward.
```

### Recent Decisions

- **2025-01-12:** Migrate from NestJS to Supabase-only architecture
  - Simpler stack, built-in auth/RLS, Edge Functions for complex logic
  - NestJS code archived to `archive/nestjs-api` branch

---

## 14) Guardrails Against Scope Creep

Do not implement in MVP:

- Public communities, search, recommendations, DMs
- HealthKit / wearable sync
- Human coaching workflows
- Advanced analytics pipelines
- Complex notification types beyond daily quest + inactivity
- A/B testing infrastructure

**Note:** Multi-language localization (Spanish, Portuguese) is now IN SCOPE for MVP as of 2026-01-19 (see decisions.md #2026-01-19-001).

If you believe something beyond MVP is required for correctness, document it in `decisions.md` and keep implementation minimal.

---

## 15) When Stuck

| Situation                          | Action                                                                    |
| ---------------------------------- | ------------------------------------------------------------------------- |
| Spec is ambiguous                  | Choose conservative interpretation → Document in `decisions.md` → Proceed |
| Blocked by external dependency     | Stub with `// TODO: [reason]` → Continue with other work                  |
| Test fails unexpectedly            | **Do NOT delete or skip.** Investigate root cause → Fix code or fix test  |
| Unsure if feature is in scope      | Re-read Section 14 → If still unsure, ask human                           |
| Implementation conflicts with spec | Spec wins → Document conflict in `decisions.md`                           |
| Security concern                   | **Stop.** Document concern → Ask human before proceeding                  |

---

## Appendix: Quick Reference

### Common Commands

```bash
# Start local Supabase
supabase start

# Apply migrations
supabase db push

# Deploy Edge Functions
supabase functions deploy

# View logs
supabase functions logs <function-name>

# Open local dashboard
open http://localhost:54323

# Run iOS tests
cd apps/ios && xcodebuild test -scheme MindFriendApp -destination 'platform=iOS Simulator,name=iPhone 17'

# Generate types from schema
supabase gen types typescript --local > types/supabase.ts
```

### Key File Locations

| Purpose              | Path                                                   |
| -------------------- | ------------------------------------------------------ |
| **Progress log**     | `docs/PROGRESS.md`                                     |
| Decision log         | `docs/decisions.md`                                    |
| iOS app entry        | `apps/ios/MindFriendApp/App/MindFriendApp.swift`       |
| Dependency container | `apps/ios/MindFriendApp/App/DependencyContainer.swift` |
| Core models          | `apps/ios/MindFriendApp/Core/Models.swift`             |
| Supabase config      | `supabase/config.toml`                                 |
| Migrations           | `supabase/migrations/`                                 |
| Edge Functions       | `supabase/functions/`                                  |

---

## 16) Landing Page Website (getmindfriend.app)

The marketing/landing page is hosted on a Hostinger VPS.

### SSH Access

```bash
# Connect to the server (uses ~/.ssh/config alias)
ssh hostinger
```

### File Locations

| Path                                    | Purpose             |
| --------------------------------------- | ------------------- |
| `/var/www/mindfriend/`                  | Website root        |
| `/var/www/mindfriend/index.html`        | Landing page        |
| `/var/www/mindfriend/auth/`             | Auth callback pages |
| `/var/www/mindfriend/assets/`           | Images, logo        |
| `/var/www/mindfriend/css/`              | Stylesheets         |
| `/var/www/mindfriend/js/`               | JavaScript files    |
| `/etc/nginx/sites-available/mindfriend` | Nginx site config   |

### Auth Pages

| File                       | Purpose                                    |
| -------------------------- | ------------------------------------------ |
| `auth/callback.html`       | Handles Supabase auth redirects (PKCE)     |
| `auth/confirmed.html`      | Email confirmation success + app deep link |
| `auth/reset-password.html` | Password reset form                        |

### Common Operations

```bash
# View website files
ssh hostinger "ls -la /var/www/mindfriend/"

# Edit a file (use heredoc for multi-line)
ssh hostinger "cat > /var/www/mindfriend/path/to/file.html" << 'EOF'
<html>...</html>
EOF

# Or use cat with pipe
cat local-file.html | ssh hostinger "cat > /var/www/mindfriend/path/to/file.html"

# View nginx config
ssh hostinger "cat /etc/nginx/sites-available/mindfriend"

# Reload nginx (if config changed)
ssh hostinger "sudo systemctl reload nginx"

# Check nginx status
ssh hostinger "sudo systemctl status nginx"

# View nginx error logs
ssh hostinger "sudo tail -50 /var/log/nginx/error.log"
```

### Supabase Auth Configuration

The website handles Supabase email confirmation redirects. Ensure these settings in Supabase Dashboard → Authentication → URL Configuration:

| Setting       | Value                                      |
| ------------- | ------------------------------------------ |
| Site URL      | `https://getmindfriend.app/auth/callback`  |
| Redirect URLs | `https://getmindfriend.app`                |
|               | `https://getmindfriend.app/auth/callback`  |
|               | `https://getmindfriend.app/auth/confirmed` |
|               | `mindfriend://` (for deep links)           |

### Domain & DNS

- **Domain:** getmindfriend.app (managed via Squarespace)
- **DNS Records:** A record points to Hostinger VPS IP
- **Email:** Uses Resend SMTP with SPF, DKIM, DMARC configured

---
