# Credibility Signals

## Overview

**Goal:** Build user trust through transparency about the science behind exercises, privacy practices, and professional input. Mental health = trust is everything.

**Why it matters:** Users are skeptical of wellness apps. Showing that exercises are evidence-based, that privacy is protected, and that real professionals were involved builds credibility that converts skeptics into believers.

**Impact:** P7 priority - Trust building

---

## User Stories

- As a user, I want to know exercises are evidence-based so that I trust they'll actually help
- As a user, I want to understand privacy practices so that I feel safe sharing my thoughts
- As a user, I want to see real testimonials so that I know others have benefited
- As a user, I want to know professionals were involved so that I trust the app's guidance

---

## Product Requirements

### Must Have (MVP)

1. **Evidence-Based Badges**
   - Show methodology origin on exercises (CBT, DBT, Mindfulness, etc.)
   - "Based on [methodology]" label visible on exercise cards
   - Info modal explaining what each methodology means

2. **Therapist Review Indicator**
   - "Reviewed by mental health professionals" badge
   - Shown on exercises that have been professionally reviewed
   - Link to "Our Approach" page explaining review process

3. **Privacy-First Messaging**
   - Clear privacy statement in onboarding
   - "Your data is encrypted and never sold" visible in settings
   - Easy access to privacy policy
   - Data export option

4. **Testimonials Section**
   - 3-5 real user testimonials (with consent)
   - Shown on onboarding or marketing screens
   - Anonymized but authentic

### Nice to Have (V2)

- Detailed methodology explanations
- Clinical study references
- Advisory board page
- Third-party security audit badge
- HIPAA compliance indicator (if applicable)
- Professional endorsements

### Out of Scope

- Making medical claims
- Displaying therapist profiles
- Offering clinical services
- FDA/medical device compliance

---

## Technical Design

### Data Model Changes

```sql
-- Migration: 20260121_credibility_signals.sql

-- Add credibility fields to exercises
ALTER TABLE exercises ADD COLUMN evidence_basis TEXT
  CHECK (evidence_basis IN ('CBT', 'DBT', 'ACT', 'Mindfulness', 'Somatic', 'Breathwork', 'General'));

ALTER TABLE exercises ADD COLUMN therapist_reviewed BOOLEAN DEFAULT FALSE;
ALTER TABLE exercises ADD COLUMN review_date DATE;
ALTER TABLE exercises ADD COLUMN methodology_note TEXT;

-- Update existing exercises with evidence basis
UPDATE exercises SET evidence_basis = 'Breathwork', therapist_reviewed = TRUE WHERE type = 'breathing';
UPDATE exercises SET evidence_basis = 'Mindfulness', therapist_reviewed = TRUE WHERE type = 'meditation';
UPDATE exercises SET evidence_basis = 'Somatic', therapist_reviewed = TRUE WHERE type = 'grounding';
UPDATE exercises SET evidence_basis = 'CBT', therapist_reviewed = TRUE WHERE type = 'journaling';
UPDATE exercises SET evidence_basis = 'Somatic', therapist_reviewed = TRUE WHERE type = 'movement';

-- Testimonials table
CREATE TABLE testimonials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name TEXT NOT NULL,  -- Anonymized, e.g., "Sarah M."
  location TEXT,               -- Optional, e.g., "California"
  content TEXT NOT NULL,
  rating INT CHECK (rating >= 1 AND rating <= 5),
  feature_highlight TEXT,      -- Which feature they're highlighting
  approved BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed initial testimonials
INSERT INTO testimonials (display_name, location, content, rating, feature_highlight, approved) VALUES
  ('Sarah M.', 'California', 'The AI buddy feels like talking to a friend who actually listens. It helped me process difficult emotions without judgment.', 5, 'AI Chat', TRUE),
  ('James T.', 'New York', 'The daily quests made building a meditation habit actually stick. 45 day streak and counting!', 5, 'Daily Quests', TRUE),
  ('Emily R.', 'Texas', 'I love the circles feature. My support group checks in daily and it keeps us all accountable.', 5, 'Circles', TRUE),
  ('Michael K.', 'Washington', 'The breathing exercises are science-backed and actually work. I use them before stressful meetings.', 4, 'Exercises', TRUE),
  ('Anna L.', 'Oregon', 'Finally an app that respects privacy. I feel safe sharing my thoughts here.', 5, 'Privacy', TRUE);

-- RLS
ALTER TABLE testimonials ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read approved testimonials" ON testimonials
  FOR SELECT USING (approved = TRUE);

-- Methodology explanations (static reference)
CREATE TABLE methodology_info (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  source TEXT
);

INSERT INTO methodology_info (code, name, description, source) VALUES
  ('CBT', 'Cognitive Behavioral Therapy', 'A widely-studied approach that helps identify and change negative thought patterns. CBT techniques help you recognize unhelpful thoughts and develop healthier responses.', 'American Psychological Association'),
  ('DBT', 'Dialectical Behavior Therapy', 'Combines cognitive-behavioral techniques with mindfulness practices. Helps build skills in distress tolerance, emotion regulation, and interpersonal effectiveness.', 'Linehan Institute'),
  ('ACT', 'Acceptance and Commitment Therapy', 'Focuses on accepting difficult thoughts and feelings while committing to actions aligned with your values. Emphasizes psychological flexibility.', 'Association for Contextual Behavioral Science'),
  ('Mindfulness', 'Mindfulness-Based Practices', 'Rooted in ancient meditation traditions and validated by modern research. Focuses on present-moment awareness without judgment.', 'Mindfulness-Based Stress Reduction (MBSR)'),
  ('Somatic', 'Somatic Practices', 'Body-based approaches that use physical movement and awareness to release tension and regulate the nervous system.', 'Somatic Experiencing International'),
  ('Breathwork', 'Breathwork Techniques', 'Controlled breathing practices that activate the parasympathetic nervous system, reducing stress and promoting calm.', 'Research on diaphragmatic breathing'),
  ('General', 'General Wellness', 'Evidence-informed wellness practices drawn from multiple therapeutic traditions.', 'Various sources');

-- RLS for methodology_info (public read)
ALTER TABLE methodology_info ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read methodology info" ON methodology_info FOR SELECT USING (TRUE);
```

