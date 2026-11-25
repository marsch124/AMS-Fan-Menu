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

    /// 0.5: a graphics reading of about 9° (that part asleep) is no reading, also in what was kept before.
    func testAGraphicsReadingThatCannotBeTrueIsNoReading() {
        XCTAssertNil(Reading.average([9.2, 9.2, 0, 0], floor: Reading.graphicsFloor))
        XCTAssertEqual(Reading.average([9.2, 54, 52], floor: Reading.graphicsFloor), 53)
        var history = History()
        history.add(Sample(time: 0, chip: 50, speeds: [0], graphics: 9.2, battery: 30))
        history.add(Sample(time: 5, chip: 51, speeds: [0], graphics: 52, battery: 30))
        let clean = history.withoutFalseGraphics()
        XCTAssertNil(clean.samples[0].graphics)
        XCTAssertEqual(clean.samples[0].battery, 30)
        XCTAssertEqual(clean.samples[1].graphics, 52)
    }

    /// 0.6: a stretch without readings carries its reason, and old files without any still open.
    func testAPauseSaysWhyThereAreNoReadings() throws {
        var history = History()
        history.add(Sample(time: 0, chip: 50, speeds: [0], charging: true))
        history.pause(from: 5, to: 12, why: Pause.asleep)
        XCTAssertTrue(history.pauses.isEmpty, "shorter than three readings: not worth a word")
        history.pause(from: 100, to: 1900, why: Pause.asleep)
        XCTAssertEqual(history.pause(at: 500)?.why, "asleep")
        XCTAssertNil(history.pause(at: 2000))
        XCTAssertEqual(history.pauses(last: 600, now: 2400).count, 1, "it ends inside the last ten minutes")
        XCTAssertTrue(history.pauses(last: 600, now: 9000).isEmpty)
        let back = try JSONDecoder().decode(History.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(back.pauses, history.pauses)
        XCTAssertEqual(back.samples.first?.charging, true)
        let old = try JSONDecoder().decode(History.self, from: Data(#"{"samples":[{"time":5,"chip":70,"speeds":[1500]}],"marks":[]}"#.utf8))
        XCTAssertTrue(old.pauses.isEmpty)
        XCTAssertNil(old.samples.first?.charging)
        history.add(Sample(time: 1900 + History.keep + 10, chip: 50, speeds: [0]))
        XCTAssertTrue(history.pauses.isEmpty, "a pause older than six hours is dropped")
    }

    /// 0.6: the word when a timed choice ends.
    func testTheWordWhenATimedChoiceEnds() {
        XCTAssertEqual(Worth.overWords(title: "Cool", change: Worth.change(seconds: 600, from: 78, to: 61)),
                       "Cool is over: chip 78° down to 61°. The Mac has the fans again.")
        XCTAssertEqual(Worth.overWords(title: "Full", change: Worth.change(seconds: 60, from: 78, to: 61)),
                       "Full is over. The Mac has the fans again.")
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
