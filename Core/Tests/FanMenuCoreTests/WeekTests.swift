import XCTest
@testable import FanMenuCore

final class WeekTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-11-25 12:00 UTC is a Wednesday.
    private let noon = 1_795_608_000.0
    private let day = 86_400.0

    private func add(_ week: inout Week, _ time: Double, chip: Double? = 70, fans: Bool = true, app: Bool = false, seconds: Double = 5) {
        week.add(time: time, chip: chip, fansTurning: fans, appRuns: app, seconds: seconds, timeZone: utc)
    }

    func testMidnightStartsANewDay() {
        var week = Week()
        add(&week, noon + 11.9 * 3600)
        add(&week, noon + 12.1 * 3600)
        XCTAssertEqual(week.days.map(\.key), ["2026-11-25", "2026-11-26"])
    }

    func testOnlyEightDaysAreKept() {
        var week = Week()
        for back in (0..<10).reversed() { add(&week, noon - Double(back) * day) }
        XCTAssertEqual(week.days.count, 8)
        XCTAssertEqual(week.days.first?.key, "2026-11-18")
    }

    func testGapsAndBadSecondsCountAsZero() {
        var week = Week()
        add(&week, noon, chip: 95, app: true, seconds: 5)
        add(&week, noon + 100, chip: 95, app: true, seconds: 600)
        add(&week, noon + 200, chip: 95, app: true, seconds: -3)
        let tally = week.days[0]
        XCTAssertEqual(tally.secondsHot, 5)
        XCTAssertEqual(tally.secondsFans, 5)
        XCTAssertEqual(tally.secondsApp, 5)
    }

    func testHottestAndHotSecondsAdd() {
        var week = Week()
        add(&week, noon, chip: 89)
        add(&week, noon + 5, chip: 93)
        add(&week, noon + 10, chip: 90)
        add(&week, noon + 15, chip: 80, fans: false)
        XCTAssertEqual(week.days[0].hottest, 93)
        XCTAssertEqual(week.days[0].hottestTime, noon + 5)
        XCTAssertEqual(week.days[0].secondsHot, 10)
        XCTAssertEqual(week.days[0].secondsFans, 15)
    }

    func testSummaryOverSevenDays() {
        var week = Week()
        add(&week, noon - 7 * day, chip: 99)            // the eighth day: kept, not in the figures
        add(&week, noon - 2 * day, chip: 91, app: true)
        add(&week, noon, chip: 85)
        let summary = week.summary(now: noon, timeZone: utc)
        XCTAssertEqual(summary.days, 2)
        XCTAssertEqual(summary.hottest, 91)
        XCTAssertEqual(summary.secondsHot, 5)
        XCTAssertEqual(summary.secondsFans, 10)
        XCTAssertEqual(summary.secondsApp, 5)
        XCTAssertEqual(summary.since, noon - 2 * day - 12 * 3600)
        XCTAssertTrue(Week().summary(now: noon, timeZone: utc).isEmpty)
        XCTAssertNil(Week().summary(now: noon, timeZone: utc).hottest)
    }

    func testWords() {
        XCTAssertEqual(Words.duration(0), "0 min")
        XCTAssertEqual(Words.duration(30), "under 1 min")
        XCTAssertEqual(Words.duration(12 * 60 + 40), "12 min")
        XCTAssertEqual(Words.duration(5 * 3600 + 10 * 60), "5 h 10 min")
        XCTAssertEqual(Words.hottestMoment(93, at: noon + 2 * 3600 + 20 * 60, timeZone: utc), "93° · Wed 14:20")
        XCTAssertEqual(Words.countedSince(noon - 12 * 3600, days: 3, timeZone: utc), "Counted since 25 Nov")
        XCTAssertNil(Words.countedSince(noon, days: 7, timeZone: utc))
        XCTAssertNil(Words.countedSince(nil, days: 0, timeZone: utc))
    }

    func testCodableRoundTripAndSample() throws {
        var week = Week()
        add(&week, noon, chip: 92, app: true)
        let back = try JSONDecoder().decode(Week.self, from: JSONEncoder().encode(week))
        XCTAssertEqual(back, week)
        XCTAssertEqual(Week.sample(now: 1_795_000_000).summary(now: 1_795_000_000).days, 7)
    }
}
