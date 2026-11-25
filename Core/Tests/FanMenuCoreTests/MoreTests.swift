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

    /// 0.3.1: another app may ask for a choice with a time of its own ("cool:600").
    func testAWishFromOutsideMayCarryItsOwnTime() {
        XCTAssertEqual(OutsideAsk.parse("cool")?.choice, .cool)
        XCTAssertNil(OutsideAsk.parse("cool")?.seconds, "a plain wish follows the For line, as before")
        XCTAssertEqual(OutsideAsk.parse("cool:600")?.seconds, 600)
        XCTAssertEqual(OutsideAsk.parse("full:600")?.choice, .full)
        XCTAssertNil(OutsideAsk.parse("automatic:600")?.seconds, "Automatic never has a time")
        XCTAssertEqual(OutsideAsk.parse("automatic:600")?.choice, .automatic)
        XCTAssertEqual(OutsideAsk.parse("cool:5")?.seconds, 60, "never shorter than a minute")
        XCTAssertEqual(OutsideAsk.parse("cool:999999")?.seconds, 4 * 3600, "never longer than four hours")
        XCTAssertNil(OutsideAsk.parse("cool:soon"))
        XCTAssertNil(OutsideAsk.parse("cool:-5"))
        XCTAssertNil(OutsideAsk.parse("cool:600:1"))
        XCTAssertNil(OutsideAsk.parse("warm"))
        XCTAssertEqual(OutsideAsk.words(seconds: 600), "10 minutes")
        XCTAssertEqual(OutsideAsk.words(seconds: 3600), "1 hour")
        XCTAssertEqual(OutsideAsk.words(seconds: 5400), "90 minutes")
        XCTAssertEqual(OutsideAsk.shown(pick: .untilChanged, ownSeconds: nil), .untilChanged)
        XCTAssertEqual(OutsideAsk.shown(pick: .untilChanged, ownSeconds: 600), .tenMinutes, "the For line shows the time that runs")
        XCTAssertNil(OutsideAsk.shown(pick: .hour, ownSeconds: 900), "a time that is none of the four lights none")
    }

    /// 0.4: a reading carries all three temperatures; one kept before 0.4 has only the chip and still opens.
    func testAReadingKeepsAllThreeTemperaturesAndOldOnesStillOpen() throws {
        let new = Sample(time: 5, chip: 70, speeds: [1500], graphics: 64, battery: 31)
        let back = try JSONDecoder().decode(Sample.self, from: JSONEncoder().encode(new))
        XCTAssertEqual(back, new)
        XCTAssertEqual(Sensor.graphics.value(in: back), 64)
        XCTAssertEqual(Sensor.battery.value(in: back), 31)
        let old = try JSONDecoder().decode(Sample.self, from: Data(#"{"time":5,"chip":70,"speeds":[1500]}"#.utf8))
        XCTAssertEqual(old.chip, 70)
        XCTAssertNil(old.graphics)
        XCTAssertNil(old.battery)
    }

    /// 0.4: the level lines hold only true figures, and the scale always shows them.
    func testLevelLinesAndTheirScale() {
        XCTAssertEqual(Levels.of(.chip).map(\.degrees), [90, 100])
        XCTAssertEqual(Levels.of(.chip).map(\.words), ["Heat notice 90°", "Too hot 100°"])
        XCTAssertEqual(Levels.of(.chip, fullSeenAt: 97.4).last?.words, "Fans at full in Automatic · seen at 97°")
        XCTAssertEqual(Levels.of(.chip, fullSeenAt: 97.4).last?.kind, .macFull)
        XCTAssertTrue(Levels.of(.graphics).isEmpty, "nobody gives a figure for the graphics")
        XCTAssertEqual(Levels.of(.battery).map(\.degrees), [35, 44])
        XCTAssertEqual(Levels.scale(.chip, []), 80...110)
        XCTAssertEqual(Levels.scale(.chip, [sample(0, chip: 56), sample(5, chip: 78)]), 50...110)
        XCTAssertEqual(Levels.scale(.chip, [sample(0, chip: 112)]), 90...120, "a reading above the top lifts it")
        XCTAssertEqual(Levels.scale(.chip, [sample(0, chip: 95)]), 80...110, "never less than 30° tall")
        let cool = Sample(time: 0, chip: 60, speeds: [], graphics: 55, battery: 28)
        XCTAssertEqual(Levels.scale(.battery, [cool]), 20...50)
        XCTAssertEqual(Levels.scale(.graphics, [cool]), 50...110)
    }

    /// 0.4: the usual range is the middle 80 % of the kept readings, and needs 30 minutes of them.
    func testUsualRange() {
        XCTAssertNil(Usual.band(Array(repeating: 60, count: 359)))
        let values = (0..<1000).map { 40 + Double($0) * 0.05 }   // 40.00 … 89.95
        let band = Usual.band(values.shuffled())
        XCTAssertEqual(band?.lowerBound ?? 0, 45, accuracy: 0.1)
        XCTAssertEqual(band?.upperBound ?? 0, 85, accuracy: 0.1)
        XCTAssertEqual(Usual.words(41.2...77.6), "usual here 41° to 78°")
    }

    /// 0.4: where the Mac itself takes the fans to full is learned on the reading where that begins.
    func testFansAtFullInAutomaticIsLearnedOnlyFromTheMac() {
        let tops = [5348.0, 5776.0]
        XCTAssertFalse(FullSeen.isFull(speeds: [3000, 3000], tops: tops))
        XCTAssertTrue(FullSeen.isFull(speeds: [5100, 5300], tops: tops))
        XCTAssertFalse(FullSeen.isFull(speeds: [], tops: tops))
        // The Mac has the fans, they reach full: learned once, at that reading.
        var step = FullSeen.step(macHasFans: true, full: true, wasFull: false, chip: 97)
        XCTAssertEqual(step.seenAt, 97)
        step = FullSeen.step(macHasFans: true, full: true, wasFull: step.wasFull, chip: 92)
        XCTAssertNil(step.seenAt, "still full: nothing new, even though the chip has cooled")
        // You set Full, then give the fans back while they still spin fast: that was not the Mac's doing.
        step = FullSeen.step(macHasFans: false, full: true, wasFull: false, chip: 70)
        XCTAssertNil(step.seenAt)
        step = FullSeen.step(macHasFans: true, full: true, wasFull: step.wasFull, chip: 70)
        XCTAssertNil(step.seenAt)
        step = FullSeen.step(macHasFans: true, full: false, wasFull: step.wasFull, chip: 65)
        XCTAssertFalse(step.wasFull)
    }
}
