import Foundation

// The rules added in 0.2: the history behind the graphs, a choice for a limited time, your own Quiet and
// Cool, the heat notice, Quiet during calls, on battery, and the "What happened" list.

// MARK: History and graphs

/// One reading for the graphs.
public struct Sample: Codable, Equatable, Sendable {
    /// Seconds since 1970.
    public let time: Double
    /// The chip temperature in °C; nil when the Mac gave no reading.
    public let chip: Double?
    /// One speed per fan, in turns a minute.
    public let speeds: [Double]

    public init(time: Double, chip: Double?, speeds: [Double]) {
        self.time = time
        self.chip = chip
        self.speeds = speeds
    }
}

/// The moment the choice changed: a dashed line in the graphs.
public struct ChoiceMark: Codable, Equatable, Sendable {
    public let time: Double
    /// What it changed to, for example "Cool" or "Automatic".
    public let title: String

    public init(time: Double, title: String) {
        self.time = time
        self.title = title
    }
}

/// How much time a graph shows.
public enum GraphSpan: String, CaseIterable, Sendable {
    case quarter, hour, sixHours

    public var seconds: Double {
        switch self {
        case .quarter: return 15 * 60
        case .hour: return 60 * 60
        case .sixHours: return 6 * 60 * 60
        }
    }

    public var title: String {
        switch self {
        case .quarter: return "15 minutes"
        case .hour: return "1 hour"
        case .sixHours: return "6 hours"
        }
    }
}

/// The last six hours of readings, one every five seconds, and the moments the choice changed.
public struct History: Codable, Equatable, Sendable {
    /// Seconds between two readings.
    public static let every = 5.0
    /// Seconds kept.
    public static let keep = 6 * 60 * 60.0

    public private(set) var samples: [Sample] = []
    public private(set) var marks: [ChoiceMark] = []

    public init() {}

    /// Adds a reading unless the last one is younger than five seconds; drops what is older than six hours.
    /// Returns whether it was added.
    @discardableResult
    public mutating func add(_ sample: Sample) -> Bool {
        if let last = samples.last, sample.time - last.time < History.every - 0.5 { return false }
        samples.append(sample)
        trim(now: sample.time)
        return true
    }

    public mutating func mark(_ title: String, at time: Double) {
        marks.append(ChoiceMark(time: time, title: title))
        trim(now: time)
    }

    public mutating func trim(now: Double) {
        let oldest = now - History.keep
        if let first = samples.first, first.time < oldest { samples.removeAll { $0.time < oldest } }
        if let first = marks.first, first.time < oldest { marks.removeAll { $0.time < oldest } }
    }

    public func samples(last seconds: Double, now: Double) -> [Sample] {
        samples.filter { $0.time >= now - seconds && $0.time <= now }
    }

    public func marks(last seconds: Double, now: Double) -> [ChoiceMark] {
        marks.filter { $0.time >= now - seconds && $0.time <= now }
    }
}

/// Where things sit in a graph.
public enum Plot {
    /// The temperature scale: whole tens that hold every reading, at least 30° apart. No readings: 40…100.
    public static func temperatureScale(_ samples: [Sample]) -> ClosedRange<Double> {
        let values = samples.compactMap(\.chip)
        guard let low = values.min(), let high = values.max() else { return 40...100 }
        var bottom = (low / 10).rounded(.down) * 10
        var top = (high / 10).rounded(.up) * 10
        if top == bottom { top += 10 }
        while top - bottom < 30 {
            if top < 100 { top += 10 }
            if top - bottom < 30 { bottom -= 10 }
        }
        return bottom...top
    }

    /// The speed scale: from 0 to the fastest fan's top, rounded up to a whole thousand.
    public static func speedScale(_ samples: [Sample], top: Double) -> ClosedRange<Double> {
        let highest = max(top, samples.flatMap(\.speeds).max() ?? 0)
        return 0...max(1000, (highest / 1000).rounded(.up) * 1000)
    }

