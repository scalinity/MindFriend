# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Conversation Rehearsal Studio**: Practice difficult conversations with AI-powered roleplay
  - 21 pre-built scenarios across 6 categories (work, relationships, social, family, health, financial)
  - Custom scenario builder for personalized practice
  - Real-time feedback on communication style (assertive, empathetic, defensive, etc.)
  - Progress tracking with session history and bookmarks
  - Quota enforcement: Free tier (2 rehearsals/week, 10 exchanges/session), Premium (unlimited)
  - Crisis detection and safety escalation for self-harm content

### Fixed

- **Rehearsal Edge Function**: Fixed 10 critical bugs discovered in code review
  - Fixed AI character context loss in multi-turn conversations (system prompt now included in every exchange)
  - Fixed double-charging for custom scenarios (creation is now free, only session start costs quota)
  - Fixed transcript null safety to prevent crashes on corrupted data
  - Fixed division by zero in average score calculations
  - Fixed feedback timing off-by-one error in exchange counting
  - Fixed null feedback insertion errors
  - Replaced undefined `callXAI` with `callXaiWithRetry` for proper error handling
  - Added missing `scenario` parameter to feedback generation calls
  - Removed manual quota increment (now handled by atomic RPC)

### Security

- **Rehearsal Prompt Injection Prevention**: Added sanitization for all user-submitted scenario fields
  - Escapes system/assistant/user markers to prevent prompt hijacking
  - Enforces max length (1000 chars) per field
  - Removes control characters from user input

### Performance

- **Atomic Quota Enforcement**: Implemented database-level row locking to prevent race conditions
  - Uses `SELECT ... FOR UPDATE` to ensure atomic quota check-and-increment
  - Eliminates TOCTOU vulnerability where concurrent requests could bypass quota limits
  - Returns structured result with {allowed, remaining, is_premium, reason}

## [0.1.0] - 2026-01-20

### Added

- Initial MindFriend MVP implementation
  - Authentication (Apple, Google, Email)
  - AI chat companion with crisis detection
  - Daily quests with streaks and badges
  - Mood logging and history
  - Friend circles with daily check-ins
  - Exercise library (45 exercises across 5 types)
  - StoreKit 2 subscription management
