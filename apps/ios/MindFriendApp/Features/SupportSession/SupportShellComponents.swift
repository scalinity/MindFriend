import SwiftUI
import UIKit

// MARK: - Feature switch

/// One development switch for the stable Today / Chat / Explore / You shell (SUPPORT_SESSION_SPEC §10.1.7).
///
/// - Default: ON in every build. 1.0.6 ships the Today / Chat / Explore / You shell.
/// - Override without a rebuild: launch argument `-mf.supportShell.enabled YES|NO`
///   (UserDefaults picks launch arguments up automatically) or `defaults write <bundle> mf.supportShell.enabled -bool NO`.
/// - Turning it off only swaps the navigation shell back to the legacy tabs. Records, pins, and sessions are untouched.
enum SupportShellFeature {
    static let defaultsKey = "mf.supportShell.enabled"

    /// The stable shell uses the local, immediately reversible presentation preference.
    static let simplerViewIsImmediatelyReversible = true

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: defaultsKey) != nil {
            return defaults.bool(forKey: defaultsKey)
        }
        return true
    }
}

// MARK: - Tabs

/// The four fixed destinations. They reuse the legacy `MainTab` values as tab tags so `AppState.selectedTab`
/// needs no enum additions: Today = `.home`, Chat = `.chat`, Explore = `.circles`, You = `.profile`.
enum SupportShellTab: CaseIterable, Identifiable, Hashable {
    var id: Self { self }
    case today, chat, explore, you

    var mainTab: MainTab {
        switch self {
        case .today: return .home
        case .chat: return .chat
        case .explore: return .circles
        case .you: return .profile
        }
    }

    /// `nil` for legacy tabs that have no tab in the new shell (`programs`, `outcomes`, `mentorship`, ...).
    init?(mainTab: MainTab) {
        switch mainTab {
        case .home: self = .today
        case .chat: self = .chat
        case .circles: self = .explore
        case .profile: self = .you
        case .programs, .outcomes, .mentorship, .sleep, .personalization: return nil
        }
    }

    var title: String {
        switch self {
        case .today: return String(localized: "Today")
        case .chat: return String(localized: "Chat")
        case .explore: return String(localized: "Explore")
        case .you: return String(localized: "You")
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .chat: return "bubble.left.and.bubble.right"
        case .explore: return "square.grid.2x2"
        case .you: return "person.crop.circle"
        }
    }
}

// MARK: - Destination registry

enum SupportSection: String, CaseIterable {
    case practices, programsAndPathways, toolsAndExperiments, peopleAndCircles
    case progress, history, memory, measurements, settings, help

    var title: String {
        switch self {
        case .practices: return String(localized: "Practices")
        case .programsAndPathways: return String(localized: "Programs and Pathways")
        case .toolsAndExperiments: return String(localized: "Tools and Experiments")
        case .peopleAndCircles: return String(localized: "People and Circles")
        case .progress: return String(localized: "Progress")
        case .history: return String(localized: "History")
        case .memory: return String(localized: "What MindFriend remembers")
        case .measurements: return String(localized: "Measurements")
        case .settings: return String(localized: "Settings")
        case .help: return String(localized: "Help")
        }
    }
}

/// Every retained legacy capability that has a push destination in the new shell.
/// Pure data (no view construction) so the route map is testable; views are built by `SupportDestinationView`.
enum SupportDestination: String, Codable, CaseIterable, Hashable, Identifiable {
    // Explore → Practices
    case exerciseLibrary, quickBreathing, microMoments, sensoryToolkit, journal, sleep
    case generatedForYou, creativeHub, liveSessions, quote
    // Explore → Programs and Pathways
    case programs, therapeuticPrograms, questArcs, pathways
    // Explore → Tools and Experiments
    case insightLab, warningSigns, forYou, therapists
    // Explore → People and Circles
    case circles, mentorship, peerSupport, partnerMode, family, seasonalEvents, buddy
    // You → Progress / History
    case outcomes, dailyQuest, achievements, badges, certificates, stories, journey
    case weeklyInsights, streaks, moodHistory, habits, plans, dailyBriefing, weeklyRecap
    // You → What MindFriend remembers / Measurements
    case memorySettings, memoryVault, privateVault, healthSettings
    case sleepTracking, wellbeingDebt, capacity, moodPrediction
    // You → Settings (list) and its named subviews
    case settings, notificationSettings, aiPreferences, interventionSettings, privacySettings, appLock
    case appearance, language, proactiveCheckIns, wellnessAgent, sosSettings, recoveryMode
    case ourApproach, dataExport, becomeTherapist
    // Help
    case safetyPlan

    var id: String { rawValue }

    var tab: SupportShellTab {
        switch section {
        case .practices, .programsAndPathways, .toolsAndExperiments, .peopleAndCircles: return .explore
        default: return .you
        }
    }

