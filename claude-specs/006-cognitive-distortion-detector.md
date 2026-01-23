# N003: Cognitive Distortion Detector

> **Type:** NOVEL DIFFERENTIATOR
> **Phase:** Core AI
> **Complexity:** High
> **Priority:** P0
> **Dependencies:** Voice transcription (Existing), Emotion Analyzer (Existing)

---

## 1. Overview

### 1.1 Summary

The Cognitive Distortion Detector brings automated Cognitive Behavioral Therapy (CBT) to voice journaling. As users speak, the system analyzes their language patterns in real-time to identify common cognitive distortions — the irrational thought patterns that perpetuate anxiety and depression. When detected, the system provides gentle, non-judgmental micro-prompts that guide users toward more balanced thinking, effectively acting as an always-available CBT coach.

This is **CBT at scale**: the therapeutic intervention that works best, made accessible 24/7.

### 1.2 Business Value

- **Therapeutic Efficacy:** CBT is the gold-standard for anxiety/depression with 50-80% response rates
- **Scalability:** Automates what therapists do manually (spot distortions, reframe)
- **Therapist Complement:** Extends therapy between sessions; therapists will recommend
- **Measurable Outcomes:** Track distortion frequency over time as proof of improvement
- **Differentiation:** No consumer app does real-time CBT pattern detection during voice

### 1.3 Scientific Foundation

- **Cognitive Behavioral Therapy:** Beck (1979) - Thought patterns drive emotions
- **Cognitive Distortions:** Burns (1980) - 15 common distortion types identified
- **NLP for Mental Health:** Gkotsis et al. (2017) - Language markers of psychological distress
- **Self-Monitoring Efficacy:** Recording distortions reduces their occurrence (thought awareness training)

---

## 2. Requirements

### 2.1 Functional Requirements

| ID     | Requirement                                                                         | Priority |
| ------ | ----------------------------------------------------------------------------------- | -------- |
| FR-001 | System SHALL detect 10 core cognitive distortions from voice transcripts            | P0       |
| FR-002 | Detection SHALL occur in real-time during voice journaling (< 5 second lag)         | P0       |
| FR-003 | System SHALL provide gentle, non-judgmental micro-prompts when distortions detected | P0       |
| FR-004 | System SHALL track distortion frequency over time per type                          | P0       |
| FR-005 | System SHALL correlate distortions with mood entries to show patterns               | P0       |
| FR-006 | System SHALL explain each distortion type in user-friendly language                 | P1       |
| FR-007 | System SHALL suggest reframing alternatives for detected distortions                | P1       |
| FR-008 | System SHALL allow users to review and label distortions post-journal               | P1       |
| FR-009 | System SHALL generate "Thought Pattern Report" showing weekly trends                | P1       |
| FR-010 | System SHALL integrate with therapist sharing (export distortion history)           | P2       |

### 2.2 Non-Functional Requirements

| ID      | Requirement                                    | Target                           |
| ------- | ---------------------------------------------- | -------------------------------- |
| NFR-001 | Detection latency from speech to prompt        | < 5 seconds                      |
| NFR-002 | Detection precision (true positives)           | > 75%                            |
| NFR-003 | Detection recall (catching actual distortions) | > 60%                            |
| NFR-004 | False positive rate (mistaken detections)      | < 15%                            |
| NFR-005 | User experience impact (not intrusive)         | < 3 prompts per 5-minute journal |

### 2.3 Acceptance Criteria

1. Given a user who says "I always mess everything up", when the system processes this, then it detects "Overgeneralization" within 5 seconds and displays a gentle prompt
2. Given a user who says "My life will be ruined if I don't get this job", when processed, then the system detects "Catastrophizing" and offers a reframing option
3. Given 30 days of journaling data, when the user views their Thought Pattern Report, then they see trends in distortion types and correlation with low mood days
4. Given a distortion is detected, when the user dismisses the prompt, then the system does not show prompts for 60 seconds to avoid intrusiveness

---

## 3. Technical Design

### 3.1 Cognitive Distortion Types

