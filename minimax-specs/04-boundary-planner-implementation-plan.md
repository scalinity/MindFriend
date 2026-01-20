# Boundary & Needs Planner - Implementation Plan

**Version:** 1.0  
**Status:** Ready for Implementation  
**Created:** 2026-01-20  
**Specification:** `04-boundary-planner-spec-formal.md` (READY, 10/10 completeness)

---

## Executive Summary

The Boundary & Needs Planner feature will be implemented across three layers:

1. **Database Layer:** 4 new tables with RLS policies, triggers, and indexes
2. **Backend Layer:** 9 Edge Functions for business logic and AI script generation
3. **iOS Layer:** 7 SwiftUI views + models + service integration

**Integration Points:**
- Conversation Rehearsal Studio (existing) via `custom_scenarios` table extension
- Localization system (existing) via `Localizable.xcstrings` additions
- Subscription/Entitlements (existing) for tier limit enforcement

**Estimated Effort:** 22-30 hours across 5 implementation phases

---

## Change Impact

### Files to Create

#### Database Migrations (1 file)

| File | Purpose | Risk |
|------|---------|------|
| `supabase/migrations/20260120270000_boundary_planner_schema.sql` | Core schema with 4 tables, RLS policies, indexes, triggers | Low |

#### Edge Functions (9 files)

| File | Purpose | Risk |
|------|---------|------|
| `supabase/functions/create-assessment/index.ts` | POST - Create needs assessment with top_needs calculation | Low |
| `supabase/functions/generate-boundary/index.ts` | POST - Generate boundary with tier limit check | Low |
| `supabase/functions/generate-scripts/index.ts` | POST - Generate boundary scripts from templates | Medium |
| `supabase/functions/save-boundary/index.ts` | POST - Update boundary status with state validation | Low |
| `supabase/functions/list-boundaries/index.ts` | GET - List user boundaries with filters | Low |
| `supabase/functions/schedule-followup/index.ts` | POST - Schedule follow-up check-in | Low |
| `supabase/functions/record-outcome/index.ts` | POST - Record follow-up outcome | Low |
| `supabase/functions/get-assessment/index.ts` | GET - Retrieve assessment by ID | Low |
| `supabase/functions/get-templates/index.ts` | GET - Retrieve script templates | Low |

#### iOS Models (1 file)

| File | Purpose | Risk |
|------|---------|------|
| `apps/ios/MindFriendApp/Core/BoundaryModels.swift` | Swift models for all boundary entities | Low |

#### iOS Services (1 file)

| File | Purpose | Risk |
|------|---------|------|
| `apps/ios/MindFriendApp/Core/Services/BoundaryPlannerService.swift` | Network service layer for boundary APIs | Low |

#### iOS Views (7 files)

| File | Purpose | Risk |
|------|---------|------|
| `apps/ios/MindFriendApp/Features/Boundaries/NeedsAssessmentView.swift` | 4-step guided assessment flow | Medium |
| `apps/ios/MindFriendApp/Features/Boundaries/PriorityMatrixView.swift` | Visual needs matrix display | Low |
| `apps/ios/MindFriendApp/Features/Boundaries/BoundaryDefinitionView.swift` | Boundary statement builder form | Medium |
| `apps/ios/MindFriendApp/Features/Boundaries/ScriptGeneratorView.swift` | Script template selection & generation | Medium |
| `apps/ios/MindFriendApp/Features/Boundaries/BoundaryPracticeView.swift` | Integration with Conversation Rehearsal | High |
| `apps/ios/MindFriendApp/Features/Boundaries/BoundaryFollowUpView.swift` | Check-in and outcome recording | Low |
| `apps/ios/MindFriendApp/Features/Boundaries/BoundariesListView.swift` | List view with filters | Low |

#### Seed Data (1 file)

| File | Purpose | Risk |
|------|---------|------|
| `supabase/migrations/20260120270001_seed_boundary_templates.sql` | 135 script templates (45 en + 45 es + 45 pt) | Low |

#### Test Files (3 files)

| File | Purpose | Risk |
|------|---------|------|
| `apps/ios/MindFriendAppTests/BoundaryPlannerServiceTests.swift` | Unit tests for service layer | Low |
| `apps/ios/MindFriendAppTests/BoundaryModelsTests.swift` | Unit tests for model validation | Low |
| `supabase/functions/create-assessment/test.ts` | Edge function tests for assessment logic | Low |

**Total New Files:** 24

---

### Files to Modify

#### Database Schema Extensions (1 file)

| File | Change Type | Description | Risk |
|------|-------------|-------------|------|
| `supabase/migrations/20260120310000_conversation_rehearsal_schema.sql` | Extend | Add `source_feature` and `source_id` to `custom_scenarios` table | Low |

#### iOS Core (2 files)

| File | Change Type | Description | Risk |
|------|-------------|-------------|------|
| `apps/ios/MindFriendApp/App/DependencyContainer.swift` | Modify | Add `BoundaryPlannerService` lazy property | Low |
| `apps/ios/MindFriendApp/Resources/Localizable.xcstrings` | Extend | Add 75 LocalizedStringKey entries | Low |

#### iOS Conversation Rehearsal Integration (2 files)

| File | Change Type | Description | Risk |
|------|-------------|-------------|------|
| `apps/ios/MindFriendApp/Core/RehearsalModels.swift` | Extend | Add `sourceFeature` and `sourceId` to `CustomScenario` | Low |
| `apps/ios/MindFriendApp/Features/Rehearsal/ConversationRehearsalView.swift` | Modify | Accept custom scenarios from boundary planner | Medium |

