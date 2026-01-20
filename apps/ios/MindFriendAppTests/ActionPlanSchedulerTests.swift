import XCTest
@testable import MindFriendApp

@MainActor
final class ActionPlanSchedulerTests: XCTestCase {
    func testAdjustForQuietHoursShiftsAfterQuietHoursEnd() {
        let scheduler = ActionPlanScheduler()
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: Date())!

        let adjusted = scheduler.adjustForQuietHours(
            date: date,
            quietHoursStart: "22:00",
            quietHoursEnd: "07:00"
        )

        let components = calendar.dateComponents([.hour, .minute], from: adjusted)
        XCTAssertEqual(components.hour, 7)
        XCTAssertEqual(components.minute, 0)
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
