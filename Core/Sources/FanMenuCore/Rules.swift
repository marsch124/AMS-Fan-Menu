import Foundation

// The rules of AMS Fan Menu that need no hardware, so they can be tested in seconds.

/// Who runs the fans, and how.
public enum FanChoice: String, CaseIterable, Sendable {
    case automatic, quiet, cool, full, mySpeed, follow

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .quiet: return "Quiet"
        case .cool: return "Cool"
        case .full: return "Full"
        case .mySpeed: return "My speed"
        case .follow: return "Follow temperature"
        }
    }

    /// A few plain words under the button.
    public var hint: String {
        switch self {
        case .automatic: return "the Mac decides"
        case .quiet: return "lowest speed"
        case .cool: return "half speed"
        case .full: return "top speed"
        case .mySpeed: return "the speed you set"
        case .follow: return "faster as it gets warmer"
        }
    }

    /// The app runs the fans: the menu bar mark is blue.
    public var appDecides: Bool { self != .automatic }
}

/// One fan's own range, as the Mac reports it, in turns a minute.
public struct FanRange: Equatable, Sendable {
    public let lowest: Double
    public let top: Double

    public init(lowest: Double, top: Double) {
        self.lowest = lowest
        self.top = max(top, lowest)
    }

    /// The speed a share of the way from lowest (0) to top (1), in whole turns.
    public func speed(share: Double) -> Double {
        let part = min(max(share, 0), 1)
        return (lowest + part * (top - lowest)).rounded()
    }

    /// Never below the fan's lowest, never above its top.
    public func kept(_ speed: Double) -> Double {
        guard speed.isFinite else { return lowest }
        return min(max(speed, lowest), top)
    }
}

/// From a choice to a speed.
public enum FanPlan {
    public static let coolShare = 0.5

    /// How far from lowest (0) to top (1) the fans should run; nil = the Mac decides.
    public static func share(choice: FanChoice, myPercent: Double, chip: Double?, start: Double, full: Double) -> Double? {
        switch choice {
        case .automatic: return nil
        case .quiet: return 0
        case .cool: return coolShare
        case .full: return 1
        case .mySpeed: return min(max(myPercent, 0), 100) / 100
        case .follow:
            // No reading: stay in the middle rather than guess low.
            guard let chip else { return coolShare }
            return Follow.share(chip: chip, start: start, full: full)
        }
    }
}

/// Follow temperature: lowest speed up to Start, top speed from Full, evenly in between.
public enum Follow {
    public static let startRange = 40.0...85.0
    public static let fullRange = 60.0...100.0
    /// Start and Full stay at least this far apart.
    public static let gap = 10.0
    public static let step = 5.0
    public static let defaultStart = 65.0
    public static let defaultFull = 95.0
    /// A new speed is sent only when it differs by this many turns, so the fans do not hunt.
    public static let worthTurns = 100.0
    /// The temperature is the average of this many readings.
    public static let smoothOver = 3

    public static func share(chip: Double, start: Double, full: Double) -> Double {
        guard full > start else { return chip >= full ? 1 : 0 }
        return min(max((chip - start) / (full - start), 0), 1)
    }

    /// Keeps the two in their ranges and apart: the one that was moved wins, the other gives way.
    public static func settled(start: Double, full: Double, movedStart: Bool) -> (start: Double, full: Double) {
        var s = min(max(start, startRange.lowerBound), startRange.upperBound)
        var f = min(max(full, fullRange.lowerBound), fullRange.upperBound)
        if f - s < gap {
            if movedStart {
                f = min(s + gap, fullRange.upperBound)
                s = min(s, f - gap)
            } else {
                s = max(f - gap, startRange.lowerBound)
                f = max(f, s + gap)
            }
        }
        return (s, f)
    }

    /// The average of the newest readings; nil when there are none.
    public static func smoothed(_ readings: [Double]) -> Double? {
        let newest = readings.suffix(smoothOver)
        guard !newest.isEmpty else { return nil }
        return newest.reduce(0, +) / Double(newest.count)
    }

    /// `atAnEnd`: the new speed is the fan's lowest or its top; that last small step is always taken,
    /// so the fans really arrive there.
    public static func worthSending(new: Double, last: Double?, atAnEnd: Bool = false) -> Bool {
        guard let last else { return true }
        if atAnEnd { return new != last }
        return abs(new - last) >= worthTurns
    }
}

/// Too hot: the Mac gets its fans back.
public enum HeatGuard {
    /// The hottest processor core at or above this …
    public static let limit = 100.0
    /// … for this many seconds.
    public static let patience = 15.0

    /// Full already runs the fans at their top, so there is nothing to hand back.
    public static func watches(_ choice: FanChoice) -> Bool {
        choice.appDecides && choice != .full
    }

    /// Since when it has been too hot without a break (nil = it is not).
    public static func hotSince(hottest: Double?, now: Double, since: Double?) -> Double? {
        guard let hottest, hottest >= limit else { return nil }
        return since ?? now
    }

    public static func handsBack(choice: FanChoice, hotSince: Double?, now: Double) -> Bool {
        guard watches(choice), let hotSince else { return false }
        return now - hotSince >= patience
    }
}

