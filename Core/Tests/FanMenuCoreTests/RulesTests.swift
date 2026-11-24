import XCTest
@testable import FanMenuCore

final class RulesTests: XCTestCase {
    private let left = FanRange(lowest: 1499, top: 5348)
    private let right = FanRange(lowest: 1499, top: 5776)

    func testSpeedFromShareStaysInsideTheFansOwnRange() {
        XCTAssertEqual(left.speed(share: 0), 1499)
        XCTAssertEqual(left.speed(share: 1), 5348)
        XCTAssertEqual(left.speed(share: 0.5), 3424)   // 1499 + 1924.5, rounded
        XCTAssertEqual(right.speed(share: 0.5), 3638)  // 1499 + 2138.5, rounded
        XCTAssertEqual(left.speed(share: -3), 1499)
        XCTAssertEqual(left.speed(share: 7), 5348)
        XCTAssertEqual(left.kept(0), 1499)
        XCTAssertEqual(left.kept(9000), 5348)
        XCTAssertEqual(left.kept(.nan), 1499)
    }

    func testEachChoiceGivesItsShare() {
        func share(_ choice: FanChoice, chip: Double? = 80) -> Double? {
            FanPlan.share(choice: choice, myPercent: 45, chip: chip, start: 65, full: 95)
        }
        XCTAssertNil(share(.automatic))
        XCTAssertEqual(share(.quiet), 0)
        XCTAssertEqual(share(.cool), 0.5)
        XCTAssertEqual(share(.full), 1)
        XCTAssertEqual(share(.mySpeed), 0.45)
        XCTAssertEqual(share(.follow), 0.5)                 // 80° is halfway from 65° to 95°
        XCTAssertEqual(share(.follow, chip: nil), 0.5)      // no reading: the middle, not the lowest
    }

    func testFollowIsLowestUpToStartAndTopFromFull() {
        XCTAssertEqual(Follow.share(chip: 40, start: 65, full: 95), 0)
        XCTAssertEqual(Follow.share(chip: 65, start: 65, full: 95), 0)
        XCTAssertEqual(Follow.share(chip: 95, start: 65, full: 95), 1)
        XCTAssertEqual(Follow.share(chip: 120, start: 65, full: 95), 1)
        XCTAssertEqual(Follow.share(chip: 72.5, start: 65, full: 95), 0.25)
    }

    func testStartAndFullStayTenApartAndTheMovedOneWins() {
        var pair = Follow.settled(start: 90, full: 95, movedStart: true)
        XCTAssertEqual(pair.start, 85); XCTAssertEqual(pair.full, 95)       // Start cannot pass 85
        pair = Follow.settled(start: 80, full: 85, movedStart: true)
        XCTAssertEqual(pair.start, 80); XCTAssertEqual(pair.full, 90)       // Full is pushed up
        pair = Follow.settled(start: 65, full: 60, movedStart: false)
        XCTAssertEqual(pair.start, 50); XCTAssertEqual(pair.full, 60)       // Start is pushed down
        pair = Follow.settled(start: 40, full: 45, movedStart: false)
        XCTAssertEqual(pair.start, 40); XCTAssertEqual(pair.full, 60)       // Full cannot go under 60
    }

    func testFollowSmoothsAndDoesNotHunt() {
        XCTAssertNil(Follow.smoothed([]))
        XCTAssertEqual(Follow.smoothed([70]), 70)
        XCTAssertEqual(Follow.smoothed([10, 70, 80, 90]), 80)   // only the newest three
        XCTAssertTrue(Follow.worthSending(new: 3000, last: nil))
        XCTAssertFalse(Follow.worthSending(new: 3099, last: 3000))
        XCTAssertTrue(Follow.worthSending(new: 2900, last: 3000))
        XCTAssertTrue(Follow.worthSending(new: 1499, last: 1560, atAnEnd: true))    // the last small step down
        XCTAssertFalse(Follow.worthSending(new: 1499, last: 1499, atAnEnd: true))
    }