**Total Modified Files:** 5

---

### Files to Delete

None (this is a greenfield feature with no deprecations).

---

## Component Design

### Architecture Overview (ASCII Diagram)

```
┌─────────────────────────────────────────────────────────────────┐
│                         iOS App Layer                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    │
│  │ Assessment     │→ │ Matrix         │→ │ Boundary       │    │
│  │ View (4 steps) │  │ View (display) │  │ Definition     │    │
│  └────────────────┘  └────────────────┘  └────────────────┘    │
│           │                                       │             │
│           ├───────────────────────────────────────┘             │
│           ↓                                                     │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    │
│  │ Script         │→ │ Practice       │→ │ Follow-Up      │    │
│  │ Generator      │  │ View (CRS)     │  │ View           │    │
│  └────────────────┘  └────────────────┘  └────────────────┘    │
│           │                   │                   │             │
│           └─────────┬─────────┴─────────┬─────────┘             │
│                     ↓                   ↓                       │
│            ┌─────────────────┐  ┌─────────────────┐             │
│            │ BoundaryPlanner │  │ Rehearsal       │             │
│            │ Service         │  │ Service         │             │
│            └─────────────────┘  └─────────────────┘             │
│                     │                   │                       │
└─────────────────────┼───────────────────┼───────────────────────┘
                      │                   │
                      ↓                   ↓
┌─────────────────────────────────────────────────────────────────┐
│                     Edge Functions Layer                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ create-      │  │ generate-    │  │ generate-    │          │
│  │ assessment   │→ │ boundary     │→ │ scripts      │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│         │                   │                   │               │
│         └─────────┬─────────┴─────────┬─────────┘               │
│                   ↓                   ↓                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ save-        │  │ schedule-    │  │ record-      │          │
│  │ boundary     │  │ followup     │  │ outcome      │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│         │                   │                   │               │
│         └─────────┬─────────┴─────────┬─────────┘               │
│                   ↓                   ↓                         │
│            ┌──────────────┐   ┌──────────────┐                  │
│            │ list-        │   │ get-         │                  │
│            │ boundaries   │   │ templates    │                  │
│            └──────────────┘   └──────────────┘                  │
│                   │                   │                         │
└───────────────────┼───────────────────┼─────────────────────────┘
                    │                   │
                    ↓                   ↓
┌─────────────────────────────────────────────────────────────────┐
│                      Database Layer                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ needs_           │  │ defined_         │                    │
│  │ assessments      │→ │ boundaries       │                    │
│  └──────────────────┘  └──────────────────┘                    │
│           │                     │                               │
│           ↓                     ↓                               │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ boundary_        │  │ boundary_        │                    │
│  │ follow_ups       │  │ script_templates │                    │
│  └──────────────────┘  └──────────────────┘                    │
│                                 │                               │
│                    ┌────────────┴────────────┐                  │
│                    ↓                         ↓                  │
│         ┌──────────────────┐      ┌──────────────────┐         │
│         │ custom_scenarios │      │ rehearsal_       │         │
│         │ (extended)       │      │ sessions         │         │
│         └──────────────────┘      └──────────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### Component: NeedsAssessment

**Purpose:** Guided 4-step questionnaire to identify user's unmet needs  
**Location:** `apps/ios/MindFriendApp/Features/Boundaries/NeedsAssessmentView.swift`  
**Dependencies:**
- `BoundaryPlannerService` for API calls
- `BoundaryModels.swift` for data structures

**Interface:**
- Input: `AssessmentType` (work, relationships, family, friends)
- Output: `NeedsAssessment` with `topNeeds` array
- Errors: Network errors, validation errors

**State Management:**
- Local `@State` for current step and form inputs
- Service call on step 4 completion
- Navigation to PriorityMatrixView on success

---

### Component: BoundaryPlannerService

**Purpose:** Network service layer wrapping all boundary Edge Functions  
**Location:** `apps/ios/MindFriendApp/Core/Services/BoundaryPlannerService.swift`  
**Dependencies:**
- `SupabaseClient` for authenticated requests
- `BoundaryModels.swift` for request/response types

**Interface:**

```swift
class BoundaryPlannerService {
    func createAssessment(_ request: CreateAssessmentRequest) async throws -> AssessmentResponse
    func generateBoundary(_ request: GenerateBoundaryRequest) async throws -> BoundaryResponse
    func generateScripts(_ request: GenerateScriptsRequest) async throws -> ScriptsResponse
    func saveBoundary(id: UUID, status: BoundaryStatus) async throws -> Boundary
    func listBoundaries(status: String?, limit: Int, offset: Int) async throws -> BoundariesListResponse
    func scheduleFollowUp(boundaryId: UUID, checkInAt: Date) async throws -> FollowUpResponse
    func recordOutcome(_ request: RecordOutcomeRequest) async throws -> OutcomeResponse
    func getAssessment(id: UUID) async throws -> NeedsAssessment
    func getTemplates(boundaryType: String, relationshipType: String, locale: String) async throws -> [ScriptTemplate]
}
```

**Error Handling:**
- Throws `BoundaryPlannerError` enum with specific cases
- Network errors wrapped with user-friendly messages
- Validation errors surfaced to UI

---

### Component: Script Template Matching

**Purpose:** Match boundary parameters to localized script templates  
**Location:** `supabase/functions/generate-scripts/index.ts`  
**Dependencies:**
- `boundary_script_templates` table
- User's locale setting from `profiles` table

**Algorithm:**

```typescript
async function findTemplate(
  boundaryType: string,
  relationshipType: string,
  variation: string,
  locale: string,
  isPremium: boolean
): Promise<Template | null> {
  // 1. Query for exact match
  let template = await supabase
    .from('boundary_script_templates')
    .select('*')
    .eq('boundary_type', boundaryType)
    .eq('relationship_type', relationshipType)
    .eq('template_variation', variation)
    .eq('locale', locale)
    .lte('is_premium', isPremium)  // Free users can't access premium
    .single();

  if (template) return template;

  // 2. Fallback to 'other' relationship type
  template = await supabase
    .from('boundary_script_templates')
    .select('*')
    .eq('boundary_type', boundaryType)
    .eq('relationship_type', 'other')
    .eq('template_variation', variation)
    .eq('locale', locale)
    .lte('is_premium', isPremium)
    .single();

  if (template) return template;

  // 3. Fallback to 'en' locale
  template = await supabase
    .from('boundary_script_templates')
    .select('*')
    .eq('boundary_type', boundaryType)
    .eq('relationship_type', relationshipType)
    .eq('template_variation', variation)
    .eq('locale', 'en')
    .lte('is_premium', isPremium)
    .single();

  return template || null;
}
```

**Placeholder Replacement:**

```typescript
function replaceTemplatePlaceholders(
  templateText: string,
  boundary: Boundary,
  userSettings: UserSettings
): string {
  return templateText
    .replace('[boundary]', boundary.statementText)
    .replace('[why_matters]', boundary.whyMatters || 'maintain healthy boundaries')
    .replace('[stakeholder]', boundary.stakeholder || 'the other person')
    .replace('[contact_method]', userSettings.preferredContact || 'text message');
}
```

---

### Component: Boundary State Machine

**Purpose:** Validate status transitions for boundaries  
**Location:** `supabase/functions/save-boundary/index.ts`  
**Dependencies:** None (pure business logic)

**Validation Function:**

```typescript
interface ValidationResult {
  allowed: boolean;
  reason?: string;
  allowedStates?: string[];
}

