import XCTest
@testable import FanMenuCore

final class MoreTests: XCTestCase {
    private func sample(_ time: Double, chip: Double? = 70, speeds: [Double] = [2000, 3000]) -> Sample {
        Sample(time: time, chip: chip, speeds: speeds)
    }

    func testHistoryKeepsOneReadingEveryFiveSecondsForSixHours() throws {
        var history = History()
        XCTAssertTrue(history.add(sample(1000)))
        XCTAssertFalse(history.add(sample(1004)))        // younger than 5 s after the last: not added
        XCTAssertTrue(history.add(sample(1005)))
        XCTAssertEqual(history.samples.count, 2)
        history.mark("Cool", at: 1010)
        XCTAssertEqual(history.samples(last: 6, now: 1010).map(\.time), [1005])
        XCTAssertEqual(history.marks(last: 60, now: 1050).map(\.title), ["Cool"])
        XCTAssertTrue(history.marks(last: 60, now: 1100).isEmpty)   // the mark is older than the window

        var old = History()
        old.add(sample(0)); old.mark("Quiet", at: 0)
        old.add(sample(21_600))                          // exactly six hours: still kept
        XCTAssertEqual(old.samples.count, 2)
        old.add(sample(21_601 + 5))                      // older than six hours: dropped
        XCTAssertEqual(old.samples.first?.time, 21_600)
        XCTAssertTrue(old.marks.isEmpty)

        let data = try JSONEncoder().encode(history)     // it survives being saved
        XCTAssertEqual(try JSONDecoder().decode(History.self, from: data), history)
    }

    func testTemperatureScaleIsWholeTensAtLeastThirtyApart() {
        XCTAssertEqual(Plot.temperatureScale([]), 40...100)
        XCTAssertEqual(Plot.temperatureScale([sample(0, chip: nil)]), 40...100)   // no chip reading at all
        XCTAssertEqual(Plot.temperatureScale([sample(0, chip: 71), sample(5, chip: 78)]), 60...90)
        XCTAssertEqual(Plot.temperatureScale([sample(0, chip: 95), sample(5, chip: 99)]), 70...100)   // grows downward at 100
        XCTAssertEqual(Plot.temperatureScale([sample(0, chip: 45), sample(5, chip: 95)]), 40...100)
    }

    func testSpeedScaleStartsAtZeroAndRoundsUpToAThousand() {
        XCTAssertEqual(Plot.speedScale([], top: 5776), 0...6000)
        XCTAssertEqual(Plot.speedScale([sample(0, speeds: [6400])], top: 5776), 0...7000)
        XCTAssertEqual(Plot.speedScale([], top: 0), 0...1000)     // never flatter than 1000
    }

    func testPlotPlacesPointsInTheGraph() {
        XCTAssertEqual(Plot.x(time: 550, now: 1000, span: 900), 0.5)
        XCTAssertEqual(Plot.x(time: 1000, now: 1000, span: 900), 1)
        XCTAssertEqual(Plot.x(time: 0, now: 1000, span: 900), 0)      // older than the edge: clamped
        XCTAssertEqual(Plot.x(time: 500, now: 1000, span: 0), 1)
        XCTAssertEqual(Plot.y(75, in: 60...90), 0.5)
        XCTAssertEqual(Plot.y(100, in: 60...90), 1)
        XCTAssertEqual(Plot.y(10, in: 60...90), 0)
        XCTAssertEqual(Plot.y(5, in: 5...5), 0)
        XCTAssertEqual(Plot.meanSpeed(sample(0, speeds: [2000, 3000])), 2500)
        XCTAssertNil(Plot.meanSpeed(sample(0, speeds: [])))
    }

    func testThinnedKeepsFirstAndLastAndTheLimit() {
        let all = (0..<10).map { sample(Double($0) * 5) }
        let few = Plot.thinned(all, limit: 4)
        XCTAssertEqual(few.count, 4)
        XCTAssertEqual(few.map(\.time), [0, 15, 30, 45])
        XCTAssertEqual(Plot.thinned(all, limit: 10), all)             // nothing to thin
        XCTAssertEqual(Plot.thinned(all, limit: 1), all)              // a limit under 2 is ignored
        XCTAssertEqual(Plot.thinned(all, limit: 2).map(\.time), [0, 45])
    }

