import SwiftUI
import Combine
import Supabase

// MARK: - Global Supabase Client Reference
// We capture the global `supabase` constant here BEFORE defining DependencyContainer,
// which has a computed property also named `supabase`. This avoids shadowing issues.
private let _globalSupabaseClient: SupabaseClient = supabase

/// Dependency injection container for all app services
@MainActor
final class DependencyContainer: ObservableObject {
    /// Reference to the global Supabase client (defined in SupabaseClient.swift)
    /// Captured via _globalSupabaseClient to avoid circular reference issues.
    let supabaseClient: SupabaseClient = _globalSupabaseClient

    // MARK: - Supabase Services
    lazy var supabaseAuthService: SupabaseAuthService = {
        SupabaseAuthService()
    }()

    lazy var supabaseDataService: SupabaseDataService = {
        SupabaseDataService(authService: supabaseAuthService)
    }()

    // MARK: - Feature Services
    lazy var chatService: ChatService = {
        ChatService(dataService: supabaseDataService)
    }()

    lazy var billingService: BillingService = {
        BillingService(authService: supabaseAuthService)
    }()
    
    lazy var coachService: CoachService = {
        CoachService(supabase: self.supabaseClient)
    }()

    // TODO: Fix GrokVoiceService compilation errors (inputNode, isPlayerPlaying references)
    // lazy var grokVoiceService: GrokVoiceService = {
    //     GrokVoiceService(supabase: self.supabaseClient)
    // }()

    lazy var liveService: LiveService = {
        LiveService()
    }()

    lazy var creativeExpressionService: CreativeExpressionService = {
        CreativeExpressionService()
    }()

    lazy var personalizationService: PersonalizationService = {
        PersonalizationService(supabase: self.supabaseClient)
    }()

    lazy var accessibilityService: AccessibilityService = {
        AccessibilityService(supabase: self.supabaseClient)
    }()

    lazy var localizationService: LocalizationService = {
        LocalizationService(supabase: self.supabaseClient)
    }()

    lazy var actionPlanService: ActionPlanService = {
        ActionPlanService(authService: supabaseAuthService, supabase: supabaseClient)
    }()

    lazy var privacyLockManager: PrivacyLockManager = {
        PrivacyLockManager.shared
    }()

    lazy var achievementService: AchievementService = {
        AchievementService(
            supabase: self.supabaseClient,
            authService: self.supabaseAuthService
        )
    }()

    lazy var photoMoodService: PhotoMoodService = {
        PhotoMoodService(supabase: self.supabaseClient)
    }()

    lazy var therapyIntegrationService: TherapyIntegrationService = {
        TherapyIntegrationService(supabase: self.supabaseClient)
    }()

    lazy var therapistService: TherapistService = {
        TherapistService(supabase: self.supabaseClient)
    }()

    lazy var familyService: FamilyService = {
        FamilyService(supabase: self.supabaseClient)
    }()

    lazy var sleepService: SleepService = {
        SleepService(supabase: self.supabaseClient)
    }()

    // Sleep Tracking Services
    lazy var sleepTrackingService: SleepTrackingService = {
        SleepTrackingService(supabase: self.supabaseClient)
    }()

    lazy var sleepHealthKitManager: SleepHealthKitManager = {
        SleepHealthKitManager(sleepTrackingService: self.sleepTrackingService)
    }()

    lazy var difficultyService: DifficultyService = {
        DifficultyService(supabase: self.supabaseClient)
    }()

    lazy var audioPlayerService: AudioPlayerService = {
        AudioPlayerService(supabase: self.supabaseClient)
    }()

    // MARK: - Daily Briefing (F009)

    lazy var calendarService: CalendarService = {
        CalendarService()
    }()

    lazy var dailyBriefingService: DailyBriefingService = {
        DailyBriefingService(supabase: self.supabaseClient)
    }()

    lazy var dailyBriefingViewModel: DailyBriefingViewModel = {
        DailyBriefingViewModel(
            briefingService: self.dailyBriefingService,
            calendarService: self.calendarService
        )
    }()

    // MARK: - Sensory Regulation Services