function validateTransition(
  currentStatus: string,
  newStatus: string,
  boundary: Boundary
): ValidationResult {
  // Allow archiving from any state
  if (newStatus === 'archived') {
    return { allowed: true };
  }

  // Draft → Ready: requires scripts
  if (currentStatus === 'draft' && newStatus === 'ready') {
    if (!boundary.scripts || boundary.scripts.length === 0) {
      return {
        allowed: false,
        reason: 'Scripts must be generated before marking as ready',
        allowedStates: ['draft', 'archived']
      };
    }
    return { allowed: true };
  }

  // Ready → Practiced: requires practice_count >= 3
  if (currentStatus === 'ready' && newStatus === 'practiced') {
    if (boundary.practiceCount < 3) {
      return {
        allowed: false,
        reason: 'Complete at least 3 practice sessions before marking as practiced',
        allowedStates: ['ready', 'archived']
      };
    }
    return { allowed: true };
  }

  // Practiced → Set: always allowed
  if (currentStatus === 'practiced' && newStatus === 'set') {
    return { allowed: true };
  }

  // Set → Adjusted: always allowed
  if (currentStatus === 'set' && newStatus === 'adjusted') {
    return { allowed: true };
  }

  // Adjusted → Set: always allowed
  if (currentStatus === 'adjusted' && newStatus === 'set') {
    return { allowed: true };
  }

  // All other transitions invalid
  return {
    allowed: false,
    reason: `Cannot transition from ${currentStatus} to ${newStatus}`,
    allowedStates: getAllowedStates(currentStatus, boundary)
  };
}
```

---

### Component: Conversation Rehearsal Integration

**Purpose:** Enable practicing boundary scripts via Conversation Rehearsal Studio  
**Location:** `apps/ios/MindFriendApp/Features/Boundaries/BoundaryPracticeView.swift`  
**Dependencies:**
- `ConversationRehearsalView` (existing)
- `CustomScenario` model (extended)
- Database trigger for practice count synchronization

**Flow:**

```swift
struct BoundaryPracticeView: View {
    let boundary: DefinedBoundary
    let script: BoundaryScript
    @State private var showRehearsalView = false
    @EnvironmentObject var dependencies: DependencyContainer

    var body: some View {
        VStack {
            // Display script
            ScriptCard(script: script)

            Button("Practice This Script") {
                showRehearsalView = true
            }
        }
        .sheet(isPresented: $showRehearsalView) {
            ConversationRehearsalView(
                customScenario: createCustomScenario()
            )
        }
    }

    private func createCustomScenario() -> CustomScenario {
        CustomScenario(
            id: UUID(),
            userId: dependencies.supabaseAuthService.currentUser!.id,
            title: "Practice: \(boundary.boundaryType.rawValue.capitalized)",
            otherPartyRole: boundary.stakeholder ?? "The other person",
            situationSummary: boundary.statementText,
            keyPoints: [script.text],
            desiredOutcome: boundary.expectedImpact ?? "Set a clear boundary",
            situationType: .boundary,
            contextDetails: [
                "source_feature": "boundary_planner",
                "source_id": boundary.id.uuidString
            ],
            isPublic: false,
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: nil,
            archivedAt: nil
        )
    }
}
```

**Database Synchronization:**

Practice count is auto-incremented via database trigger when a rehearsal session is created with `source_feature = 'boundary_planner'`:

```sql
-- Trigger function (already defined in spec)
CREATE OR REPLACE FUNCTION increment_boundary_practice_count()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.source_feature = 'boundary_planner' THEN
        UPDATE defined_boundaries
        SET practice_count = practice_count + 1,
            updated_at = NOW()
        WHERE id = NEW.source_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on custom_scenarios INSERT