    func testAGapIsMoreThanThreeReadingsApart() {
        XCTAssertFalse(Plot.isGap(sample(0), sample(15)))
        XCTAssertTrue(Plot.isGap(sample(0), sample(16)))
        XCTAssertFalse(Plot.isGap(sample(0), sample(30), thinnedBy: 2))   // thinned graphs allow wider steps
        XCTAssertTrue(Plot.isGap(sample(0), sample(31), thinnedBy: 2))
    }

    func testLastingEndsAndSaysHowMuchIsLeft() {
        XCTAssertEqual(Lasting.tenMinutes.seconds, 600)
        XCTAssertEqual(Lasting.thirtyMinutes.seconds, 1800)
        XCTAssertEqual(Lasting.hour.seconds, 3600)
        XCTAssertNil(Lasting.untilChanged.seconds)
        XCTAssertEqual(Lasting.tenMinutes.endsAt(from: 100), 700)
        XCTAssertNil(Lasting.untilChanged.endsAt(from: 100))
        XCTAssertFalse(Lasting.isOver(endsAt: 700, now: 699))
        XCTAssertTrue(Lasting.isOver(endsAt: 700, now: 700))
        XCTAssertFalse(Lasting.isOver(endsAt: nil, now: 9999))
        XCTAssertEqual(Lasting.leftWords(endsAt: 600, now: 0), "10 min left")
        XCTAssertEqual(Lasting.leftWords(endsAt: 450, now: 0), "8 min left")    // 7.5 rounds up
        XCTAssertEqual(Lasting.leftWords(endsAt: 61, now: 0), "2 min left")
        XCTAssertEqual(Lasting.leftWords(endsAt: 60, now: 0), "under a minute left")
        XCTAssertEqual(Lasting.leftWords(endsAt: 10, now: 20), "under a minute left")
        XCTAssertNil(Lasting.leftWords(endsAt: nil, now: 0))
    }

    func testOwnQuietAndCoolAreCleanedAndNamed() {
        XCTAssertEqual(Presets.cleanQuiet(22), 20)
        XCTAssertEqual(Presets.cleanQuiet(23), 25)
        XCTAssertEqual(Presets.cleanQuiet(60), 40)
        XCTAssertEqual(Presets.cleanQuiet(-5), 0)
        XCTAssertEqual(Presets.cleanQuiet(.nan), 0)
        XCTAssertEqual(Presets.cleanCool(10), 30)
        XCTAssertEqual(Presets.cleanCool(97), 90)
        XCTAssertEqual(Presets.cleanCool(52), 50)
        XCTAssertEqual(Presets.cleanCool(53), 55)
        XCTAssertEqual(Presets.cleanCool(.nan), 30)
        XCTAssertEqual(Presets.hint(.quiet, quiet: 0, cool: 50), "lowest speed")
        XCTAssertEqual(Presets.hint(.quiet, quiet: 20, cool: 50), "20 % speed")
        XCTAssertEqual(Presets.hint(.cool, quiet: 0, cool: 50), "half speed")
        XCTAssertEqual(Presets.hint(.cool, quiet: 0, cool: 40), "40 % speed")
        XCTAssertEqual(Presets.hint(.full, quiet: 20, cool: 40), "top speed")   // another choice keeps its own words
    }

    func testFanPlanUsesYourOwnQuietAndCool() {
        func share(_ choice: FanChoice, quiet: Double? = nil, cool: Double? = nil) -> Double? {
            if let quiet, let cool {
                return FanPlan.share(choice: choice, myPercent: 45, chip: 80, start: 65, full: 95,
                                     quietPercent: quiet, coolPercent: cool)
            }
            return FanPlan.share(choice: choice, myPercent: 45, chip: 80, start: 65, full: 95)
        }
        XCTAssertEqual(share(.quiet, quiet: 20, cool: 40), 0.2)
        XCTAssertEqual(share(.cool, quiet: 20, cool: 40), 0.4)
        XCTAssertEqual(share(.quiet), 0)       // defaults unchanged
        XCTAssertEqual(share(.cool), 0.5)
        XCTAssertEqual(share(.full, quiet: 20, cool: 40), 1)
    }