    var section: SupportSection {
        switch self {
        case .exerciseLibrary, .quickBreathing, .microMoments, .sensoryToolkit, .journal, .sleep,
             .generatedForYou, .creativeHub, .liveSessions, .quote:
            return .practices
        case .programs, .therapeuticPrograms, .questArcs, .pathways:
            return .programsAndPathways
        case .insightLab, .warningSigns, .forYou, .therapists:
            return .toolsAndExperiments
        case .circles, .mentorship, .peerSupport, .partnerMode, .family, .seasonalEvents, .buddy:
            return .peopleAndCircles
        case .outcomes, .dailyQuest, .achievements, .badges, .certificates, .stories, .journey,
             .weeklyInsights, .streaks, .habits, .plans, .dailyBriefing, .weeklyRecap:
            return .progress
        case .moodHistory:
            return .history
        case .memorySettings, .memoryVault, .privateVault:
            return .memory
        case .healthSettings, .sleepTracking, .wellbeingDebt, .capacity, .moodPrediction:
            return .measurements
        case .settings, .notificationSettings, .aiPreferences, .interventionSettings, .privacySettings,
             .appLock, .appearance, .language, .proactiveCheckIns, .wellnessAgent, .sosSettings,
             .recoveryMode, .ourApproach, .dataExport, .becomeTherapist:
            return .settings
        case .safetyPlan:
            return .help
        }
    }

    var title: String {
        switch self {
        case .exerciseLibrary: return String(localized: "Exercises")
        case .quickBreathing: return String(localized: "Quick breathing")
        case .microMoments: return String(localized: "Micro-moments")
        case .sensoryToolkit: return String(localized: "Sensory toolkit")
        case .journal: return String(localized: "Journal")
        case .sleep: return String(localized: "Sleep")
        case .sleepTracking: return String(localized: "Sleep tracking")
        case .generatedForYou: return String(localized: "Made for you")
        case .creativeHub: return String(localized: "Create")
        case .liveSessions: return String(localized: "Live sessions")
        case .quote: return String(localized: "Quotes")
        case .habits: return String(localized: "Habits")
        case .plans: return String(localized: "Plans")
        case .dailyBriefing: return String(localized: "Daily briefing")
        case .weeklyRecap: return String(localized: "Weekly recap")
        case .seasonalEvents: return String(localized: "Seasonal events")
        case .buddy: return String(localized: "Buddy")
        case .capacity: return String(localized: "Capacity")
        case .moodPrediction: return String(localized: "Mood outlook")
        case .programs: return String(localized: "Programs")
        case .therapeuticPrograms: return String(localized: "Therapeutic programs")
        case .questArcs: return String(localized: "Quest arcs")
        case .pathways: return String(localized: "Transition pathways")
        case .insightLab: return String(localized: "Insight Lab")
        case .warningSigns: return String(localized: "Early warning signs")
        case .wellbeingDebt: return String(localized: "Wellbeing debt")
        case .forYou: return String(localized: "For You")
        case .therapists: return String(localized: "Find a therapist")
        case .circles: return String(localized: "Circles")
        case .mentorship: return String(localized: "Mentorship")
        case .peerSupport: return String(localized: "Peer support")
        case .partnerMode: return String(localized: "Partner mode")
        case .family: return String(localized: "Family")
        case .outcomes: return String(localized: "Progress and assessments")
        case .dailyQuest: return String(localized: "Daily quests")
        case .achievements: return String(localized: "Achievements")
        case .badges: return String(localized: "Badges")
        case .certificates: return String(localized: "Certificates")
        case .stories: return String(localized: "My stories")
        case .journey: return String(localized: "Your journey")
        case .weeklyInsights: return String(localized: "Weekly insights")
        case .streaks: return String(localized: "Streaks and shields")
        case .moodHistory: return String(localized: "Mood history")
        case .memorySettings: return String(localized: "AI memory settings")
        case .memoryVault: return String(localized: "Saved memories")
        case .privateVault: return String(localized: "Private journal · on this device")
        case .healthSettings: return String(localized: "Apple Health")
        case .settings: return String(localized: "Settings")
        case .notificationSettings: return String(localized: "Notifications")
        case .aiPreferences: return String(localized: "AI preferences")
        case .interventionSettings: return String(localized: "Smart interventions")
        case .privacySettings: return String(localized: "Privacy")
        case .appLock: return String(localized: "App lock")
        case .appearance: return String(localized: "Appearance")
        case .language: return String(localized: "Language")
        case .proactiveCheckIns: return String(localized: "Proactive check-ins")
        case .wellnessAgent: return String(localized: "Wellness agent")
        case .sosSettings: return String(localized: "SOS button")
        case .recoveryMode:
            return SupportShellFeature.simplerViewIsImmediatelyReversible
                ? String(localized: "Simpler view") : String(localized: "Recovery mode")
        case .ourApproach: return String(localized: "Our approach")
        case .dataExport: return String(localized: "Export data")
        case .becomeTherapist: return String(localized: "Become a therapist or coach")
        case .safetyPlan: return String(localized: "Safety plan")
        }
    }

    /// Short plain-language description. Nil when the title is sufficient.
    var subtitle: String? {
        switch self {
        case .privateVault: return String(localized: "Encrypted, stays on this device. Never shared with AI.")
        case .memorySettings: return String(localized: "Choose what the AI may use")
        case .memoryVault: return String(localized: "Review, edit, or remove")
        case .healthSettings: return String(localized: "Optional. You choose what to connect.")
        case .recoveryMode:
            return SupportShellFeature.simplerViewIsImmediatelyReversible
                ? String(localized: "A simpler screen you can leave any time")
                : String(localized: "The simpler-view change is pending; the existing exit rule still applies")
        case .quote: return String(localized: "Not available yet")
        case .plans: return String(localized: "Your current action plan, if you have one")
        case .dailyBriefing: return String(localized: "Today's briefing")
        case .weeklyRecap: return String(localized: "A look back at your week")
        case .seasonalEvents: return String(localized: "Current event and your participation")
        case .buddy: return String(localized: "Check in with your buddy")
        case .capacity: return String(localized: "An estimate, not a score of you")
        case .moodPrediction: return String(localized: "An interpretation of recent patterns, not a diagnosis")
        case .sleepTracking: return String(localized: "Your tracked sleep")
        case .generatedForYou: return String(localized: "Meditations, stories, soundscapes")
        case .wellbeingDebt: return String(localized: "An estimate based on recorded activity")
        case .outcomes: return String(localized: "Check-ins, goals, and assessments")
        case .sleep: return String(localized: "Wind-down audio and bedtime stories")
        default: return nil
        }
    }