CREATE TRIGGER sync_boundary_practice_count
AFTER INSERT ON custom_scenarios
FOR EACH ROW
WHEN (NEW.source_feature = 'boundary_planner')
EXECUTE FUNCTION increment_boundary_practice_count();
```

---

## Data Flow

### End-to-End Flow: Creating a Boundary

```
User taps "Create Boundary"
         ↓
┌────────────────────┐
│ Step 1: Assessment │
│ (4-step form)      │
└────────────────────┘
         ↓
POST /create-assessment
  - Calculates top_needs using gap_score matrix
  - Suggests recommended boundaries
  - Returns assessmentId + topNeeds
         ↓
┌────────────────────┐
│ Step 2: Matrix     │
│ (visual display)   │
└────────────────────┘
         ↓
User taps "Define Boundary"
         ↓
┌────────────────────┐
│ Step 3: Definition │
│ (statement form)   │
└────────────────────┘
         ↓
POST /generate-boundary
  - Validates statement length (10-500 chars)
  - Checks tier limit (3 for free)
  - Inserts into defined_boundaries
  - Returns boundaryId
         ↓
┌────────────────────┐
│ Step 4: Scripts    │
│ (template select)  │
└────────────────────┘
         ↓
POST /generate-scripts
  - Queries boundary_script_templates
  - Replaces placeholders
  - Updates boundary.scripts JSONB
  - Returns 3-4 script variations
         ↓
User selects script
         ↓
┌────────────────────┐
│ Step 5: Practice   │
│ (Rehearsal Studio) │
└────────────────────┘
         ↓
INSERT into custom_scenarios (source_feature='boundary_planner')
  - Trigger increments practice_count
  - Rehearsal session created
  - AI simulates stakeholder
         ↓
POST /save-boundary (status='practiced')
  - Validates practice_count >= 3
  - Updates status to 'practiced'
         ↓
User marks as "Set"
         ↓
POST /save-boundary (status='set')
  - Updates status to 'set'
         ↓
POST /schedule-followup
  - Inserts into boundary_follow_ups
  - Schedules local notification (iOS)
         ↓
24 hours later...
         ↓
POST /record-outcome
  - Updates follow-up with outcome
  - Suggests adjustments if challenged
```

---

## Integration Points

### 1. Conversation Rehearsal Studio

**Tables Modified:**
- `custom_scenarios` (add `source_feature`, `source_id` columns)

**Trigger Added:**
```sql
CREATE TRIGGER sync_boundary_practice_count
AFTER INSERT ON custom_scenarios
FOR EACH ROW
WHEN (NEW.source_feature = 'boundary_planner')
EXECUTE FUNCTION increment_boundary_practice_count();
```

**iOS Integration:**
- `BoundaryPracticeView` creates `CustomScenario` objects
- Navigation to `ConversationRehearsalView` with custom scenario
- Practice count auto-synced via database trigger

**Risk:** Medium (depends on Conversation Rehearsal being fully functional)  
**Mitigation:** Feature-flag practice integration; allow manual practice count increment as fallback

---

### 2. Localization System

**Files Modified:**
- `apps/ios/MindFriendApp/Resources/Localizable.xcstrings`

**Additions:**
- 75 new LocalizedStringKey entries (see spec Section 5.1)
- Translations for Spanish and Portuguese
- Total keys in file: ~75 + existing keys

**Workflow:**
1. Add English keys with descriptive comments
2. Generate translation strings via Xcode
3. Send to translation service or use AI translation
4. Import translated `.xliff` files

**Risk:** Low (additive change, no breaking changes)  
**Mitigation:** Use Xcode's built-in string validation

---

### 3. Subscription/Entitlements

**Tier Limit Enforcement:**
- Free tier: 3 boundaries max
- Premium tier: Unlimited boundaries

**Implementation:**

```typescript
// In generate-boundary/index.ts
async function checkTierLimit(userId: string, supabase: SupabaseClient): Promise<boolean> {
  // Check user's entitlements
  const { data: profile } = await supabase
    .from('profiles')
    .select('entitlements')
    .eq('id', userId)
    .single();

  const isPremium = profile?.entitlements?.tier === 'premium';
  if (isPremium) return true;  // No limit

  // Count active boundaries
  const { count } = await supabase
    .from('defined_boundaries')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', userId)
    .neq('status', 'archived');

  return count < 3;
}
```

**Error Response (402):**
```json
{
  "error": "Free tier limit reached",
  "message": "You've reached the free tier limit of 3 boundaries. Upgrade to Premium for unlimited boundaries.",
  "upgradeRequired": true
}
```

**iOS Handling:**
- Show paywall sheet on 402 error
- Display upgrade CTA in BoundariesListView when at limit

**Risk:** Low (existing entitlements system is robust)

---

### 4. Local Notifications

**Use Case:** Remind user to check in on boundary after 24 hours

**Implementation:**

```swift
// In BoundaryPlannerService
func scheduleFollowUpNotification(followUpId: UUID, checkInAt: Date, boundaryText: String) {
    let content = UNMutableNotificationContent()
    content.title = NSLocalizedString("followup.notification_title", comment: "Boundary Check-In")
    content.body = String(format: NSLocalizedString("followup.notification_body", comment: ""), boundaryText)
    content.sound = .default
    content.userInfo = ["followUpId": followUpId.uuidString, "type": "boundary_followup"]

    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: checkInAt)
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

    let request = UNNotificationRequest(identifier: followUpId.uuidString, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}
