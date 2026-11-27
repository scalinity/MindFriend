import XCTest
@testable import MindFriendApp

@MainActor
final class ActionPlanSchedulerTests: XCTestCase {
    func testAdjustForQuietHoursShiftsAfterQuietHoursEnd() {
        let scheduler = ActionPlanScheduler()
        let calendar = Calendar.current
        // Fixed clock at noon; the 06:00 slot is the next morning, so it is always in the future.
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 6))!

        let adjusted = scheduler.adjustForQuietHours(
            date: date,
            quietHoursStart: "22:00",
            quietHoursEnd: "07:00",
            now: now
        )

        let components = calendar.dateComponents([.hour, .minute], from: adjusted)
        XCTAssertEqual(components.hour, 7)
        XCTAssertEqual(components.minute, 0)
        XCTAssertTrue(calendar.isDate(adjusted, inSameDayAs: date))
    }

    func testAdjustForQuietHoursMovesPastEndTimeToFiveMinutesFromNow() {
        let scheduler = ActionPlanScheduler()
        let calendar = Calendar.current
        // 06:00 is inside quiet hours, but today's 07:00 end has already passed at noon.
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 12))!
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 6))!

        let adjusted = scheduler.adjustForQuietHours(
            date: date,
            quietHoursStart: "22:00",
            quietHoursEnd: "07:00",
            now: now
        )

        XCTAssertEqual(adjusted.timeIntervalSince(now), 5 * 60, accuracy: 0.001)
    }

    func testAdjustForQuietHoursKeepsOutsideWindow() {
        let scheduler = ActionPlanScheduler()
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: 15, minute: 30, second: 0, of: Date())!

        let adjusted = scheduler.adjustForQuietHours(
            date: date,
            quietHoursStart: "22:00",
            quietHoursEnd: "07:00"
        )

        XCTAssertEqual(adjusted.timeIntervalSince(date), 0, accuracy: 1.0)
    }

    func testAdjustForQuietHoursShiftsNextDayWhenOvernight() {
        let scheduler = ActionPlanScheduler()
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: Date())!

        let adjusted = scheduler.adjustForQuietHours(
            date: date,
            quietHoursStart: "22:00",
            quietHoursEnd: "07:00"
        )

        let components = calendar.dateComponents([.hour, .minute], from: adjusted)
        XCTAssertEqual(components.hour, 7)
        XCTAssertEqual(components.minute, 0)
        XCTAssertTrue(adjusted >= date)
    }
}