    var icon: String {
        switch self {
        case .exerciseLibrary: return "figure.mind.and.body"
        case .quickBreathing: return "lungs.fill"
        case .microMoments: return "timer"
        case .sensoryToolkit: return "hand.raised.fill"
        case .journal: return "book.closed"
        case .sleep: return "moon.fill"
        case .sleepTracking: return "bed.double.fill"
        case .generatedForYou: return "wand.and.stars"
        case .creativeHub: return "paintpalette.fill"
        case .liveSessions: return "person.3.sequence.fill"
        case .quote: return "quote.opening"
        case .habits: return "checklist"
        case .plans: return "list.clipboard"
        case .dailyBriefing: return "sun.horizon"
        case .weeklyRecap: return "rectangle.stack"
        case .seasonalEvents: return "leaf"
        case .buddy: return "heart.circle"
        case .capacity: return "gauge.with.dots.needle.33percent"
        case .moodPrediction: return "cloud.sun"
        case .programs: return "book.fill"
        case .therapeuticPrograms: return "cross.case.fill"
        case .questArcs: return "map.fill"
        case .pathways: return "signpost.right.fill"
        case .insightLab: return "flask.fill"
        case .warningSigns: return "shield.checkered"
        case .wellbeingDebt: return "scalemass.fill"
        case .forYou: return "sparkles"
        case .therapists: return "person.2.wave.2.fill"
        case .circles: return "person.3.fill"
        case .mentorship: return "star.fill"
        case .peerSupport: return "bubble.left.and.text.bubble.right.fill"
        case .partnerMode: return "person.2.fill"
        case .family: return "figure.2.and.child.holdinghands"
        case .outcomes: return "chart.line.uptrend.xyaxis"
        case .dailyQuest: return "flag.fill"
        case .achievements: return "trophy.fill"
        case .badges: return "medal.fill"
        case .certificates: return "checkmark.seal.fill"
        case .stories: return "book.closed.fill"
        case .journey: return "point.topleft.down.curvedto.point.bottomright.up"
        case .weeklyInsights: return "chart.bar.xaxis"
        case .streaks: return "shield.lefthalf.filled"
        case .moodHistory: return "face.smiling"
        case .memorySettings: return "brain.head.profile"
        case .memoryVault: return "archivebox.fill"
        case .privateVault: return "lock.shield.fill"
        case .healthSettings: return "heart.fill"
        case .settings: return "gearshape"
        case .notificationSettings: return "bell.fill"
        case .aiPreferences: return "brain"
        case .interventionSettings: return "waveform.path.ecg"
        case .privacySettings: return "lock.fill"
        case .appLock: return "faceid"
        case .appearance: return "circle.lefthalf.filled"
        case .language: return "globe"
        case .proactiveCheckIns: return "sparkles"
        case .wellnessAgent: return "brain.head.profile"
        case .sosSettings: return "heart.fill"
        case .recoveryMode: return "heart.circle.fill"
        case .ourApproach: return "checkmark.seal.fill"
        case .dataExport: return "square.and.arrow.up"
        case .becomeTherapist: return "person.badge.plus"
        case .safetyPlan: return "heart.shield.fill"
        }
    }