| Distortion             | Description                            | Language Markers                                      |
| ---------------------- | -------------------------------------- | ----------------------------------------------------- |
| All-or-Nothing         | Black/white thinking, no middle ground | "always", "never", "completely", "totally", "perfect" |
| Overgeneralization     | One event = universal pattern          | "always", "never", "everyone", "nobody", "all"        |
| Mental Filter          | Focus only on negatives                | Ignoring positives, "but", dwelling on bad            |
| Disqualifying Positive | Dismissing good things                 | "that doesn't count", "anyone could do that"          |
| Jumping to Conclusions | Mind reading, fortune telling          | "they think", "I know they...", "it will definitely"  |
| Catastrophizing        | Worst-case scenario thinking           | "disaster", "ruined", "terrible", "can't survive"     |
| Emotional Reasoning    | Feelings = facts                       | "I feel stupid so I am", "I feel like a failure"      |
| Should Statements      | Rigid rules for self/others            | "should", "must", "have to", "ought to"               |
| Labeling               | Attaching fixed labels                 | "I'm a loser", "I'm stupid", "they're an idiot"       |
| Personalization        | Blaming self for external events       | "it's my fault", "because of me", "I caused"          |

### 3.2 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    iOS App Layer                                 │
├─────────────────────────────────────────────────────────────────┤
│  VoiceJournalView  │  DistortionOverlay  │  PatternReportView   │
├─────────────────────────────────────────────────────────────────┤
│              CognitiveDistortionViewModel                        │
├─────────────────────────────────────────────────────────────────┤
│               CognitiveDistortionEngine                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Transcript   │  │  Pattern     │  │  Reframe     │          │
│  │  Buffer      │  │  Matcher     │  │  Suggester   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
├─────────────────────────────────────────────────────────────────┤
│  Speech Recognition │ LLM Integration │ Analytics Service       │
│     (existing)      │    (existing)   │    (existing)          │
└─────────────────────────────────────────────────────────────────┘
```

### 3.3 Data Models

#### 3.3.1 CognitiveDistortion Enum

```swift
enum CognitiveDistortionType: String, Codable, CaseIterable {
    case allOrNothing = "all_or_nothing"
    case overgeneralization = "overgeneralization"
    case mentalFilter = "mental_filter"
    case disqualifyingPositive = "disqualifying_positive"
    case jumpingToConclusions = "jumping_to_conclusions"
    case catastrophizing = "catastrophizing"
    case emotionalReasoning = "emotional_reasoning"
    case shouldStatements = "should_statements"
    case labeling = "labeling"
    case personalization = "personalization"

    var displayName: String {
        switch self {
        case .allOrNothing: return "All-or-Nothing Thinking"
        case .overgeneralization: return "Overgeneralization"
        case .mentalFilter: return "Mental Filter"
        case .disqualifyingPositive: return "Disqualifying the Positive"
        case .jumpingToConclusions: return "Jumping to Conclusions"
        case .catastrophizing: return "Catastrophizing"
        case .emotionalReasoning: return "Emotional Reasoning"
        case .shouldStatements: return "Should Statements"
        case .labeling: return "Labeling"
        case .personalization: return "Personalization"
        }
    }

    var explanation: String {
        switch self {
        case .allOrNothing:
            return "Seeing things in black and white, with no middle ground. One mistake means total failure."
        case .overgeneralization:
            return "Taking one event and believing it will always happen. 'This always happens to me.'"
        case .catastrophizing:
            return "Expecting the worst-case scenario. 'This will ruin everything.'"
        // ... etc for all types
        default: return ""
        }
    }

    var reframingPrompt: String {
        switch self {
        case .allOrNothing:
            return "What would be a more balanced way to look at this? Is there a middle ground?"
        case .overgeneralization:
            return "Can you think of a time when this didn't happen?"
        case .catastrophizing:
            return "What's the most likely outcome, not the worst possible one?"
        // ... etc
        default: return ""
        }
    }
}
```

#### 3.3.2 DetectedDistortion Model

```swift
struct DetectedDistortion: Codable, Identifiable {
    let id: UUID
    let userId: String
    let sessionId: String                  // Voice journal session
    let type: CognitiveDistortionType
    let triggerPhrase: String              // The exact phrase that triggered detection
    let fullContext: String                // Surrounding 30 words for context
    let confidence: Double                 // 0.0-1.0
    let timestamp: Date
    let promptDelivered: Bool
    let promptDismissed: Bool
    let userEngaged: Bool                  // Did user interact with reframing
    let userFeedback: DistortionFeedback?  // User's correction if false positive
}

