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
