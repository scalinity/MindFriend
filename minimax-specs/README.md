# MindFriend Minimax Specifications

**Breakthrough Features from App Analysis + Quick Wins**

This directory contains detailed specifications for new feature development, including the top 10 breakthrough features and quick win enhancements identified in the App Analysis.

## Breakthrough Features (Priority Order)

| Priority | File | Name | Scores | Description |
|----------|------|------|--------|-------------|
| #1 | `02-conversation-rehearsal-spec.md` | Conversation Rehearsal Studio | Delight 8/10 \| Diff 7/10 | Role-play with AI for difficult conversations with tone rewrites. |
| #2 | `03-cognitive-bias-coach-spec.md` | Real-Time Cognitive Bias Coach | Delight 8/10 \| Diff 7/10 | Detect distortions during chat and offer gentle reframes. |
| #3 | `04-boundary-planner-spec.md` | Boundary & Needs Planner | Delight 8/10 \| Diff 7/10 | Guided tool to clarify needs, set boundaries, generate scripts. |
| #4 | `13-camera-biofeedback-spec.md` | Camera Biofeedback Breathing Coach | Delight 8/10 \| Diff 8/10 | On-device camera respiration detection for breathing guidance. |
| #5 | `12-emotion-aware-voice-spec.md` | Emotion-Aware Voice Companion | Delight 9/10 \| Diff 8/10 | Voice prosody analysis to adjust response pacing and empathy. |
| #6 | `14-adaptive-home-spec.md` | Adaptive Home Layout & Ritual Surfaces | Delight 7/10 \| Diff 7/10 | Home screen modules reorder based on time and behavior. |
| #7 | `06-stress-signature-explorer-spec.md` | Stress Signature Explorer | Delight 7/10 \| Diff 7/10 | Interactive map of internal triggers using in-app data. |
| #8 | `08-sensory-regulation-spec.md` | Sensory Regulation Toolkit | Delight 7/10 \| Diff 7/10 | Visual and haptic regulation patterns for discreet calming. |
| #9 | `11-values-compass-spec.md` | Values Compass & Decision Coach | Delight 7/10 \| Diff 6/10 | Values clarification tool with guided trade-offs. |
| #10 | `15-multimodal-engine-spec.md` | Multimodal Emotional State Engine | Delight 10/10 \| Diff 10/10 | **Moonshot** - Fusion of voice, typing, respiration for closed-loop co-regulation. |

## Quick Win Features

| Priority | File | Name | Effort | Description |
|----------|------|------|--------|-------------|
| #1 | `20-privacy-quick-lock-spec.md` | Privacy Quick Lock | Low | Optional app-level passcode/Face ID with auto-lock. |
| #2 | `21-chat-action-cards-spec.md` | Chat Action Cards | Low | Convert AI suggestions into one-tap actions. |
| #3 | `23-calm-screen-mode-spec.md` | Calm Screen Mode | Low | Low-stimulus UI preset with reduced motion/soft typography. |
| #4 | `22-rewrite-my-thought-spec.md` | One-Tap Rewrite My Thought | Medium | Instant reframing for selected chat messages. |

**Already Implemented:** Adaptive Tone Slider (aiTone enum in Models.swift:678-701)

## Implementation Roadmap

### Phase 1: Quick Wins (Low Effort, High Value)
1. Privacy Quick Lock
2. Chat Action Cards
3. Calm Screen Mode
4. One-Tap "Rewrite My Thought"

### Phase 2: Core Experience
1. Conversation Rehearsal Studio
2. Real-Time Cognitive Bias Coach
3. Boundary & Needs Planner

### Phase 3: Emotional Intelligence
1. Emotion-Aware Voice Companion
2. Camera Biofeedback Breathing Coach

### Phase 4: Personalization
1. Adaptive Home Layout
2. Stress Signature Explorer
3. Sensory Regulation Toolkit
4. Values Compass & Decision Coach

### Phase 5: Moonshot
1. Multimodal Emotional State Engine

## Feature Summary

### Core Experience
- **Conversation Rehearsal Studio** - Practice difficult conversations with AI role-play
- **Real-Time Cognitive Bias Coach** - Chat distortion detection
- **Boundary & Needs Planner** - Practical life tool for boundaries
- **One-Tap Rewrite My Thought** - Cognitive reframing in chat

### Emotional Intelligence
- **Emotion-Aware Voice Companion** - Voice prosody analysis
- **Multimodal Emotional State Engine** - Fusion of all signals
- **Stress Signature Explorer** - Pattern visualization

### Regulation & Breathing
- **Camera Biofeedback Breathing Coach** - Camera-based respiration
- **Sensory Regulation Toolkit** - Non-audio calming

### Personalization
- **Adaptive Home Layout** - Contextual home surface
- **Values Compass & Decision Coach** - Values-based decisions
- **Privacy Quick Lock** - Security layer
- **Chat Action Cards** - One-tap actions
- **Calm Screen Mode** - Sensory-friendly UI

## Spec Format

Each specification includes:
- Feature Analysis (purpose, users, dependencies)
- Feature Overview (name, description, business justification)
- Functional Requirements (user stories, acceptance criteria)
- Technical Specifications (data models, API endpoints, integration points)
- User Interface (wireframes, user flows)
- Edge Cases and Error Handling
- Testing Requirements
- Implementation Notes
- Success Metrics

## Quick Reference

| Category | Files |
|----------|-------|
| Breakthrough Features | 02-15 (except quick wins) |
| Quick Wins | 20-23 |
| Already Implemented | Adaptive Tone Slider |

## Notes

- All specs include full SQL schemas for Supabase
- API endpoints follow Edge Function patterns
- UI mockups use ASCII wireframes
- Success metrics include specific targets
- Specs can be implemented independently or as part of phases