```

**Localization Keys (add to spec Section 5.1):**
- `followup.notification_title` = "Boundary Check-In"
- `followup.notification_body` = "How did your boundary go? Tap to record your experience."

**Risk:** Low (standard iOS notification API)

---

## Implementation Sequence

### Phase 0: Foundation (No dependencies)

**Estimated Time:** 2-3 hours

**Tasks:**

- [ ] Create `apps/ios/MindFriendApp/Core/BoundaryModels.swift`
  - Define all Swift models matching database schema
  - Add `Codable`, `Identifiable`, `Equatable` conformance
  - Add custom `CodingKeys` for snake_case ↔ camelCase mapping

- [ ] Create `supabase/migrations/20260120270000_boundary_planner_schema.sql`
  - Copy schema definition from formal spec
  - Add tables, indexes, RLS policies, triggers
  - Test idempotency with `IF NOT EXISTS` checks

- [ ] Create `supabase/functions/_shared/boundary-validation.ts`
  - State machine validation logic
  - Placeholder replacement utility
  - Top needs calculation algorithm

**Verification:**
- [ ] Migration applies without errors: `supabase db push`
- [ ] RLS policies prevent cross-user access
- [ ] Swift models compile without warnings

---

### Phase 1: Backend Core (Depends on Phase 0)

**Estimated Time:** 6-8 hours

**Tasks:**

- [ ] Create Edge Function: `create-assessment`
  - Parse request body
  - Validate assessment_type
  - Calculate top_needs using gap_score matrix
  - Generate recommended boundaries
  - Insert into `needs_assessments` table
  - Return assessmentId + topNeeds + recommendations

- [ ] Create Edge Function: `generate-boundary`
  - Validate statement length (10-500 chars)
  - Check tier limit (call `checkTierLimit()`)
  - Insert into `defined_boundaries` with status='draft'
  - Calculate expected_impact (placeholder for now)
  - Return boundaryId

- [ ] Create Edge Function: `generate-scripts`
  - Fetch boundary from database
  - Query `boundary_script_templates` with fallbacks
  - Replace placeholders using utility function
  - Update boundary.scripts JSONB
  - Return scripts array with metadata

- [ ] Create Edge Function: `save-boundary`
  - Validate status transition using state machine
  - Update boundary status and updated_at
  - Return updated boundary

- [ ] Create Edge Function: `list-boundaries`
  - Parse query params (status, limit, offset)
  - Query `defined_boundaries` with filters
  - Check for pending follow-ups (LEFT JOIN)
  - Return paginated results

- [ ] Create Edge Function: `schedule-followup`
  - Validate checkInAt is in future
  - Insert into `boundary_follow_ups`
  - Return followUpId

- [ ] Create Edge Function: `record-outcome`
  - Update follow-up with outcome + completed_at
  - Generate encouragement message based on outcome
  - Suggest boundary adjustment if outcome='challenged' or 'ignored'
  - Return encouragement + suggestions

- [ ] Create Edge Function: `get-assessment`
  - Fetch assessment by ID
  - Verify user ownership via RLS
  - Return assessment object

- [ ] Create Edge Function: `get-templates`
  - Query `boundary_script_templates`
  - Filter by boundaryType, relationshipType, locale
  - Filter by is_premium based on user tier
  - Return templates array

**Verification:**
- [ ] All endpoints respond with correct status codes
- [ ] Authentication rejects missing/invalid tokens
- [ ] RLS prevents unauthorized access
- [ ] State machine rejects invalid transitions
- [ ] Top needs calculation matches spec examples

---

### Phase 2: iOS Service Layer (Depends on Phase 1)

**Estimated Time:** 3-4 hours

**Tasks:**

- [ ] Create `apps/ios/MindFriendApp/Core/Services/BoundaryPlannerService.swift`
  - Implement all 9 API wrapper methods
  - Handle authentication via `supabaseClient.functions.invoke()`
  - Map JSON responses to Swift models
  - Throw typed errors for specific failure cases

- [ ] Modify `apps/ios/MindFriendApp/App/DependencyContainer.swift`
  - Add lazy `boundaryPlannerService` property
  - Inject `supabaseClient` dependency

- [ ] Create `apps/ios/MindFriendAppTests/BoundaryPlannerServiceTests.swift`
  - Mock network responses
  - Test request encoding
  - Test response decoding
  - Test error handling (401, 402, 404, 500)

**Verification:**
- [ ] Service compiles without errors
- [ ] Tests pass with mocked responses
- [ ] Dependency container provides service instance

---

### Phase 3: iOS Views (Depends on Phase 2)

**Estimated Time:** 8-10 hours

**Tasks:**

- [ ] Create `NeedsAssessmentView.swift`
  - 4-step wizard UI with progress indicator
  - Step 1: Checkboxes for drain triggers
  - Step 2: Segmented controls for importance ratings
  - Step 3: Segmented controls for currently met
  - Step 4: Confirmation + submit button
  - Call `boundaryPlannerService.createAssessment()`
  - Navigate to PriorityMatrixView on success

- [ ] Create `PriorityMatrixView.swift`
  - Display 2x2 matrix (importance × currently met)
  - Plot user's needs as labeled dots
  - Highlight top 3 needs
  - "Continue" button to BoundaryDefinitionView

- [ ] Create `BoundaryDefinitionView.swift`
  - Text field for boundary statement (10-500 chars)
  - Text field for "why it matters" (optional)
  - Text field for stakeholder (optional)
  - Picker for boundary type
  - Call `boundaryPlannerService.generateBoundary()`
  - Handle 402 error → show paywall
  - Navigate to ScriptGeneratorView on success

- [ ] Create `ScriptGeneratorView.swift`
  - Display selected boundary summary
  - Picker for relationship type
  - Checkboxes for script variations (direct, gentle, assertive, collaborative)
  - Call `boundaryPlannerService.generateScripts()`
  - Display generated scripts in cards
  - Copy, practice, edit actions per script

- [ ] Create `BoundaryPracticeView.swift`
  - Display selected script
  - "Practice" button → show ConversationRehearsalView sheet
  - Pass custom scenario with source_feature='boundary_planner'
  - On dismiss, refresh boundary to check practice_count

- [ ] Create `BoundaryFollowUpView.swift`
  - Display boundary text and set date
  - Radio buttons for outcome (successful, partial, challenged, ignored)
  - Text field for notes (optional)
  - Text field for next action (optional)
  - Call `boundaryPlannerService.recordOutcome()`
  - Display encouragement message from API

- [ ] Create `BoundariesListView.swift`
  - Fetch boundaries via `boundaryPlannerService.listBoundaries()`
  - Filter pills: All, Active, Practiced, Set
  - List items: boundary text, status badge, practice count
  - Tap → navigate to detail view
  - Empty state with "Create Boundary" CTA

**Verification:**
- [ ] All views compile without errors
- [ ] Navigation flow works end-to-end
- [ ] Forms validate input correctly
- [ ] Network errors show user-friendly alerts
- [ ] VoiceOver labels present on all interactive elements

---

### Phase 4: Integration & Localization (Depends on Phase 3)

**Estimated Time:** 4-5 hours

**Tasks:**

- [ ] Extend `custom_scenarios` table
  - Add migration to add `source_feature` and `source_id` columns
  - Add trigger `sync_boundary_practice_count`
  - Test trigger increments practice_count correctly

- [ ] Modify `RehearsalModels.swift`
  - Add optional `sourceFeature` and `sourceId` to `CustomScenario`
  - Update CodingKeys

- [ ] Modify `ConversationRehearsalView`
  - Accept custom scenarios from external features
  - Record source_feature and source_id when creating session

- [ ] Add 75 localization keys to `Localizable.xcstrings`
  - Copy keys from spec Section 5.1
  - Add descriptive comments for translators
  - Generate Spanish and Portuguese translations
  - Test locale switching

- [ ] Seed script templates
  - Create `supabase/migrations/20260120270001_seed_boundary_templates.sql`
  - Insert 135 template records (45 per locale)
  - Verify templates match spec examples

- [ ] Add notification scheduling
  - Implement `scheduleFollowUpNotification()` in BoundaryPlannerService
  - Request notification permissions if not granted
  - Add deep link handling for `boundary_followup` notifications

**Verification:**
- [ ] Practice count increments after rehearsal session
- [ ] Localization switches correctly between en/es/pt
- [ ] Script templates return correct locale
- [ ] Notifications fire at scheduled time
- [ ] Deep links navigate to BoundaryFollowUpView

---

### Phase 5: Testing & Polish (Depends on Phase 4)

**Estimated Time:** 3-4 hours

**Tasks:**

- [ ] Write unit tests for state machine
  - Test all valid transitions
  - Test all invalid transitions
  - Test edge cases (missing scripts, low practice count)

- [ ] Write unit tests for top_needs calculation
  - Test gap_score matrix
  - Test tie-breaking (alphabetical)
  - Test minimum threshold (gap_score >= 6)

- [ ] Write integration tests for end-to-end flow
  - Create assessment → generate boundary → generate scripts → practice → follow-up
  - Test tier limit enforcement
  - Test RLS policy enforcement

- [ ] Manual UAT testing
  - Complete full flow in simulator
  - Test Spanish and Portuguese locales
  - Test free tier limit (create 3 boundaries, verify 4th blocked)
  - Test premium tier (verify unlimited)
  - Test offline behavior (show error, cache retry)

- [ ] Accessibility audit
  - VoiceOver labels on all buttons, fields, cards
  - Dynamic Type support (test largest accessibility sizes)
  - Minimum touch targets (44×44 pt)
  - Color contrast (WCAG AA)

- [ ] Performance testing
  - Measure Edge Function latency (target < 300ms for all endpoints)
  - Test with 50+ boundaries (list view performance)
  - Test with 10+ script variations (scroll performance)

**Verification:**
- [ ] All unit tests pass
- [ ] Integration tests pass
- [ ] UAT checklist completed
- [ ] Accessibility score 100% in Xcode Accessibility Inspector
- [ ] Performance targets met

---

## Test Strategy

### Unit Tests

#### iOS Unit Tests (Target: 80% coverage)

**File:** `apps/ios/MindFriendAppTests/BoundaryModelsTests.swift`

| Test Case | Coverage |
|-----------|----------|
| `testNeedsAssessmentCodable` | Codable conformance for all models |
| `testBoundaryStatusValidation` | Enum rawValue mapping |
| `testScriptVariationCaseIterable` | All cases present |

**File:** `apps/ios/MindFriendAppTests/BoundaryPlannerServiceTests.swift`

| Test Case | Coverage |
|-----------|----------|
| `testCreateAssessmentSuccess` | Request encoding, response decoding |
| `testGenerateBoundaryTierLimitError` | 402 error handling |
| `testGenerateScriptsLocaleHandling` | Locale parameter passing |
| `testSaveBoundaryInvalidTransition` | 400 error parsing |

#### Edge Function Unit Tests (Target: 90% coverage)

**File:** `supabase/functions/create-assessment/test.ts`

```typescript
Deno.test("calculates top needs correctly", () => {
  const responses = {
    step2_importance_ratings: {
      personal_time: "high",
      emotional_safety: "high",
      respect: "medium"
    },
    step3_currently_met: {
      personal_time: "no",
      emotional_safety: "sometimes",
      respect: "yes"
    }
  };
  
  const topNeeds = calculateTopNeeds(responses);
  
  assertEquals(topNeeds.length, 3);
  assertEquals(topNeeds[0], "personal_time");  // gap_score=9
  assertEquals(topNeeds[1], "emotional_safety");  // gap_score=7
  assertEquals(topNeeds[2], "respect");  // gap_score=2
});
```

**File:** `supabase/functions/save-boundary/test.ts`

```typescript
Deno.test("rejects invalid state transition", () => {
  const result = validateTransition("draft", "set", {
    scripts: null,
    practiceCount: 0
  });
  
  assertEquals(result.allowed, false);
  assertEquals(result.reason, "Scripts must be generated before marking as ready");
});
```

---

### Integration Tests

#### End-to-End Flow Test

**File:** `apps/ios/MindFriendAppTests/BoundaryPlannerIntegrationTests.swift`

```swift
func testFullBoundaryCreationFlow() async throws {
    // 1. Create assessment
    let assessment = try await service.createAssessment(
        CreateAssessmentRequest(
            assessmentType: "work",
            responses: mockResponses
        )
    )
    XCTAssertEqual(assessment.topNeeds.count, 3)
    
    // 2. Generate boundary
    let boundary = try await service.generateBoundary(
        GenerateBoundaryRequest(
            assessmentId: assessment.id,
            boundaryType: "time",
            statement: "I need to disconnect after 6pm",
            whyMatters: "To spend time with family",
            stakeholder: "My manager"
        )
    )
    XCTAssertEqual(boundary.status, .draft)
    
    // 3. Generate scripts
    let scripts = try await service.generateScripts(
        GenerateScriptsRequest(
            boundaryId: boundary.id,
            relationshipType: "manager",
            variations: ["direct", "gentle"]
        )
    )
    XCTAssertEqual(scripts.count, 2)
    
    // 4. Save as ready
    let updated = try await service.saveBoundary(id: boundary.id, status: .ready)
    XCTAssertEqual(updated.status, .ready)
}
```

#### Conversation Rehearsal Integration Test

**File:** `apps/ios/MindFriendAppTests/BoundaryRehearsalIntegrationTests.swift`

```swift
func testPracticeCountIncrement() async throws {
    // 1. Create boundary with scripts
    let boundary = try await createTestBoundary()
    
    // 2. Create custom scenario
    let scenario = CustomScenario(
        id: UUID(),
        userId: testUserId,
        title: "Practice: Time Boundary",
        otherPartyRole: "Manager",
        situationSummary: boundary.statementText,
        keyPoints: [boundary.scripts![0].text],
        desiredOutcome: "Set clear work hours",
        situationType: .boundary,
        contextDetails: [
            "source_feature": "boundary_planner",
            "source_id": boundary.id.uuidString
        ],
        isPublic: false,
        createdAt: Date(),
        updatedAt: Date(),
        deletedAt: nil,
        archivedAt: nil
    )
    
    // 3. Insert scenario (trigger should fire)
    try await supabase.from("custom_scenarios").insert(scenario).execute()
    
    // 4. Verify practice count incremented
    let updatedBoundary = try await service.getBoundary(id: boundary.id)
    XCTAssertEqual(updatedBoundary.practiceCount, 1)
}
```

---

### Edge Cases & Error Handling

| Scenario | Expected Behavior | Test Location |
|----------|-------------------|---------------|
| Assessment abandoned mid-way | Save progress in responses JSONB | Manual UAT |
| Script generation fails | Fallback to manual template selection | Integration test |
| Boundary statement too short (< 10 chars) | 400 error with validation message | Unit test |
| User reports violation (outcome='ignored') | Suggest reflection exercise | Edge function test |
| Follow-up missed | Gentle reminder notification | Manual UAT |
| Free tier limit (3 boundaries) | 402 error with paywall | Integration test |
| Network error during save | Show retry button | Manual UAT |
| Template not found for locale | Fallback to 'en' templates | Edge function test |
| User deletes boundary with follow-up | Cascade delete follow-up | Database test |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Conversation Rehearsal integration breaks** | Medium | High | Feature-flag practice integration; allow manual practice count increment as fallback |
| **Script template quality issues** | Low | Medium | Seed templates reviewed by content team before launch |
| **State machine complexity causes bugs** | Low | High | Comprehensive unit tests for all transitions; log state changes for debugging |
| **Tier limit bypass via client manipulation** | Low | Critical | Enforce limit server-side in Edge Function; RLS prevents direct DB access |
| **Localization missing keys** | Medium | Low | Xcode validates string references at compile time; fallback to English |
| **Database trigger fails silently** | Low | Medium | Add logging to trigger function; monitor practice_count discrepancies |
| **Follow-up notifications not delivered** | Medium | Low | Use reliable UNNotificationRequest API; test on real device |
| **Performance degradation with many boundaries** | Low | Medium | Pagination with limit=20; indexes on user_id + created_at |
| **RLS policy misconfiguration** | Low | Critical | Test with multiple users; verify cross-user access blocked |

---

## Dependencies

### External

| Dependency | Purpose | Version | Security |
|------------|---------|---------|----------|
| Supabase Swift SDK | Database queries, Edge Function calls | Latest | Audit clean |
| Supabase Edge Runtime | Deno-based serverless functions | Latest | Audit clean |
| UNUserNotifications | Local notifications | iOS 17+ | Standard framework |

### Internal

| Module | Usage | Changes Needed |
|--------|-------|----------------|
| `SupabaseClient` | All network requests | None |
| `DependencyContainer` | Service injection | Add `boundaryPlannerService` property |
| `Localizable.xcstrings` | UI strings | Add 75 new keys |
| `RehearsalModels.swift` | Custom scenario creation | Add `sourceFeature` and `sourceId` |
| `custom_scenarios` table | Practice tracking | Add 2 columns + trigger |
| `ConversationRehearsalView` | Practice integration | Accept external scenarios |

---

## Rollback Plan

### Scenario: Critical bug discovered post-deploy

**Option 1: Feature Flag Disable (Fastest)**

1. Add feature flag check in iOS:
   ```swift
   @AppStorage("boundaryPlannerEnabled") var boundaryPlannerEnabled = true
   
   if !boundaryPlannerEnabled {
       // Hide Boundary Planner tab/entry points
   }
   ```

2. Deploy iOS update with flag disabled by default
3. Users on old version see degraded experience (safe mode)

**Option 2: Database Rollback**

1. Archive all boundary data:
   ```sql
   CREATE TABLE boundary_planner_backup AS 
   SELECT * FROM needs_assessments;
   
   CREATE TABLE boundaries_backup AS 
   SELECT * FROM defined_boundaries;
   ```

2. Drop tables and functions:
   ```sql
   DROP TABLE IF EXISTS boundary_follow_ups CASCADE;
   DROP TABLE IF EXISTS defined_boundaries CASCADE;
   DROP TABLE IF EXISTS needs_assessments CASCADE;
   DROP TABLE IF EXISTS boundary_script_templates CASCADE;
   ```

3. Remove Edge Functions:
   ```bash
   supabase functions delete create-assessment
   supabase functions delete generate-boundary
   # ... (all 9 functions)
   ```

**Option 3: Edge Function Hotfix**

If issue is isolated to specific Edge Function:

1. Identify failing function via logs
2. Deploy patched version:
   ```bash
   supabase functions deploy <function-name>
   ```
3. Monitor error rates

**Recovery Time Objective (RTO):** 30 minutes  
**Recovery Point Objective (RPO):** 0 (no data loss, all writes atomic)

---

## Questions for Clarification

Before proceeding, confirm:

1. **AI Script Generation:** The spec mentions "AI-generated scripts" but templates are static. Should we add an optional AI enhancement layer for custom script generation? Or is template-based sufficient for MVP?

2. **Premium Template Access:** Should free users see premium templates as "locked" with upgrade CTA, or should they be completely hidden?

3. **Follow-Up Reminders:** Should we send a second reminder if user ignores the first follow-up notification? Or single notification only?

4. **Boundary Sharing:** The spec mentions `is_public` on custom scenarios. Should boundaries also support sharing (e.g., to circles)? Or private-only for MVP?

5. **Analytics Events:** What analytics events should we track? (e.g., `boundary_created`, `script_generated`, `practice_completed`, `followup_recorded`)

6. **Conversation Rehearsal Dependency:** If Conversation Rehearsal is not yet deployed, should we:
   - Block Boundary Planner launch until CRS is ready?
   - Launch without practice feature?
   - Mock practice feature with placeholder UI?

---

## Verdict

**READY FOR IMPLEMENTATION**

This plan provides a clear path to implement Boundary & Needs Planner with:

- [x] Minimal risk to existing functionality (greenfield feature, isolated tables)
- [x] Clear component boundaries (iOS ↔ Edge Functions ↔ Database)
- [x] Comprehensive test coverage (unit, integration, E2E)
- [x] Defined error handling (state machine, tier limits, network errors)
- [x] Rollback capability (feature flag, database backup, Edge Function versioning)
- [x] Integration strategy (Conversation Rehearsal, Localization, Entitlements)

**Next Steps:**

1. Answer clarification questions above
2. Review and approve this implementation plan
3. Execute Phase 0 (Foundation) to validate database schema
4. Proceed with sequential phase execution

**Estimated Timeline:** 22-30 hours (5-7 working days for single developer)

---

**END OF IMPLEMENTATION PLAN**