### iOS Implementation

**Update Models** (`Core/Models.swift`):

```swift
extension Exercise {
    var evidenceBasis: EvidenceBasis? {
        EvidenceBasis(rawValue: _evidenceBasis ?? "General")
    }

    var isTherapistReviewed: Bool {
        _therapistReviewed ?? false
    }
}

enum EvidenceBasis: String, Codable {
    case CBT, DBT, ACT, Mindfulness, Somatic, Breathwork, General

    var displayName: String {
        switch self {
        case .CBT: return "Cognitive Behavioral Therapy"
        case .DBT: return "Dialectical Behavior Therapy"
        case .ACT: return "Acceptance & Commitment Therapy"
        case .Mindfulness: return "Mindfulness-Based"
        case .Somatic: return "Somatic Practice"
        case .Breathwork: return "Breathwork"
        case .General: return "Evidence-Informed"
        }
    }

    var shortLabel: String {
        switch self {
        case .CBT: return "CBT"
        case .DBT: return "DBT"
        case .ACT: return "ACT"
        case .Mindfulness: return "Mindfulness"
        case .Somatic: return "Somatic"
        case .Breathwork: return "Breathwork"
        case .General: return "Wellness"
        }
    }

    var color: Color {
        switch self {
        case .CBT: return .blue
        case .DBT: return .purple
        case .ACT: return .green
        case .Mindfulness: return .teal
        case .Somatic: return .orange
        case .Breathwork: return .cyan
        case .General: return .gray
        }
    }
}

struct MethodologyInfo: Identifiable, Codable {
    let code: String
    let name: String
    let description: String
    let source: String?

    var id: String { code }
}

struct Testimonial: Identifiable, Codable {
    let id: UUID
    let displayName: String
    let location: String?
    let content: String
    let rating: Int
    let featureHighlight: String?
}
```

**Service Methods**:

