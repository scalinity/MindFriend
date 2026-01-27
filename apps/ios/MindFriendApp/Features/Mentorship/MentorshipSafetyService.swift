import Foundation
import Combine

/// Manages safety monitoring, reporting, and escalation in mentorships
@MainActor
final class MentorshipSafetyService: ObservableObject {
    @Published var reports: [MentorshipReport] = []
    @Published var escalations: [MentorshipEscalation] = []
    @Published var flaggedMessages: [MentorshipMessage] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let dataService: MentorshipDataService

    nonisolated init(dataService: MentorshipDataService) {
        self.dataService = dataService
    }

    // MARK: - Reset

    func reset() {
        reports = []
        escalations = []
        flaggedMessages = []
        isLoading = false
        error = nil
    }

    // MARK: - Facade-compatible Methods

    func reportIssue(
        matchId: UUID,
        reportedUserId: UUID,
        reason: String,
        description: String?
    ) async throws {
        isLoading = true
        defer { isLoading = false }

        let report = try await dataService.createReport(
            matchId: matchId,
            reportedUserId: reportedUserId,
            reason: reason,
            description: description,
            messageIds: nil
        )
        reports.append(report)
    }

    // MARK: - Reporting

    /// Create a safety report for a mentorship
    func reportMentorship(
        matchId: UUID,
        reportedUserId: UUID,
        reason: String,
        description: String? = nil,
        messageIds: [UUID]? = nil
    ) async {
        isLoading = true
        error = nil

        do {
            let report = try await dataService.createReport(
                matchId: matchId,
                reportedUserId: reportedUserId,
                reason: reason,
                description: description,
                messageIds: messageIds
            )

            reports.append(report)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Load reports for a mentorship match
    func loadReports(matchId: UUID) async {
        isLoading = true
        error = nil

        do {
            reports = try await dataService.fetchReports(matchId: matchId)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Flag a message for safety review
    func flagMessage(messageId: UUID, reason: String) async {
        error = nil

        do {
            try await dataService.flagMessage(messageId: messageId, reason: reason)
            
            // Add to local flagged messages list
            let flaggedMsg = MentorshipMessage(
                id: messageId,
                matchId: UUID(),
                senderId: UUID(),
                content: "Flagged message",
                isFlagged: true,
                flaggedAt: Date()
            )
            flaggedMessages.append(flaggedMsg)
        } catch {
            self.error = error
        }
    }

    // MARK: - Safety Checks

    /// Run manual safety check
    func runSafetyCheck() async {
        isLoading = true
        error = nil

        do {
            let response = try await dataService.runSafetyCheck()
            
            // Log results
            print("Safety check completed: \(response.messagesChecked) checked, \(response.messagesFlagged) flagged")
            
            if response.criticalEscalations > 0 {
                print("⚠️ CRITICAL: \(response.criticalEscalations) escalations detected")
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Computed Properties

    var hasReports: Bool {
        !reports.isEmpty
    }

    var reportCount: Int {
        reports.count
    }

    var hasFlaggedMessages: Bool {
        !flaggedMessages.isEmpty
    }

    var flaggedMessageCount: Int {
        flaggedMessages.count
    }

    var pendingReports: [MentorshipReport] {
        reports.filter { $0.status == .pending }
    }

    var resolvedReports: [MentorshipReport] {
        reports.filter { $0.status == .resolved }
    }

    var escalatedReports: [MentorshipReport] {
        reports.filter { $0.status == .escalated }
    }

    var criticalEscalations: [MentorshipEscalation] {
        escalations.filter { $0.severity == .critical }
    }

    var hasCriticalEscalations: Bool {
        !criticalEscalations.isEmpty
    }

    // MARK: - Report Types

    /// Check if user has reported this match before
    func hasReportedMatch(_ matchId: UUID) -> Bool {
        reports.contains { $0.matchId == matchId }
    }

    /// Get reports by status
    func reportsByStatus(_ status: ReportStatus) -> [MentorshipReport] {
        reports.filter { $0.status == status }
    }

    /// Get reports mentioning a specific reason
    func reportsByReason(_ reason: String) -> [MentorshipReport] {
        reports.filter { $0.reason.localizedCaseInsensitiveContains(reason) }
    }

    // MARK: - Safety Concerns

    /// Common safety concern reasons
    static let safetyReasons = [
        "Inappropriate language",
        "Sexual or romantic advances",
        "Requests for personal information",
        "Pressure to meet in person",
        "Financial requests",
        "Boundary violations",
        "Disrespectful behavior",
        "Threatening language",
        "Other",
    ]

    /// Get user-friendly description of safety concern
    static func descriptionForReason(_ reason: String) -> String {
        switch reason {
        case "Inappropriate language":
            return "The other person used offensive or inappropriate language"
        case "Sexual or romantic advances":
            return "The other person made unwanted sexual or romantic advances"
        case "Requests for personal information":
            return "The other person requested personal information like phone number or address"
        case "Pressure to meet in person":
            return "The other person pressured me to meet in person"
        case "Financial requests":
            return "The other person asked for money or financial information"
        case "Boundary violations":
            return "The other person violated professional boundaries"
        case "Disrespectful behavior":
            return "The other person was disrespectful or rude"
        case "Threatening language":
            return "The other person used threatening language"
        default:
            return reason
        }
    }

    // MARK: - Safety Resources

    /// Crisis resources for safety escalations
    static let crisisResources = [
        SafetyResource(
            title: "National Suicide Prevention Lifeline",
            phone: "988",
            url: URL(string: "https://suicidepreventionlifeline.org")!,
            available24_7: true
        ),
        SafetyResource(
            title: "Crisis Text Line",
            phone: "Text HOME to 741741",
            url: URL(string: "https://www.crisistextline.org")!,
            available24_7: true
        ),
        SafetyResource(
            title: "International Association for Suicide Prevention",
            phone: nil,
            url: URL(string: "https://www.iasp.info/resources/Crisis_Centres/")!,
            available24_7: false
        ),
    ]

    struct SafetyResource {
        let title: String
        let phone: String?
        let url: URL
        let available24_7: Bool
    }
}

// MARK: - Safety Escalation Levels

/// Severity levels for safety concerns
enum SafetySeverity: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    var color: String {
        switch self {
        case .low: return "gray"
        case .medium: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }

    var icon: String {
        switch self {
        case .low: return "info.circle"
        case .medium: return "exclamationmark.circle"
        case .high: return "exclamationmark.triangle"
        case .critical: return "xmark.circle"
        }
    }
}

// MARK: - Safety Event

/// Record of a safety event for monitoring
struct SafetyEvent: Identifiable, Codable {
    let id: UUID
    let matchId: UUID
    let eventType: SafetyEventType
    let severity: SafetySeverity
    let description: String
    let createdAt: Date

    enum SafetyEventType: String, Codable {
        case flaggedMessage = "flagged_message"
        case reportCreated = "report_created"
        case escalationTriggered = "escalation_triggered"
        case crisisDetected = "crisis_detected"
        case matchEnded = "match_ended"
    }
}