/// Temperature readings.
public enum Reading {
    /// A sensor that is not there answers 0 or nonsense.
    public static func plausible(_ value: Double) -> Bool { value > 5 && value < 130 }

    public static func average(_ values: [Double]) -> Double? {
        let good = values.filter(plausible)
        guard !good.isEmpty else { return nil }
        return good.reduce(0, +) / Double(good.count)
    }

    public static func hottest(_ values: [Double]) -> Double? {
        values.filter(plausible).max()
    }
}

/// The words and figures the app shows.
public enum Words {
    /// "1,776": whole turns with a comma, the same on every Mac.
    public static func turns(_ speed: Double?) -> String {
        guard let speed, speed.isFinite else { return "–" }
        let whole = Int(speed.rounded())
        let digits = String(abs(whole))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return (whole < 0 ? "-" : "") + out
    }

    /// "72°"
    public static func degrees(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        return "\(Int(value.rounded()))°"
    }

    public static func status(_ choice: FanChoice) -> String {
        choice.appDecides ? "You decide: \(choice.title)" : "The Mac decides"
    }

    public static func hover(_ choice: FanChoice) -> String {
        choice.appDecides ? "Fans: you decide (\(choice.title))" : "Fans: the Mac decides"
    }

    /// The name of a fan by its place: the first is the left one.
    public static func fanName(index: Int, count: Int) -> String {
        guard count == 2 else { return count == 1 ? "Fan" : "Fan \(index + 1)" }
        return index == 0 ? "Left" : "Right"
    }
}

/// The small helper that is allowed to set the fans.
public enum HelperState: Equatable, Sendable {
    /// Never approved (or removed).
    case missing
    /// There, but from an older version of the app.
    case outdated
    case ready
}

public enum HelperCheck {
    public static func state(installed: String?, wanted: String) -> HelperState {
        guard let installed else { return .missing }
        return installed == wanted ? .ready : .outdated
    }
}

/// The helper gives the fans back by itself when the app has gone silent.
public enum DeadMan {
    /// The app repeats its choice every few seconds; this long without a word means it is gone.
    public static let seconds = 20.0
    /// How often the app repeats its choice.
    public static let repeatEvery = 3.0
    /// With nothing to do for this long, the helper ends; the Mac starts it again when needed.
    public static let idleExit = 60.0

    public static func expired(running: Bool, lastWord: Double, now: Double) -> Bool {
        running && now - lastWord >= seconds
    }

    public static func mayEnd(running: Bool, lastWord: Double, now: Double) -> Bool {
        !running && now - lastWord >= idleExit
    }
}

/// Where the menu bar item sits, and when it has to be put back.
public enum BarPlace {
    /// The starting place: points from the right edge.
    public static let home = 190.0
    /// Saved places above this are the Mac's far-left group.
    public static let farLeft = 1000.0
    /// How long the item must be out of sight before it is moved back.
    public static let patience = 10.0

    public static func needsRepair(saved: Double?, visible: Bool, unseenSeconds: Double) -> Bool {
        guard let saved, !visible else { return false }
        return saved > farLeft && unseenSeconds >= patience
    }
}

/// Only one copy of the app in the menu bar.
public enum OneCopy {
    /// One running copy: when it started (seconds) and its process number.
    public struct Copy: Equatable {
        public let started: Double
        public let pid: Int32
        public init(started: Double, pid: Int32) { self.started = started; self.pid = pid }
    }

    /// The copies that started before `me`. Same start time: the smaller process number counts as earlier.
    public static func earlier(than me: Copy, among others: [Copy]) -> [Copy] {
        others.filter { $0.started < me.started || ($0.started == me.started && $0.pid < me.pid) }
    }

    /// When two copies start in the same moment, the one that started first stays and the later one quits.
    public static func mustQuit(me: Copy, others: [Copy]) -> Bool {
        !earlier(than: me, among: others).isEmpty
    }
}

/// The keeper: a second start order with the Mac, apart from the Mac's own login list. It opens the app at
/// every login and opens it again when it stops unexpectedly.
public enum Keeper {
    public static let label = "com.schabbauer.AMSFanMenu.keeper"
    /// How a copy knows the keeper opened it.
    public static let argument = "--keeper"
    /// For checks: a copy opened with this never hands itself over to the keeper.
    public static let plainArgument = "--plain"

    /// The start order as the Mac wants it written down.
    public static func plist(executable: String, bundleID: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executable, argument],
            // Opened at every login …
            "RunAtLoad": true,
            // … and again after an unexpected stop, but not after Quit (a clean end).
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            // So that System Settings lists it under the app's own name.
            "AssociatedBundleIdentifiers": [bundleID],
        ]
    }

    /// A copy opened by hand (or by the Mac's login list) gives way to the keeper, so the app is always looked
    /// after — but only while "Open at login" is on and the app sits in an Applications folder.
    public static func handsOver(wanted: Bool, openedByKeeper: Bool, plain: Bool, inApplications: Bool) -> Bool {
        wanted && !openedByKeeper && !plain && inApplications
    }
}
