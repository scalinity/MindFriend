# Multi-Language Localization

> Expand MindFriend's reach globally with comprehensive localization support.

**Priority:** P3 - Nice to Have
**Effort:** High (8-10 weeks for full implementation)
**Impact:** TAM expansion; global accessibility

---

## 1. Overview

### 1.1 What It Does

Full localization infrastructure supporting:

- UI translation to multiple languages
- Localized content (exercises, prompts, stories)
- Right-to-left (RTL) language support
- Cultural adaptation of wellness content
- Localized AI chat responses

### 1.2 Why It Exists

- **Market Expansion:** Mental health is universal, language is a barrier
- **Accessibility:** Serve non-English speakers in English-speaking countries
- **Competitive Edge:** Most wellness apps are English-only
- **Revenue Growth:** 75% of world doesn't speak English

### 1.3 Target Languages

| Phase | Languages                              | Market Size |
| ----- | -------------------------------------- | ----------- |
| 1     | Spanish, Portuguese, French            | 700M        |
| 2     | German, Italian, Dutch, Polish         | 200M        |
| 3     | Japanese, Korean, Chinese (Simplified) | 1.5B        |
| 4     | Arabic, Hebrew, Hindi                  | 600M        |

### 1.4 Success Metrics

| Metric               | Target      | Measurement          |
| -------------------- | ----------- | -------------------- |
| International users  | 30% of MAU  | Non-US users         |
| Translation coverage | 100% UI     | Strings translated   |
| Content localization | 80%+        | Content available    |
| User satisfaction    | 4.5+ rating | Localized app stores |

---

## 2. Functional Requirements

### 2.1 UI Localization

| ID    | Requirement                         | Priority |
| ----- | ----------------------------------- | -------- |
| UL-01 | All UI strings translatable         | Must     |
| UL-02 | Language picker in settings         | Must     |
| UL-03 | Auto-detect device language         | Must     |
| UL-04 | RTL layout support (Arabic, Hebrew) | Should   |
| UL-05 | Number/date/currency formatting     | Must     |
| UL-06 | Pluralization rules                 | Must     |
| UL-07 | Language-specific fonts             | Should   |

### 2.2 Content Localization

| ID    | Requirement                      | Priority |
| ----- | -------------------------------- | -------- |
| CL-01 | Translated exercise instructions | Must     |
| CL-02 | Localized meditation/sleep audio | Should   |
| CL-03 | Translated journal prompts       | Must     |
| CL-04 | Localized quest descriptions     | Must     |
| CL-05 | Cultural adaptation of content   | Should   |
| CL-06 | Local crisis resources           | Must     |

### 2.3 AI Localization

| ID    | Requirement                        | Priority |
| ----- | ---------------------------------- | -------- |
| AL-01 | AI chat in user's language         | Must     |
| AL-02 | Culturally appropriate responses   | Should   |
| AL-03 | Language-specific safety detection | Must     |
| AL-04 | Localized AI prompts and personas  | Should   |

---

## 3. Technical Requirements

### 3.1 Database Schema Updates