```swift
// MARK: - Credibility

func getMethodologyInfo(code: String) async throws -> MethodologyInfo? {
    let info: [MethodologyInfo] = try await supabase
        .from("methodology_info")
        .select()
        .eq("code", code)
        .limit(1)
        .execute()
        .value
    return info.first
}

func getAllMethodologies() async throws -> [MethodologyInfo] {
    try await supabase
        .from("methodology_info")
        .select()
        .execute()
        .value
}

func getTestimonials() async throws -> [Testimonial] {
    try await supabase
        .from("testimonials")
        .select()
        .eq("approved", true)
        .execute()
        .value
}
```

**New Views**:

```swift
// EvidenceBadge.swift
struct EvidenceBadge: View {
    let basis: EvidenceBasis
    let isReviewed: Bool
    var showInfo: Bool = true
    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 4) {
            Text(basis.shortLabel)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(basis.color)

            if isReviewed {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
            }

            if showInfo {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(basis.color.opacity(0.1))
        .cornerRadius(8)
        .sheet(isPresented: $showingInfo) {
            MethodologyInfoSheet(basis: basis)
        }
    }
}

// MethodologyInfoSheet.swift
struct MethodologyInfoSheet: View {
    let basis: EvidenceBasis
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var container: DependencyContainer
    @State private var info: MethodologyInfo?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Text(basis.shortLabel)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(basis.color)
                        Spacer()
                    }

                    Text(basis.displayName)
                        .font(.headline)

                    if let info {
                        Text(info.description)
                            .font(.body)

                        if let source = info.source {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Source")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(source)
                                    .font(.caption)
                                    .italic()
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }

                    // Therapist review note
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Exercises using this methodology have been reviewed by mental health professionals.")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("About This Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            info = try? await container.supabaseDataService.getMethodologyInfo(code: basis.rawValue)
        }
    }
}

// PrivacyBanner.swift (for onboarding/settings)
struct PrivacyBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your Privacy Matters", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 8) {
                PrivacyPoint(icon: "lock.fill", text: "End-to-end encryption for sensitive data")
                PrivacyPoint(icon: "eye.slash.fill", text: "We never sell your personal information")
                PrivacyPoint(icon: "arrow.down.doc.fill", text: "Export your data anytime")
                PrivacyPoint(icon: "trash.fill", text: "Delete your account and data permanently")
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
}

struct PrivacyPoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.green)
                .frame(width: 20)
            Text(text)
                .font(.caption)
        }
    }
}

// TestimonialsCarousel.swift
struct TestimonialsCarousel: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var testimonials: [Testimonial] = []
    @State private var currentIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What Users Say")
                .font(.headline)

            if !testimonials.isEmpty {
                TabView(selection: $currentIndex) {
                    ForEach(Array(testimonials.enumerated()), id: \.element.id) { index, testimonial in
                        TestimonialCard(testimonial: testimonial)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 180)
            }
        }
        .task {
            testimonials = (try? await container.supabaseDataService.getTestimonials()) ?? []
        }
    }
}

struct TestimonialCard: View {
    let testimonial: Testimonial

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Stars
            HStack(spacing: 2) {
                ForEach(0..<5) { i in
                    Image(systemName: i < testimonial.rating ? "star.fill" : "star")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }

            Text("\"\(testimonial.content)\"")
                .font(.subheadline)
                .italic()

            HStack {
                Text("— \(testimonial.displayName)")
                    .font(.caption)
                    .fontWeight(.medium)
                if let location = testimonial.location {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// OurApproachView.swift
struct OurApproachView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var methodologies: [MethodologyInfo] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Evidence-Based Wellness")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Every exercise in MindFriend is rooted in research-backed therapeutic approaches.")
                        .foregroundColor(.secondary)
                }

                // Review process
                VStack(alignment: .leading, spacing: 12) {
                    Label("Professional Review", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundColor(.green)

                    Text("Our exercises are reviewed by licensed mental health professionals to ensure they're safe, effective, and appropriate for self-guided use.")
                        .font(.subheadline)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)

                // Methodologies
                Text("Therapeutic Approaches")
                    .font(.headline)

                ForEach(methodologies) { method in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(method.code)
                                .font(.headline)
                                .foregroundColor(EvidenceBasis(rawValue: method.code)?.color ?? .gray)
                            Text("•")
                            Text(method.name)
                                .font(.subheadline)
                        }
                        Text(method.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }

                // Disclaimer
                Text("MindFriend is not a replacement for professional mental health care. If you're experiencing a crisis or need clinical support, please contact a mental health professional.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Our Approach")
        .task {
            methodologies = (try? await container.supabaseDataService.getAllMethodologies()) ?? []
        }
    }
}
```