    lazy var tactilePatternService: TactilePatternService = {
        TactilePatternService()
    }()

    lazy var visualAnimationService: VisualAnimationService = {
        VisualAnimationService()
    }()

    lazy var audioSoundscapeService: AudioSoundscapeService = {
        AudioSoundscapeService()
    }()

    lazy var sensoryRegulationService: SensoryRegulationService = {
        SensoryRegulationService(
            supabase: supabaseDataService,
            tactileService: tactilePatternService,
            visualService: visualAnimationService,
            audioService: audioSoundscapeService,
            achievementService: achievementService
        )
    }()

    lazy var valuesService: ValuesService = {
        ValuesService(supabase: self.supabaseClient)
    }()

    // MARK: - Medication Services
    lazy var medicationRepository: MedicationRepository = {
        SupabaseMedicationRepository(supabase: supabaseClient)
    }()

    lazy var medicationLogRepository: MedicationLogRepository = {
        SupabaseMedicationLogRepository(supabase: supabaseClient)
    }()

    lazy var notificationScheduler: NotificationScheduler = {
        NotificationScheduler()
    }()

    lazy var adherenceCalculator: AdherenceCalculator = {
        AdherenceCalculator()
    }()

    lazy var medicationService: MedicationService = {
        MedicationService(
            medicationRepository: medicationRepository,
            logRepository: medicationLogRepository,
            notificationScheduler: notificationScheduler,
            adherenceCalculator: adherenceCalculator
        )
    }()

    lazy var companionMemoryService: CompanionMemoryService = {
        CompanionMemoryService(authService: supabaseAuthService, supabase: supabaseClient)
    }()

    lazy var questArcsService: QuestArcsService = {
        QuestArcsService(supabase: supabaseClient, difficultyService: difficultyService)
    }()

    lazy var insightLabService: InsightLabService = {
        InsightLabService(supabase: supabaseClient)
    }()

    lazy var ritualService: RitualService = {
        RitualService(supabase: supabaseClient)
    }()

    lazy var predictiveService: PredictiveService = {
        PredictiveService(authService: supabaseAuthService)
    }()

    lazy var outcomeService: OutcomeTrackingService = {
        OutcomeTrackingService(supabase: supabaseClient, authService: supabaseAuthService)
    }()

    // MARK: - SOS Services

    lazy var sosCoordinator: SOSCoordinator = {
        SOSCoordinator(supabase: supabaseClient)
    }()

    // MARK: - Smart Notification Services

    /// Context engine for aggregating calendar, location, biometric, and focus mode data
    lazy var contextEngine: ContextEngine = {
        ContextEngine()
    }()

    /// ML prediction engine for engagement probability
    lazy var predictionEngine: MLPredictionEngine = {
        MLPredictionEngine()
    }()

    /// Notification queue with bundling and priority handling
    lazy var notificationQueue: NotificationQueue = {
        NotificationQueue()
    }()

    /// Engagement tracker for ML training data
    lazy var engagementTracker: EngagementTracker = {
        EngagementTracker(supabaseDataService: supabaseDataService)
    }()

    /// Main smart notification orchestrator service
    lazy var smartNotificationService: SmartNotificationService = {
        SmartNotificationService(
            contextEngine: contextEngine,
            predictionEngine: predictionEngine,
            notificationQueue: notificationQueue,
            engagementTracker: engagementTracker,
            notificationManager: NotificationManager.shared,
            supabaseDataService: supabaseDataService
        )
    }()

    // MARK: - Vault Services (Local-only, encrypted journal)

    lazy var vaultEncryptionService: VaultEncryptionService = {
        VaultEncryptionService()
    }()

    lazy var vaultAuthService: VaultAuthService = {
        VaultAuthService()
    }()

    lazy var vaultStorageService: VaultStorageService = {
        VaultStorageService(encryptionService: vaultEncryptionService)
    }()

    lazy var vaultViewModel: VaultViewModel = {
        VaultViewModel(
            storageService: vaultStorageService,
            authService: vaultAuthService,
            encryptionService: vaultEncryptionService
        )
    }()

    // MARK: - Creator Services