    /// Extra search terms so Explore search finds a capability by its old name.
    var keywords: [String] {
        switch self {
        case .exerciseLibrary: return ["grounding", "meditation", "breathing", "practice", "library"]
        case .quickBreathing: return ["breathe", "calm", "breath"]
        case .microMoments: return ["micro", "quick", "moment"]
        case .sensoryToolkit: return ["sensory", "audio", "tactile", "visual"]
        case .journal: return ["write", "voice journal", "voice", "text journal", "diary", "prompts"]
        case .sleep: return ["bedtime", "story", "wind down", "quotes"]
        case .sleepTracking: return ["sleep dashboard", "rest"]
        case .generatedForYou: return ["generated", "meditation", "story", "soundscape"]
        case .creativeHub: return ["art", "draw", "creative"]
        case .liveSessions: return ["live", "group"]
        case .quote: return ["quote", "daily quote", "inspiration"]
        case .habits: return ["habit", "routine"]
        case .plans: return ["action plan", "plan"]
        case .dailyBriefing: return ["briefing", "morning"]
        case .weeklyRecap: return ["progress story", "recap", "week"]
        case .seasonalEvents: return ["event", "season", "challenge"]
        case .buddy: return ["buddy", "encouragement", "invite"]
        case .capacity: return ["difficulty", "capacity", "energy"]
        case .moodPrediction: return ["prediction", "forecast", "intervention", "outlook"]
        case .programs: return ["course", "enroll", "ar", "program"]
        case .therapeuticPrograms: return ["cbt", "therapy", "thought record"]
        case .questArcs: return ["quest", "arc", "adventure"]
        case .pathways: return ["transition", "pathway", "change"]
        case .insightLab: return ["experiment", "stress signature", "pattern"]
        case .warningSigns: return ["alerts", "early", "signature"]
        case .wellbeingDebt: return ["debt", "balance", "recovery"]
        case .forYou: return ["personalized", "recommend", "insights"]
        case .therapists: return ["therapist", "coach", "professional", "discover"]
        case .circles: return ["circle", "group", "friends", "buddy", "invite", "ritual"]
        case .mentorship: return ["mentor"]
        case .peerSupport: return ["peer", "support"]
        case .partnerMode: return ["partner", "couple", "together"]
        case .family: return ["family", "together", "kids"]
        case .outcomes: return ["assessment", "phq", "gad", "who-5", "pss", "goals", "progress"]
        case .dailyQuest: return ["quest", "daily"]
        case .achievements: return ["xp", "level", "trophy"]
        case .badges: return ["badge"]
        case .certificates: return ["certificate"]
        case .stories: return ["narrative", "story"]
        case .journey: return ["longitudinal", "life events", "yearly", "reports"]
        case .weeklyInsights: return ["insights", "weekly"]
        case .streaks: return ["streak", "shield", "vacation", "recovery quest"]
        case .moodHistory: return ["mood", "history", "check-in"]
        case .memorySettings: return ["memory", "remember", "ai"]
        case .memoryVault: return ["memory", "remember", "vault"]
        case .privateVault: return ["vault", "private", "journal"]
        case .healthSettings: return ["healthkit", "hrv", "biometrics", "health"]
        case .settings: return ["account", "profile"]
        case .notificationSettings: return ["reminders"]
        case .aiPreferences: return ["ai", "tone", "coach"]
        case .interventionSettings: return ["intervention"]
        case .privacySettings: return ["privacy", "data"]
        case .appLock: return ["face id", "passcode", "lock"]
        case .appearance: return ["theme", "dark", "text size"]
        case .language: return ["locale", "region"]
        case .proactiveCheckIns: return ["proactive", "check-in"]
        case .wellnessAgent: return ["agent"]
        case .sosSettings: return ["sos", "panic"]
        case .recoveryMode: return ["simpler view", "recovery"]
        case .ourApproach: return ["evidence", "method"]
        case .dataExport: return ["export", "download"]
        case .becomeTherapist: return ["apply", "professional"]
        case .safetyPlan: return ["crisis", "safety", "help"]
        }
    }

    /// The destination's root view declares its own `NavigationStack` when standalone. `SupportDestinationView`
    /// renders these in embedded mode (`supportRootEmbedded`) so a pushed destination adds no second stack.
    /// Found by source inspection of each view's root `body` (InsightLabView and LiveSessionsView do not).
    var ownsNavigationStack: Bool {
        switch self {
        case .microMoments, .sleepTracking, .programs, .therapeuticPrograms, .questArcs, .wellbeingDebt,
             .forYou, .therapists, .circles, .outcomes, .dailyQuest, .stories, .journey, .healthSettings,
             .wellnessAgent, .safetyPlan:
            return true
        default:
            return false
        }
    }

    /// Candidates for "Pin to Today". Settings, memory, history and help rows (and the unavailable Quotes
    /// placeholder) are never pinnable.
    var isPinnable: Bool {
        switch section {
        case .settings, .memory, .help, .history: return false
        default: return self != .quote
        }
    }

    /// Where the capability lived before this shell (for the inventory / reviewers).
    var legacyOrigin: String {
        switch self {
        case .exerciseLibrary: return "Home Quick Actions · deep links exercises/exercise/meditation"
        case .quickBreathing: return "Deep link breathing · micro-moment player"
        case .microMoments: return "Deep link micro"
        case .sensoryToolkit: return "Home SensoryToolkitCard"
        case .journal: return "Deep link journal (text JournalListView; voice via Create hub)"
        case .sleep: return "Profile → Features → Sleep · deep link sleep"
        case .sleepTracking: return "Home SleepHomeCard (SleepDashboardView)"
        case .generatedForYou: return "Home Quick Actions → For You"
        case .creativeHub: return "Home Quick Actions → Create"
        case .liveSessions: return "Home Quick Actions → Live"
        case .quote: return "Deep link quote (no quote UI existed; routed to Home)"
        case .habits: return "Home TodaysHabitsHomeCard"
        case .plans: return "Home ActionPlanHomeCard (fetchLatestPlan; no initial-generation UI exists)"
        case .dailyBriefing: return "Home DailyBriefingCard"
        case .weeklyRecap: return "Home ProgressStoryPreviewCard"
        case .seasonalEvents: return "Home SeasonalEventCard"
        case .buddy: return "Home BuddyWidget / InviteBuddyPrompt"
        case .capacity: return "Home CapacityIndicator"
        case .moodPrediction: return "Home MoodPredictionCard / PreemptiveInterventionView"
        case .programs: return "Programs tab (activation-gated) · deep link programs"
        case .therapeuticPrograms: return "Deep link therapeutic"
        case .questArcs: return "Home QuestArc cards"
        case .pathways: return "Home Your Journeys / ActivePathwayCard / PathwaySelectionView"
        case .insightLab: return "Home InsightLabHomeCard"
        case .warningSigns: return "Home Quick Actions → Alerts"
        case .wellbeingDebt: return "Home WellbeingDebtCard"
        case .forYou: return "Profile → Features → For You"
        case .therapists: return "Home Quick Actions → Therapists"
        case .circles: return "Profile → Features → Circles · deep link circles"
        case .mentorship: return "Profile → Social → Mentorship"
        case .peerSupport: return "Profile → Social → Peer Support"
        case .partnerMode: return "Profile → Social → Partner Mode"
        case .family: return "Profile → Social → Family"
        case .outcomes: return "Progress tab (activation-gated) · deep links progress/assessment"
        case .dailyQuest: return "Home QuestCard · deep link quest"
        case .achievements: return "Profile → Progress · deep link achievements"
        case .badges: return "Home Quick Actions → Badges"
        case .certificates: return "Profile → Progress → Certificates"
        case .stories: return "Profile → Progress → My Stories"
        case .journey: return "Profile → Progress → Your Journey"
        case .weeklyInsights: return "Home InsightsPreviewCard · deep link insights"
        case .streaks: return "Home StreakCardWithShields · Profile Shield History/Vacation · RecoveryQuestView · deep link streak"
        case .moodHistory: return "Home Quick Actions → Mood · deep link mood/history"
        case .memorySettings: return "Profile → Settings → AI Memory"
        case .memoryVault: return "Profile → Settings → Memory Vault"
        case .privateVault: return "Profile → Settings → Private Vault"
        case .healthSettings: return "Profile → Settings → Apple Health"
        case .settings: return "Profile → Settings section · deep link settings"
        case .notificationSettings: return "Profile → Settings"
        case .aiPreferences: return "Profile → Settings"
        case .interventionSettings: return "Profile → Settings"
        case .privacySettings: return "Profile → Settings"
        case .appLock: return "Profile → Settings"
        case .appearance: return "Profile → Settings"
        case .language: return "Profile → Settings"
        case .proactiveCheckIns: return "Profile → Settings"
        case .wellnessAgent: return "Profile → Settings"
        case .sosSettings: return "Profile → Settings"
        case .recoveryMode: return "Profile → Settings"
        case .ourApproach: return "Profile → Settings"
        case .dataExport: return "Profile → Data"
        case .becomeTherapist: return "Profile → Professional"
        case .safetyPlan: return "Home Quick Actions (pinned Safety)"
        }
    }

