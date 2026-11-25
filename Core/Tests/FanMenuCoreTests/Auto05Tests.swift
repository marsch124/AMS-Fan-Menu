import XCTest
@testable import FanMenuCore

final class Auto05Tests: XCTestCase {
    /// 0.5: the heat notice counts from your own level, and the amber line moves with it.
    func testYourOwnHeatNoticeLevel() {
        XCTAssertEqual(HeatNotice.clean(88), 90)
        XCTAssertEqual(HeatNotice.clean(20), 80)
        XCTAssertEqual(HeatNotice.clean(200), 95)
        XCTAssertNil(HeatNotice.hotSince(chip: 84, level: 85, now: 10, since: nil))
        XCTAssertEqual(HeatNotice.hotSince(chip: 85, level: 85, now: 10, since: nil), 10)
        XCTAssertEqual(HeatNotice.hotSince(chip: 91, level: 85, now: 50, since: 10), 10)
        XCTAssertEqual(Levels.of(.chip, heatNotice: 85).first?.words, "Heat notice 85°")
        XCTAssertFalse(Levels.of(.chip, heatNotice: nil).contains { $0.kind == .watch }, "notice off: no amber line")
    }

    /// 0.5: the battery above 35° for 10 minutes is worth a word, at most once an hour.
    func testBatteryHeatNotice() {
        XCTAssertNil(BatteryNotice.hotSince(battery: 35, now: 0, since: nil), "above 35, not at 35")
        XCTAssertEqual(BatteryNotice.hotSince(battery: 35.6, now: 7, since: nil), 7)
        XCTAssertFalse(BatteryNotice.due(enabled: true, hotSince: 0, now: 599, lastTold: nil))
        XCTAssertTrue(BatteryNotice.due(enabled: true, hotSince: 0, now: 600, lastTold: nil))
        XCTAssertFalse(BatteryNotice.due(enabled: false, hotSince: 0, now: 600, lastTold: nil))
        XCTAssertFalse(BatteryNotice.due(enabled: true, hotSince: 0, now: 4000, lastTold: 600), "not again within the hour")
        XCTAssertTrue(BatteryNotice.due(enabled: true, hotSince: 0, now: 4200, lastTold: 600))
    }

    /// 0.5: quiet hours may run over midnight.
    func testQuietHours() {
        let from = 22 * 60, to = 7 * 60
        XCTAssertTrue(QuietHours.inside(minute: 22 * 60, from: from, to: to))
        XCTAssertTrue(QuietHours.inside(minute: 3 * 60, from: from, to: to))
        XCTAssertFalse(QuietHours.inside(minute: 7 * 60, from: from, to: to), "the end itself is outside")
        XCTAssertFalse(QuietHours.inside(minute: 12 * 60, from: from, to: to))
        XCTAssertTrue(QuietHours.inside(minute: 13 * 60, from: 12 * 60, to: 14 * 60))
        XCTAssertFalse(QuietHours.inside(minute: 13 * 60, from: 9 * 60, to: 9 * 60), "the same time twice: no hours")
        XCTAssertEqual(QuietHours.step(enabled: true, inside: true, active: false), .goQuiet)
        XCTAssertEqual(QuietHours.step(enabled: true, inside: true, active: true), .nothing)
        XCTAssertEqual(QuietHours.step(enabled: true, inside: false, active: true), .putBack)
        XCTAssertEqual(QuietHours.step(enabled: false, inside: true, active: true), .putBack, "switched off in the middle: back at once")
        XCTAssertEqual(QuietHours.step(enabled: false, inside: true, active: false), .nothing)
        XCTAssertEqual(QuietHours.words(22 * 60), "22:00")
        XCTAssertEqual(QuietHours.words(7 * 60 + 5), "07:05")
        XCTAssertEqual(QuietHours.clean(1500), 60)
        XCTAssertEqual(QuietHours.minute(of: 1_795_000_000, timeZone: TimeZone(identifier: "UTC")!), 11 * 60 + 6)
    }

    /// 0.5: what a choice did to the chip, said when it ends.
    func testWasTheChoiceWorthIt() {
        XCTAssertEqual(Worth.words(title: "Cool", seconds: 600, from: 78.2, to: 61.4), "Cool for 10 min: chip 78° down to 61°")
        XCTAssertEqual(Worth.words(title: "Quiet", seconds: 3900, from: 60, to: 71), "Quiet for 1 h 5 min: chip 60° up to 71°")
        XCTAssertEqual(Worth.words(title: "Full", seconds: 7200, from: 70.2, to: 69.8), "Full for 2 h: chip stayed at 70°")
        XCTAssertNil(Worth.words(title: "Cool", seconds: 90, from: 78, to: 70), "too short to say anything")
        XCTAssertNil(Worth.words(title: "Cool", seconds: 600, from: nil, to: 70))
    }
}
