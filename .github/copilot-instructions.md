# GitHub Copilot Instructions for MindFriend

## Project Overview

MindFriend is an iOS app providing a personalized AI wellness companion with daily habits (quests), mood logging, and private friend circles for mental self-care and focus-building.

**Tech Stack:**
- **iOS**: Swift 5.9+, SwiftUI (iOS 17+)
- **Backend**: Supabase (PostgreSQL, Edge Functions, Auth, Realtime, Storage)
- **AI Provider**: xAI (Grok) via Supabase Edge Functions
- **Payments**: StoreKit 2
- **State Management**: Swift Concurrency (async/await) + Observable/@StateObject
- **Networking**: URLSession + Codable
- **Package Management**: Swift Package Manager (SPM only)

**Source of Truth**: `MindFriend-spec.md` - If implementation details conflict with the spec, the spec wins.

## Architecture and Patterns

### Supabase-First Architecture
- All API calls go through Supabase (no separate backend server)
- Use Supabase Swift SDK for auth, database, and functions
- Edge Functions (Deno/TypeScript) handle complex logic (AI chat, notifications, billing)
- Row Level Security (RLS) enforces data access at database level

### iOS Application Structure
```
apps/ios/MindFriendApp/
  App/                  # App entry, DependencyContainer
  Core/                 # Models, APIClient, Extensions
  Features/             # Feature modules (Auth, Home, Chat, Mood, Quests, Circles, Exercises, Profile)
  Resources/            # Assets, Localizable strings
```

### Dependency Injection
Use `DependencyContainer` for all services:
```swift
@MainActor
final class DependencyContainer: ObservableObject {
    lazy var supabaseAuthService: SupabaseAuthService
    lazy var supabaseDataService: SupabaseDataService
    let apiClient: APIClient
    let keychainManager: KeychainManager
    let sessionManager: SessionManager
}
```

## Coding Standards

### Swift/SwiftUI Conventions
- Use modern SwiftUI with Swift Concurrency (async/await)
- Prefer `@Observable` and `@StateObject` for state management
- Use functional patterns and avoid imperative code where possible
- Follow Apple's Swift API Design Guidelines
- Use Swift Package Manager exclusively (no CocoaPods/Carthage)

### Naming Conventions
- **Database columns**: `snake_case` (e.g., `created_at`)
- **Swift models**: `camelCase` properties (e.g., `createdAt`)
- **JSON API payloads**: `camelCase` (e.g., `createdAt`)
- **Edge Functions**: `kebab-case` filenames (e.g., `assign-quest`)

### File Organization
- One View per file
- ViewModels in same directory as their View
- Shared models in `Core/Models.swift`
- Feature-specific models in feature directory

### Code Style
- Use SwiftLint rules (when configured)
- Prefer explicit types for public APIs
- Use type inference for local variables
- Add documentation comments for public APIs
- Keep functions focused and under 50 lines when possible

## Database and Backend

### Supabase Edge Functions
```typescript
// Standard Edge Function structure
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Validate JWT
  const authHeader = req.headers.get("Authorization")!;
  const { data: { user } } = await supabase.auth.getUser(
    authHeader.replace("Bearer ", "")
  );
  
  if (!user) {
    return new Response("Unauthorized", { status: 401 });
  }

  // Business logic...

  return new Response(JSON.stringify(result), {
    headers: { "Content-Type": "application/json" },
  });
});
```

### Database Migrations
- **ALWAYS** run `supabase db push` immediately after creating or modifying a migration
- Use `CREATE TABLE IF NOT EXISTS` and `ALTER TABLE ADD COLUMN IF NOT EXISTS` for idempotency
- Wrap `CREATE POLICY` in conditional `DO $$ ... END $$` blocks checking `pg_policies`
- Create tables before policies that reference them
- Enable Row Level Security (RLS) on all user-facing tables

### RLS Policy Pattern
```sql
-- Users can only read/write their own data
CREATE POLICY "Users read own data" ON table_name
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users insert own data" ON table_name
  FOR INSERT WITH CHECK (auth.uid() = user_id);
```

## Security Requirements

### Critical Security Rules
- **Never** call AI providers directly from iOS client - always through Edge Functions
- **Never** commit secrets or API keys to code
- Implement self-harm escalation behavior exactly as specified (block normal response → crisis template + `crisis_event` logging)
- Use Row Level Security (RLS) policies for all data access
- Validate all Edge Function requests with JWT authentication
- Store sensitive data in Keychain, never UserDefaults
- Use HTTPS for all network requests

### Data Privacy
- User data is private by default (enforced via RLS)
- Circle data visible only to members
- Crisis events logged for safety monitoring
- Implement proper data deletion on account termination

## Testing Requirements

### iOS Tests
- Unit tests for ViewModels and business logic
- Integration tests for Supabase interactions
- Test authentication flows
- Test offline behavior and caching
- Verify entitlement gating (free vs premium quotas)
- Test crisis detection and escalation

