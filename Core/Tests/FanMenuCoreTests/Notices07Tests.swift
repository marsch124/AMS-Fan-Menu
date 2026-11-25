import XCTest
@testable import FanMenuCore

final class Notices07Tests: XCTestCase {
    /// 0.7: the heat notice names the app working hardest; an app's helpers count for the app.
    func testBusiestApp() {
        let ps = """
          45.0 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)
          30.0 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
         120.0 /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend
         300.0 kernel_task
          12,5 /usr/libexec/trustd
        """
        XCTAssertEqual(BusiestApp.busiest(psOutput: ps)?.name, "Xcode")
        XCTAssertEqual(BusiestApp.busiest(psOutput: ps)?.share, 120)
        XCTAssertEqual(BusiestApp.appName(path: "/usr/libexec/trustd"), "trustd")
        XCTAssertEqual(BusiestApp.appName(path: "/System/Library/Frameworks/CoreServices.framework/Support/mds_stores"), "Spotlight")
        XCTAssertEqual(BusiestApp.appName(path: "/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac-setapp.HealthMonitor"), "CleanMyMac-setapp HealthMonitor")
        XCTAssertEqual(BusiestApp.busiest(psOutput: " 15.0 /x/mds\n 15.0 /x/mds_stores\n 25.0 /x/trustd")?.name, "Spotlight", "its workers count together")
        XCTAssertNil(BusiestApp.busiest(psOutput: "  5.0 /usr/libexec/trustd\n  300.0 kernel_task"), "nothing stands out")
        XCTAssertEqual(BusiestApp.words("Xcode"), "Working hardest: Xcode.")
    }

    /// 0.7: the fan check-up says which fan got to 90 % of its top.
    func testFanCheckWords() {
        let names = ["Left", "Right"], tops = [5348.0, 5776.0]
        XCTAssertEqual(FanCheck.words(names: names, best: [5310, 5750], tops: tops),
                       "Both fans fine \u{00B7} Left 5,310 of 5,348 \u{00B7} Right 5,750 of 5,776")
        XCTAssertEqual(FanCheck.words(names: names, best: [5310, 3900], tops: tops),
                       "Right fan fell short \u{00B7} Left 5,310 of 5,348 \u{00B7} Right 3,900 of 5,776")
        XCTAssertTrue(FanCheck.words(names: names, best: [100, 100], tops: tops).hasPrefix("Both fans fell short"))
    }

    /// 0.7: a fan well below what was asked for 30 seconds is worth one notice in six hours.
    func testFanFallingShort() {
        XCTAssertEqual(FanShort.short(asked: [3600, 3600], actual: [3500, 2100]), [1])
        XCTAssertEqual(FanShort.short(asked: nil, actual: [0, 0]), [], "the Mac decides: nothing was asked")
        XCTAssertEqual(FanShort.shortSince(short: [1], now: 10, since: nil), 10)
        XCTAssertNil(FanShort.shortSince(short: [], now: 20, since: 10))
        XCTAssertFalse(FanShort.due(shortSince: 10, now: 39, lastTold: nil))
        XCTAssertTrue(FanShort.due(shortSince: 10, now: 40, lastTold: nil))
        XCTAssertFalse(FanShort.due(shortSince: 10, now: 4000, lastTold: 100), "not again within six hours")
    }

    /// 0.7: notices are kept for the dots, by graph; files from before 0.7 still open.
    func testNoticesKept() throws {
        var history = History()
        history.notice("Heat notice", sensor: .chip, at: 100)
        history.notice("Right fan fell short", sensor: nil, at: 200)
        XCTAssertEqual(history.notices(.chip, last: 600, now: 300).map(\.words), ["Heat notice"])
        XCTAssertEqual(history.fanNotices(last: 600, now: 300).map(\.words), ["Right fan fell short"])
        let old = try JSONDecoder().decode(History.self, from: Data(#"{"samples":[],"marks":[]}"#.utf8))
        XCTAssertTrue(old.notices.isEmpty)
    }
}