    func testHeatNoticeWaitsFiveMinutesAndThenPausesThirtyMinutes() {
        XCTAssertEqual(HeatNotice.hotSince(chip: 90, now: 100, since: nil), 100)
        XCTAssertEqual(HeatNotice.hotSince(chip: 95, now: 100, since: 40), 40)
        XCTAssertNil(HeatNotice.hotSince(chip: 89.9, now: 100, since: 40))     // cooled: the count starts again
        XCTAssertNil(HeatNotice.hotSince(chip: nil, now: 100, since: 40))
        func due(enabled: Bool = true, appDecides: Bool = false, hot: Double? = 0, now: Double, told: Double? = nil) -> Bool {
            HeatNotice.due(enabled: enabled, appDecides: appDecides, hotSince: hot, now: now, lastTold: told)
        }
        XCTAssertFalse(due(now: 299))
        XCTAssertTrue(due(now: 300))
        XCTAssertFalse(due(appDecides: true, now: 300))       // only while the Mac decides
        XCTAssertFalse(due(enabled: false, now: 300))
        XCTAssertFalse(due(hot: nil, now: 300))
        XCTAssertFalse(due(now: 2000, told: 1000))            // told 1000 s ago: too soon
        XCTAssertTrue(due(now: 2000, told: 200))              // exactly 30 minutes ago: again
    }

    func testCallQuietStartsAfterFifteenSecondsAndEndsAfterThirtyFree() {
        func start(enabled: Bool = true, inUse: Double? = 0, now: Double) -> CallQuiet.Step {
            CallQuiet.step(enabled: enabled, inUseSince: inUse, freeSince: nil, now: now, active: false)
        }
        XCTAssertEqual(start(now: 14.9), .nothing)            // a short dictation is no call
        XCTAssertEqual(start(now: 15), .goQuiet)
        XCTAssertEqual(start(enabled: false, now: 60), .nothing)
        XCTAssertEqual(start(inUse: nil, now: 60), .nothing)
        func end(enabled: Bool = true, free: Double? = 0, now: Double) -> CallQuiet.Step {
            CallQuiet.step(enabled: enabled, inUseSince: nil, freeSince: free, now: now, active: true)
        }
        XCTAssertEqual(end(now: 29), .nothing)
        XCTAssertEqual(end(now: 30), .putBack)
        XCTAssertEqual(end(free: nil, now: 500), .nothing)    // still in use
        XCTAssertEqual(end(enabled: false, free: nil, now: 5), .putBack)   // switched off mid-call: back at once
    }

    func testBatteryHandsBackWhenTheCableIsPulledAndPutsBackWhenItReturns() {
        func step(enabled: Bool = true, on: Bool, was: Bool, decides: Bool = true, parked: Bool = false) -> BatteryRule.Step {
            BatteryRule.step(enabled: enabled, onBattery: on, wasOnBattery: was, appDecides: decides, parked: parked)
        }
        XCTAssertEqual(step(on: true, was: false), .handBack)
        XCTAssertEqual(step(on: true, was: false, decides: false), .nothing)    // Automatic already
        XCTAssertEqual(step(enabled: false, on: true, was: false), .nothing)
        XCTAssertEqual(step(on: false, was: true, parked: true), .putBack)
        XCTAssertEqual(step(on: false, was: true, parked: false), .nothing)
        XCTAssertEqual(step(on: true, was: true), .nothing)
        XCTAssertEqual(step(on: false, was: false, parked: true), .nothing)
    }

    func testHappenedLogKeepsSixtyAndShowsTwentyNewestFirst() {
        var list: [Happening] = []
        for i in 1...59 { list = HappenedLog.adding(Happening(time: Double(i), text: "e\(i)"), to: list) }
        XCTAssertEqual(list.count, 59)
        list = HappenedLog.adding(Happening(time: 60, text: "e60"), to: list)
        XCTAssertEqual(list.count, 60)
        list = HappenedLog.adding(Happening(time: 61, text: "e61"), to: list)
        XCTAssertEqual(list.count, 60)
        XCTAssertEqual(list.first?.time, 2)                   // the oldest one went
        let shown = HappenedLog.forShow(list)
        XCTAssertEqual(shown.count, 20)
        XCTAssertEqual(shown.first?.time, 61)
        XCTAssertEqual(shown.last?.time, 42)
        XCTAssertEqual(HappenedLog.forShow(Array(list.prefix(3))).map(\.time), [4, 3, 2])
    }

