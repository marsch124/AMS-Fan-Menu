import Foundation

// The rules added in 0.5: your own heat notice level, the battery heat notice, quiet hours, and what a choice did.

public extension HeatNotice {
    /// The levels you can pick for the heat notice.
    static let levels: [Double] = [80, 85, 90, 95]

    /// The nearest level you can pick.
    static func clean(_ value: Double) -> Double {
        levels.min { abs($0 - value) < abs($1 - value) } ?? limit
    }
}

/// Quiet between two times of day.
public enum QuietHours {
    /// Minutes since midnight: 22:00 and 07:00.
    public static let defaultFrom = 22 * 60
    public static let defaultTo = 7 * 60

    /// A time of day inside 00:00 … 23:59.
    public static func clean(_ minute: Int) -> Int { ((minute % 1440) + 1440) % 1440 }
}

public extension QuietHours {
    enum Step: Equatable, Sendable { case nothing, goQuiet, putBack }

    /// Is this time of day inside the hours? `from` counts, `to` does not. From 22:00 to 07:00 runs over
    /// midnight. The same time twice means no hours at all.
    static func inside(minute: Int, from: Int, to: Int) -> Bool {
        let now = clean(minute), from = clean(from), to = clean(to)
        if from == to { return false }
        return from < to ? (now >= from && now < to) : (now >= from || now < to)
    }

    /// `active`: Quiet is on because of the hours.
    static func step(enabled: Bool, inside: Bool, active: Bool) -> Step {
        if active { return enabled && inside ? .nothing : .putBack }
        return enabled && inside ? .goQuiet : .nothing
    }

    /// "22:00"
    static func words(_ minute: Int) -> String {
        let clean = clean(minute)
        return String(format: "%02d:%02d", clean / 60, clean % 60)
    }

    /// The time of day of a moment, in minutes since midnight.
    static func minute(of time: Double, timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: time))
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

// MARK: The battery heat notice

public enum BatteryNotice {
    /// The battery above this (Apple's limit for the room) …
    public static let limit = Levels.appleRoomLimit
    /// … for this many seconds …
    public static let patience = 10 * 60.0
    /// … and then not again for this long.
    public static let pause = 60 * 60.0

    /// Since when the battery has been that warm without a break (nil = it is not).
    public static func hotSince(battery: Double?, now: Double, since: Double?) -> Double? {
        guard let battery, battery > limit else { return nil }
        return since ?? now
    }

    public static func due(enabled: Bool, hotSince: Double?, now: Double, lastTold: Double?) -> Bool {
        guard enabled, let hotSince, now - hotSince >= patience else { return false }
        if let lastTold, now - lastTold < pause { return false }
        return true
    }
}

public extension HeatNotice {
    /// Since when the chip has been at your own level or more without a break (nil = it is not).
    static func hotSince(chip: Double?, level: Double, now: Double, since: Double?) -> Double? {
        guard let chip, chip >= level else { return nil }
        return since ?? now
    }
}

// MARK: Was the choice worth it?

/// What a choice of yours did to the chip, said when it ends: "Cool for 10 min: chip 78° down to 61°".
public enum Worth {
    /// A choice shorter than this says nothing: the chip needs time to follow the fans.
    public static let atLeast = 2 * 60.0

    public static func words(title: String, seconds: Double, from: Double?, to: Double?) -> String? {
        guard seconds >= atLeast, let from, let to, from.isFinite, to.isFinite else { return nil }
        let before = Int(from.rounded()), after = Int(to.rounded())
        let change = after < before ? "chip \(before)\u{00B0} down to \(after)\u{00B0}"
            : after > before ? "chip \(before)\u{00B0} up to \(after)\u{00B0}" : "chip stayed at \(before)\u{00B0}"
        return "\(title) for \(howLong(seconds)): \(change)"
    }

    /// "10 min", "1 h 5 min", "2 h"
    public static func howLong(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
