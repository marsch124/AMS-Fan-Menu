import XCTest
@testable import FanMenuCore

final class GraphsTests: XCTestCase {
    func testShownGraphsParseAndStore() {
        XCTAssertEqual(ShownGraphs.parse(nil), ShownGraphs.first)
        XCTAssertEqual(ShownGraphs.parse(""), ShownGraphs.first)
        XCTAssertEqual(ShownGraphs.parse("nonsense"), ShownGraphs.first)
        XCTAssertEqual(ShownGraphs.parse("fans,chip,zzz"), [.chip, .fans])      // fixed order, unknown dropped
        XCTAssertEqual(ShownGraphs.stored(ShownGraphs.first), "chip,graphics,battery,fans")
        XCTAssertEqual(ShownGraphs.parse(ShownGraphs.stored(GraphPick.allCases)), GraphPick.allCases)
    }

    func testToggleNeverLeavesNothing() {
        XCTAssertEqual(ShownGraphs.toggled(.storage, in: ShownGraphs.first), [.chip, .graphics, .battery, .storage, .fans])
        XCTAssertEqual(ShownGraphs.toggled(.graphics, in: ShownGraphs.first), [.chip, .battery, .fans])
        XCTAssertEqual(ShownGraphs.toggled(.chip, in: [.chip]), [.chip])
    }

    func testHeightsShareTheRoomByWeight() {
        XCTAssertEqual(ShownGraphs.heights(for: ShownGraphs.first, room: 570, spacing: 8), [172, 128, 128, 118])
        XCTAssertEqual(ShownGraphs.heights(for: [.chip, .fans], room: 570, spacing: 8).reduce(0, +), 562, accuracy: 0.001)
        XCTAssertEqual(ShownGraphs.heights(for: [.chip], room: 570, spacing: 8), [570])
        XCTAssertTrue(ShownGraphs.heights(for: [], room: 570, spacing: 8).isEmpty)
    }

    func testTimeIsTheInverseOfX() {
        XCTAssertEqual(Plot.time(share: 1, now: 1000, span: 600), 1000)
        XCTAssertEqual(Plot.time(share: 0, now: 1000, span: 600), 400)
        let t = Plot.time(share: 0.25, now: 1000, span: 600)
        XCTAssertEqual(Plot.x(time: t, now: 1000, span: 600), 0.25, accuracy: 1e-9)
    }

    func testNearestAndGap() {
        let samples = [100.0, 105, 110, 200].map { Sample(time: $0, chip: 70, speeds: []) }
        XCTAssertEqual(Plot.nearest(samples, to: 106, within: 45)?.time, 105)
        XCTAssertEqual(Plot.nearest(samples, to: 160, within: 45)?.time, 200)
        XCTAssertNil(Plot.nearest(samples, to: 150, within: 30))      // 40 s from 110, 50 from 200: a gap
        XCTAssertNil(Plot.nearest([], to: 1, within: 45))
        XCTAssertEqual(Plot.pointReach(span: 900), 45)
        XCTAssertEqual(Plot.pointReach(span: 21_600), 1080)
    }

    func testClockWords() {
        let utc = TimeZone(identifier: "UTC")!
        let t = 1_700_000_000.0          // 22:13:20 UTC
        XCTAssertEqual(Words.clock(t, seconds: false, timeZone: utc), "22:13")
        XCTAssertEqual(Words.clock(t, seconds: true, timeZone: utc), "22:13:20")
        XCTAssertEqual(Words.clock(t, seconds: false, timeZone: TimeZone(identifier: "Europe/Stockholm")!), "23:13")
    }

    func testStretches() {
        var h = History()
        XCTAssertTrue(h.stretches(last: 600, now: 1000).isEmpty)
        h.mark("Cool", at: 100)                       // began long before the window
        XCTAssertEqual(h.stretches(last: 600, now: 1000), [Stretch(from: 400, to: 1000, title: "Cool")])   // still on
        h.mark("Automatic", at: 700)
        XCTAssertEqual(h.stretches(last: 600, now: 1000), [Stretch(from: 400, to: 700, title: "Cool")])
        h.mark("Quiet", at: 800); h.mark("Cool", at: 900)
        XCTAssertEqual(h.stretches(last: 600, now: 1000).map(\.title), ["Cool", "Quiet", "Cool"])
        XCTAssertEqual(h.stretches(last: 600, now: 1000)[1], Stretch(from: 800, to: 900, title: "Quiet"))
        XCTAssertEqual(h.stretches(last: 50, now: 1000), [Stretch(from: 950, to: 1000, title: "Cool")])
        var none = History(); none.mark("Cool", at: 10); none.mark("Automatic", at: 20)
        XCTAssertTrue(none.stretches(last: 600, now: 1000).isEmpty)   // ended before the window
    }
}

final class Graphs06Tests: XCTestCase {
    private func history(_ flags: [Bool?], gapAfter: Int? = nil) -> History {
        var h = History()
        var t = 1000.0
        for (i, flag) in flags.enumerated() {
            h.add(Sample(time: t, chip: 50, speeds: [2000], charging: flag))
            t += History.every + (i == gapAfter ? 60 : 0)
        }
        return h
    }

    func testChargingStretches() {
        let now = 1000 + 5 * 9.0
        XCTAssertEqual(history([true, true, true, false, false]).chargingStretches(last: 600, now: now),
                       [Stretch(from: 1000, to: 1010, title: "charging")])
        XCTAssertEqual(history([false, true, true, nil, true]).chargingStretches(last: 600, now: now).count, 2)
        XCTAssertEqual(history([true, true, true, true], gapAfter: 1).chargingStretches(last: 600, now: now + 60).count, 2)
        XCTAssertEqual(history([false, true, true]).chargingStretches(last: 600, now: 1010),
                       [Stretch(from: 1005, to: 1010, title: "charging")])
        XCTAssertEqual(history([true, true, true, true]).chargingStretches(last: 10, now: 1015),
                       [Stretch(from: 1005, to: 1015, title: "charging")])
        XCTAssertTrue(history([false, nil, false]).chargingStretches(last: 600, now: 1010).isEmpty)
    }

    func testPauseShares() {
        let p = Pause(from: 700, to: 800, why: Pause.asleep)
        XCTAssertEqual(Plot.pauseShares(p, now: 1000, span: 400)?.lowerBound ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(Plot.pauseShares(p, now: 1000, span: 400)?.upperBound ?? -1, 0.5, accuracy: 0.0001)
        let clipped = Plot.pauseShares(p, now: 1000, span: 250)    // edge at 750
        XCTAssertEqual(clipped?.lowerBound ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(clipped?.upperBound ?? -1, 0.2, accuracy: 0.0001)
        XCTAssertNil(Plot.pauseShares(p, now: 1000, span: 100))
        XCTAssertNil(Plot.pauseShares(p, now: 600, span: 100))
    }

    func testSmallGraphScale() {
        XCTAssertEqual(Plot.tensScale([29.2, 33.8]), 20...40)
        XCTAssertEqual(Plot.tensScale([31, 31.5]), 30...40)
        XCTAssertEqual(Plot.tensScale([30, 30]), 30...40)
        XCTAssertEqual(Plot.tensScale([]), 20...50)
    }
}