```sql
-- Supported languages
CREATE TABLE supported_languages (
    code TEXT PRIMARY KEY, -- 'en', 'es', 'pt-BR', 'fr', 'ar'
    name TEXT NOT NULL, -- 'English', 'Español'
    native_name TEXT NOT NULL, -- 'English', 'Español'
    direction TEXT DEFAULT 'ltr', -- 'ltr' or 'rtl'
    is_active BOOLEAN DEFAULT false,
    translation_coverage DECIMAL(5,2) DEFAULT 0, -- Percentage complete
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- UI string translations
CREATE TABLE ui_translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    string_key TEXT NOT NULL, -- 'home.greeting', 'button.save'
    language_code TEXT NOT NULL REFERENCES supported_languages(code),
    translation TEXT NOT NULL,
    context TEXT, -- For translator reference
    is_verified BOOLEAN DEFAULT false,
    verified_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(string_key, language_code)
);

-- Content translations (exercises, prompts, etc.)
CREATE TABLE content_translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_type TEXT NOT NULL, -- 'exercise', 'quest', 'prompt', 'badge'
    content_id UUID NOT NULL,
    language_code TEXT NOT NULL REFERENCES supported_languages(code),

    -- Translated fields
    title TEXT,
    description TEXT,
    instructions JSONB, -- For exercises with steps
    content TEXT, -- Long-form content

    -- Status
    is_verified BOOLEAN DEFAULT false,
    verified_by UUID REFERENCES auth.users(id),
    translation_notes TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(content_type, content_id, language_code)
);

-- Localized audio content
CREATE TABLE localized_audio (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_audio_id UUID NOT NULL, -- Reference to original content
    language_code TEXT NOT NULL REFERENCES supported_languages(code),
    audio_url TEXT NOT NULL,
    duration_seconds INTEGER,
    voice_artist TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(original_audio_id, language_code)
);

-- Localized crisis resources
CREATE TABLE localized_crisis_resources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    country_code TEXT NOT NULL, -- 'US', 'ES', 'BR'
    language_code TEXT NOT NULL REFERENCES supported_languages(code),

    -- Resources
    emergency_number TEXT NOT NULL, -- '911', '112', '190'
    crisis_hotline TEXT,
    crisis_hotline_name TEXT,
    crisis_text_line TEXT,
    crisis_website TEXT,

    -- Custom message
    intro_message TEXT NOT NULL,

    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(country_code, language_code)
);

-- User language preference (stored in profiles)
ALTER TABLE profiles ADD COLUMN preferred_language TEXT DEFAULT 'en' REFERENCES supported_languages(code);

-- RLS
ALTER TABLE supported_languages ENABLE ROW LEVEL SECURITY;
ALTER TABLE ui_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE localized_crisis_resources ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Languages readable" ON supported_languages FOR SELECT USING (is_active = true);
CREATE POLICY "Translations readable" ON ui_translations FOR SELECT USING (true);
CREATE POLICY "Content translations readable" ON content_translations FOR SELECT USING (is_verified = true);
CREATE POLICY "Crisis resources readable" ON localized_crisis_resources FOR SELECT USING (is_active = true);

-- Indexes
CREATE INDEX idx_ui_translations_key ON ui_translations(string_key);
CREATE INDEX idx_content_translations_type ON content_translations(content_type, content_id);
```

### 3.2 Insert Initial Language Data

```sql
INSERT INTO supported_languages (code, name, native_name, direction, is_active) VALUES
('en', 'English', 'English', 'ltr', true),
('es', 'Spanish', 'Español', 'ltr', false),
('pt-BR', 'Portuguese (Brazil)', 'Português (Brasil)', 'ltr', false),
('fr', 'French', 'Français', 'ltr', false),
('de', 'German', 'Deutsch', 'ltr', false),
('it', 'Italian', 'Italiano', 'ltr', false),
('ja', 'Japanese', '日本語', 'ltr', false),
('ko', 'Korean', '한국어', 'ltr', false),
('zh-CN', 'Chinese (Simplified)', '简体中文', 'ltr', false),
('ar', 'Arabic', 'العربية', 'rtl', false),
('he', 'Hebrew', 'עברית', 'rtl', false);

-- US Crisis Resources (English)
INSERT INTO localized_crisis_resources (country_code, language_code, emergency_number, crisis_hotline, crisis_hotline_name, crisis_text_line, crisis_website, intro_message) VALUES
('US', 'en', '911', '988', 'Suicide & Crisis Lifeline', 'Text HOME to 741741', 'https://988lifeline.org', 'If you''re in crisis, help is available 24/7.'),
('ES', 'es', '112', '024', 'Línea de Atención a la Conducta Suicida', NULL, 'https://www.sanidad.gob.es/linea024', 'Si estás en crisis, hay ayuda disponible 24/7.'),
('BR', 'pt-BR', '190', '188', 'CVV - Centro de Valorização da Vida', NULL, 'https://www.cvv.org.br', 'Se você está em crise, há ajuda disponível 24h.');
```

