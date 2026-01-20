import Foundation
import EventKit
import UserNotifications

@MainActor
final class ActionPlanScheduler {
    private let eventStore = EKEventStore()
    private let notificationCenter = UNUserNotificationCenter.current()

    func requestCalendarAccess() async throws -> Bool {
        try await eventStore.requestAccess(to: .event)
    }

    func schedulePlan(
        planId: String,
        title: String,
        scheduledFor: Date,
        quietHoursStart: String?,
        quietHoursEnd: String?,
        fallbackToNotifications: Bool
    ) async throws -> Date {
        let adjusted = adjustForQuietHours(
            date: scheduledFor,
            quietHoursStart: quietHoursStart,
            quietHoursEnd: quietHoursEnd
        )

        if fallbackToNotifications {
            try await scheduleLocalNotification(
                planId: planId,
                title: title,
                scheduledFor: adjusted
            )
            return adjusted
        }

        let granted = try await requestCalendarAccess()
        if !granted {
            try await scheduleLocalNotification(
                planId: planId,
                title: title,
                scheduledFor: adjusted
            )
            return adjusted
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = adjusted
        event.endDate = adjusted.addingTimeInterval(60 * 15)
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(absoluteDate: adjusted))

        try eventStore.save(event, span: .thisEvent)
        return adjusted
    }

    func cancelSchedule(planId: String) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [planNotificationId(planId)])
    }

    func adjustForQuietHours(date: Date, quietHoursStart: String?, quietHoursEnd: String?) -> Date {
        guard let start = quietHoursStart, let end = quietHoursEnd else {
            return date
        }

        guard let startMinutes = minutesFromTimeString(start),
              let endMinutes = minutesFromTimeString(end) else {
            return date
        }

        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let inQuietHours: Bool

        if startMinutes > endMinutes {
            inQuietHours = minutes >= startMinutes || minutes < endMinutes
        } else {
            inQuietHours = minutes >= startMinutes && minutes < endMinutes
        }

        guard inQuietHours else { return date }

        var adjusted = date
        let dayOffset = startMinutes > endMinutes && minutes < endMinutes ? -1 : 0
        if let endDate = calendar.date(bySettingHour: endMinutes / 60, minute: endMinutes % 60, second: 0, of: date) {
            adjusted = endDate
            if dayOffset == 0 && adjusted < date {
                adjusted = calendar.date(byAdding: .day, value: 1, to: adjusted) ?? adjusted
            }
        }

        if adjusted < Date() {
            adjusted = Date().addingTimeInterval(60 * 5)
        }

        return adjusted
    }

    private func scheduleLocalNotification(planId: String, title: String, scheduledFor: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Your Action Plan is ready to start."
        content.sound = .default
        content.userInfo = ["type": "action_plan", "plan_id": planId]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledFor)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: planNotificationId(planId), content: content, trigger: trigger)

        try await notificationCenter.add(request)
    }

    private func planNotificationId(_ planId: String) -> String {
        "action_plan_\(planId)"
    }

    private func minutesFromTimeString(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return hour * 60 + minute
    }
}