enum DistortionFeedback: String, Codable {
    case accurate = "accurate"             // User agrees it was a distortion
    case notDistorted = "not_distorted"    // User says this was accurate thinking
    case unclearContext = "unclear"        // System misunderstood context
}
```

#### 3.3.3 Database Schema

```sql
-- Detected cognitive distortions
CREATE TABLE cognitive_distortions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL,  -- Voice journal session
    distortion_type TEXT NOT NULL CHECK (distortion_type IN (
        'all_or_nothing', 'overgeneralization', 'mental_filter',
        'disqualifying_positive', 'jumping_to_conclusions', 'catastrophizing',
        'emotional_reasoning', 'should_statements', 'labeling', 'personalization'
    )),
    trigger_phrase TEXT NOT NULL,
    full_context TEXT NOT NULL,
    confidence DECIMAL(3,2) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    prompt_delivered BOOLEAN DEFAULT FALSE,
    prompt_dismissed BOOLEAN DEFAULT FALSE,
    user_engaged BOOLEAN DEFAULT FALSE,
    user_feedback TEXT CHECK (user_feedback IN ('accurate', 'not_distorted', 'unclear')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Daily distortion aggregates for trends
CREATE TABLE distortion_daily_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    distortion_type TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    avg_confidence DECIMAL(3,2),
    mood_correlation DECIMAL(4,3),  -- Correlation with that day's mood
    UNIQUE(user_id, date, distortion_type)
);

-- Indexes
CREATE INDEX idx_distortions_user_time ON cognitive_distortions(user_id, created_at DESC);
CREATE INDEX idx_distortion_stats_user_date ON distortion_daily_stats(user_id, date DESC);

-- RLS
ALTER TABLE cognitive_distortions ENABLE ROW LEVEL SECURITY;
ALTER TABLE distortion_daily_stats ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own distortions" ON cognitive_distortions
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own distortions" ON cognitive_distortions
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own distortions" ON cognitive_distortions
    FOR UPDATE USING (auth.uid() = user_id);
```

### 3.4 Detection Algorithm

```swift
class CognitiveDistortionDetector {
    // Pattern matchers for each distortion type
    private let patternMatchers: [CognitiveDistortionType: [DistortionPattern]]

    struct DistortionPattern {
        let regex: NSRegularExpression?
        let keywords: Set<String>
        let contextualRules: [(String) -> Bool]
        let baseConfidence: Double
    }

    func detectDistortions(in transcript: String) -> [DetectedDistortion] {
        var detections: [DetectedDistortion] = []

        // Sentence-level analysis
        let sentences = transcript.splitIntoSentences()

        for sentence in sentences {
            let sentenceNormalized = sentence.lowercased()

            for (type, patterns) in patternMatchers {
                for pattern in patterns {
                    if let match = matchPattern(pattern, in: sentenceNormalized) {
                        // Calculate confidence based on pattern strength and context
                        let confidence = calculateConfidence(
                            pattern: pattern,
                            match: match,
                            sentence: sentence,
                            fullContext: transcript
                        )

                        if confidence > 0.6 {  // Threshold for showing prompt
                            detections.append(DetectedDistortion(
                                id: UUID(),
                                userId: currentUserId,
                                sessionId: currentSessionId,
                                type: type,
                                triggerPhrase: match.phrase,
                                fullContext: extractContext(around: match, in: transcript),
                                confidence: confidence,
                                timestamp: Date(),
                                promptDelivered: false,
                                promptDismissed: false,
                                userEngaged: false,
                                userFeedback: nil
                            ))
                        }
                    }
                }
            }
        }

        // Deduplicate overlapping detections
        return deduplicateDetections(detections)
    }