    /// Service for content creator platform (profiles, content, earnings, marketplace)
    lazy var creatorService: CreatorService = {
        CreatorService(supabase: supabaseClient)
    }()

    // MARK: - Boundary Planner Service
    
    lazy var boundaryPlannerService: BoundaryPlannerService = {
        BoundaryPlannerService(supabase: supabaseClient)
    }()

    // MARK: - Nervous System State Engine Services
    
    lazy var healthKitService: HealthKitService = {
        HealthKitService.shared
    }()
    
    lazy var voicePolyvagalExtractor: VoicePolyvagalExtractor = {
        VoicePolyvagalExtractor()
    }()
    
    lazy var hrvPolyvagalExtractor: HRVPolyvagalExtractor = {
        HRVPolyvagalExtractor(healthKitService: healthKitService)
    }()
    
    lazy var behavioralPolyvagalTracker: BehavioralPolyvagalTracker = {
        BehavioralPolyvagalTracker()
    }()
    
    lazy var polyvagalClassifier: PolyvagalClassifier = {
        PolyvagalClassifier()
    }()
    
    lazy var cascadeDetector: CascadeDetector = {
        CascadeDetector()
    }()
    
    lazy var interventionRecommender: InterventionRecommender = {
        InterventionRecommender(supabase: supabaseClient)
    }()
    
    lazy var nervousSystemStateEngine: NervousSystemStateEngine = {
        NervousSystemStateEngine(
            voiceExtractor: voicePolyvagalExtractor,
            hrvExtractor: hrvPolyvagalExtractor,
            behavioralTracker: behavioralPolyvagalTracker,
            classifier: polyvagalClassifier,
            cascadeDetector: cascadeDetector,
            interventionRecommender: interventionRecommender,
            supabase: supabaseClient
        )
    }()

    // MARK: - Circadian Vulnerability Shield Services

    lazy var armorScheduler: ArmorScheduler = {
        ArmorScheduler()
    }()

    lazy var circadianEngine: CircadianVulnerabilityEngine = {
        CircadianVulnerabilityEngine(
            healthKitService: healthKitService,
            dataService: supabaseDataService
        )
    }()

    // MARK: - Cognitive Distortion Detection Services (F006)

    lazy var distortionPatternMatcher: DistortionPatternMatcher = {
        DistortionPatternMatcher()
    }()

    lazy var distortionRateLimiter: DistortionRateLimiter = {
        DistortionRateLimiter()
    }()

    lazy var cognitiveDistortionEngine: CognitiveDistortionEngine = {
        CognitiveDistortionEngine(
            supabase: supabaseClient,
            patternMatcher: distortionPatternMatcher,
            rateLimiter: distortionRateLimiter
        )
    }()

    // MARK: - Intervention Efficacy Services

    lazy var efficacyCalculator: EfficacyCalculator = {
        EfficacyCalculator()
    }()

    lazy var trajectoryTracker: TrajectoryTracker = {
        TrajectoryTracker(supabase: self.supabaseClient)
    }()

    lazy var efficacyRecommender: EfficacyBasedRecommender = {
        EfficacyBasedRecommender(supabase: self.supabaseClient)
    }()

    lazy var interventionEfficacyEngine: InterventionEfficacyEngine = {
        InterventionEfficacyEngine(
            tracker: self.trajectoryTracker,
            calculator: self.efficacyCalculator,
            recommender: self.efficacyRecommender,
            supabase: self.supabaseClient
        )
    }()

    // MARK: - Incomplete Feature Services (TODO: Add when features are ready)
    // lazy var microMomentsService: MicroMomentsService
    // lazy var peerSupportService: PeerSupportService
    // lazy var audioPlayerService: AudioPlayerService
    // lazy var audioContentService: AudioContentService

    // MARK: - Initialization

    // MARK: - Shared Instance

    /// Shared singleton instance for the app
    static let shared = DependencyContainer()

    /// Convenience accessor for Supabase client (alias for supabaseClient)
    var supabase: SupabaseClient { supabaseClient }

    // MARK: - Preview Support


    /// Preview instance for SwiftUI previews
    static var preview: DependencyContainer {
        DependencyContainer()
    }
}
