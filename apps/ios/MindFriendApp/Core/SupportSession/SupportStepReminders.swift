import Foundation
import UserNotifications

enum SupportStepReminderError: Error, LocalizedError {
    case permissionDenied, invalidDate, schedulingFailed, requestInProgress
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Notifications are off. Your step is still saved. You can allow notifications in Settings."
        case .invalidDate: return "Choose a future time for this reminder."
        case .requestInProgress: return "The earlier reminder request is still finishing. Try again in a moment."
        case .schedulingFailed: return "The reminder was not set. Your step is saved; try setting the reminder again."
        }
    }
}

@MainActor
protocol SupportStepReminding {
    func schedule(ownerID: UUID, activityID: UUID, at: Date) async throws
    func cancel(ownerID: UUID, activityID: UUID)
    func pending(ownerID: UUID) async -> [UUID: Date]
    func cancelAll(ownerID: UUID) async
    func authorizationAllowsDelivery() async -> Bool
}

/// Only explicit Set reminder calls add a notification. Reconciliation reads and cancels;
/// it never asks permission or silently recreates reminders after a sign-in or sync.
@MainActor
final class LocalSupportStepReminders: SupportStepReminding {
    private let center: UNUserNotificationCenter
    private let epochID: UUID
    private var knownIdentifiers: [UUID: [UUID: Set<String>]] = [:]
    init(center: UNUserNotificationCenter = .current(), epochID: UUID = UUID()) {
        self.center = center
        self.epochID = epochID
    }

    static func prefix(ownerID: UUID) -> String { "support-step.\(ownerID.uuidString.lowercased())." }
    static func identifier(ownerID: UUID, activityID: UUID, epochID: UUID) -> String {
        prefix(ownerID: ownerID) + activityID.uuidString.lowercased() + "." + epochID.uuidString.lowercased()
    }

    private func identifier(ownerID: UUID, activityID: UUID) -> String {
        Self.identifier(ownerID: ownerID, activityID: activityID, epochID: epochID)
    }

    func schedule(ownerID: UUID, activityID: UUID, at: Date) async throws {
        guard at.timeIntervalSinceNow > 0, at.timeIntervalSince1970.isFinite else { throw SupportStepReminderError.invalidDate }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { throw SupportStepReminderError.permissionDenied }
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            throw SupportStepReminderError.permissionDenied
        }
        try Task.checkCancellation()
        guard at.timeIntervalSinceNow > 0 else { throw SupportStepReminderError.invalidDate }
        let content = UNMutableNotificationContent()
        content.title = "MindFriend"
        content.body = "A step you saved is here when you want it."
        content.sound = .default
        // Match the chosen absolute instant. Travel does not move the notification.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let id = identifier(ownerID: ownerID, activityID: activityID)
        knownIdentifiers[ownerID, default: [:]][activityID, default: []].insert(id)
        let request = UNNotificationRequest(identifier: id,
            content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        do { try await center.add(request) }
        catch { throw SupportStepReminderError.schedulingFailed }
    }

    func cancel(ownerID: UUID, activityID: UUID) {
        let ids = Array((knownIdentifiers[ownerID]?[activityID] ?? []).union([identifier(ownerID: ownerID, activityID: activityID)]))
        knownIdentifiers[ownerID]?[activityID] = nil
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func cancelAll(ownerID: UUID) async {
        let prefix = Self.prefix(ownerID: ownerID)
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier)
        let delivered = await center.deliveredNotifications().filter { $0.request.identifier.hasPrefix(prefix) }.map { $0.request.identifier }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    func authorizationAllowsDelivery() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func pending(ownerID: UUID) async -> [UUID: Date] {
        let prefix = Self.prefix(ownerID: ownerID)
        var values: [UUID: Date] = [:]
        for request in await center.pendingNotificationRequests() where request.identifier.hasPrefix(prefix) {
            let suffix = String(request.identifier.dropFirst(prefix.count))
            if let id = UUID(uuidString: String(suffix.split(separator: ".", maxSplits: 1).first ?? "")),
               let trigger = request.trigger as? UNCalendarNotificationTrigger, let date = trigger.nextTriggerDate() {
                values[id] = date
                knownIdentifiers[ownerID, default: [:]][id, default: []].insert(request.identifier)
            }
        }
        return values
    }
}