    /// Across the graph: 0 = the oldest edge, 1 = now.
    public static func x(time: Double, now: Double, span: Double) -> Double {
        guard span > 0 else { return 1 }
        return min(max(1 - (now - time) / span, 0), 1)
    }

    /// Up the graph: 0 = the bottom of the scale, 1 = its top.
    public static func y(_ value: Double, in scale: ClosedRange<Double>) -> Double {
        let height = scale.upperBound - scale.lowerBound
        guard height > 0 else { return 0 }
        return min(max((value - scale.lowerBound) / height, 0), 1)
    }

    /// At most `limit` readings for drawing, evenly picked, always with the first and the last.
    public static func thinned(_ samples: [Sample], limit: Int) -> [Sample] {
        guard limit >= 2, samples.count > limit else { return samples }
        let step = Double(samples.count - 1) / Double(limit - 1)
        return (0..<limit).map { samples[min(Int((Double($0) * step).rounded()), samples.count - 1)] }
    }

    /// Two readings this far apart are not joined by a line: the app was not running, or the Mac slept.
    public static func isGap(_ earlier: Sample, _ later: Sample, thinnedBy factor: Double = 1) -> Bool {
        later.time - earlier.time > History.every * 3 * max(factor, 1)
    }

    /// One speed for both fans: their average.
    public static func meanSpeed(_ sample: Sample) -> Double? {
        guard !sample.speeds.isEmpty else { return nil }
        return sample.speeds.reduce(0, +) / Double(sample.speeds.count)
    }
}

// MARK: A choice for a limited time

/// How long a choice stays on before the Mac gets the fans back.
public enum Lasting: String, CaseIterable, Codable, Sendable {
    case tenMinutes, thirtyMinutes, hour, untilChanged

    public var seconds: Double? {
        switch self {
        case .tenMinutes: return 10 * 60
        case .thirtyMinutes: return 30 * 60
        case .hour: return 60 * 60
        case .untilChanged: return nil
        }
    }

    public var title: String {
        switch self {
        case .tenMinutes: return "10 min"
        case .thirtyMinutes: return "30 min"
        case .hour: return "1 hour"
        case .untilChanged: return "Until I change"
        }
    }

    /// In a sentence: "Cool for 10 minutes". nil = no end.
    public var words: String? {
        switch self {
        case .tenMinutes: return "10 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .hour: return "1 hour"
        case .untilChanged: return nil
        }
    }

    /// When a choice switched on now ends; nil = it stays until you change it.
    public func endsAt(from now: Double) -> Double? {
        seconds.map { now + $0 }
    }

    public static func isOver(endsAt: Double?, now: Double) -> Bool {
        guard let endsAt else { return false }
        return now >= endsAt
    }

    /// "8 min left", "under a minute left"; nil when there is no end.
    public static func leftWords(endsAt: Double?, now: Double) -> String? {
        guard let endsAt else { return nil }
        let left = endsAt - now
        if left <= 60 { return "under a minute left" }
        return "\(Int((left / 60).rounded(.up))) min left"
    }
}

// MARK: Your own Quiet and Cool

public enum Presets {
    public static let quietRange = 0.0...40.0
    public static let coolRange = 30.0...90.0
    public static let step = 5.0
    public static let defaultQuiet = 0.0
    public static let defaultCool = 50.0

    public static func cleanQuiet(_ percent: Double) -> Double { clean(percent, quietRange) }
    public static func cleanCool(_ percent: Double) -> Double { clean(percent, coolRange) }

    private static func clean(_ percent: Double, _ range: ClosedRange<Double>) -> Double {
        guard percent.isFinite else { return range.lowerBound }
        return min(max((percent / step).rounded() * step, range.lowerBound), range.upperBound)
    }

    /// The words under a button: "lowest speed", "half speed", or the figure when you changed it.
    public static func hint(_ choice: FanChoice, quiet: Double, cool: Double) -> String {
        switch choice {
        case .quiet: return quiet <= 0 ? "lowest speed" : "\(Int(quiet)) % speed"
        case .cool: return cool == 50 ? "half speed" : "\(Int(cool)) % speed"
        default: return choice.hint
        }
    }
}