    func testQuietRestsWhenCoolAndHoldsWhenTheMacWantsMore() {
        // Cool for 30 seconds: the fans may rest. Not before, not without a reading, not above 60°.
        XCTAssertEqual(QuietRest.coolSince(chip: 60, now: 10, since: nil), 10)
        XCTAssertEqual(QuietRest.coolSince(chip: 55, now: 20, since: 10), 10)
        XCTAssertNil(QuietRest.coolSince(chip: 60.5, now: 20, since: 10))
        XCTAssertNil(QuietRest.coolSince(chip: nil, now: 20, since: 10))
        func holding(cool: Double?, held: Double? = nil, now: Double, enabled: Bool = true) -> QuietRest.Step {
            QuietRest.step(enabled: enabled, resting: false, coolSince: cool, overSince: nil, heldSince: held, now: now)
        }
        XCTAssertEqual(holding(cool: 0, now: 29), .nothing)
        XCTAssertEqual(holding(cool: 0, now: 30), .rest)
        XCTAssertEqual(holding(cool: nil, now: 500), .nothing)
        XCTAssertEqual(holding(cool: 0, now: 30, enabled: false), .nothing)
        // Taken back from a rest: held for five minutes, however cool.
        XCTAssertEqual(holding(cool: 100, held: 100, now: 399), .nothing)
        XCTAssertEqual(holding(cool: 100, held: 100, now: 400), .rest)
        // Resting: a fan more than 150 turns above its Quiet speed for 4 seconds ends the rest.
        XCTAssertNil(QuietRest.overSince(speeds: [0, 0], quiet: [1499, 1499], now: 5, since: nil))
        XCTAssertNil(QuietRest.overSince(speeds: [1514, 1649], quiet: [1499, 1499], now: 5, since: nil))
        XCTAssertNil(QuietRest.overSince(speeds: [nil, nil], quiet: [1499, 1499], now: 5, since: 1))
        XCTAssertEqual(QuietRest.overSince(speeds: [1514, 1650], quiet: [1499, 1499], now: 5, since: nil), 5)
        XCTAssertEqual(QuietRest.overSince(speeds: [1900, 2000], quiet: [1499, 1499], now: 8, since: 5), 5)
        func resting(over: Double?, now: Double, enabled: Bool = true) -> QuietRest.Step {
            QuietRest.step(enabled: enabled, resting: true, coolSince: 0, overSince: over, heldSince: nil, now: now)
        }
        XCTAssertEqual(resting(over: nil, now: 1000), .nothing)
        XCTAssertEqual(resting(over: 10, now: 13), .nothing)
        XCTAssertEqual(resting(over: 10, now: 14), .hold)
        XCTAssertEqual(resting(over: nil, now: 1000, enabled: false), .hold)   // switched off in the middle of a rest
        XCTAssertEqual(Words.status(.quiet, left: nil, reason: nil, resting: true), "You decide: Quiet · fans resting")
        XCTAssertEqual(Words.status(.quiet, left: "8 min left", reason: "during a call", resting: true),
                       "You decide: Quiet (during a call) · fans resting · 8 min left")
        XCTAssertEqual(Words.status(.cool, left: nil, reason: nil, resting: true), "You decide: Cool")
    }

    func testMoreWords() {
        XCTAssertEqual(Words.status(.cool, left: "8 min left", reason: nil), "You decide: Cool · 8 min left")
        XCTAssertEqual(Words.status(.quiet, left: nil, reason: "during a call"), "You decide: Quiet (during a call)")
        XCTAssertEqual(Words.status(.automatic, left: nil, reason: "on battery"), "The Mac decides (on battery)")
        XCTAssertEqual(Words.status(.automatic, left: "8 min left", reason: nil), "The Mac decides")   // no "left" for Automatic
        XCTAssertEqual(Words.status(.cool, left: nil, reason: ""), "You decide: Cool")
        let fans: [(name: String, speed: Double?)] = [("Left", 3424), ("Right", nil)]
        XCTAssertEqual(Words.hover(.cool, fans: fans, chip: 71.6),
                       "Fans: you decide (Cool)\nLeft 3,424 · Right – · Chip 72°")
        XCTAssertEqual(Words.hover(.automatic, fans: [], chip: nil), "Fans: the Mac decides\nChip –")
    }
}
