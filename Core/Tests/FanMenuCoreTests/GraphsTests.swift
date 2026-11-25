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