### 3.3 Swift Localization Service

```swift
import Foundation

@MainActor
class LocalizationService: ObservableObject {
    static let shared = LocalizationService()

    @Published var currentLanguage: String = "en"
    @Published var isRTL: Bool = false

    private var cachedTranslations: [String: String] = [:]
    private var contentTranslations: [String: [String: Any]] = [:]
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseClient.shared) {
        self.supabase = supabase
        loadSavedLanguage()
    }

    // MARK: - Language Selection

    private func loadSavedLanguage() {
        if let saved = UserDefaults.standard.string(forKey: "preferred_language") {
            currentLanguage = saved
        } else {
            // Auto-detect from device
            currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        }
        updateDirection()
    }

    func setLanguage(_ languageCode: String) async throws {
        currentLanguage = languageCode
        UserDefaults.standard.set(languageCode, forKey: "preferred_language")
        updateDirection()

        // Update server preference
        let userId = try await supabase.auth.session.user.id
        try await supabase
            .from("profiles")
            .update(["preferred_language": languageCode])
            .eq("id", value: userId)
            .execute()

        // Reload translations
        try await loadTranslations()
    }

    private func updateDirection() {
        let rtlLanguages = ["ar", "he", "fa", "ur"]
        isRTL = rtlLanguages.contains(currentLanguage)
    }

    // MARK: - UI Translations

    func loadTranslations() async throws {
        let translations: [UITranslation] = try await supabase
            .from("ui_translations")
            .select()
            .eq("language_code", value: currentLanguage)
            .execute()
            .value

        cachedTranslations = Dictionary(
            uniqueKeysWithValues: translations.map { ($0.stringKey, $0.translation) }
        )
    }

    func translate(_ key: String, default defaultValue: String? = nil) -> String {
        if let translation = cachedTranslations[key] {
            return translation
        }

        // Fallback to English from bundle
        if let bundleTranslation = NSLocalizedString(key, comment: "") as String?,
           bundleTranslation != key {
            return bundleTranslation
        }

        return defaultValue ?? key
    }

    func translate(_ key: String, arguments: [CVarArg]) -> String {
        let format = translate(key)
        return String(format: format, arguments: arguments)
    }

    // MARK: - Content Translations

    func getContentTranslation(
        type: String,
        id: UUID,
        field: String
    ) async throws -> String? {
        let cacheKey = "\(type)-\(id)-\(currentLanguage)"

        if let cached = contentTranslations[cacheKey],
           let value = cached[field] as? String {
            return value
        }

        let translation: ContentTranslation? = try await supabase
            .from("content_translations")
            .select()
            .eq("content_type", value: type)
            .eq("content_id", value: id)
            .eq("language_code", value: currentLanguage)
            .single()
            .execute()
            .value

        if let t = translation {
            contentTranslations[cacheKey] = [
                "title": t.title as Any,
                "description": t.description as Any,
                "content": t.content as Any,
                "instructions": t.instructions as Any
            ]
            return t[keyPath: field] as? String
        }

        return nil
    }

    // MARK: - Crisis Resources

    func getCrisisResources() async throws -> CrisisResources {
        // Detect country from device region
        let countryCode = Locale.current.region?.identifier ?? "US"

        let resources: LocalizedCrisisResources? = try await supabase
            .from("localized_crisis_resources")
            .select()
            .eq("country_code", value: countryCode)
            .eq("language_code", value: currentLanguage)
            .single()
            .execute()
            .value

        // Fallback to English if no localized version
        if let r = resources {
            return CrisisResources(from: r)
        }

        let fallback: LocalizedCrisisResources? = try await supabase
            .from("localized_crisis_resources")
            .select()
            .eq("country_code", value: countryCode)
            .eq("language_code", value: "en")
            .single()
            .execute()
            .value

        if let f = fallback {
            return CrisisResources(from: f)
        }

        // Ultimate fallback to US English
        return CrisisResources.usDefault
    }

    // MARK: - Available Languages

    func fetchAvailableLanguages() async throws -> [SupportedLanguage] {
        try await supabase
            .from("supported_languages")
            .select()
            .eq("is_active", value: true)
            .order("name", ascending: true)
            .execute()
            .value
    }
}

// MARK: - Models

struct UITranslation: Codable {
    let id: UUID
    let stringKey: String
    let languageCode: String
    let translation: String
}

struct ContentTranslation: Codable {
    let id: UUID
    let contentType: String
    let contentId: UUID
    let languageCode: String
    let title: String?
    let description: String?
    let content: String?
    let instructions: [String: Any]?
}

struct SupportedLanguage: Codable, Identifiable {
    let code: String
    let name: String
    let nativeName: String
    let direction: String
    let translationCoverage: Double

    var id: String { code }

    var isRTL: Bool { direction == "rtl" }
}

struct LocalizedCrisisResources: Codable {
    let countryCode: String
    let languageCode: String
    let emergencyNumber: String
    let crisisHotline: String?
    let crisisHotlineName: String?
    let crisisTextLine: String?
    let crisisWebsite: String?
    let introMessage: String
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
            countryCode: "US",
            languageCode: "en",
            emergencyNumber: "911",
            crisisHotline: "988",
            crisisHotlineName: "Suicide & Crisis Lifeline",
            crisisTextLine: "Text HOME to 741741",
            crisisWebsite: "https://988lifeline.org",
            introMessage: "If you're in crisis, help is available 24/7."
        )
    )
}
```