    static func destinations(in section: SupportSection) -> [SupportDestination] {
        allCases.filter { $0.section == section }
    }

    /// Additional Explore rows that deliberately appear in a second place. Assessments live in
    /// You → Progress (`.outcomes`) with this shortcut under Tools and Experiments.
    static func exploreShortcuts(in section: SupportSection) -> [SupportDestination] {
        section == .toolsAndExperiments ? [.outcomes] : []
    }

    /// Explore rows for a section: its own destinations plus shortcuts.
    static func exploreRows(in section: SupportSection) -> [SupportDestination] {
        destinations(in: section) + exploreShortcuts(in: section)
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        if title.lowercased().contains(needle) { return true }
        if let subtitle, subtitle.lowercased().contains(needle) { return true }
        return keywords.contains { $0.lowercased().contains(needle) }
    }
}

extension SupportDestination {
    /// Other code (onboarding, tutorials, widgets) may still assign a legacy `MainTab` that has no tab in the
    /// stable shell. These map to the destination that replaced it.
    static func replacingLegacyTab(_ tab: MainTab) -> SupportDestination? {
        switch tab {
        case .home, .chat, .circles, .profile: return nil
        case .programs: return .programs
        case .outcomes: return .outcomes
        case .mentorship: return .mentorship
        case .sleep: return .sleep
        case .personalization: return .forYou
        }
    }
}

extension MainTab {
    /// The stable-shell tab tag that hosts this tab's content.
    var supportShellTag: MainTab {
        if SupportShellTab(mainTab: self) != nil { return self }
        return SupportDestination.replacingLegacyTab(self)?.tab.mainTab ?? .home
    }
}

// MARK: - Navigation state

/// Programmatic navigation for the Explore and You stacks, so deep links open real destinations inside
/// the correct tab with its back stack preserved. Replacing the path avoids piling up repeated links.
@MainActor
final class SupportShellNavigator: ObservableObject {
    @Published var explorePath: [SupportDestination] = []
    @Published var youPath: [SupportDestination] = []

    func open(_ destination: SupportDestination) {
        switch destination.tab {
        case .explore: explorePath = [destination]
        case .you: youPath = [destination]
        case .today, .chat: break
        }
    }

    func popToRoot() {
        explorePath = []
        youPath = []
    }
}

// MARK: - Pins ("Pin to Today")

/// One Today pin. A plain destination pin opens the library/tool; a pin with a `Record` identifies one specific
/// program or enrollment, so "my active program" and "the Programs library" are distinct, separately pinnable
/// items. Persisted JSON is backward compatible: `record` is optional and unknown/legacy entries are dropped,
/// never reinterpreted.
struct SupportPin: Codable, Hashable, Identifiable {
    enum RecordKind: String, Codable { case program, enrollment }

    struct Record: Codable, Hashable {
        var kind: RecordKind
        var id: String
        /// For an enrollment, the program it belongs to (Today opens that program after the usual ownership check).
        var relatedProgramID: String?
        /// Display title captured when pinned; Today should prefer fresher data when it has it.
        var title: String?
    }

    var destination: SupportDestination
    var record: Record?

    init(_ destination: SupportDestination, record: Record? = nil) {
        self.destination = destination
        self.record = record
    }

    var id: String {
        guard let record else { return destination.rawValue }
        return "\(destination.rawValue):\(record.kind.rawValue):\(record.id)"
    }

    var title: String { record?.title ?? destination.title }
}