    func testTooHotHandsBackAfterFifteenSecondsButNotInFullOrAutomatic() {
        XCTAssertNil(HeatGuard.hotSince(hottest: 99.9, now: 50, since: 10))     // cooled: the count starts again
        XCTAssertEqual(HeatGuard.hotSince(hottest: 100, now: 50, since: nil), 50)
        XCTAssertEqual(HeatGuard.hotSince(hottest: 104, now: 60, since: 50), 50)
        XCTAssertNil(HeatGuard.hotSince(hottest: nil, now: 60, since: 50))
        XCTAssertFalse(HeatGuard.handsBack(choice: .quiet, hotSince: 50, now: 64.9))
        XCTAssertTrue(HeatGuard.handsBack(choice: .quiet, hotSince: 50, now: 65))
        XCTAssertTrue(HeatGuard.handsBack(choice: .follow, hotSince: 50, now: 80))
        XCTAssertFalse(HeatGuard.handsBack(choice: .full, hotSince: 50, now: 80))
        XCTAssertFalse(HeatGuard.handsBack(choice: .automatic, hotSince: 50, now: 80))
        XCTAssertFalse(HeatGuard.handsBack(choice: .cool, hotSince: nil, now: 80))
    }

    func testReadingsIgnoreSensorsThatAreNotThere() {
        XCTAssertEqual(Reading.average([70, 80, 0, 500]), 75)
        XCTAssertEqual(Reading.hottest([70, 92, 0, 500]), 92)
        XCTAssertNil(Reading.average([0, -3]))
        XCTAssertNil(Reading.hottest([]))
    }

    func testWords() {
        XCTAssertEqual(Words.turns(1775.8), "1,776")
        XCTAssertEqual(Words.turns(999), "999")
        XCTAssertEqual(Words.turns(12345678), "12,345,678")
        XCTAssertEqual(Words.turns(nil), "–")
        XCTAssertEqual(Words.degrees(71.6), "72°")
        XCTAssertEqual(Words.degrees(nil), "–")
        XCTAssertEqual(Words.status(.automatic), "The Mac decides")
        XCTAssertEqual(Words.status(.cool), "You decide: Cool")
        XCTAssertEqual(Words.hover(.follow), "Fans: you decide (Follow temperature)")
        XCTAssertEqual(Words.fanName(index: 0, count: 2), "Left")
        XCTAssertEqual(Words.fanName(index: 1, count: 2), "Right")
        XCTAssertEqual(Words.fanName(index: 0, count: 1), "Fan")
        XCTAssertEqual(Words.fanName(index: 2, count: 3), "Fan 3")
        XCTAssertFalse(FanChoice.automatic.appDecides)
        XCTAssertTrue(FanChoice.allCases.filter { $0 != .automatic }.allSatisfy(\.appDecides))
    }

    func testHelperStateAndDeadMan() {
        XCTAssertEqual(HelperCheck.state(installed: nil, wanted: "1"), .missing)
        XCTAssertEqual(HelperCheck.state(installed: "0", wanted: "1"), .outdated)
        XCTAssertEqual(HelperCheck.state(installed: "1", wanted: "1"), .ready)
        XCTAssertFalse(DeadMan.expired(running: true, lastWord: 100, now: 119.9))
        XCTAssertTrue(DeadMan.expired(running: true, lastWord: 100, now: 120))
        XCTAssertFalse(DeadMan.expired(running: false, lastWord: 100, now: 500))
        XCTAssertFalse(DeadMan.mayEnd(running: true, lastWord: 100, now: 500))
        XCTAssertTrue(DeadMan.mayEnd(running: false, lastWord: 100, now: 160))
    }

    func testBarPlaceOneCopyAndKeeper() {
        XCTAssertTrue(BarPlace.needsRepair(saved: 8250, visible: false, unseenSeconds: 10))
        XCTAssertFalse(BarPlace.needsRepair(saved: 8250, visible: false, unseenSeconds: 9))
        XCTAssertFalse(BarPlace.needsRepair(saved: 190, visible: false, unseenSeconds: 60))
        XCTAssertFalse(BarPlace.needsRepair(saved: 8250, visible: true, unseenSeconds: 60))
        let me = OneCopy.Copy(started: 10, pid: 500)
        XCTAssertTrue(OneCopy.mustQuit(me: me, others: [.init(started: 9, pid: 900)]))
        XCTAssertFalse(OneCopy.mustQuit(me: me, others: [.init(started: 11, pid: 100)]))
        XCTAssertTrue(OneCopy.mustQuit(me: me, others: [.init(started: 10, pid: 499)]))
        XCTAssertTrue(Keeper.handsOver(wanted: true, openedByKeeper: false, plain: false, inApplications: true))
        XCTAssertFalse(Keeper.handsOver(wanted: true, openedByKeeper: true, plain: false, inApplications: true))
        XCTAssertFalse(Keeper.handsOver(wanted: false, openedByKeeper: false, plain: false, inApplications: true))
    }
}
