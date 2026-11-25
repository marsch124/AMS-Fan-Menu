import Foundation

// 0.5: the week in figures. GROUNDWORK STUB: the lane that builds pick 9 fills this in and may change everything
// inside the types, but must keep the names and signatures used by AppModel: `Week()`, `add(...)`, `Week.sample(now:)`.

/// What one calendar day added up to.
public struct DayTally: Codable, Equatable, Sendable {
    public init() {}
}

/// The last days in figures: the hottest moment, the time at 90° or more, how long the fans turned and how
/// long a choice of yours was on.
public struct Week: Codable, Equatable, Sendable {
    public init() {}

    /// One reading. `seconds`: the time since the reading before (the caller never passes more than 15).
    /// `fansTurning`: any fan above 0. `appRuns`: a choice of yours is on and the app holds the fans.
    public mutating func add(time: Double, chip: Double?, fansTurning: Bool, appRuns: Bool, seconds: Double,
                             timeZone: TimeZone = .current) {
    }

    /// Sample figures for pictures.
    public static func sample(now: Double) -> Week { Week() }
}
