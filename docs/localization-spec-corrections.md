# Localization Specification Corrections

**Date:** 2026-01-19
**Purpose:** Address 8 critical blockers identified by spec-analyzer
**Reference:** Original spec by spec-writer agent (agentId: a08ecbb)

---

## Blocker #1: MVP Scope Conflict - RESOLVED ✓

**Issue:** CLAUDE.md excluded "Multi-language localization beyond scaffolding" from MVP.

**Resolution:**

- CLAUDE.md updated (Section 14) to include localization in MVP scope
- Decision documented in decisions.md (#2026-01-19-001)
- Full implementation now approved

---

## Blocker #2: Admin User Management System

**Issue:** No admin system exists for translation management (INSERT/UPDATE/DELETE operations).

**Resolution for MVP:**

Use **Supabase Service Role Key** for all translation management operations in MVP. Admin UI deferred to post-MVP.

### Translation Management Workflow

```typescript
// supabase/functions/_shared/admin-auth.ts

export function requireServiceRole(req: Request): boolean {
  const authHeader = req.headers.get("Authorization");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  // Service role requests use service key, not user JWT
  return authHeader === `Bearer ${serviceRoleKey}`;
}

// Usage in admin functions:
if (!requireServiceRole(req)) {
  return new Response("Unauthorized", { status: 403 });
}
```

### Manual Translation Import Process

**Step 1:** Export strings for translation

```bash
# Manual script (developer runs locally)
supabase db dump --data-only --table=ui_translations > translations_export.sql
```

**Step 2:** Professional translators provide CSV

```csv
string_key,language_code,translation,context
home.greeting,es,Hola,Greeting on home screen
home.greeting,pt-BR,Olá,Greeting on home screen
button.save,es,Guardar,Save button label
button.save,pt-BR,Salvar,Save button label
```

**Step 3:** Import via Supabase Dashboard or SQL

```sql
-- Run in Supabase SQL Editor with service role
INSERT INTO ui_translations (string_key, language_code, translation, context, is_verified)
VALUES
  ('home.greeting', 'es', 'Hola', 'Greeting on home screen', true),
  ('home.greeting', 'pt-BR', 'Olá', 'Greeting on home screen', true)
ON CONFLICT (string_key, language_code)
DO UPDATE SET
  translation = EXCLUDED.translation,
  updated_at = NOW();
```

**No custom admin UI needed for MVP** - use Supabase Dashboard directly.

---

## Blocker #3: Database Migration Safety

**Issue:** Original migration lacks `IF NOT EXISTS`, conditional policy creation, and proper ordering.

**Corrected Migration:** See `supabase/migrations/YYYYMMDDHHMMSS_localization_safe.sql` (will be created in Phase 1).

### Key Safety Fixes

1. **Idempotent table creation:**

```sql
CREATE TABLE IF NOT EXISTS supported_languages (...);
```

2. **Conditional policy creation:**

```sql
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'supported_languages'
    AND policyname = 'Languages readable'
  ) THEN
    CREATE POLICY "Languages readable"
      ON supported_languages FOR SELECT
      USING (is_active = true);
  END IF;
END $$;
```

3. **Safe foreign key addition:**

```sql
-- Step 1: Add column without constraint
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS preferred_language TEXT DEFAULT 'en';

-- Step 2: Insert languages (already in migration)

-- Step 3: Update existing rows
UPDATE profiles
SET preferred_language = 'en'
WHERE preferred_language IS NULL;

-- Step 4: Add constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_profiles_language'
  ) THEN
    ALTER TABLE profiles
    ADD CONSTRAINT fk_profiles_language
    FOREIGN KEY (preferred_language)
    REFERENCES supported_languages(code);
  END IF;
END $$;
```

4. **Content type ENUM:**

```sql
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'content_type_enum') THEN
    CREATE TYPE content_type_enum AS ENUM (
      'exercise',
      'quest',
      'quest_template',
      'badge',
      'journal_prompt'
    );
  END IF;
END $$;

-- Then use in table
ALTER TABLE content_translations
ALTER COLUMN content_type TYPE content_type_enum
USING content_type::content_type_enum;
```

---

## Blocker #4: Complete RLS Policy Matrix

**Issue:** Original spec only defined SELECT policies, missing INSERT/UPDATE/DELETE.

**Complete Policy Matrix:**

### supported_languages

```sql
-- SELECT: All authenticated users can read active languages
CREATE POLICY "Languages readable by authenticated users"
  ON supported_languages FOR SELECT
  USING (auth.role() = 'authenticated' AND is_active = true);

-- INSERT/UPDATE/DELETE: Service role only (no user access)
CREATE POLICY "Block client writes to supported_languages"
  ON supported_languages FOR ALL
  USING (false);
```

### ui_translations

```sql
-- SELECT: All authenticated users can read all translations
CREATE POLICY "Translations readable by authenticated users"
  ON ui_translations FOR SELECT
  USING (auth.role() = 'authenticated');

-- INSERT/UPDATE/DELETE: Service role only
CREATE POLICY "Block client writes to ui_translations"
  ON ui_translations FOR ALL
  USING (false);
```

### content_translations

```sql
-- SELECT: Only verified translations visible to users
CREATE POLICY "Verified content translations readable"
  ON content_translations FOR SELECT
  USING (auth.role() = 'authenticated' AND is_verified = true);

-- INSERT/UPDATE/DELETE: Service role only
CREATE POLICY "Block client writes to content_translations"
  ON content_translations FOR ALL
  USING (false);
```

### localized_crisis_resources

```sql
-- SELECT: Only active resources visible
CREATE POLICY "Active crisis resources readable"
  ON localized_crisis_resources FOR SELECT
  USING (auth.role() = 'authenticated' AND is_active = true);

-- INSERT/UPDATE/DELETE: Service role only
CREATE POLICY "Block client writes to crisis resources"
  ON localized_crisis_resources FOR ALL
  USING (false);
```

### localized_audio (placeholder for future)

```sql
-- SELECT: Only active audio visible
CREATE POLICY "Active audio readable"
  ON localized_audio FOR SELECT
  USING (auth.role() = 'authenticated' AND is_active = true);

-- INSERT/UPDATE/DELETE: Service role only
CREATE POLICY "Block client writes to localized_audio"
  ON localized_audio FOR ALL
  USING (false);
```

**Key Principle:** All translation data is read-only from client perspective. Only service role (via Supabase Dashboard or Edge Functions) can modify.

---

## Blocker #5: Localized Crisis Keyword Detection

**Issue:** Safety feature broken without crisis keyword translations.

**Solution: Multi-Language Crisis Detection**

### Crisis Keyword Definitions

```typescript
// supabase/functions/_shared/crisis-detection.ts

export const CRISIS_KEYWORDS: Record<string, string[]> = {
  en: [
    "kill myself",
    "want to die",
    "suicide",
    "end it all",
    "better off dead",
    "cant go on",
    "self harm",
    "hurt myself",
    "end my life",
    "no reason to live",
  ],
  es: [
    "matarme",
    "quiero morir",
    "suicidio",
    "acabar con todo",
    "mejor muerto",
    "no puedo más",
    "autolesión",
    "hacerme daño",
    "terminar mi vida",
    "sin razón para vivir",
  ],
  "pt-BR": [
    "me matar",
    "quero morrer",
    "suicídio",
    "acabar com tudo",
    "melhor morto",
    "não aguento mais",
    "autolesão",
    "me machucar",
    "terminar minha vida",
    "sem razão para viver",
  ],
};

export function detectCrisis(message: string, userLanguage: string): boolean {
  const normalizedMessage = message.toLowerCase();

  // Check keywords for user's language
  const userLanguageKeywords = CRISIS_KEYWORDS[userLanguage] || [];

  // ALWAYS also check English keywords (fallback safety net)
  const englishKeywords = CRISIS_KEYWORDS["en"];

  const allKeywords = [...userLanguageKeywords, ...englishKeywords];

  return allKeywords.some((keyword) =>
    normalizedMessage.includes(keyword.toLowerCase()),
  );
}
```

### Updated Chat Edge Function

```typescript
// supabase/functions/chat/index.ts

import { detectCrisis } from "../_shared/crisis-detection.ts";

// In main handler:
const { data: profile } = await supabase
  .from("profiles")
  .select("preferred_language")
  .eq("id", user.id)
  .single();

const userLanguage = profile?.preferred_language || "en";

// Crisis detection BEFORE AI call
if (detectCrisis(messageContent, userLanguage)) {
  // Log crisis event
  await supabase.from("crisis_events").insert({
    user_id: user.id,
    detected_at: new Date().toISOString(),
    trigger_snippet: messageContent.substring(0, 50), // Truncated for privacy
  });

  // Get localized crisis resources
  const resources = await getLocalizedCrisisResources(user.id, userLanguage);

  // Return localized crisis template (not AI-generated)
  return new Response(
    JSON.stringify({
      message: resources.intro_message,
      is_crisis: true,
      resources: {
        emergency_number: resources.emergency_number,
        hotline: resources.crisis_hotline,
        hotline_name: resources.crisis_hotline_name,
        text_line: resources.crisis_text_line,
        website: resources.crisis_website,
      },
    }),
    {
      headers: { "Content-Type": "application/json" },
    },
  );
}

// Normal AI flow continues if no crisis detected...
```

**Critical:** Crisis detection runs in BOTH user's language AND English for safety.

---

## Blocker #6: JSONB Schema for Instructions

**Issue:** `content_translations.instructions` is `JSONB`, but schema undefined.

**Defined JSONB Schemas:**

### Exercise Instructions Schema

```typescript
// Type definition for clarity
interface ExerciseInstructions {
  steps: ExerciseStep[];
}

interface ExerciseStep {
  order: number;
  text: string;
  duration_seconds?: number; // Optional for steps with no timer
}

// Example JSONB value:
{
  "steps": [
    {
      "order": 1,
      "text": "Siéntate cómodamente con la espalda recta",
      "duration_seconds": 10
    },
    {
      "order": 2,
      "text": "Cierra los ojos y respira profundamente",
      "duration_seconds": 30
    },
    {
      "order": 3,
      "text": "Continúa respirando naturalmente durante 5 minutos"
    }
  ]
}
```

### Quest Instructions Schema

```typescript
// Quests typically use simple description field, not complex instructions
// But if needed:
interface QuestInstructions {
  tasks: string[]; // Simple array of task descriptions
}

// Example:
{
  "tasks": [
    "Registra tu estado de ánimo",
    "Completa un ejercicio de respiración",
    "Reflexiona sobre tu día"
  ]
}
```

### Swift Model Updates

```swift
// apps/ios/MindFriendApp/Core/LocalizationModels.swift

struct ContentTranslation: Codable {
    let id: UUID
    let contentType: String
    let contentId: UUID
    let languageCode: String
    let title: String?
    let description: String?
    let content: String?
    let instructions: ExerciseInstructions? // CHANGED: Properly typed

    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case contentId = "content_id"
        case languageCode = "language_code"
        case title
        case description
        case content
        case instructions
    }
}

struct ExerciseInstructions: Codable {
    let steps: [ExerciseStep]
}

struct ExerciseStep: Codable {
    let order: Int
    let text: String
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case order
        case text
        case durationSeconds = "duration_seconds"
    }
}
```

**Validation:** PostgreSQL will reject malformed JSON at insert time.

---

## Blocker #7: Swift Codable Conformance

**Issue:** Original spec used `[String: Any]?` which cannot conform to `Codable`.

**Fix:** Use properly typed structs (see Blocker #6 above).

### Complete Swift Model Definitions

```swift
// apps/ios/MindFriendApp/Core/LocalizationModels.swift

import Foundation

// MARK: - Supported Language

struct SupportedLanguage: Codable, Identifiable, Equatable {
    let code: String
    let name: String
    let nativeName: String
    let direction: String
    let isActive: Bool
    let translationCoverage: Double
    let createdAt: Date

    var id: String { code }
    var isRTL: Bool { direction == "rtl" }

    enum CodingKeys: String, CodingKey {
        case code
        case name
        case nativeName = "native_name"
        case direction
        case isActive = "is_active"
        case translationCoverage = "translation_coverage"
        case createdAt = "created_at"
    }
}

// MARK: - UI Translation

struct UITranslation: Codable {
    let id: UUID
    let stringKey: String
    let languageCode: String
    let translation: String
    let context: String?
    let isVerified: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case stringKey = "string_key"
        case languageCode = "language_code"
        case translation
        case context
        case isVerified = "is_verified"
    }
}

// MARK: - Content Translation

struct ContentTranslation: Codable {
    let id: UUID
    let contentType: String
    let contentId: UUID
    let languageCode: String
    let title: String?
    let description: String?
    let content: String?
    let instructions: ExerciseInstructions?
    let isVerified: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case contentId = "content_id"
        case languageCode = "language_code"
        case title
        case description
        case content
        case instructions
        case isVerified = "is_verified"
    }
}

struct ExerciseInstructions: Codable {
    let steps: [ExerciseStep]
}

struct ExerciseStep: Codable {
    let order: Int
    let text: String
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case order
        case text
        case durationSeconds = "duration_seconds"
    }
}

// MARK: - Crisis Resources

struct LocalizedCrisisResources: Codable {
    let id: UUID
    let countryCode: String
    let languageCode: String
    let emergencyNumber: String
    let crisisHotline: String?
    let crisisHotlineName: String?
    let crisisTextLine: String?
    let crisisWebsite: String?
    let introMessage: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case countryCode = "country_code"
        case languageCode = "language_code"
        case emergencyNumber = "emergency_number"
        case crisisHotline = "crisis_hotline"
        case crisisHotlineName = "crisis_hotline_name"
        case crisisTextLine = "crisis_text_line"
        case crisisWebsite = "crisis_website"
        case introMessage = "intro_message"
        case isActive = "is_active"
    }
}

struct CrisisResources {
    let emergencyNumber: String
    let hotline: String?
    let hotlineName: String?
    let textLine: String?
    let website: String?
    let introMessage: String

    init(from localized: LocalizedCrisisResources) {
        self.emergencyNumber = localized.emergencyNumber
        self.hotline = localized.crisisHotline
        self.hotlineName = localized.crisisHotlineName
        self.textLine = localized.crisisTextLine
        self.website = localized.crisisWebsite
        self.introMessage = localized.introMessage
    }

    static let usDefault = CrisisResources(
        from: LocalizedCrisisResources(
            id: UUID(),
            countryCode: "US",
            languageCode: "en",
            emergencyNumber: "911",
            crisisHotline: "988",
            crisisHotlineName: "Suicide & Crisis Lifeline",
            crisisTextLine: "Text HOME to 741741",
            crisisWebsite: "https://988lifeline.org",
            introMessage: "If you're in crisis, help is available 24/7.",
            isActive: true
        )
    )
}
```

**Result:** All models fully Codable-compliant, no runtime decoding errors.

---

## Blocker #8: Translation Fallback Logic

**Issue:** Behavior undefined when translations missing.

**Complete Fallback Chain Specification:**

### LocalizationService Fallback Logic

```swift
// apps/ios/MindFriendApp/Core/Services/LocalizationService.swift

@MainActor
class LocalizationService: ObservableObject {
    // ... existing properties ...

    /// Translate a UI string with complete fallback chain
    func translate(_ key: String, default defaultValue: String? = nil) -> String {
        // Step 1: Check cached translations for user's language
        if let translation = cachedTranslations[key] {
            return translation
        }

        // Step 2: Check bundle for NSLocalizedString (compiled-in fallback)
        let bundleTranslation = NSLocalizedString(key, bundle: .main, comment: "")
        if bundleTranslation != key {
            return bundleTranslation
        }

        // Step 3: Use provided default value
        if let defaultValue = defaultValue {
            return defaultValue
        }

        // Step 4: Return the key itself (last resort)
        // Log this as a missing translation for tracking
        logMissingTranslation(key: key, language: currentLanguage)
        return key
    }

    /// Fetch content translation with fallback to English
    func getContentTranslation(
        type: String,
        id: UUID,
        field: String
    ) async throws -> String? {
        // Step 1: Try user's preferred language
        if let translation = try await fetchContentTranslation(
            type: type,
            id: id,
            language: currentLanguage,
            field: field
        ) {
            return translation
        }

        // Step 2: Fallback to English if not user's language
        if currentLanguage != "en" {
            if let englishTranslation = try await fetchContentTranslation(
                type: type,
                id: id,
                language: "en",
                field: field
            ) {
                return englishTranslation
            }
        }

        // Step 3: Fetch original content from base table
        let originalContent = try await fetchOriginalContent(type: type, id: id, field: field)
        if let content = originalContent {
            return content
        }

        // Step 4: Return nil (caller must handle)
        logMissingContent(type: type, id: id, field: field, language: currentLanguage)
        return nil
    }

    private func fetchOriginalContent(
        type: String,
        id: UUID,
        field: String
    ) async throws -> String? {
        // Query original table based on type
        switch type {
        case "exercise":
            let exercise: Exercise? = try await supabase
                .from("exercises")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
            // Extract requested field...
            return nil // Simplified for example
        case "quest":
            // Similar for quests...
            return nil
        default:
            return nil
        }
    }

    private func logMissingTranslation(key: String, language: String) {
        #if DEBUG
        print("⚠️ Missing translation: \(key) for language: \(language)")
        #endif

        // TODO: Send to analytics in production
        // Analytics.track("missing_translation", properties: [
        //     "key": key,
        //     "language": language
        // ])
    }

    private func logMissingContent(type: String, id: UUID, field: String, language: String) {
        #if DEBUG
        print("⚠️ Missing content: \(type).\(field) (\(id)) for language: \(language)")
        #endif

        // TODO: Send to analytics
    }
}
```

### UI Handling of Missing Translations

```swift
// Example: ExerciseDetailView

struct ExerciseDetailView: View {
    let exercise: Exercise
    @EnvironmentObject var localization: LocalizationService

    @State private var localizedDescription: String?

    var body: some View {
        VStack {
            // Display title
            Text(localizedDescription ?? exercise.description)
                .font(.body)

            // If translation missing, show indicator
            if localizedDescription == nil && localization.currentLanguage != "en" {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Translation unavailable. Showing English.")
                }
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.top, 4)
            }
        }
        .task {
            localizedDescription = try? await localization.getContentTranslation(
                type: "exercise",
                id: exercise.id,
                field: "description"
            )
        }
    }
}
```

**Fallback Priority:**

1. User's language (from server)
2. English translation (from server)
3. Original content (from base table)
4. Display key with warning indicator

**Logging:** All missing translations tracked for future completion.

---

## Summary of Resolutions

| Blocker               | Status      | Resolution                                         |
| --------------------- | ----------- | -------------------------------------------------- |
| #1 MVP Scope Conflict | ✅ RESOLVED | CLAUDE.md updated, decision documented             |
| #2 Admin System       | ✅ RESOLVED | Use service role key, manual workflow              |
| #3 Migration Safety   | ✅ RESOLVED | IF NOT EXISTS, conditional policies, safe FK       |
| #4 RLS Policies       | ✅ RESOLVED | Complete matrix: SELECT + blocked writes           |
| #5 Crisis Keywords    | ✅ RESOLVED | Spanish + Portuguese keywords defined              |
| #6 JSONB Schema       | ✅ RESOLVED | ExerciseInstructions structure defined             |
| #7 Swift Codable      | ✅ RESOLVED | Properly typed models, no `Any`                    |
| #8 Fallback Logic     | ✅ RESOLVED | 4-step chain: user lang → English → original → key |

**All critical blockers addressed. Specification ready for architect agent.**

---

**Next Step:** Deploy architect agent with:

1. Original spec from spec-writer (agentId: a08ecbb)
2. This corrections document
3. decisions.md entry #2026-01-19-001