    private func calculateConfidence(
        pattern: DistortionPattern,
        match: PatternMatch,
        sentence: String,
        fullContext: String
    ) -> Double {
        var confidence = pattern.baseConfidence

        // Boost if emotional words present
        let emotionalWords = ["terrible", "awful", "horrible", "disaster", "ruined", "worthless"]
        if emotionalWords.contains(where: { sentence.contains($0) }) {
            confidence += 0.1
        }

        // Reduce if hedging words present (might be nuanced)
        let hedgingWords = ["sometimes", "maybe", "perhaps", "might", "possibly"]
        if hedgingWords.contains(where: { sentence.contains($0) }) {
            confidence -= 0.15
        }

        // Boost if first-person distress
        if sentence.contains("i feel") || sentence.contains("i am") || sentence.contains("i'm") {
            confidence += 0.1
        }

        return min(max(confidence, 0.0), 1.0)
    }
}
```

### 3.5 LLM-Enhanced Detection (Hybrid Approach)

For complex cases, use LLM for nuanced understanding:

```swift
class LLMDistortionAnalyzer {
    private let llmClient: GrokClient

    func analyzeWithContext(transcript: String, potentialDistortions: [DetectedDistortion]) async -> [DetectedDistortion] {
        // Only call LLM for ambiguous cases (confidence 0.5-0.75)
        let ambiguousCases = potentialDistortions.filter { $0.confidence > 0.5 && $0.confidence < 0.75 }

        guard !ambiguousCases.isEmpty else {
            return potentialDistortions
        }

        let prompt = """
        Analyze this journal excerpt for cognitive distortions.
        Consider the full context before confirming.

        Excerpt: "\(transcript)"

        Potential distortions detected:
        \(ambiguousCases.map { "- \($0.type.displayName): '\($0.triggerPhrase)'" }.joined(separator: "\n"))

        For each, respond:
        1. Is this truly a cognitive distortion, or valid reasoning given context?
        2. Confidence (0-100)
        3. If distortion: suggest a gentle reframing question

        Respond in JSON format.
        """

        let response = try await llmClient.complete(prompt)
        return mergeWithLLMAnalysis(potentialDistortions, llmResponse: response)
    }
}
```

### 3.6 Gentle Prompt Delivery

```swift
struct DistortionPromptView: View {
    let distortion: DetectedDistortion
    let onDismiss: () -> Void
    let onEngage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Non-judgmental header
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundColor(.yellow)
                Text("Thought Pattern Noticed")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            // The detected phrase
            Text("\"\(distortion.triggerPhrase)\"")
                .font(.body)
                .italic()
                .foregroundColor(.secondary)

            // Distortion type (softly labeled)
            Text("This might be \(distortion.type.displayName.lowercased())")
                .font(.callout)

            // Reframing prompt
            Text(distortion.type.reframingPrompt)
                .font(.body)
                .foregroundColor(.primary)

            // Actions
            HStack {
                Button("Skip") {
                    onDismiss()
                }
                .buttonStyle(.bordered)

                Button("Explore This") {
                    onEngage()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 4)
    }
}
```

### 3.7 API Contracts

#### 3.7.1 Get Distortion History

```
GET /api/v1/distortions?start_date=2026-01-01&end_date=2026-01-22
Authorization: Bearer <jwt>

Response 200:
{
    "distortions": [
        {
            "id": "uuid",
            "type": "catastrophizing",
            "triggerPhrase": "This will ruin everything",
            "confidence": 0.85,
            "timestamp": "2026-01-22T10:30:00Z",
            "userFeedback": null
        }
    ],
    "summary": {
        "totalCount": 47,
        "byType": {
            "catastrophizing": 12,
            "shouldStatements": 15,
            "allOrNothing": 8,
            "overgeneralization": 12
        },
        "trend": "decreasing"  // Compared to previous period
    }
}
```

#### 3.7.2 Submit Distortion Feedback

```
POST /api/v1/distortions/{id}/feedback
Authorization: Bearer <jwt>
Content-Type: application/json

{
    "feedback": "not_distorted",
    "explanation": "I actually do mess up most of my presentations"
}

