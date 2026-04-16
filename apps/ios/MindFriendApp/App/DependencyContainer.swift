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
        let service = SupabaseAuthService(secureStorage: secureStorage)
        // ✅ ARCHITECTURE FIX: Wire up logout handler to break circular dependency
        service.setLogoutHandler { [weak self] in
            self?.pathwayCacheService.clearAllCaches()
            // Clear UI-level session caches keyed only by time (not user id)
            // to prevent cross-user leakage on shared devices / account switch.
            ProgressStoryLoadCache.clear()
        }
        return service
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

    // MARK: - Voice Services
    // Note: GrokVoiceService is instantiated directly in VoiceModeView/VoiceChatView as @StateObject
    // Direct instantiation preferred for audio services requiring tight lifecycle management

    lazy var liveService: LiveService = {
        LiveService()
    }()

    lazy var creativeExpressionService: CreativeExpressionService = {
        CreativeExpressionService()
    }()

    lazy var transitionService: TransitionService = {
        // ✅ ARCHITECTURE FIX: Inject centralized services (no default parameters)
        TransitionService(
            supabase: self.supabaseClient,
            networkRetry: self.networkRetryService,
            cacheService: self.pathwayCacheService,
            encryptionService: self.pathwayEncryptionService
        )
    }()

    lazy var personalizationService: PersonalizationService = {
        PersonalizationService(
            supabase: self.supabaseClient,
            authService: self.supabaseAuthService
        )
    }()

    lazy var accessibilityService: AccessibilityService = {
        AccessibilityService(supabase: self.supabaseClient)
    }()

    lazy var localizationService: LocalizationService = {
        // Use the shared instance and configure it with Supabase
        let service = LocalizationService.shared
        service.configure(supabase: self.supabaseClient)
        return service
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

    lazy var activationService: ActivationService = {
        ActivationService(supabase: self.supabaseClient, authService: self.supabaseAuthService)
    }()

    // MARK: - Mentorship
    lazy var mentorshipService: MentorshipService = {
        let userId = self.supabaseAuthService.currentUser?.id ?? UUID()
        return MentorshipService(supabase: self.supabaseClient, userId: userId)
    }()

    lazy var sleepService: SleepService = {
        SleepService(supabase: self.supabaseClient)
    }()

    // MARK: - Ambient Wellness Presence

    lazy var ambientThemeService: AmbientThemeService = {
        AmbientThemeService(dataService: self.supabaseDataService)
    }()

    // Sleep Tracking Services
    lazy var sleepTrackingService: SleepTrackingService = {
        SleepTrackingService(
            supabase: self.supabaseClient,
            notificationService: self.bedtimeNotificationService
        )
    }()

    lazy var sleepHealthKitManager: SleepHealthKitManager = {
        SleepHealthKitManager(sleepTrackingService: self.sleepTrackingService)
    }()

    lazy var notificationPermissionManager: NotificationPermissionManaging = {
        NotificationPermissionManager()
    }()

    lazy var bedtimeNotificationService: BedtimeNotificationServicing = {
        BedtimeNotificationService(permissionManager: self.notificationPermissionManager)
    }()

    lazy var questNotificationService: QuestNotificationServicing = {
        QuestNotificationService(permissionManager: self.notificationPermissionManager)
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

    // MARK: - Wellbeing Debt Calculator (N006)

    lazy var wellbeingDebtService: WellbeingDebtService = {
        WellbeingDebtService(supabase: self.supabaseClient)
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
        QuestArcsService(supabase: supabaseClient, authService: supabaseAuthService, difficultyService: difficultyService)
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

    /// Habit notification service for habit reminders and streak milestones
    lazy var habitNotificationService: HabitNotificationService = {
        HabitNotificationService()
    }()

    /// Habit service for habit tracking and completion
    lazy var habitService: HabitService = {
        HabitService(supabase: supabaseClient)
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

    // MARK: - Contextual Micro-Interventions Services

    lazy var interventionService: InterventionService = {
        InterventionService(
            supabase: self.supabaseClient,
            calendarMonitor: self.calendarTriggerMonitor,
            timingAnalyzer: self.optimalTimingAnalyzer,
            notificationManager: self.interventionNotificationManager
        )
    }()

    lazy var calendarTriggerMonitor: CalendarTriggerMonitor = {
        CalendarTriggerMonitor(supabase: self.supabaseClient)
    }()

    lazy var optimalTimingAnalyzer: OptimalTimingAnalyzer = {
        OptimalTimingAnalyzer(supabase: self.supabaseClient)
    }()

    lazy var interventionNotificationManager: InterventionNotificationManager = {
        InterventionNotificationManager()
    }()

    // MARK: - AR Grounding Exercise Services

    /// Service for detecting device AR capabilities (ARKit, TrueDepth, LiDAR)
    lazy var arCapabilityService: ARCapabilityService = {
        ARCapabilityService()
    }()

    /// Service for AR exercise session management and data persistence
    lazy var arExerciseService: ARExerciseService = {
        ARExerciseService(
            supabase: self.supabaseDataService,
            authService: self.supabaseAuthService,
            capabilityService: self.arCapabilityService
        )
    }()

    // MARK: - Autonomous Wellness Agent Services

    /// Service for the autonomous wellness agent
    lazy var agentService: AgentService = {
        AgentService(supabase: self.supabaseClient)
    }()

    // MARK: - Stress Signature Fingerprint Services (F026)

    /// Service for learning signature patterns from historical crisis data
    lazy var patternLearner: PatternLearner = {
        PatternLearner(supabaseDataService: self.supabaseDataService)
    }()

    /// Service for real-time signal monitoring from multiple data sources
    lazy var signalMonitor: SignalMonitor = {
        let monitor = SignalMonitor(supabaseDataService: self.supabaseDataService)
        // Wire N006 Wellbeing Debt integration for F026 compound signals
        monitor.wellbeingDebtService = self.wellbeingDebtService
        return monitor
    }()

    /// Service for pattern detection and weight adjustment
    lazy var patternDetector: PatternDetector = {
        PatternDetector(supabaseDataService: self.supabaseDataService)
    }()

    /// Service for delivering early interventions when patterns emerge
    lazy var earlyInterventionService: EarlyInterventionService = {
        EarlyInterventionService(supabaseDataService: self.supabaseDataService)
    }()

    /// Main coordinator for the Stress Signature system
    lazy var stressSignatureEngine: StressSignatureEngine = {
        StressSignatureEngine(
            supabaseDataService: self.supabaseDataService,
            patternLearner: self.patternLearner,
            signalMonitor: self.signalMonitor,
            patternDetector: self.patternDetector,
            interventionService: self.earlyInterventionService
        )
    }()

    // MARK: - Longitudinal Mental Health Intelligence Services (F027)

    /// Service for longitudinal wellness data aggregation and pattern detection
    lazy var longitudinalService: LongitudinalService = {
        LongitudinalService(authService: self.supabaseAuthService)
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

    // MARK: - Centralized Services

    // ✅ ARCHITECTURE FIX: Centralize SecureStorage creation
    lazy var secureStorage: SecureStorage = {
        SecureStorage()
    }()

    // ✅ ARCHITECTURE FIX: Centralize PathwayCacheService creation
    lazy var pathwayCacheService: PathwayCacheService = {
        PathwayCacheService(secureStorage: secureStorage)
    }()

    // ✅ ARCHITECTURE FIX: Centralize PathwayEncryptionService creation
    lazy var pathwayEncryptionService: PathwayEncryptionService = {
        PathwayEncryptionService(secureStorage: secureStorage)
    }()

    // ✅ ARCHITECTURE FIX: Centralize NetworkRetryService creation
    lazy var networkRetryService: NetworkRetryService = {
        NetworkRetryService()
    }()
}