### 3.4 SwiftUI Localization Extension

```swift
// String extension for easy localization
extension String {
    var localized: String {
        LocalizationService.shared.translate(self)
    }

    func localized(with arguments: CVarArg...) -> String {
        LocalizationService.shared.translate(self, arguments: arguments)
    }
}

// Environment key for RTL
struct LayoutDirectionKey: EnvironmentKey {
    static let defaultValue: LayoutDirection = .leftToRight
}

extension EnvironmentValues {
    var appLayoutDirection: LayoutDirection {
        get { self[LayoutDirectionKey.self] }
        set { self[LayoutDirectionKey.self] = newValue }
    }
}

// View modifier for RTL support
struct LocalizedView: ViewModifier {
    @ObservedObject var localization = LocalizationService.shared

    func body(content: Content) -> some View {
        content
            .environment(\.layoutDirection, localization.isRTL ? .rightToLeft : .leftToRight)
            .environment(\.appLayoutDirection, localization.isRTL ? .rightToLeft : .leftToRight)
    }
}

extension View {
    func localized() -> some View {
        modifier(LocalizedView())
    }
}
```

### 3.5 Edge Function: Localized AI Chat

```typescript
// supabase/functions/chat/index.ts (updated for localization)

const LANGUAGE_SYSTEM_PROMPTS: Record<string, string> = {
  en: "You are MindFriend, a compassionate AI companion...",
  es: "Eres MindFriend, un compañero de IA compasivo. Responde siempre en español...",
  "pt-BR":
    "Você é MindFriend, um companheiro de IA compassivo. Sempre responda em português brasileiro...",
  fr: "Vous êtes MindFriend, un compagnon IA compatissant. Répondez toujours en français...",
  de: "Du bist MindFriend, ein mitfühlender KI-Begleiter. Antworte immer auf Deutsch...",
  ja: "あなたはMindFriendです。思いやりのあるAIコンパニオンとして、日本語で応答してください...",
};

async function getSystemPrompt(userId: string, supabase: any): Promise<string> {
  const { data: profile } = await supabase
    .from("profiles")
    .select("preferred_language")
    .eq("id", userId)
    .single();

  const language = profile?.preferred_language || "en";
  return LANGUAGE_SYSTEM_PROMPTS[language] || LANGUAGE_SYSTEM_PROMPTS.en;
}

// In main handler:
const systemPrompt = await getSystemPrompt(user.id, supabase);
// Use systemPrompt when calling AI
```