Response 200:
{
    "success": true,
    "message": "Thanks for the feedback. I'll learn from this."
}
```

---

## 4. Implementation Details

### 4.1 Step-by-Step Implementation

1. **Build Pattern Matcher Library** (2 days)
   - Create regex patterns for each distortion type
   - Define keyword sets with context rules
   - Calibrate base confidence scores

2. **Integrate with Voice Transcription** (1 day)
   - Hook into existing speech recognition pipeline
   - Buffer transcript for sentence-level analysis
   - Handle streaming vs batch processing

3. **Implement Confidence Calculation** (2 days)
   - Add contextual boosters/reducers
   - Implement emotional word detection
   - Add hedging word detection

4. **Build LLM Enhancement Layer** (2 days)
   - Create prompt templates for ambiguous cases
   - Integrate with existing Grok API
   - Handle response parsing

5. **Create Prompt UI** (2 days)
   - Design non-intrusive overlay
   - Implement dismiss/engage actions
   - Add cooldown logic (no spam)

6. **Build Analytics Dashboard** (2 days)
   - Create Thought Pattern Report view
   - Implement trend calculations
   - Add mood correlation analysis

7. **Database & Edge Functions** (1 day)
   - Apply schema migrations
   - Create aggregation Edge Function
   - Set up RLS policies

8. **Testing & Calibration** (2 days)
   - Test with sample transcripts
   - Tune false positive rate
   - Validate with labeled dataset

### 4.2 File Structure

```
MindFriendApp/
├── Core/
│   ├── Services/
│   │   ├── CognitiveDistortionEngine.swift
│   │   ├── DistortionPatternMatcher.swift
│   │   ├── LLMDistortionAnalyzer.swift
│   │   └── DistortionAnalytics.swift
│   └── Models/
│       └── CognitiveDistortionModels.swift
├── Features/
│   └── CognitiveDistortion/
│       ├── DistortionPromptView.swift
│       ├── ThoughtPatternReportView.swift
│       ├── DistortionHistoryView.swift
│       └── CognitiveDistortionViewModel.swift
```

---

## 5. Dependencies

### 5.1 Prerequisites

- Voice journaling with speech-to-text (Existing)
- Grok API integration (Existing)
- Mood logging (Existing)

### 5.2 External Libraries

- Foundation (Apple) - Regex processing
- NaturalLanguage (Apple) - Tokenization, POS tagging

---

## 6. Edge Cases and Error Handling

| Edge Case                         | Expected Behavior                                   |
| --------------------------------- | --------------------------------------------------- |
| User speaks in non-English        | Disable detection; show language limitation         |
| Very short utterance (< 5 words)  | Skip detection; insufficient context                |
| Sarcasm/humor                     | Use LLM for ambiguous cases; accept false positives |
| User repeatedly dismisses prompts | Reduce prompt frequency; ask if feature is helpful  |
| User disputes all detections      | Ask for calibration session; adjust sensitivity     |
| Rapid speech (many sentences)     | Rate-limit prompts to 1 per 30 seconds              |

---

## 7. Testing Requirements

### 7.1 Unit Tests

```swift
class CognitiveDistortionEngineTests: XCTestCase {
    func testDetectsAllOrNothingFromAlways()
    func testDetectsCatastrophizingFromRuined()
    func testIgnoresHedgedStatements()
    func testConfidenceBoostForEmotionalWords()
    func testConfidenceReductionForMaybe()
    func testDeduplicationOfOverlappingDetections()
}
```

### 7.2 Validation Dataset

- 500 labeled sentences from psychology research
- Mix of true distortions and balanced thinking
- Expected performance: > 75% precision, > 60% recall

---

## 8. Success Metrics

| Metric                         | Target                          | Measurement                              |
| ------------------------------ | ------------------------------- | ---------------------------------------- |
| Detection precision            | > 75%                           | User feedback on accuracy                |
| User engagement with prompts   | > 30%                           | Engage vs dismiss rate                   |
| Distortion frequency reduction | 20% decrease over 30 days       | Per-user trending                        |
| Mood improvement correlation   | r > 0.3                         | Distortion reduction vs mood improvement |
| Feature retention              | > 60% still using after 30 days | Analytics                                |

---

## 9. Competitive Analysis

| App       | CBT Feature            | MindFriend Advantage                      |
| --------- | ---------------------- | ----------------------------------------- |
| Woebot    | Scripted CBT lessons   | Real-time detection during natural speech |
| MindDoc   | Thought diary (manual) | Automatic detection, no manual logging    |
| Sanvello  | CBT courses            | Voice-first, passive detection            |
| Talkspace | Human therapist        | 24/7 availability, no cost per session    |

**MindFriend is the first app to do real-time cognitive distortion detection during voice journaling.**
