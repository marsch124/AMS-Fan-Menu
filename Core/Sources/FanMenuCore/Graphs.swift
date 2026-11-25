import Foundation

// 0.5, the large graph: which graphs show, the figure where you point, colour while a choice is on.

/// One graph of the large window that can be shown or hidden.
public enum GraphPick: String, CaseIterable, Sendable {
    case chip, graphics, battery, storage, palm, fans

    /// The word on its pick button.
    public var title: String {
        switch self {
        case .chip: return "Chip"
        case .graphics: return "Graphics"
        case .battery: return "Battery"
        case .storage: return "Storage"
        case .palm: return "Case"
        case .fans: return "Fan speed"
        }
    }

    /// The temperature it draws; nil for the fan speed.
    public var sensor: Sensor? {
        switch self {
        case .chip: return .chip
        case .graphics: return .graphics
        case .battery: return .battery
        case .storage: return .storage
        case .palm: return .palm
        case .fans: return nil
        }
    }

    /// How much of the room a graph takes next to the others (the chip graph carries the most level lines;
    /// storage and case carry none and move little, so they give room to the others when all six show).
    public var weight: Double {
        switch self {
        case .chip: return 172
        case .fans: return 118
        case .storage, .palm: return 96
        case .graphics, .battery: return 128
        }
    }
}

/// Which graphs show: the rule, and how it is remembered.
public enum ShownGraphs {
    /// At first: chip, graphics, battery and the fan speed.
    public static let first: [GraphPick] = [.chip, .graphics, .battery, .fans]

    /// From the remembered comma list ("chip,graphics,battery,fans"): unknown names dropped, an empty or missing
    /// value gives the four first ones, the order is always the fixed one.
    public static func parse(_ stored: String?) -> [GraphPick] {
        let names = Set((stored ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let picks = GraphPick.allCases.filter { names.contains($0.rawValue) }
        return picks.isEmpty ? first : picks
    }

    /// The pick shown or hidden by a tap; the last shown graph cannot be hidden.
    public static func toggled(_ pick: GraphPick, in shown: [GraphPick]) -> [GraphPick] {
        if shown.contains(pick) {
            return shown.count <= 1 ? shown : shown.filter { $0 != pick }
        }
        return GraphPick.allCases.filter { shown.contains($0) || $0 == pick }
    }

    /// The comma list to remember.
    public static func stored(_ shown: [GraphPick]) -> String {
        shown.map(\.rawValue).joined(separator: ",")
    }

    /// The height of each shown graph: the room (gaps between graphs included) shared by weight.
    public static func heights(for shown: [GraphPick], room: Double, spacing: Double) -> [Double] {
        guard !shown.isEmpty else { return [] }
        let free = max(room - spacing * Double(shown.count - 1), 0)
        let total = shown.reduce(0) { $0 + $1.weight }
        return shown.map { free * $0.weight / total }
    }
}

public extension Plot {
    /// The moment at a place across the graph (0 = the oldest edge, 1 = now): the inverse of `x`.
    static func time(share: Double, now: Double, span: Double) -> Double {
        now - (1 - min(max(share, 0), 1)) * span
    }

    /// The kept reading nearest to a moment; nil when even the nearest is further away than `within` seconds
    /// (a gap: the Mac slept or the app was not running).
    static func nearest(_ samples: [Sample], to time: Double, within: Double) -> Sample? {
        guard let best = samples.min(by: { abs($0.time - time) < abs($1.time - time) }),
              abs(best.time - time) <= within else { return nil }
        return best
    }

    /// How far a reading may be from the pointer and still count: 3 readings' spacing as drawn.
    static func pointReach(span: Double) -> Double { 3 * max(15, span / 60) }
}

public extension Words {
    /// "14:20" (24-hour); "14:20:35" with seconds.
    static func clock(_ time: Double, seconds: Bool, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: Date(timeIntervalSince1970: time))
        let base = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        return seconds ? base + String(format: ":%02d", parts.second ?? 0) : base
    }
}

/// A stretch of time in which a choice other than Automatic was on.
public struct Stretch: Equatable, Sendable {
    public let from: Double
    public let to: Double
    public let title: String

    public init(from: Double, to: Double, title: String) {
        self.from = from
        self.to = to
        self.title = title
    }
}

public extension History {
    /// The stretches in the last `seconds` in which a choice other than Automatic was on, from all kept marks:
    /// one that began before the left edge starts at the edge, one still on runs to `now`.
    func stretches(last seconds: Double, now: Double) -> [Stretch] {
        let edge = now - seconds
        let ordered = marks.filter { $0.time <= now }.sorted { $0.time < $1.time }
        var out: [Stretch] = []
        for (index, mark) in ordered.enumerated() where mark.title != "Automatic" {
            let end = index + 1 < ordered.count ? ordered[index + 1].time : now
            let from = max(mark.time, edge), to = min(end, now)
            if to > from { out.append(Stretch(from: from, to: to, title: mark.title)) }
        }
        return out
    }
}