---

## 4. UI/UX Specifications

### 4.1 Language Settings

```
┌─────────────────────────────────┐
│ ← Language                      │
├─────────────────────────────────┤
│                                 │
│ App Language                    │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ ● English                   │ │
│ │   100% translated           │ │
│ ├─────────────────────────────┤ │
│ │ ○ Español                   │ │
│ │   98% translated            │ │
│ ├─────────────────────────────┤ │
│ │ ○ Português (Brasil)        │ │
│ │   95% translated            │ │
│ ├─────────────────────────────┤ │
│ │ ○ Français                  │ │
│ │   92% translated            │ │
│ ├─────────────────────────────┤ │
│ │ ○ Deutsch                   │ │
│ │   88% translated            │ │
│ ├─────────────────────────────┤ │
│ │ ○ 日本語                    │ │
│ │   Coming soon               │ │
│ └─────────────────────────────┘ │
│                                 │
│ Some content may not be         │
│ available in all languages.     │
│ We're always adding more!       │
│                                 │
└─────────────────────────────────┘
```

### 4.2 RTL Layout Example (Arabic)

```
┌─────────────────────────────────┐
│                    مرحباً سارة   │
│                    كيف حالك اليوم؟ │
├─────────────────────────────────┤
│                                 │
│                    المهام اليومية │
│ ┌─────────────────────────────┐ │
│ │      ○ تسجيل المزاج         │ │
│ │      ● التأمل الصباحي ✓      │ │
│ │      ○ كتابة اليوميات       │ │
│ └─────────────────────────────┘ │
│                                 │
│                       مزاجك     │
│ ┌─────────────────────────────┐ │
│ │ 😊  😐  😢  😤  😰         │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

---

## 5. Acceptance Criteria

- [ ] Users can select language in settings
- [ ] App detects device language on first launch
- [ ] All UI strings display in selected language
- [ ] RTL layout works correctly (Arabic, Hebrew)
- [ ] Numbers/dates format correctly per locale
- [ ] AI chat responds in user's language
- [ ] Crisis resources are localized per country
- [ ] Content fallback to English when translation unavailable

---

## 6. Translation Workflow

### 6.1 Process

1. **String Extraction:** Automated extraction of new strings
2. **Translation:** Professional translators via platform (Lokalise, Phrase)
3. **Review:** Native speaker verification
4. **Import:** Sync translations to database
5. **Testing:** QA pass for context/layout issues

### 6.2 Quality Standards

| Standard                 | Requirement                          |
| ------------------------ | ------------------------------------ |
| Professional translation | No machine-only translation          |
| Native review            | Verified by native speaker           |
| Context provided         | Screenshots/descriptions for strings |
| Consistent terminology   | Glossary maintained per language     |
| Cultural adaptation      | Content appropriate for culture      |

---

## 7. Rollout Plan

### Phase 1 (Week 1-2): Infrastructure

- Localization service implementation
- Database schema for translations
- String extraction tooling

### Phase 2 (Week 3-4): Spanish & Portuguese

- Full UI translation
- Exercise content localization
- Crisis resources for Spain, Mexico, Brazil

### Phase 3 (Week 5-6): European Languages

- French, German, Italian translations
- Additional crisis resources
- Cultural content review

### Phase 4 (Week 7-8): Asian Languages

- Japanese, Korean, Chinese translations
- Font support for CJK characters
- Right-to-left testing (if Arabic added)

### Phase 5 (Week 9-10): Polish & Launch

- QA across all languages
- Audio content localization begins
- App Store listing localization
- Marketing materials translation
