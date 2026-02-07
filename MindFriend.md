# MindFriend

### AI-Powered Mental Wellness Platform with Clinical Psychology Foundations

![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange?logo=swift&logoColor=white)
![iOS 17+](https://img.shields.io/badge/iOS-17+-blue?logo=apple&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-Backend-3FCF8E?logo=supabase&logoColor=white)
![Core ML](https://img.shields.io/badge/Core%20ML-On--Device%20AI-purple?logo=apple&logoColor=white)
![ARKit](https://img.shields.io/badge/ARKit-AR%20Exercises-black?logo=apple&logoColor=white)
![HealthKit](https://img.shields.io/badge/HealthKit-Biometrics-red?logo=apple&logoColor=white)
![Localization](https://img.shields.io/badge/Languages-EN%20|%20ES%20|%20PT--BR-green)

**MindFriend** is a production-grade iOS mental wellness platform that fuses large language models, on-device machine learning, and real-time biometric sensing with evidence-based clinical psychology frameworks — including Polyvagal Theory, Cognitive Behavioral Therapy (CBT), and circadian rhythm science — to deliver personalized, adaptive mental health support at scale. The system performs real-time nervous system state classification, cognitive distortion detection, predictive risk assessment, and intervention efficacy tracking, creating a closed-loop feedback system that continuously learns which therapeutic interventions are most effective for each individual user.

---

## Table of Contents

- [Motivation](#motivation)
- [AI & Machine Learning Systems](#ai--machine-learning-systems)
- [Clinical Psychology Foundations](#clinical-psychology-foundations)
- [Safety & Crisis Intervention](#safety--crisis-intervention)
- [Architecture](#architecture)
- [Technical Highlights](#technical-highlights)
- [Tech Stack](#tech-stack)
- [Project Scale](#project-scale)
- [Roadmap](#roadmap)

---

## Motivation

Over 50% of adults with a mental health condition receive no treatment. Cost, stigma, and provider shortages create a global access gap that disproportionately affects underserved communities. MindFriend addresses this by applying AI and biomedical signal processing to democratize access to evidence-based mental health support — not as a replacement for clinical care, but as a daily companion that bridges the gap between therapy sessions, detects early warning signs through physiological and behavioral signals, and escalates to human professionals when risk thresholds are crossed.

This project represents the intersection of artificial intelligence and biomedical health sciences: building intelligent systems that understand human physiology, detect psychological distress patterns, and deliver clinically-grounded interventions — while maintaining the safety, privacy, and ethical standards that health-adjacent technology demands.

---

## AI & Machine Learning Systems

### Polyvagal-Informed Nervous System State Classification

Implements Stephen Porges' Polyvagal Theory as a real-time computational model for autonomic nervous system state classification. The system fuses three physiological and behavioral signal streams to classify users into discrete nervous system states:

| State             | Polyvagal Mapping        | Physiological Signature                                  |
| ----------------- | ------------------------ | -------------------------------------------------------- |
| **Ventral Vagal** | Safe & Social            | High HRV, relaxed pitch variability, social engagement   |
| **Sympathetic**   | Fight/Flight (Mobilized) | Elevated heart rate, increased speech rate, high arousal |
| **Dorsal Vagal**  | Freeze/Shutdown          | Low HRV, flat vocal affect, behavioral withdrawal        |
| **Mixed**         | Transitional             | Conflicting signals across modalities                    |

**Signal Fusion Pipeline:**

- **Voice Features (`PolyvagalVoiceFeatures`):** Pitch variability, speech rate, voice intensity, emotion probability ratios, arousal index, social engagement score, threat activation level, shutdown risk
- **HRV Features (`PolyvagalHRVFeatures`):** Heart rate variability extracted via HealthKit with `HRVPolyvagalExtractor`, using anchored object queries with 5-minute sliding windows, exponential backoff retry (max 3 attempts), and real-time trend analysis (increasing/decreasing/stable with slope thresholds of +/-1.0 BPM per reading)
- **Behavioral Features (`PolyvagalBehavioralFeatures`):** App engagement patterns, social interaction frequency, circadian rhythm adherence

**Cascade Detection (`CascadeDetector`):** Identifies dysregulation progressions — specifically sympathetic overflow cascading into dorsal vagal shutdown — enabling proactive intervention before full nervous system collapse.

---

### Voice Emotion Analysis (On-Device Core ML)

Privacy-preserving emotion recognition that processes audio entirely on-device — no audio data is ever transmitted to external servers.

- **Core ML model** classifies 8 discrete emotion categories: angry, calm, disgust, fearful, happy, neutral, sad, surprised
- **`EmotionSnapshot`** captures timestamped detections with confidence scores and probability distributions
- **Security hardening:** URL validation with path traversal prevention, audio length limits, valid emotion allowlist (XSS prevention even for locally-processed outputs), rate limiting, and explicit user consent management
- **Apple Watch integration** via WatchConnectivity for continuous monitoring

---

### Cognitive Distortion Detection Engine

Real-time CBT-based cognitive distortion detection operating across 12 clinically-defined distortion types:

| Code  | Distortion              | Clinical Basis               |
| ----- | ----------------------- | ---------------------------- |
| AON   | All-or-Nothing Thinking | Beck's cognitive triad       |
| CAT   | Catastrophizing         | Magnification bias           |
| MIND  | Mind-Reading            | Attribution error            |
| FORT  | Fortune-Telling         | Predictive bias              |
| LAB   | Labeling                | Identity fusion              |
| SHO   | Should Statements       | Rigid rule systems           |
| EMF   | Emotional Reasoning     | Affect heuristic             |
| MINS  | Minimization            | Discounting positives        |
| BLAME | Blame/Personalization   | External locus error         |
| COMP  | Comparison              | Social comparison theory     |
| RG    | Regret Rumination       | Counterfactual thinking      |
| WHAT  | What-If Spiraling       | Anxiety-driven hypotheticals |

**Detection Pipeline:**

- Weighted keyword matching with phrase multipliers for confidence scoring
- Multi-language support (English, Spanish, Portuguese-Brazilian) with culturally-adapted keyword sets
- Configurable sensitivity levels (balanced / low / high) with per-user threshold tuning
- Timezone-aware silent hours to respect user-defined notification boundaries

**Therapeutic Response:**

- Socratic questioning prompts tailored to each distortion type
- Educational content explaining the cognitive bias mechanism
- CBT-style reframing suggestions
- Encounter logging for longitudinal coaching effectiveness analysis

---

### Stress Signature Fingerprinting

A machine learning system that learns each user's unique stress pattern from historical crisis and mood data to detect early warning signs before full escalation:

- **`StressSignatureEngine`** extracts personalized stress signatures from mood volatility patterns, engagement drops, HRV changes, and sleep disruptions
- **`PatternLearner`** builds user-specific models from historical crisis events, identifying the physiological and behavioral precursors unique to each individual
- **`SignalMonitor`** performs real-time monitoring with weight-adjustable pattern detection, integrating with the Wellbeing Debt system for compound signal analysis
- **`EarlyInterventionService`** delivers proactive therapeutic interventions when signature patterns are detected — before the user self-reports distress

---

### Predictive Risk Assessment

Multi-factor risk classification model that continuously evaluates mental health risk across physiological, behavioral, and social dimensions:

**Risk Factors Analyzed:**
| Factor | Data Source | Signal |
|--------|-----------|--------|
| Mood Trend | Daily mood logs | Declining trajectory |
| Mood Volatility | Mood variance | High emotional instability |
| App Engagement | Session frequency/duration | Withdrawal patterns |
| Sleep Quality | HealthKit sleep data | Circadian disruption |
| HRV Drop | Heart rate variability | Autonomic dysregulation |
| Streak Breaks | Quest completion | Behavioral disengagement |
| Social Engagement | Circle activity | Social withdrawal |
| Days Since Chat | Last AI interaction | Help-seeking avoidance |

**Risk Levels:** Low (0-25) / Medium (26-50) / High (51-75) / Crisis (76-100) with color-coded visualization and graduated intervention protocols.

---

### Intervention Efficacy Engine

A closed-loop recommendation system that tracks which therapeutic interventions produce the best outcomes for each user, creating a personalized treatment optimization pipeline:

- **`InterventionEfficacyEngine`** tracks pre/post mood scores, completion rates, and user ratings for every intervention delivered
- **`TrajectoryTracker`** analyzes long-term mood trajectories (3-4+ months) to identify which intervention categories produce sustained improvement vs. short-term relief
- **`EfficacyCalculator`** computes per-intervention success metrics normalized by baseline severity
- **`EfficacyBasedRecommender`** ranks available interventions by predicted effectiveness for the specific user, creating an adaptive recommendation engine that improves over time

---

### Smart Notification ML System

Machine learning-driven notification timing and content optimization:

- **`MLPredictionEngine`** predicts per-user engagement probability before sending each notification
- **`ContextEngine`** aggregates calendar data, location context, biometric state, and Focus mode status to determine optimal delivery windows
- **`EngagementTracker`** collects training data from every notification interaction, feeding back into the prediction model for continuous improvement
- Adaptive engagement thresholds by user preference: Minimal (0.70) / Moderate (0.60) / Frequent (0.50)
- **Recovery mode suppression:** Automatically blocks "pressure" notifications (streak risk, re-engagement) during difficult periods, reducing notification volume by >50%

---

### Circadian Vulnerability Detection

Analyzes sleep patterns and calendar data to predict high-vulnerability windows for optimal intervention timing:

- **`CircadianVulnerabilityEngine`** identifies circadian rhythm disruptions by correlating sleep data with mood and behavioral patterns
- Integrates HealthKit sleep stages with calendar stress analysis
- Times interventions for periods of peak receptivity rather than peak distress

---

### AI Companion with Adaptive Memory

Conversational AI companion powered by large language models with sophisticated context management:

- **Memory system:** Dual-layer memory architecture — user-curated companion memories (boundaries, preferences, triggers, life context) and auto-extracted memory fragments (people, events, preferences, facts) with temporal reasoning and expiry management
- **Tone personalization:** 4 adaptive modes (supportive, direct, gentle, motivational) adjusted to user preference and emotional state
- **Privacy mode:** Enhanced privacy mode disables all context injection — zero memory, zero re-engagement context
- **Streaming responses:** Server-Sent Events (SSE) for token-by-token delivery
- **Re-engagement intelligence:** Contextual warmth calibration based on absence duration (3 days / 7 days / 30+ days)

---

## Clinical Psychology Foundations

MindFriend's feature set is grounded in established clinical psychology and neuroscience research:

| Framework                                         | Application in MindFriend                                                                                                            |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| **Polyvagal Theory** (Porges, 1994)               | Nervous system state classification from voice prosody, HRV, and behavioral signals; cascade detection for dysregulation progression |
| **Cognitive Behavioral Therapy** (Beck, 1979)     | 12-type cognitive distortion detection with Socratic questioning, psychoeducation, and guided reframing                              |
| **Behavioral Activation**                         | Gamified daily quest system with streak mechanics, XP progression, and badge achievements to combat behavioral withdrawal            |
| **Heart Rate Variability** as autonomic biomarker | Real-time HRV monitoring via HealthKit/Apple Watch as a proxy for autonomic nervous system regulation and stress response            |
| **Circadian Rhythm Science**                      | Sleep pattern analysis for vulnerability window detection and optimal intervention timing                                            |
| **Exposure & Response Prevention**                | Conversation Rehearsal Studio for anxiety-provoking social scenarios with role-play practice                                         |
| **Mindfulness-Based Stress Reduction**            | 45-exercise library spanning breathing (10), meditation (12), grounding (8), journaling (8), and movement (7)                        |
| **Social Support Theory**                         | Private friend circles with daily check-ins, peer encouragement, and community wisdom sharing                                        |

---

## Safety & Crisis Intervention

Safety is the highest-priority design constraint in MindFriend. The system implements defense-in-depth for mental health crisis scenarios:

### Multi-Language Crisis Detection

- **41 crisis keywords** across 3 languages (English: 11, Spanish: 15, Portuguese-BR: 15)
- Redundant detection: always checks both user's language AND English keywords
- Matched keyword logged to `crisis_events` — never the user's actual message content (PII protection)
- Immediate response: blocks normal AI response, returns standardized crisis template with 988 Suicide & Crisis Lifeline, Crisis Text Line, and IASP international resources

### Therapist Alert System

- When crisis keywords are detected and a therapist connection exists with `crisis_alerts_enabled`, the system automatically sends push notifications to the connected therapist
- All therapist notifications logged to immutable `therapy_access_log` audit trail
- Therapist data access governed by RLS policies requiring active, verified connections

### Prompt Injection Prevention

Multi-layer input sanitization protects the AI system from adversarial manipulation:

- Role impersonation blocking (`system:`, `assistant:`, `user:` prefix stripping)
- LLM delimiter neutralization (`[INST]`, `<<SYS>>`, `<|...|>`)
- Instruction override detection ("ignore all previous instructions")
- Jailbreak pattern blocking (DAN, "do anything now", "pretend you're evil")
- Roleplay escape prevention ("stop being helpful", "exit character")
- Token stuffing prevention (4,000 character input limit)

### Privacy Architecture

- **Enhanced privacy mode:** Zero context injection — no memories, no re-engagement context, no behavioral signals fed to AI
- **On-device voice processing:** Emotion analysis via Core ML — audio never leaves the device
- **Multi-layer encryption:** AES-256-GCM for time capsules with per-capsule keys, HMAC metadata integrity signatures, device-only Keychain storage (no iCloud sync) for vault content
- **Row Level Security:** All database tables enforce user-level data isolation at the PostgreSQL level
- **Fail-closed rate limiting:** Rate limiter defaults to denied on database errors
- **Timing-safe comparisons:** Constant-time string comparison for security-critical operations (prevents timing attacks on service keys)

---

## Architecture

```
                    ┌─────────────────────────────────┐
                    │         iOS Client (SwiftUI)     │
                    │                                  │
                    │  79 Feature Modules               │
                    │  70+ Injected Services            │
                    │  Core ML (Voice Emotion)          │
                    │  HealthKit (HRV, HR, Sleep)       │
                    │  ARKit (Grounding Exercises)      │
                    │  StoreKit 2 (Subscriptions)       │
                    └──────────────┬──────────────────┘
                                   │
                         HTTPS / WSS / SSE
                                   │
                    ┌──────────────▼──────────────────┐
                    │      Supabase Platform           │
                    │                                  │
                    │  Auth (Apple, Google, Email/PKCE) │
                    │  PostgreSQL + Row Level Security  │
                    │  208 Edge Functions (Deno/TS)     │
                    │  Realtime (WebSocket)             │
                    │  Storage (Audio/Media)            │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │       External Services          │
                    │                                  │
                    │  xAI (Grok) — AI Conversations   │
                    │  APNs — Push Notifications        │
                    │  App Store Server API — Billing   │
                    └─────────────────────────────────┘
```

**iOS Architecture:** MVVM with centralized `DependencyContainer` providing 70+ lazy-loaded services via SwiftUI environment injection. Full `@MainActor` isolation for thread safety. Modern Swift concurrency throughout (async/await, structured concurrency, no legacy callback patterns).

**Backend Architecture:** Supabase-only (no separate API server). All business logic in 208 Edge Functions with Row Level Security enforcing data isolation at the database level. Atomic operations via PostgreSQL RPCs for race-condition-critical flows (quota enforcement, streak protection, rate limiting).

**Data Flow:** Offline-first design with `SyncQueueManager` for pending operations, exponential backoff retry, and optimistic UI patterns. Real-time updates via Supabase Realtime channels. AI responses streamed via Server-Sent Events.

---

## Technical Highlights

- **Modern Swift Concurrency:** async/await, @MainActor isolation, structured concurrency with Task cancellation, parallel execution via `async let`
- **Multi-Layer Encryption:** AES-256-GCM with per-record keys for time capsules, HMAC metadata integrity verification, device-bound Keychain storage (non-exportable)
- **Offline-First Sync:** `OfflineStorageManager` + `SyncQueueManager` with connectivity monitoring, exponential backoff, and queue persistence
- **Real-Time Streaming:** Supabase Realtime channels for social features, SSE for AI response streaming
- **StoreKit 2 Server Verification:** JWS signature validation against Apple's public keys with two-pass strategy (production + sandbox fallback), cross-account prevention, idempotent transaction processing
- **Subscription Tiers:** Individual, Couples (2 seats), and Family (6 seats) plans with cryptographic invite code generation and seat management
- **AR Grounding Exercises:** ARKit integration with device capability detection (TrueDepth, LiDAR) and graceful fallback for unsupported devices
- **Accessibility:** Dynamic Type (including accessibility sizes), VoiceOver labels on all interactive elements, configurable letter spacing, color blind modes, high contrast support
- **Internationalization:** Full localization in English, Spanish, and Portuguese-Brazilian with culturally-adapted crisis detection keywords

---

## Tech Stack

| Layer                  | Technology                                                          |
| ---------------------- | ------------------------------------------------------------------- |
| **iOS Client**         | SwiftUI, Swift 5.9+, iOS 17+                                        |
| **On-Device AI**       | Core ML (emotion classification)                                    |
| **Augmented Reality**  | ARKit (grounding exercises)                                         |
| **Biometrics**         | HealthKit (HRV, heart rate, sleep), WatchConnectivity               |
| **Payments**           | StoreKit 2 with server-side JWS verification                        |
| **Backend**            | Supabase (PostgreSQL, Edge Functions/Deno, Realtime, Storage, Auth) |
| **AI Provider**        | xAI (Grok) via Edge Functions                                       |
| **Authentication**     | Sign in with Apple, Google OAuth, Email/PKCE                        |
| **Encryption**         | AES-256-GCM, HMAC-SHA256, Keychain Services                         |
| **Data Security**      | Row Level Security (RLS), JWT/PKCE, timing-safe comparisons         |
| **Push Notifications** | APNs with ES256 JWT authentication, 50-min token cache              |
| **Monitoring**         | Sentry (crash reporting), Firebase Analytics                        |
| **Localization**       | English, Spanish, Portuguese-Brazilian                              |

---

## Project Scale

| Metric                           | Count                   |
| -------------------------------- | ----------------------- |
| Swift source files               | 747                     |
| Feature modules                  | 79                      |
| Edge Functions (Deno/TypeScript) | 208                     |
| Test files                       | 1,479                   |
| Injected services                | 70+                     |
| Database tables                  | 25+                     |
| RLS policies                     | 40+                     |
| Cognitive distortion types       | 12                      |
| Therapeutic exercises            | 45                      |
| Achievement badges               | 29                      |
| Crisis detection keywords        | 41 (across 3 languages) |
| Notification types               | 24+                     |
| Supported languages              | 3                       |

---

## Roadmap

| Direction                 | Description                                                                                                |
| ------------------------- | ---------------------------------------------------------------------------------------------------------- |
| **Federated Learning**    | On-device model personalization without centralizing sensitive mental health data                          |
| **Wearable Expansion**    | Dedicated Apple Watch app for continuous HRV/stress monitoring with haptic interventions                   |
| **Clinical Validation**   | IRB-approved efficacy study comparing MindFriend-augmented vs. standard care outcomes                      |
| **Provider Dashboard**    | Therapist-facing portal for monitoring client progress with consent-gated data sharing                     |
| **Multimodal Biomarkers** | Integrating additional physiological signals (EDA, skin temperature) for richer autonomic state estimation |

---

## License

Proprietary. All rights reserved.

---

<p align="center">
  <em>Building intelligent systems at the intersection of AI and mental health — because access to emotional wellbeing support shouldn't depend on geography, income, or stigma.</em>
</p>