### Edge Function Tests
```bash
# Run Edge Function tests
deno test supabase/functions/*/test.ts
```

### Testing Checklist Before Merging
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing in simulator
- [ ] No linting errors
- [ ] Documentation updated if APIs changed

## Feature-Specific Guidelines

### AI Chat
- All AI conversations go through `chat` Edge Function
- Implement streaming responses for better UX
- Enforce daily quota for free tier users
- Detect self-harm keywords and trigger crisis flow
- Store conversation history in `conversations` and `messages` tables

### Authentication
- Support Sign in with Apple, Google, and Email/Password
- Use Supabase Auth for all authentication
- Store session tokens via `supabase-swift` SDK
- Implement proper sign-out clearing all local data
- Handle token refresh automatically

### Subscriptions (StoreKit 2)
1. Client initiates purchase via StoreKit 2
2. Client sends `originalTransactionId` to `verify-purchase` Edge Function
3. Edge Function validates with App Store Server API
4. Edge Function updates `subscriptions` table
5. RLS policies gate premium features based on subscription status

### Push Notifications
- Register APNs token via Edge Function
- Respect user's quiet hours settings
- Send daily quest reminder
- Send inactivity nudge (if configured)
- Handle notification permissions properly

## Common Patterns

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

### Error Handling
```swift
do {
    let result = try await supabase.from("table").select()
    // Handle success
} catch {
    // Log error
    logger.error("Failed to fetch data: \(error)")
    // Show user-friendly message
    errorMessage = "Unable to load data. Please try again."
}
```

## Documentation Requirements

### When to Update Documentation
- **After every feature**: Log in `docs/PROGRESS.md` using standard entry format
- **Architectural decisions**: Record in `docs/decisions.md`
- **Ideas and brainstorming**: Use `SCRATCHPAD.md`
- **Migration notes**: Include in migration file comments

### Progress Entry Format
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

## What NOT to Do

### Scope Creep Prevention
Do **not** implement in MVP:
- Public communities, search, recommendations
- Direct messages between users
- HealthKit / wearable sync
- Human coaching workflows
- Advanced analytics pipelines
- Multi-language localization beyond scaffolding
- Complex notification types beyond daily quest + inactivity
- A/B testing infrastructure

### Anti-Patterns
- ❌ Don't invent endpoints not in spec
- ❌ Don't use CocoaPods or Carthage (SPM only)
- ❌ Don't call external APIs directly from iOS (use Edge Functions)
- ❌ Don't store secrets in code or UserDefaults
- ❌ Don't skip RLS policies on database tables
- ❌ Don't implement features not in `MindFriend-spec.md` without documenting decision
- ❌ Don't delete or modify working tests to make them pass
- ❌ Don't add comments unless they match existing style or explain complex logic

## Development Workflow

### Local Development
```bash
# Start Supabase locally
supabase start

# Apply migrations
supabase db push

# Serve Edge Functions
supabase functions serve

# Deploy Edge Functions
supabase functions deploy

# Open iOS project
cd apps/ios && open MindFriendApp.xcodeproj
```

### Before Committing
1. Run tests and ensure they pass
2. Build the app and verify no warnings
3. Run linters if configured
4. Update documentation if APIs changed
5. Log progress in `docs/PROGRESS.md`

### Change Discipline
- Prefer small, reviewable diffs
- Make minimal modifications to achieve goals
- Update tests when changing behavior
- Document decisions in `docs/decisions.md`

## Accessibility

- Support Dynamic Type including accessibility sizes
- Provide VoiceOver labels on all interactive elements
- Minimum touch target: 44×44 pt
- Ensure sufficient color contrast
- Test with VoiceOver enabled

## Environment Configuration

### Required Environment Variables (Edge Functions)
- `XAI_API_KEY` - AI chat/voice provider
- `APNS_KEY_ID` - Push notifications
- `APNS_TEAM_ID` - Push notifications
- `APNS_PRIVATE_KEY` - Push notifications (base64)
- `APP_STORE_ISSUER_ID` - StoreKit validation
- `APP_STORE_KEY_ID` - StoreKit validation
- `APP_STORE_PRIVATE_KEY` - StoreKit validation (base64)

### iOS Configuration
- Supabase credentials in `SupabaseConfig.swift`
- Debug builds: Local Supabase (`localhost:54321`)
- Release builds: Production Supabase URL

## Additional Resources

- **Full Spec**: `MindFriend-spec.md`
- **Agent Instructions**: `CLAUDE.md`
- **Progress Log**: `docs/PROGRESS.md`
- **Decisions Log**: `docs/decisions.md`
- **Scratchpad**: `SCRATCHPAD.md`

---

**Remember**: When in doubt, refer to `MindFriend-spec.md` - it is the source of truth. Choose the lowest-risk, most conservative interpretation for ambiguous requirements and document your decision.
