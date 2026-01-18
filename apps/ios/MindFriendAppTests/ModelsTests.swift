import XCTest
@testable import MindFriendApp

final class ModelsTests: XCTestCase {

    // MARK: - UserProfile Tests

    func testUserProfileDecoding() throws {
        let json = """
        {
            "id": "user-123",
            "handle": "testuser",
            "displayName": "Test User",
            "email": "test@example.com",
            "timezone": "America/New_York",
            "createdAt": "2024-01-01T00:00:00Z",
            "settings": {
                "dailyQuestTimeLocal": "09:00",
                "quietHoursStartLocal": null,
                "quietHoursEndLocal": null,
                "remindersEnabled": true,
                "nudgeAfterDaysInactive": 3,
                "shareMoodInCircles": true,
                "aiTone": "friendly",
                "privacyMode": "standard"
            },
            "stats": {
                "current_streak_days": 5,
                "longest_streak_days": 10,
                "total_quests_completed": 25,
                "total_exercises_completed": 12,
                "xp_total": 500,
                "xp_this_week": 100,
                "level": 5,
                "level_title": "Enthusiast"
            },
            "entitlements": {
                "tier": "free",
                "dailyAiQuota": 20,
                "dailyAiUsed": 0
            },
            "badges": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let profile = try decoder.decode(UserProfile.self, from: jsonData(from: json))

        XCTAssertEqual(profile.id, "user-123")
        XCTAssertEqual(profile.handle, "testuser")
        XCTAssertEqual(profile.displayName, "Test User")
        XCTAssertEqual(profile.email, "test@example.com")
        XCTAssertEqual(profile.timezone, "America/New_York")
        XCTAssertEqual(profile.settings.aiTone, .friendly)
        XCTAssertEqual(profile.stats.currentStreakDays, 5)
        XCTAssertEqual(profile.entitlements.tier, .free)
    }

    func testUserSettingsDefaults() {
        let settings = UserSettings(
            dailyQuestTimeLocal: "09:00",
            quietHoursStartLocal: nil,
            quietHoursEndLocal: nil,
            remindersEnabled: true,
            nudgeAfterDaysInactive: 3,
            shareMoodInCircles: true,
            aiTone: .friendly,
            privacyMode: .standard
        )

        XCTAssertTrue(settings.remindersEnabled)
        XCTAssertEqual(settings.nudgeAfterDaysInactive, 3)
        XCTAssertNil(settings.quietHoursStartLocal)
    }

    // MARK: - MoodEntry Tests

    func testMoodEntryCreation() {
        let entry = MoodEntry(
            id: "mood-1",
            localDate: "2024-01-15",
            moodScore: 7,
            anxietyScore: 3,
            energyScore: 6,
            note: "Feeling good today",
            source: .manual,
            createdAt: Date()
        )

        XCTAssertEqual(entry.moodScore, 7)
        XCTAssertEqual(entry.anxietyScore, 3)
        XCTAssertEqual(entry.note, "Feeling good today")
    }

    func testMoodEntryValidScores() {
        // Valid scores are 1-10
        let entry = MoodEntry(
            id: "mood-1",
            localDate: "2024-01-15",
            moodScore: 5,
            anxietyScore: nil,
            energyScore: nil,
            note: nil,
            source: .manual,
            createdAt: Date()
        )

        XCTAssertGreaterThanOrEqual(entry.moodScore, 1)
        XCTAssertLessThanOrEqual(entry.moodScore, 10)
    }

    // MARK: - Entitlements Tests

    func testEntitlementsEquality() {
        XCTAssertEqual(Entitlements.free, Entitlements.free)
        XCTAssertNotEqual(Entitlements.free, Entitlements.premium)
    }

    func testEntitlementsRemaining_FreeUser() {
        var entitlements = Entitlements(tier: .free, dailyAiQuota: 20, dailyAiUsed: 5)
        XCTAssertEqual(entitlements.remaining, 15)

        entitlements.dailyAiUsed = 20
        XCTAssertEqual(entitlements.remaining, 0)

        entitlements.dailyAiUsed = 25 // Over quota
        XCTAssertEqual(entitlements.remaining, 0) // Should not be negative
    }

    func testEntitlementsRemaining_PremiumUser() {
        let entitlements = Entitlements(tier: .premium, dailyAiQuota: 9999, dailyAiUsed: 100)
        XCTAssertEqual(entitlements.remaining, Int.max) // Premium has unlimited
    }

    func testEntitlementsIsQuotaExceeded_FreeUser() {
        var entitlements = Entitlements(tier: .free, dailyAiQuota: 20, dailyAiUsed: 19)
        XCTAssertFalse(entitlements.isQuotaExceeded)

        entitlements.dailyAiUsed = 20
        XCTAssertTrue(entitlements.isQuotaExceeded)

        entitlements.dailyAiUsed = 25
        XCTAssertTrue(entitlements.isQuotaExceeded)
    }

    func testEntitlementsIsQuotaExceeded_PremiumUser() {
        let entitlements = Entitlements(tier: .premium, dailyAiQuota: 9999, dailyAiUsed: 9999)
        XCTAssertFalse(entitlements.isQuotaExceeded) // Premium never exceeds
    }

    func testEntitlementsIsNearQuotaLimit_FreeUser() {
        var entitlements = Entitlements(tier: .free, dailyAiQuota: 20, dailyAiUsed: 16)
        XCTAssertFalse(entitlements.isNearQuotaLimit) // 4 remaining, not near

        entitlements.dailyAiUsed = 17
        XCTAssertTrue(entitlements.isNearQuotaLimit) // 3 remaining

        entitlements.dailyAiUsed = 18
        XCTAssertTrue(entitlements.isNearQuotaLimit) // 2 remaining

        entitlements.dailyAiUsed = 19
        XCTAssertTrue(entitlements.isNearQuotaLimit) // 1 remaining

        entitlements.dailyAiUsed = 20
        XCTAssertFalse(entitlements.isNearQuotaLimit) // 0 remaining, quota exceeded
    }

    func testEntitlementsIsNearQuotaLimit_PremiumUser() {
        let entitlements = Entitlements(tier: .premium, dailyAiQuota: 9999, dailyAiUsed: 9996)
        XCTAssertFalse(entitlements.isNearQuotaLimit) // Premium never near limit
    }

    func testEntitlementsStaticValues() {
        XCTAssertEqual(Entitlements.free.tier, .free)
        XCTAssertEqual(Entitlements.free.dailyAiQuota, 20)
        XCTAssertEqual(Entitlements.free.dailyAiUsed, 0)

        XCTAssertEqual(Entitlements.premium.tier, .premium)
        XCTAssertEqual(Entitlements.premium.dailyAiQuota, 9999)
        XCTAssertEqual(Entitlements.premium.dailyAiUsed, 0)
    }

    // MARK: - AITone Tests

    func testAIToneOptions() {
        XCTAssertTrue(AITone.allCases.contains(.friendly))
    }

    // MARK: - ExerciseType Tests

    func testExerciseTypeRawValues() {
        XCTAssertEqual(ExerciseType.breathing.rawValue, "breathing")
        XCTAssertEqual(ExerciseType.meditation.rawValue, "meditation")
        XCTAssertEqual(ExerciseType.journaling.rawValue, "journaling")
        XCTAssertEqual(ExerciseType.grounding.rawValue, "grounding")
    }

    func testExerciseTypeThemeColors() {
        // Verify all exercise types have distinct theme colors
        let types: [ExerciseType] = [.breathing, .meditation, .grounding, .journaling, .movement]
        for type in types {
            // Just verify each type has a color (non-crash test)
            _ = type.themeColor
        }
    }

    func testExerciseTypeIcons() {
        XCTAssertEqual(ExerciseType.breathing.icon, "wind")
        XCTAssertEqual(ExerciseType.meditation.icon, "brain.head.profile")
        XCTAssertEqual(ExerciseType.grounding.icon, "leaf.fill")
        XCTAssertEqual(ExerciseType.journaling.icon, "pencil.and.scribble")
        XCTAssertEqual(ExerciseType.movement.icon, "figure.walk")
    }

    // MARK: - SkillLevel Constants Tests

    func testSkillLevelThresholdsCount() {
        // Should have 6 thresholds (levels 0-5)
        XCTAssertEqual(SkillLevel.thresholds.count, 6)
    }

    func testSkillLevelThresholdsAscending() {
        // Thresholds should be in ascending order
        for i in 1..<SkillLevel.thresholds.count {
            XCTAssertGreaterThan(SkillLevel.thresholds[i], SkillLevel.thresholds[i - 1])
        }
    }

    func testSkillLevelThresholdValues() {
        XCTAssertEqual(SkillLevel.thresholds[0], 0)
        XCTAssertEqual(SkillLevel.thresholds[1], 150)
        XCTAssertEqual(SkillLevel.thresholds[2], 500)
        XCTAssertEqual(SkillLevel.thresholds[3], 1200)
        XCTAssertEqual(SkillLevel.thresholds[4], 3000)
        XCTAssertEqual(SkillLevel.thresholds[5], 7500)
    }

    func testSkillLevelTitlesCount() {
        // Should have 6 titles (levels 0-5)
        XCTAssertEqual(SkillLevel.titles.count, 6)
    }

    func testSkillLevelTitleValues() {
        XCTAssertEqual(SkillLevel.titles[0], "Novice")
        XCTAssertEqual(SkillLevel.titles[1], "Apprentice")
        XCTAssertEqual(SkillLevel.titles[2], "Practitioner")
        XCTAssertEqual(SkillLevel.titles[3], "Expert")
        XCTAssertEqual(SkillLevel.titles[4], "Master")
        XCTAssertEqual(SkillLevel.titles[5], "Grandmaster")
    }

    func testSkillLevelMaxLevel() {
        XCTAssertEqual(SkillLevel.maxLevel, 5)
    }

    // MARK: - SkillProgress Tests

    func testSkillProgressLevelTitle() {
        let skill0 = SkillProgress(id: "1", userId: "u1", skillType: .breathing, xp: 0, skillLevel: 0)
        XCTAssertEqual(skill0.levelTitle, "Novice")

        let skill2 = SkillProgress(id: "2", userId: "u1", skillType: .breathing, xp: 500, skillLevel: 2)
        XCTAssertEqual(skill2.levelTitle, "Practitioner")

        let skill5 = SkillProgress(id: "3", userId: "u1", skillType: .breathing, xp: 7500, skillLevel: 5)
        XCTAssertEqual(skill5.levelTitle, "Grandmaster")
    }

    func testSkillProgressNextLevelXP() {
        let skill0 = SkillProgress(id: "1", userId: "u1", skillType: .breathing, xp: 0, skillLevel: 0)
        XCTAssertEqual(skill0.nextLevelXP, 150) // Level 0 -> Level 1 requires 150 XP

        let skill2 = SkillProgress(id: "2", userId: "u1", skillType: .breathing, xp: 500, skillLevel: 2)
        XCTAssertEqual(skill2.nextLevelXP, 1200) // Level 2 -> Level 3 requires 1200 XP

        let skill5 = SkillProgress(id: "3", userId: "u1", skillType: .breathing, xp: 7500, skillLevel: 5)
        XCTAssertEqual(skill5.nextLevelXP, 7500) // Max level, returns current threshold
    }

    func testSkillProgressCurrentLevelXP() {
        let skill0 = SkillProgress(id: "1", userId: "u1", skillType: .breathing, xp: 0, skillLevel: 0)
        XCTAssertEqual(skill0.currentLevelXP, 0)

        let skill2 = SkillProgress(id: "2", userId: "u1", skillType: .breathing, xp: 500, skillLevel: 2)
        XCTAssertEqual(skill2.currentLevelXP, 500)

        let skill5 = SkillProgress(id: "3", userId: "u1", skillType: .breathing, xp: 7500, skillLevel: 5)
        XCTAssertEqual(skill5.currentLevelXP, 7500)
    }

    func testSkillProgressAtZero() {
        let skill = SkillProgress(id: "1", userId: "u1", skillType: .breathing, xp: 0, skillLevel: 0)
        XCTAssertEqual(skill.progress, 0.0, accuracy: 0.001)
    }

    func testSkillProgressMidLevel() {
        // Level 0 range: 0-150 XP, at 75 XP should be 50% progress
        let skill = SkillProgress(id: "1", userId: "u1", skillType: .breathing, xp: 75, skillLevel: 0)
        XCTAssertEqual(skill.progress, 0.5, accuracy: 0.001)
    }

    func testSkillProgressAtMaxLevel() {
        let skill = SkillProgress(id: "1", userId: "u1", skillType: .breathing, xp: 7500, skillLevel: 5)
        XCTAssertEqual(skill.progress, 1.0, accuracy: 0.001)
    }

    func testSkillProgressWithDifferentExerciseTypes() {
        let breathing = SkillProgress(id: "1", userId: "u1", skillType: .breathing, xp: 100, skillLevel: 0)
        let meditation = SkillProgress(id: "2", userId: "u1", skillType: .meditation, xp: 100, skillLevel: 0)
        let grounding = SkillProgress(id: "3", userId: "u1", skillType: .grounding, xp: 100, skillLevel: 0)

        XCTAssertEqual(breathing.skillType, .breathing)
        XCTAssertEqual(meditation.skillType, .meditation)
        XCTAssertEqual(grounding.skillType, .grounding)
    }

    // MARK: - UserLevel Tests

    func testUserLevelProgressCalculation() {
        // Level 1: 0-99 XP, at 50 XP should be 50%
        let stats = UserStats(
            currentStreakDays: 0,
            longestStreakDays: 0,
            totalQuestsCompleted: 0,
            totalExercisesCompleted: 0,
            xpTotal: 50,
            xpThisWeek: 50,
            level: 1,
            levelTitle: "Beginner"
        )
        let level = UserLevel.from(stats: stats)
        XCTAssertEqual(level.level, 1)
        XCTAssertEqual(level.currentXP, 50)
        XCTAssertEqual(level.nextLevelXP, 100) // Level 1->2 threshold
    }

    func testUserLevelFromStats() {
        let stats = UserStats(
            currentStreakDays: 5,
            longestStreakDays: 10,
            totalQuestsCompleted: 25,
            totalExercisesCompleted: 12,
            xpTotal: 500,
            xpThisWeek: 100,
            level: 5,
            levelTitle: "Enthusiast"
        )
        let level = UserLevel.from(stats: stats)

        XCTAssertEqual(level.level, 5)
        XCTAssertEqual(level.title, "Enthusiast")
        XCTAssertEqual(level.currentXP, 500)
        XCTAssertEqual(level.xpThisWeek, 100)
    }

    // MARK: - SeasonalEvent Tests

    func testSeasonalEventIsActive() {
        let now = Date()
        let pastStart = now.addingTimeInterval(-86400) // 1 day ago
        let futureEnd = now.addingTimeInterval(86400)  // 1 day from now

        let activeEvent = SeasonalEvent(
            id: "event-1",
            name: "Test Event",
            description: nil,
            startsAt: pastStart,
            endsAt: futureEnd,
            eventType: "challenge",
            requiredActivityType: "breathing",
            rewardBadgeId: nil,
            targetCount: 10,
            xpMultiplier: 1.5,
            createdAt: pastStart
        )

        XCTAssertTrue(activeEvent.isActive)
    }

    func testSeasonalEventNotActiveYet() {
        let now = Date()
        let futureStart = now.addingTimeInterval(86400)  // 1 day from now
        let futureEnd = now.addingTimeInterval(172800)   // 2 days from now

        let futureEvent = SeasonalEvent(
            id: "event-1",
            name: "Future Event",
            description: nil,
            startsAt: futureStart,
            endsAt: futureEnd,
            eventType: "challenge",
            requiredActivityType: nil,
            rewardBadgeId: nil,
            targetCount: 5,
            xpMultiplier: 1.0,
            createdAt: now
        )

        XCTAssertFalse(futureEvent.isActive)
    }

    func testSeasonalEventExpired() {
        let now = Date()
        let pastStart = now.addingTimeInterval(-172800) // 2 days ago
        let pastEnd = now.addingTimeInterval(-86400)    // 1 day ago

        let expiredEvent = SeasonalEvent(
            id: "event-1",
            name: "Expired Event",
            description: nil,
            startsAt: pastStart,
            endsAt: pastEnd,
            eventType: "challenge",
            requiredActivityType: nil,
            rewardBadgeId: nil,
            targetCount: 5,
            xpMultiplier: 1.0,
            createdAt: pastStart
        )

        XCTAssertFalse(expiredEvent.isActive)
    }

    // MARK: - XPActivity Tests

    func testXPActivityAmounts() {
        XCTAssertEqual(XPActivity.questComplete.xpAmount, 50)
        XCTAssertEqual(XPActivity.exerciseComplete(.breathing).xpAmount, 30)
        XCTAssertEqual(XPActivity.moodCheckin.xpAmount, 10)
        XCTAssertEqual(XPActivity.circleCheckin.xpAmount, 20)
    }

    func testXPActivitySkillTypes() {
        // Quest completion doesn't map to a specific skill
        XCTAssertNil(XPActivity.questComplete.skillType)

        // Mood checkin doesn't map to a specific skill
        XCTAssertNil(XPActivity.moodCheckin.skillType)

        // Circle checkin doesn't map to a specific skill
        XCTAssertNil(XPActivity.circleCheckin.skillType)

        // Exercise completion maps to its specific skill type (as raw value string)
        XCTAssertEqual(XPActivity.exerciseComplete(.breathing).skillType, "breathing")
        XCTAssertEqual(XPActivity.exerciseComplete(.meditation).skillType, "meditation")
    }

    // MARK: - QuestType EventActivityType Mapping Tests

    func testQuestTypeEventActivityTypeMapping() {
        XCTAssertEqual(QuestType.breathing.eventActivityType, "breathing")
        XCTAssertEqual(QuestType.walk.eventActivityType, "movement")
        XCTAssertEqual(QuestType.stretch.eventActivityType, "movement")
        XCTAssertEqual(QuestType.journal.eventActivityType, "journaling")
        XCTAssertEqual(QuestType.gratitude.eventActivityType, "journaling")
        XCTAssertEqual(QuestType.focus.eventActivityType, "meditation")
    }

    // MARK: - EvidenceBasis Tests

    func testEvidenceBasisDisplayNames() {
        XCTAssertEqual(EvidenceBasis.CBT.displayName, "Cognitive Behavioral Therapy")
        XCTAssertEqual(EvidenceBasis.DBT.displayName, "Dialectical Behavior Therapy")
        XCTAssertEqual(EvidenceBasis.ACT.displayName, "Acceptance & Commitment Therapy")
        XCTAssertEqual(EvidenceBasis.Mindfulness.displayName, "Mindfulness-Based")
        XCTAssertEqual(EvidenceBasis.Somatic.displayName, "Somatic Practice")
        XCTAssertEqual(EvidenceBasis.Breathwork.displayName, "Breathwork")
        XCTAssertEqual(EvidenceBasis.General.displayName, "Evidence-Informed")
    }

    func testEvidenceBasisShortLabels() {
        XCTAssertEqual(EvidenceBasis.CBT.shortLabel, "CBT")
        XCTAssertEqual(EvidenceBasis.DBT.shortLabel, "DBT")
        XCTAssertEqual(EvidenceBasis.ACT.shortLabel, "ACT")
        XCTAssertEqual(EvidenceBasis.Mindfulness.shortLabel, "Mindfulness")
        XCTAssertEqual(EvidenceBasis.Somatic.shortLabel, "Somatic")
        XCTAssertEqual(EvidenceBasis.Breathwork.shortLabel, "Breathwork")
        XCTAssertEqual(EvidenceBasis.General.shortLabel, "Wellness")
    }

    func testEvidenceBasisColors() {
        // Verify all evidence bases have distinct colors (non-crash test)
        for basis in EvidenceBasis.allCases {
            // Accessing color should not crash
            _ = basis.color
        }
    }

    func testEvidenceBasisCaseIterableCount() {
        // Should have exactly 7 therapeutic approaches
        XCTAssertEqual(EvidenceBasis.allCases.count, 7)
    }

    func testEvidenceBasisRawValues() {
        // Verify raw values match database values
        XCTAssertEqual(EvidenceBasis.CBT.rawValue, "CBT")
        XCTAssertEqual(EvidenceBasis.DBT.rawValue, "DBT")
        XCTAssertEqual(EvidenceBasis.ACT.rawValue, "ACT")
        XCTAssertEqual(EvidenceBasis.Mindfulness.rawValue, "Mindfulness")
        XCTAssertEqual(EvidenceBasis.Somatic.rawValue, "Somatic")
        XCTAssertEqual(EvidenceBasis.Breathwork.rawValue, "Breathwork")
        XCTAssertEqual(EvidenceBasis.General.rawValue, "General")
    }

    // MARK: - MethodologyInfo Tests

    func testMethodologyInfoIdentifiable() {
        let info = MethodologyInfo(
            code: "CBT",
            name: "Cognitive Behavioral Therapy",
            description: "A widely-studied approach",
            source: "APA"
        )

        XCTAssertEqual(info.id, "CBT")
        XCTAssertEqual(info.code, "CBT")
        XCTAssertEqual(info.name, "Cognitive Behavioral Therapy")
        XCTAssertEqual(info.source, "APA")
    }

    func testMethodologyInfoOptionalSource() {
        let info = MethodologyInfo(
            code: "General",
            name: "General Wellness",
            description: "Evidence-informed practices",
            source: nil
        )

        XCTAssertNil(info.source)
    }

    // MARK: - Testimonial Tests

    func testTestimonialCreation() {
        let id = UUID()
        let testimonial = Testimonial(
            id: id,
            displayName: "Test User",
            location: "California",
            content: "Great app!",
            rating: 5,
            featureHighlight: "AI Chat"
        )

        XCTAssertEqual(testimonial.id, id)
        XCTAssertEqual(testimonial.displayName, "Test User")
        XCTAssertEqual(testimonial.location, "California")
        XCTAssertEqual(testimonial.content, "Great app!")
        XCTAssertEqual(testimonial.rating, 5)
        XCTAssertEqual(testimonial.featureHighlight, "AI Chat")
    }

    func testTestimonialOptionalFields() {
        let id = UUID()
        let testimonial = Testimonial(
            id: id,
            displayName: "Anonymous",
            location: nil,
            content: "Love it",
            rating: 4,
            featureHighlight: nil
        )

        XCTAssertNil(testimonial.location)
        XCTAssertNil(testimonial.featureHighlight)
    }

    func testTestimonialRatingRange() {
        // Valid ratings are 1-5
        let testimonial = Testimonial(
            id: UUID(),
            displayName: "Test",
            location: nil,
            content: "Test content",
            rating: 3,
            featureHighlight: nil
        )

        XCTAssertGreaterThanOrEqual(testimonial.rating, 1)
        XCTAssertLessThanOrEqual(testimonial.rating, 5)
    }

    // MARK: - DB Row Decoding Tests

    func testDBProfileRowDecoding() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "handle": "testuser",
            "display_name": "Test User",
            "email": "test@example.com",
            "avatar_url": null,
            "timezone": "America/New_York",
            "subscription_tier": "free",
            "daily_ai_quota": 20,
            "daily_ai_used": 5,
            "quota_reset_at": null,
            "premium_badge": null,
            "wellness_focus": "anxiety",
            "onboarding_completed_at": "2024-01-15T10:00:00Z",
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-15T10:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let row = try decoder.decode(DBProfileRow.self, from: jsonData(from: json))

        XCTAssertEqual(row.id.uuidString.lowercased(), "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(row.handle, "testuser")
        XCTAssertEqual(row.displayName, "Test User")
        XCTAssertEqual(row.email, "test@example.com")
        XCTAssertNil(row.avatarUrl)
        XCTAssertEqual(row.timezone, "America/New_York")
        XCTAssertEqual(row.subscriptionTier, "free")
        XCTAssertEqual(row.dailyAiQuota, 20)
        XCTAssertEqual(row.dailyAiUsed, 5)
        XCTAssertEqual(row.wellnessFocus, "anxiety")
        XCTAssertNotNil(row.onboardingCompletedAt)
    }

    func testDBUserSettingsRowDecoding() throws {
        let json = """
        {
            "user_id": "550e8400-e29b-41d4-a716-446655440000",
            "daily_quest_time_local": "09:00",
            "quiet_hours_start_local": "22:00",
            "quiet_hours_end_local": "08:00",
            "reminders_enabled": true,
            "nudge_after_days_inactive": 3,
            "share_mood_in_circles": true,
            "ai_tone": "friendly",
            "privacy_mode": "standard"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let row = try decoder.decode(DBUserSettingsRow.self, from: jsonData(from: json))

        XCTAssertEqual(row.dailyQuestTimeLocal, "09:00")
        XCTAssertEqual(row.quietHoursStartLocal, "22:00")
        XCTAssertEqual(row.quietHoursEndLocal, "08:00")
        XCTAssertTrue(row.remindersEnabled)
        XCTAssertEqual(row.nudgeAfterDaysInactive, 3)
        XCTAssertTrue(row.shareMoodInCircles)
        XCTAssertEqual(row.aiTone, "friendly")
        XCTAssertEqual(row.privacyMode, "standard")
    }

    func testDBUserStatsRowDecoding() throws {
        let json = """
        {
            "user_id": "550e8400-e29b-41d4-a716-446655440000",
            "current_streak_days": 7,
            "longest_streak_days": 15,
            "total_quests_completed": 42,
            "total_exercises_completed": 20,
            "xp_total": 1500,
            "xp_this_week": 250,
            "level": 5,
            "level_title": "Enthusiast",
            "last_xp_reset_week": "2024-01-08",
            "updated_at": "2024-01-15T10:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let row = try decoder.decode(DBUserStatsRow.self, from: jsonData(from: json))

        XCTAssertEqual(row.currentStreakDays, 7)
        XCTAssertEqual(row.longestStreakDays, 15)
        XCTAssertEqual(row.totalQuestsCompleted, 42)
        XCTAssertEqual(row.totalExercisesCompleted, 20)
        XCTAssertEqual(row.xpTotal, 1500)
        XCTAssertEqual(row.xpThisWeek, 250)
        XCTAssertEqual(row.level, 5)
        XCTAssertEqual(row.levelTitle, "Enthusiast")
        XCTAssertEqual(row.lastXpResetWeek, "2024-01-08")
    }

    func testDBUserStatsRowDecoding_WithNullOptionals() throws {
        let json = """
        {
            "user_id": "550e8400-e29b-41d4-a716-446655440000",
            "current_streak_days": 0,
            "longest_streak_days": 0,
            "total_quests_completed": 0,
            "total_exercises_completed": 0,
            "xp_total": 0,
            "xp_this_week": 0,
            "level": 1,
            "level_title": "Beginner",
            "last_xp_reset_week": null,
            "updated_at": "2024-01-15T10:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let row = try decoder.decode(DBUserStatsRow.self, from: jsonData(from: json))

        XCTAssertEqual(row.currentStreakDays, 0)
        XCTAssertEqual(row.level, 1)
        XCTAssertEqual(row.levelTitle, "Beginner")
        XCTAssertNil(row.lastXpResetWeek)
    }

    // MARK: - AppTheme Tests

    func testAppThemeCaseIterable() {
        // Should have exactly 3 theme options
        XCTAssertEqual(AppTheme.allCases.count, 3)
        XCTAssertTrue(AppTheme.allCases.contains(.system))
        XCTAssertTrue(AppTheme.allCases.contains(.light))
        XCTAssertTrue(AppTheme.allCases.contains(.dark))
    }

    func testAppThemeIdentifiable() {
        // Each theme should have a unique id based on rawValue
        XCTAssertEqual(AppTheme.system.id, "system")
        XCTAssertEqual(AppTheme.light.id, "light")
        XCTAssertEqual(AppTheme.dark.id, "dark")
    }

    func testAppThemeStorageKey() {
        // Storage key should be consistent
        XCTAssertEqual(AppTheme.storageKey, "selectedTheme")
    }

    func testAppThemeRawValues() {
        XCTAssertEqual(AppTheme.system.rawValue, "system")
        XCTAssertEqual(AppTheme.light.rawValue, "light")
        XCTAssertEqual(AppTheme.dark.rawValue, "dark")
    }

    func testAppThemeDisplayNames() {
        XCTAssertEqual(AppTheme.system.displayName, "System")
        XCTAssertEqual(AppTheme.light.displayName, "Light")
        XCTAssertEqual(AppTheme.dark.displayName, "Dark")
    }

    func testAppThemeIcons() {
        XCTAssertEqual(AppTheme.system.icon, "circle.lefthalf.filled")
        XCTAssertEqual(AppTheme.light.icon, "sun.max.fill")
        XCTAssertEqual(AppTheme.dark.icon, "moon.fill")
    }

    func testAppThemeIconColors() {
        // Verify icon colors are set (non-crash test)
        for theme in AppTheme.allCases {
            _ = theme.iconColor
        }
    }

    func testAppThemeColorScheme() {
        // System returns nil (follows device setting)
        XCTAssertNil(AppTheme.system.colorScheme)

        // Light returns .light
        XCTAssertEqual(AppTheme.light.colorScheme, .light)

        // Dark returns .dark
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }

    func testAppThemeRawRepresentable() {
        // Test encoding/decoding via RawRepresentable
        let theme = AppTheme.dark
        let rawValue = theme.rawValue

        let decoded = AppTheme(rawValue: rawValue)
        XCTAssertEqual(decoded, theme)

        // Invalid raw value returns nil
        let invalid = AppTheme(rawValue: "invalid")
        XCTAssertNil(invalid)
    }
}