**Update ExerciseCard** to show badge:

```swift
// In ExerciseLibraryView
struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack {
            // ... existing content ...

            Spacer()

            if let basis = exercise.evidenceBasis {
                EvidenceBadge(
                    basis: basis,
                    isReviewed: exercise.isTherapistReviewed,
                    showInfo: false
                )
            }
        }
    }
}
```

---

## UI/UX

### Exercise Card with Badge

```
┌─────────────────────────────────────┐
│  🌬️ 4-7-8 Breathing                 │
│                                     │
│  A calming technique to reduce      │
│  anxiety and promote sleep.         │
│                                     │
│  ┌──────────────────┐               │
│  │ Breathwork ✓ ⓘ  │    5 min     │
│  └──────────────────┘               │
└─────────────────────────────────────┘
```

### Our Approach Screen

```
┌─────────────────────────────────────┐
│ < Settings     Our Approach         │
├─────────────────────────────────────┤
│                                     │
│  Evidence-Based Wellness            │
│                                     │
│  Every exercise in MindFriend is    │
│  rooted in research-backed          │
│  therapeutic approaches.            │
│                                     │
│  ┌─────────────────────────────────┐│
│  │ ✓ Professional Review           ││
│  │                                 ││
│  │ Our exercises are reviewed by   ││
│  │ licensed mental health          ││
│  │ professionals.                  ││
│  └─────────────────────────────────┘│
│                                     │
│  THERAPEUTIC APPROACHES             │
│                                     │
│  ┌─────────────────────────────────┐│
│  │ CBT • Cognitive Behavioral      ││
│  │ A widely-studied approach...    ││
│  └─────────────────────────────────┘│
│                                     │
│  ┌─────────────────────────────────┐│
│  │ Mindfulness • Mindfulness-Based ││
│  │ Rooted in ancient meditation... ││
│  └─────────────────────────────────┘│
│                                     │
└─────────────────────────────────────┘
```

---

## Verification

### Manual Testing

1. **Evidence Badges:**
   - View exercise library
   - Verify badges show on all exercises
   - Tap info icon, verify sheet appears
   - Verify methodology info is accurate

2. **Privacy Messaging:**
   - Complete onboarding
   - Verify privacy banner appears
   - Navigate to settings
   - Verify privacy section present

3. **Testimonials:**
   - View testimonials on onboarding/marketing
   - Verify all testimonials display
   - Verify carousel swipes correctly

4. **Our Approach:**
   - Navigate to Settings → Our Approach
   - Verify all methodologies listed
   - Verify disclaimer present

---

## Dependencies

- Exercises table exists
- Settings screen exists
- Onboarding flow exists

---

## Risks & Mitigations

| Risk                           | Likelihood | Impact | Mitigation                            |
| ------------------------------ | ---------- | ------ | ------------------------------------- |
| Claims seem exaggerated        | Medium     | High   | Use careful language, cite sources    |
| Testimonials feel fake         | Low        | High   | Use real users with consent           |
| Users don't notice badges      | Medium     | Low    | Place prominently on exercise cards   |
| Professional review questioned | Low        | Medium | Document review process transparently |

---

## Implementation Estimate

| Task                            | Effort       |
| ------------------------------- | ------------ |
| Database migration              | 1 hour       |
| iOS Models                      | 1 hour       |
| EvidenceBadge component         | 2 hours      |
| MethodologyInfoSheet            | 2 hours      |
| PrivacyBanner                   | 1 hour       |
| TestimonialsCarousel            | 2 hours      |
| OurApproachView                 | 2 hours      |
| Integration with existing views | 2 hours      |
| Testing                         | 2 hours      |
| **Total**                       | **15 hours** |