/// Up to three user-chosen pins for Today's compact active-work area. Explore owns pin/unpin/replace; Today (the
/// session owner) reads `pins` and owns the visible Move up / Move down controls, calling `moveUp`/`moveDown`.
/// Persisted per account. Nothing is evicted automatically: when full, `pin` returns false and the caller offers
/// the explicit Replace chooser.
@MainActor
final class SupportPinStore: ObservableObject {
    static let maxPins = 3

    @Published private(set) var pins: [SupportPin]
    private let defaults: UserDefaults
    private let key: String

    /// `accountID == nil` yields an in-memory-only store (nothing is written to a shared key).
    init(accountID: UUID?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let accountID else {
            key = ""
            pins = []
            return
        }
        key = "mf.support.pins.v2.\(accountID.uuidString)"
        let legacyKey = "mf.support.pins.\(accountID.uuidString)"
        var loaded: [SupportPin]
        if let data = defaults.data(forKey: key) {
            loaded = Self.decode(data)
        } else {
            // Migrate the first-generation destination-only list.
            loaded = (defaults.stringArray(forKey: legacyKey) ?? [])
                .compactMap { SupportDestination(rawValue: $0) }.map { SupportPin($0) }
        }
        var seen = Set<String>()
        loaded = loaded.filter { $0.destination.isPinnable && seen.insert($0.id).inserted }
        pins = Array(loaded.prefix(Self.maxPins))
    }

    private struct Lossy: Decodable {
        let pin: SupportPin?
        init(from decoder: Decoder) throws { pin = try? SupportPin(from: decoder) }
    }

    private static func decode(_ data: Data) -> [SupportPin] {
        ((try? JSONDecoder().decode([Lossy].self, from: data)) ?? []).compactMap(\.pin)
    }

    var isFull: Bool { pins.count >= Self.maxPins }
    func isPinned(_ pin: SupportPin) -> Bool { pins.contains { $0.id == pin.id } }
    func isPinned(_ destination: SupportDestination) -> Bool { isPinned(SupportPin(destination)) }

    /// Returns true if the pin is now present. False when full (offer Replace) or not pinnable.
    @discardableResult
    func pin(_ pin: SupportPin) -> Bool {
        guard pin.destination.isPinnable else { return false }
        if let index = pins.firstIndex(where: { $0.id == pin.id }) {
            pins[index] = pin
            persist()
            return true
        }
        guard !isFull else { return false }
        pins.append(pin)
        persist()
        return true
    }

    @discardableResult
    func pin(_ destination: SupportDestination) -> Bool { pin(SupportPin(destination)) }

    func unpin(_ pin: SupportPin) {
        pins.removeAll { $0.id == pin.id }
        persist()
    }

    func unpin(_ destination: SupportDestination) { unpin(SupportPin(destination)) }

    /// Explicit replacement chosen by the person; never an automatic eviction.
    func replace(_ existing: SupportPin, with new: SupportPin) {
        guard new.destination.isPinnable, let index = pins.firstIndex(where: { $0.id == existing.id }), !isPinned(new) else { return }
        pins[index] = new
        persist()
    }

    func replace(_ existing: SupportPin, with new: SupportDestination) { replace(existing, with: SupportPin(new)) }

    func moveUp(_ pin: SupportPin) {
        guard let index = pins.firstIndex(where: { $0.id == pin.id }), index > 0 else { return }
        pins.swapAt(index, index - 1)
        persist()
    }

    func moveDown(_ pin: SupportPin) {
        guard let index = pins.firstIndex(where: { $0.id == pin.id }), index < pins.count - 1 else { return }
        pins.swapAt(index, index + 1)
        persist()
    }

    private func persist() {
        guard !key.isEmpty, let data = try? JSONEncoder().encode(pins) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Design tokens (SUPPORT_SESSION_SPEC §6.1)

enum SupportTheme {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 12
    static let minimumTarget: CGFloat = 44
    static let primaryButtonHeight: CGFloat = 48
    static let readableWidth: CGFloat = 680

    static let canvas = dynamic(light: 0xF7F8FC, dark: 0x0E1522)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x192335)
    /// Raised surfaces over content: toasts, celebration cards, floating bars.
    static let elevated = dynamic(light: 0xFFFFFF, dark: 0x22304A)
    static let textPrimary = dynamic(light: 0x182234, dark: 0xEDF2FC)
    static let textSecondary = dynamic(light: 0x526176, dark: 0xAFBDD1, highLight: 0x3D4A5E, highDark: 0xC9D4E5)
    static let accent = dynamic(light: 0x3557B7, dark: 0x9BB5FF, highLight: 0x26449A, highDark: 0xB9CCFF)
    /// Text on an accent-filled primary button (dark action text in dark mode).
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x0E1522)
    /// Fill of text entry fields, distinct from both canvas and surface.
    static let field = dynamic(light: 0xFFFFFF, dark: 0x131C2C)
    /// Boundary of fields and controls: at least 3:1 against canvas, surface and field.
    static let border = dynamic(light: 0x76839A, dark: 0x64779A, highLight: 0x4F5C72, highDark: 0x8A9CC0)
    /// Decorative dividers between rows; never the only boundary of a control.
    static let separator = dynamic(light: 0xDDE2EC, dark: 0x26324A, highLight: 0x8592A6, highDark: 0x5C6F8E)

    /// Reward moments: the accent, a soft glow behind it and a warm gold for levels and badges.
    enum Celebration {
        static let accent = SupportTheme.accent
        static let glow = dynamic(light: 0xC9D7FF, dark: 0x3E5A9E)
        static let gold = dynamic(light: 0x9A6A12, dark: 0xF2C46D)
    }

