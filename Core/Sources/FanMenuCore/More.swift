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
    /// The graphics temperature in °C; nil when there was no reading, and in every reading kept before 0.4.
    public let graphics: Double?
    /// The battery temperature in °C; nil when there was no reading, and in every reading kept before 0.4.
    public let battery: Double?
    /// 0.5: the storage and the case under the hands in °C, and the whole Mac's power use in watts.
    /// nil when there was no reading, and in every reading kept before 0.5.
    public let storage: Double?
    public let palm: Double?
    public let power: Double?
    /// 0.6: the battery was charging; nil when the Mac did not say, and in every reading kept before 0.6.
    public let charging: Bool?

    public init(time: Double, chip: Double?, speeds: [Double], graphics: Double? = nil, battery: Double? = nil,
                storage: Double? = nil, palm: Double? = nil, power: Double? = nil, charging: Bool? = nil) {
        self.charging = charging
        self.time = time
        self.chip = chip
        self.speeds = speeds
        self.graphics = graphics
        self.battery = battery
        self.storage = storage
        self.palm = palm
        self.power = power
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

/// 0.6: a stretch without readings, and why: the Mac was asleep, or the app was not running.
/// 0.7: a notice that was sent, shown as an amber dot in the graph of its sensor.
public struct NoticeMark: Codable, Equatable, Sendable {
    public let time: Double
    public let sensor: Sensor
    public let words: String
    public init(time: Double, sensor: Sensor, words: String) {
        self.time = time
        self.sensor = sensor
        self.words = words
    }
}

public struct Pause: Codable, Equatable, Sendable {
    public static let asleep = "asleep", notRunning = "not running"
    public let from: Double
    public let to: Double
    /// The words drawn in the gap: "asleep" or "not running".
    public let why: String

    public init(from: Double, to: Double, why: String) {
        self.from = from
        self.to = to
        self.why = why
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
    /// Missing in files kept before 0.6.
    private var pauseList: [Pause]?
    /// 0.7: the notices sent, for the amber dots in the graphs. Missing in files kept before 0.7.
    private var noticeList: [NoticeMark]?

    public init() {}

    /// 0.6: the stretches without readings whose reason is known.
    public var pauses: [Pause] { pauseList ?? [] }

    /// Notes why there are no readings for a while. Anything shorter than three readings is not worth a word.
    public mutating func pause(from: Double, to: Double, why: String) {
        guard to - from >= History.every * 3 else { return }
        pauseList = pauses + [Pause(from: from, to: to, why: why)]
        trim(now: to)
    }

    /// 0.7: the notices sent (heat, too hot, battery, a fan falling short).
    public var notices: [NoticeMark] { noticeList ?? [] }

    /// Notes a notice that was sent, so the graphs can show an amber dot at its moment.
    public mutating func notice(_ words: String, sensor: Sensor, at time: Double) {
        noticeList = notices + [NoticeMark(time: time, sensor: sensor, words: words)]
        trim(now: time)
    }

    /// The notices of one graph in the last `seconds`.
    public func notices(_ sensor: Sensor, last seconds: Double, now: Double) -> [NoticeMark] {
        notices.filter { $0.sensor == sensor && $0.time >= now - seconds && $0.time <= now }
    }

    /// The pauses that touch the last `seconds`.
    public func pauses(last seconds: Double, now: Double) -> [Pause] {
        pauses.filter { $0.to >= now - seconds && $0.from <= now }
    }

    /// The pause a moment lies in, if any.
    public func pause(at time: Double) -> Pause? {
        pauses.first { time >= $0.from && time <= $0.to }
    }

    /// Adds a reading unless the last one is younger than five seconds; drops what is older than six hours.
    /// Returns whether it was added.
    @discardableResult
    public mutating func add(_ sample: Sample) -> Bool {
        if let last = samples.last, sample.time - last.time < History.every - 0.5 { return false }
        samples.append(sample)
        trim(now: sample.time)
        return true
    }

    /// For tidying kept readings: the same moments, corrected.
    mutating func replaceSamples(_ new: [Sample]) { samples = new }

    public mutating func mark(_ title: String, at time: Double) {
        marks.append(ChoiceMark(time: time, title: title))
        trim(now: time)
    }

    public mutating func trim(now: Double) {
        let oldest = now - History.keep
        if let first = samples.first, first.time < oldest { samples.removeAll { $0.time < oldest } }
        if let first = marks.first, first.time < oldest { marks.removeAll { $0.time < oldest } }
        if let first = pauseList?.first, first.to < oldest { pauseList?.removeAll { $0.to < oldest } }
        if let first = noticeList?.first, first.time < oldest { noticeList?.removeAll { $0.time < oldest } }
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

// MARK: The three temperatures and their level lines (0.4)

/// One of the temperatures the Mac reports (0.4: chip, graphics, battery; 0.5: storage and the case under the hands).
public enum Sensor: String, CaseIterable, Codable, Sendable {
    case chip, graphics, battery, storage, palm

    public var title: String {
        switch self {
        case .chip: return "Chip temperature"
        case .graphics: return "Graphics temperature"
        case .battery: return "Battery temperature"
        case .storage: return "Storage temperature"
        case .palm: return "Case temperature"
        }
    }

    public func value(in sample: Sample) -> Double? {
        switch self {
        case .chip: return sample.chip
        case .graphics: return sample.graphics
        case .battery: return sample.battery
        case .storage: return sample.storage
        case .palm: return sample.palm
        }
    }

    /// The scale of this graph always reaches at least this high, so its level lines are in view.
    public var scaleTop: Double {
        switch self {
        case .chip: return 120
        case .graphics: return 110
        case .battery, .palm: return 50
        case .storage: return 80
        }
    }
}

/// A temperature that means something: a flat line across a graph, with its words.
public struct Level: Equatable, Sendable {
    /// `watch` = from here it needs your eye (amber); `tooHot` = from here something protects itself (red);
    /// `macFull` = here the Mac itself took the fans to full (green); `report` = a rough figure from other
    /// owners' reports, not from Apple and not measured on this Mac (dotted grey, words at the left).
    public enum Kind: String, Sendable { case watch, tooHot, macFull, report }
    public let kind: Kind
    public let degrees: Double
    public let words: String

    public init(kind: Kind, degrees: Double, words: String) {
        self.kind = kind
        self.degrees = degrees
        self.words = words
    }
}

/// The level lines of each graph. The solid ones are true figures: the app's own rules, Apple's one published
/// figure, one named measurement, and what this Mac itself was seen to do. Apple publishes no figure for where
/// the fans speed up or the chip slows itself; since 0.4.1 (his yes) those two are shown as rough lines from
/// other owners' reports, marked as such. Nobody gives a figure for where the Mac turns itself off: no line.
public enum Levels {
    /// Apple: use a Mac laptop where it is 10° to 35° (the room, not the battery itself).
    public static let appleRoomLimit = 35.0
    /// Charging stopped at 44° on the battery sensor in one test (Howard Oakley, 2021, an M1 MacBook Air).
    public static let chargingMayStop = 44.0
    /// Other owners report (forums, not Apple): the Mac lets the chip get to about 95° before the fans speed up.
    public static let reportFansSpeedUp = 95.0
    /// Other owners report (forums, not Apple): the chip slows itself somewhere from 100° to 110°. Drawn in the middle.
    public static let reportChipSlows = 105.0

    /// `heatNotice`: the level of the heat notice (0.5: your own pick); nil = the notice is switched off, no amber line.
    public static func of(_ sensor: Sensor, fullSeenAt: Double? = nil, heatNotice: Double? = HeatNotice.limit) -> [Level] {
        switch sensor {
        case .chip:
            var out: [Level] = []
            if let heatNotice {
                out.append(Level(kind: .watch, degrees: heatNotice, words: "Heat notice \(Words.degrees(heatNotice))"))
            }
            out.append(Level(kind: .tooHot, degrees: HeatGuard.limit, words: "Too hot \(Words.degrees(HeatGuard.limit))"))
            if let fullSeenAt, fullSeenAt.isFinite {
                out.append(Level(kind: .macFull, degrees: fullSeenAt,
                                 words: "Fans at full in Automatic \u{00B7} seen at \(Words.degrees(fullSeenAt))"))
            }
            out.append(Level(kind: .report, degrees: reportFansSpeedUp,
                             words: "Reports: fans speed up at about \(Words.degrees(reportFansSpeedUp))"))
            out.append(Level(kind: .report, degrees: reportChipSlows,
                             words: "Reports: chip slows itself at about 100\u{00B0} to 110\u{00B0}"))
            return out
        case .graphics, .storage, .palm:
            return []
        case .battery:
            return [
                Level(kind: .watch, degrees: appleRoomLimit, words: "Apple's limit for the room \(Words.degrees(appleRoomLimit))"),
                Level(kind: .tooHot, degrees: chargingMayStop, words: "Charging may stop about \(Words.degrees(chargingMayStop))"),
            ]
        }
    }

    /// The scale of a temperature graph with level lines: whole tens from below the lowest reading up to at
    /// least the sensor's `scaleTop` (higher if a reading is higher). No readings: 30° below the top.
    public static func scale(_ sensor: Sensor, _ samples: [Sample]) -> ClosedRange<Double> {
        let values = samples.compactMap { sensor.value(in: $0) }
        let top = max(sensor.scaleTop, ((values.max() ?? 0) / 10).rounded(.up) * 10)
        guard let low = values.min() else { return (top - 30)...top }
        let bottom = min((low / 10).rounded(.down) * 10, top - 30)
        return bottom...top
    }
}

/// The usual range on this Mac: where the middle 80 % of the kept readings lie.
public enum Usual {
    /// Readings needed before a range is shown: 30 minutes' worth.
    public static let needs = 360

    public static func band(_ values: [Double]) -> ClosedRange<Double>? {
        guard values.count >= needs else { return nil }
        let sorted = values.sorted()
        let low = sorted[Int((Double(sorted.count - 1) * 0.1).rounded())]
        let high = sorted[Int((Double(sorted.count - 1) * 0.9).rounded())]
        return low...high
    }

    /// "usual here 41° to 78°"
    public static func words(_ band: ClosedRange<Double>) -> String {
        "usual here \(Words.degrees(band.lowerBound)) to \(Words.degrees(band.upperBound))"
    }
}

/// Learns where the Mac itself takes the fans to full: the chip temperature on the reading where that
/// first becomes true while the Mac has the fans.
public enum FullSeen {
    /// "Full" = the fans' average speed at or above this share of their average top speed.
    public static let share = 0.9

    public static func isFull(speeds: [Double], tops: [Double]) -> Bool {
        guard !speeds.isEmpty, speeds.count == tops.count else { return false }
        let top = tops.reduce(0, +) / Double(tops.count)
        guard top > 0 else { return false }
        return speeds.reduce(0, +) / Double(speeds.count) >= top * share
    }

    /// One reading. `wasFull` is what the reading before gave back. While the app runs the fans nothing is
    /// learned and the answer is "was full", so a speed the app itself set is never taken for the Mac's
    /// doing just after the fans go back.
    public static func step(macHasFans: Bool, full: Bool, wasFull: Bool, chip: Double?) -> (wasFull: Bool, seenAt: Double?) {
        guard macHasFans else { return (true, nil) }
        guard full else { return (false, nil) }
        return (true, wasFull ? nil : chip)
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

// MARK: A wish from another app (0.3.1)

/// What another app asks for over the `choose` notification (AMS Deck Mate's fan keys): the choice in
/// its own word, "cool", or with a time of its own behind a colon, "cool:600" = Cool for 600 seconds,
/// then the Mac gets the fans back. A time of its own never changes the pick in the "For" line.
public enum OutsideAsk {
    /// A time of its own is kept between one minute and four hours.
    public static let shortest = 60.0
    public static let longest = 4 * 3600.0

    /// nil for anything that is not a choice (the wish is then ignored). Automatic never has a time.
    public static func parse(_ word: String) -> (choice: FanChoice, seconds: Double?)? {
        let parts = word.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(parts.count), let choice = FanChoice(rawValue: parts[0]) else { return nil }
        guard parts.count == 2 else { return (choice, nil) }
        guard let seconds = Double(parts[1]), seconds.isFinite, seconds > 0 else { return nil }
        return (choice, choice.appDecides ? min(longest, max(shortest, seconds)) : nil)
    }

    /// In a sentence: "10 minutes", "1 hour", "90 minutes".
    public static func words(seconds: Double) -> String {
        if let known = Lasting.allCases.first(where: { $0.seconds == seconds }), let words = known.words { return words }
        let minutes = Int((seconds / 60).rounded())
        if minutes % 60 == 0 { return minutes == 60 ? "1 hour" : "\(minutes / 60) hours" }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    /// The time shown in full colour in the "For" line: the time of its own while one runs (none of the
    /// four when it is not one of them), else his own pick.
    public static func shown(pick: Lasting, ownSeconds: Double?) -> Lasting? {
        guard let ownSeconds else { return pick }
        return Lasting.allCases.first { $0.seconds == ownSeconds }
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

// MARK: Quiet lets the fans stop (0.3)

/// Left alone, this Mac stops its fans completely while the chip is cool; the app can never set a fan below
/// its lowest running speed. So while Quiet is on and the chip is cool, the app gives the fans to the Mac
/// ("resting"). The moment the Mac wants them faster than Quiet, the app takes them again and holds them
/// at Quiet's speed. Quiet is then never louder than before, and silent when the Mac is cool.
public enum QuietRest {
    /// The chip at or below this …
    public static let coolBelow = 60.0
    /// … for this many seconds: the fans may rest.
    public static let coolFor = 30.0
    /// A fan this many turns above its Quiet speed means the Mac wants more than Quiet …
    public static let overBy = 150.0
    /// … for this many seconds in a row.
    public static let overFor = 4.0
    /// After taking the fans again, they are held at least this long, so they do not hunt.
    public static let holdAtLeast = 5 * 60.0

    public enum Step: Equatable, Sendable { case nothing, rest, hold }

    /// Since when the chip has been cool without a break (nil = it is not, or there is no reading).
    public static func coolSince(chip: Double?, now: Double, since: Double?) -> Double? {
        guard let chip, chip <= coolBelow else { return nil }
        return since ?? now
    }

    /// Since when a fan has run faster than Quiet allows (nil = none does). `quiet`: Quiet's speed per fan.
    public static func overSince(speeds: [Double?], quiet: [Double], now: Double, since: Double?) -> Double? {
        let over = zip(speeds, quiet).contains { speed, quiet in (speed ?? 0) > quiet + overBy }
        return over ? (since ?? now) : nil
    }

    /// `resting`: the Mac has the fans because it is cool. `heldSince`: when the app last took them back
    /// from a rest (nil = not yet in this Quiet).
    public static func step(enabled: Bool, resting: Bool, coolSince: Double?, overSince: Double?,
                            heldSince: Double?, now: Double) -> Step {
        if resting {
            // Switched off in Settings in the middle of a rest: Quiet's own speed at once.
            if !enabled { return .hold }
            if let overSince, now - overSince >= overFor { return .hold }
            return .nothing
        }
        guard enabled, let coolSince, now - coolSince >= coolFor else { return .nothing }
        if let heldSince, now - heldSince < holdAtLeast { return .nothing }
        return .rest
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
    /// "You decide: Cool · 8 min left", "You decide: Quiet (during a call)", "The Mac decides (on battery)",
    /// "You decide: Quiet · fans resting" while Quiet has given the fans to the cool Mac.
    static func status(_ choice: FanChoice, left: String?, reason: String?, resting: Bool = false) -> String {
        var text = status(choice)
        if let reason, !reason.isEmpty { text += " (\(reason))" }
        if choice == .quiet, resting { text += " · fans resting" }
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