// MARK: The heat notice while the Mac decides

public enum HeatNotice {
    /// The chip at or above this …
    public static let limit = 90.0
    /// … for this many seconds, while the Mac decides …
    public static let patience = 5 * 60.0
    /// … and then not again for this long.
    public static let pause = 30 * 60.0

    /// Since when the chip has been that warm without a break (nil = it is not).
    public static func hotSince(chip: Double?, now: Double, since: Double?) -> Double? {
        guard let chip, chip >= limit else { return nil }
        return since ?? now
    }

    public static func due(enabled: Bool, appDecides: Bool, hotSince: Double?, now: Double, lastTold: Double?) -> Bool {
        guard enabled, !appDecides, let hotSince, now - hotSince >= patience else { return false }
        if let lastTold, now - lastTold < pause { return false }
        return true
    }
}

// MARK: Quiet during calls

public enum CallQuiet {
    /// The microphone in use for this long counts as a call (a short dictation does not) …
    public static let startAfter = 15.0
    /// … and free for this long counts as the call's end.
    public static let endAfter = 30.0

    public enum Step: Equatable, Sendable { case nothing, goQuiet, putBack }

    /// `inUseSince` / `freeSince`: since when the microphone has been in use, or free (one of them is nil).
    /// `active`: Quiet is on because of a call.
    public static func step(enabled: Bool, inUseSince: Double?, freeSince: Double?, now: Double, active: Bool) -> Step {
        if active {
            // Switched off in Settings in the middle of a call: back at once.
            if !enabled { return .putBack }
            if let freeSince, now - freeSince >= endAfter { return .putBack }
            return .nothing
        }
        guard enabled, let inUseSince, now - inUseSince >= startAfter else { return .nothing }
        return .goQuiet
    }
}

// MARK: On battery

public enum BatteryRule {
    public enum Step: Equatable, Sendable { case nothing, handBack, putBack }

    /// `parked`: a choice was handed back when the cable was pulled, and waits for the power to return.
    public static func step(enabled: Bool, onBattery: Bool, wasOnBattery: Bool, appDecides: Bool, parked: Bool) -> Step {
        if onBattery, !wasOnBattery { return enabled && appDecides ? .handBack : .nothing }
        if !onBattery, wasOnBattery { return parked ? .putBack : .nothing }
        return .nothing
    }
}

// MARK: What happened

/// One line of the "What happened" list.
public struct Happening: Codable, Equatable, Sendable, Identifiable {
    public let time: Double
    public let text: String
    public var id: String { "\(time)-\(text)" }

    public init(time: Double, text: String) {
        self.time = time
        self.text = text
    }
}

public enum HappenedLog {
    /// Kept on the Mac.
    public static let keep = 60
    /// Shown in Settings.
    public static let shown = 20

    public static func adding(_ new: Happening, to list: [Happening]) -> [Happening] {
        var all = list
        all.append(new)
        if all.count > keep { all.removeFirst(all.count - keep) }
        return all
    }

    /// Newest first, at most twenty.
    public static func forShow(_ list: [Happening]) -> [Happening] {
        Array(list.suffix(shown).reversed())
    }
}

// MARK: More words

public extension Words {
    /// "You decide: Cool · 8 min left", "You decide: Quiet (during a call)", "The Mac decides (on battery)".
    static func status(_ choice: FanChoice, left: String?, reason: String?) -> String {
        var text = status(choice)
        if let reason, !reason.isEmpty { text += " (\(reason))" }
        if choice.appDecides, let left { text += " · \(left)" }
        return text
    }

    /// What hovering over the menu bar mark says: who decides, then the figures.
    static func hover(_ choice: FanChoice, fans: [(name: String, speed: Double?)], chip: Double?) -> String {
        var parts = fans.map { "\($0.name) \(turns($0.speed))" }
        parts.append("Chip \(degrees(chip))")
        return hover(choice) + "\n" + parts.joined(separator: " · ")
    }
}