    /// Increase Contrast selects the `high` values where a token has them.
    fileprivate static func dynamic(light: UInt32, dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            let hex = traits.userInterfaceStyle == .dark ? (high ? highDark ?? dark : dark) : (high ? highLight ?? light : light)
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension View {
    /// Canvas background for list-based support screens, with a readable content width on large layouts.
    func supportCanvas() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(SupportTheme.canvas.ignoresSafeArea())
            // The app-wide accent and the default gray section headers fall just under 4.5:1 on
            // this canvas; the support palette and prominent headers keep both readable.
            .tint(SupportTheme.accent)
            .headerProminence(.increased)
    }
}

/// Text entry on support screens: field fill, a 1pt boundary at least 3:1 against
/// its surroundings, and the small-control radius. Replaces `.roundedBorder`,
/// which renders a pure black field on the navy canvas in dark mode.
struct SupportFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .foregroundStyle(SupportTheme.textPrimary)
            .padding(SupportTheme.Spacing.s)
            .frame(minHeight: SupportTheme.minimumTarget)
            .background(SupportTheme.field, in: RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                .strokeBorder(SupportTheme.border, lineWidth: 1))
    }
}

/// An opaque content card on the canvas.
struct SupportCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(SupportTheme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }
}

/// The one primary action on a screen: accent fill, at least 48pt tall, grows with text.
struct SupportPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(SupportTheme.onAccent)
            .padding(.horizontal, SupportTheme.Spacing.m)
            .padding(.vertical, SupportTheme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: SupportTheme.primaryButtonHeight)
            .background(SupportTheme.accent, in: RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }
}

/// Secondary actions: field fill, a 3:1 boundary and accent text.
struct SupportSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(SupportTheme.accent)
            .padding(.horizontal, SupportTheme.Spacing.m)
            .padding(.vertical, SupportTheme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: SupportTheme.minimumTarget)
            .background(SupportTheme.field, in: RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: SupportTheme.controlRadius).strokeBorder(SupportTheme.border, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }
}

extension ButtonStyle where Self == SupportPrimaryButtonStyle {
    static var supportPrimary: SupportPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == SupportSecondaryButtonStyle {
    static var supportSecondary: SupportSecondaryButtonStyle { .init() }
}

extension View {
    func supportField() -> some View { modifier(SupportFieldStyle()) }
    func supportCard() -> some View { modifier(SupportCardStyle()) }

    /// A whole screen in the support look: canvas behind lists and forms, a canvas-coloured
    /// navigation bar when content scrolls under it, and the support tint. Applied where a
    /// router hosts a destination, so the destinations inherit it.
    func supportScreen() -> some View {
        self
            .supportCanvas()
            .toolbarBackground(SupportTheme.canvas, for: .navigationBar)
    }

    /// A sheet presented from the shell: the support screen look on a canvas sheet background.
    func supportSheet() -> some View {
        supportScreen().presentationBackground(SupportTheme.canvas)
    }
}

// MARK: - Embedded root navigation

private struct SupportRootEmbeddedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when a destination root view is already hosted inside the shell's one `NavigationStack`.
    var supportRootEmbedded: Bool {
        get { self[SupportRootEmbeddedKey.self] }
        set { self[SupportRootEmbeddedKey.self] = newValue }
    }
}

/// Used by destination root views in place of a bare `NavigationStack`: standalone callers (default) get the
/// same stack as before; the shell sets `supportRootEmbedded` so exactly one stack hosts full work.
struct SupportRootNavigation<Content: View>: View {
    let embedded: Bool
    private let content: Content

    init(embedded: Bool, @ViewBuilder content: () -> Content) {
        self.embedded = embedded
        self.content = content()
    }

    var body: some View {
        if embedded {
            content.environment(\.supportRootEmbedded, false)
        } else {
            NavigationStack { content.environment(\.supportRootEmbedded, false) }
        }
    }
}

// MARK: - Components

/// Icon + title + optional subtitle row label. Minimum 44pt target, wraps at large Dynamic Type sizes.
struct SupportRowLabel: View {
    let title: String
    var subtitle: String?
    let icon: String

    init(_ destination: SupportDestination) {
        title = destination.title
        subtitle = destination.subtitle
        icon = destination.icon
    }

    init(title: String, subtitle: String? = nil, icon: String) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(SupportTheme.accent)
        }
        .frame(minHeight: SupportTheme.minimumTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Spec `UnavailableState`: what remains available and a route back. Never substitutes another destination.
struct SupportUnavailableState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
    }
}

// MARK: - Destination views

/// Builds the real, existing view for each registry destination. Root views that declare their own
/// `NavigationStack` render in embedded mode here, so exactly one stack hosts pushed work and history.
struct SupportDestinationView: View {
    let destination: SupportDestination
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var pins: SupportPinStore
    @State private var replaceCandidate: SupportPin?

    var body: some View {
        content.environment(\.supportRootEmbedded, true).supportScreen()
            .toolbar {
                if destination.isPinnable {
                    ToolbarItem(placement: .primaryAction) {
                        let pinned = pins.isPinned(destination)
                        Button {
                            if pinned { pins.unpin(destination) }
                            else if pins.isFull { replaceCandidate = SupportPin(destination) }
                            else { pins.pin(destination) }
                        } label: {
                            Label(pinned ? "Unpin from Today" : "Pin to Today", systemImage: pinned ? "pin.fill" : "pin")
                        }
                        .accessibilityIdentifier("support-pin-toggle")
                    }
                }
            }
            .sheet(item: $replaceCandidate) { ReplacePinSheet(candidate: $0).environmentObject(pins) }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .exerciseLibrary: ExerciseLibraryView()
        case .quickBreathing: QuickBreathingView()
        case .microMoments: MicroMomentsHubView(supabase: container.supabase)
        case .sensoryToolkit: SensoryHomeView()
        case .journal: SupportJournalHub()
        case .sleep: SleepTabView(contentIdToPlay: .constant(nil))
        case .sleepTracking: SleepDashboardView().environmentObject(container)
        case .generatedForYou: GenerativeHomeView()
        case .creativeHub: CreativeHubView()
        case .liveSessions: LiveSessionsView()
        case .quote:
            // No quote content or UI exists in the app. Say so; never show an invented quote.
            SupportUnavailableState(
                title: String(localized: "Quotes aren't available yet"),
                message: String(localized: "There is no quotes feature to open right now. Your other practices are in Explore.")
            )
            .navigationTitle(destination.title)
        case .habits: HabitLibraryView()
        case .programs: ProgramsLibraryView()
        case .therapeuticPrograms:
            TherapeuticProgramsListView(service: TherapeuticProgramService(supabase: container.supabase))
        case .questArcs: QuestArcCatalogView().environmentObject(container)
        case .pathways: SupportPathwaysHub()
        case .insightLab: InsightLabView().environmentObject(container.insightLabService)
        case .warningSigns: WarningSignsDashboardView(engine: container.stressSignatureEngine)
        case .wellbeingDebt: WellbeingDebtDashboardView().environmentObject(container)
        case .forYou: ForYouView()
        case .therapists: TherapistDiscoveryView()
        case .circles: CirclesListView()
        case .mentorship: MentorshipTabView()
        case .peerSupport: PeerSupportHubView(supabase: container.supabase)
        case .partnerMode: PartnerModeView()
        case .family: FamilyHubView()
        case .seasonalEvents: SupportSeasonalHub()
        case .buddy: SupportBuddyHub()
        case .outcomes:
            OutcomeHomeView(outcomeService: container.outcomeService, authService: container.supabaseAuthService)
        case .dailyQuest: QuestChoiceView()
        case .achievements: AchievementsView().environmentObject(container.achievementService)
        case .badges: BadgesView()
        case .certificates: CertificatesListView()
        case .stories: NarrativeListView(dataService: container.supabaseDataService)
        case .journey: LongitudinalDashboardView()
        case .weeklyInsights: WeeklyInsightsView()
        case .streaks: SupportStreaksHub()
        case .plans: SupportPlansHub()
        case .dailyBriefing: SupportDailyBriefingHub()
        case .weeklyRecap: SupportWeeklyRecapHub()
        case .moodHistory: MoodHistoryView()
        case .capacity: SupportCapacityHub()
        case .moodPrediction: SupportMoodOutlookHub()
        case .memorySettings: SupportMemoryView()
        case .memoryVault: SupportMemoryView()
        case .privateVault: VaultListView().environmentObject(container.vaultViewModel)
        case .healthSettings: BiometricsSettingsView(healthKit: container.healthKitService)
        case .settings: SupportSettingsView()
        case .notificationSettings: NotificationSettingsView()
        case .aiPreferences: AIPreferencesView()
        case .interventionSettings: InterventionSettingsView()
        case .privacySettings: PrivacySettingsView()
        case .appLock: PrivacyLockSettingsView()
        case .appearance: AppearanceSettingsView()
        case .language: LanguageSettingsView().environmentObject(container.localizationService)
        case .proactiveCheckIns: ProactiveSettingsView()
        case .wellnessAgent: AgentDashboardView()
        case .sosSettings: SOSSettingsView()
        case .recoveryMode: SupportSimplerViewSettings()
        case .ourApproach: OurApproachView()
        case .dataExport: DataExportView()
        case .becomeTherapist: TherapistApplicationView()
        case .safetyPlan: SafetyPlanView()
        }
    }
}

/// A record pin resolves the exact retained enrollment/program rather than opening a substitute library item.
struct SupportPinnedDestinationView: View {
    let pin: SupportPin
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var program: Program?
    @State private var isLoading = true

    var body: some View {
        Group {
            if pin.record == nil {
                SupportDestinationView(destination: pin.destination)
            } else if let program {
                ProgramDetailView(program: program)
            } else if isLoading {
                ProgressView("Opening pinned work…")
            } else {
                SupportUnavailableState(title: "Pinned work unavailable",
                    message: "This exact program or enrollment could not be opened. Your other saved work remains available.")
            }
        }
        .task(id: appState.accountEpoch) { await resolve() }
    }

    private func resolve() async {
        guard let record = pin.record, let owner = appState.currentUser?.id else { isLoading = false; return }
        let epoch = appState.accountEpoch
        program = nil
        isLoading = true
        do {
            let resolved: Program?
            switch record.kind {
            case .enrollment:
                guard let programID = record.relatedProgramID else { isLoading = false; return }
                let enrollment = try await container.supabaseDataService.getEnrollment(programId: programID)
                resolved = enrollment?.id == record.id ? enrollment?.program : nil
            case .program:
                resolved = try await container.supabaseDataService.getPrograms().first { $0.id == record.id }
            }
            guard !Task.isCancelled, owner == appState.currentUser?.id, epoch == appState.accountEpoch else { return }
            program = resolved
            isLoading = false
        } catch {
            guard !Task.isCancelled, owner == appState.currentUser?.id, epoch == appState.accountEpoch else { return }
            isLoading = false
        }
    }
}
