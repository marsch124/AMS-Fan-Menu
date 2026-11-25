import Foundation

// 0.5: the week in figures. One tally per calendar day, for today and the seven days before.

/// What one calendar day added up to.
public struct DayTally: Codable, Equatable, Sendable {
    /// The day, such as "2026-11-25", in the time zone of the Mac.
    public var key: String
    /// The start of that day (seconds since 1970), to say "since 25 Nov".
    public var start: Double
    /// The hottest chip reading of the day and when it was.
    public var hottest: Double?
    public var hottestTime: Double?
    /// Seconds with the chip at 90° or more.
    public var secondsHot: Double = 0
    /// Seconds any fan was turning.
    public var secondsFans: Double = 0
    /// Seconds a choice of yours was on (the app held the fans).
    public var secondsApp: Double = 0

    public init(key: String, start: Double) {
        self.key = key
        self.start = start
    }
}

/// The figures of the last seven days, shown on "What happened".
public struct WeekSummary: Equatable, Sendable {
    public var hottest: Double?
    public var hottestTime: Double?
    public var secondsHot: Double
    public var secondsFans: Double
    public var secondsApp: Double
    /// The start of the first day counted; nil when no day has figures.
    public var since: Double?
    /// How many of the seven days have figures.
    public var days: Int

    public var isEmpty: Bool { days == 0 }
}

/// The last days in figures: the hottest moment, the time at 90° or more, how long the fans turned and how
/// long a choice of yours was on.
public struct Week: Codable, Equatable, Sendable {
    /// The chip at this or more counts as hot.
    public static let hotFrom = 90.0
    /// Today and the seven days before are kept; the summary shows today and the six before.
    public static let kept = 8
    public static let shown = 7

    public var days: [DayTally] = []

    public init() {}

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func key(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The keys and starts of the last `count` days, today first.
    private static func lastDays(_ count: Int, now: Double, _ calendar: Calendar) -> [(key: String, start: Double)] {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: now))
        return (0..<count).compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return (key(day, calendar), day.timeIntervalSince1970)
        }
    }

    /// One reading. `seconds`: the time since the reading before (the caller never passes more than 15).
    /// `fansTurning`: any fan above 0. `appRuns`: a choice of yours is on and the app holds the fans.
    public mutating func add(time: Double, chip: Double?, fansTurning: Bool, appRuns: Bool, seconds: Double,
                             timeZone: TimeZone = .current) {
        guard time.isFinite else { return }
        let calendar = Self.calendar(timeZone)
        let date = Date(timeIntervalSince1970: time)
        let today = Self.key(date, calendar)
        let wanted = Set(Self.lastDays(Self.kept, now: time, calendar).map(\.key))
        days.removeAll { !wanted.contains($0.key) }

        let index: Int
        if let found = days.firstIndex(where: { $0.key == today }) {
            index = found
        } else {
            days.append(DayTally(key: today, start: calendar.startOfDay(for: date).timeIntervalSince1970))
            days.sort { $0.key < $1.key }
            index = days.firstIndex { $0.key == today } ?? days.count - 1
        }
        // A gap (a sleep, a pause) adds no time.
        let step = seconds.isFinite && seconds > 0 && seconds <= 15 ? seconds : 0
        if let chip, chip.isFinite {
            if days[index].hottest == nil || chip > days[index].hottest! {
                days[index].hottest = chip
                days[index].hottestTime = time
            }
            if chip >= Self.hotFrom { days[index].secondsHot += step }
        }
        if fansTurning { days[index].secondsFans += step }
        if appRuns { days[index].secondsApp += step }
    }

    /// The figures over today and the six days before.
    public func summary(now: Double, timeZone: TimeZone = .current) -> WeekSummary {
        let calendar = Self.calendar(timeZone)
        let wanted = Set(Self.lastDays(Self.shown, now: now, calendar).map(\.key))
        let counted = days.filter { wanted.contains($0.key) }
        var out = WeekSummary(hottest: nil, hottestTime: nil, secondsHot: 0, secondsFans: 0, secondsApp: 0,
                              since: counted.map(\.start).min(), days: counted.count)
        for day in counted {
            if let hot = day.hottest, out.hottest == nil || hot > out.hottest! {
                out.hottest = hot
                out.hottestTime = day.hottestTime
            }
            out.secondsHot += day.secondsHot
            out.secondsFans += day.secondsFans
            out.secondsApp += day.secondsApp
        }
        return out
    }

    /// Sample figures for pictures: seven days, the last one still running.
    public static func sample(now: Double) -> Week {
        let calendar = calendar(.current)
        var week = Week()
        let hottest: [Double] = [84, 88, 91, 86, 93, 89, 87]
        let hot: [Double] = [0, 0, 240, 0, 360, 90, 30]
        let fans: [Double] = [2400, 3300, 3900, 2700, 4200, 3000, 1800]
        let app: [Double] = [600, 0, 900, 300, 1200, 600, 300]
        for (index, day) in lastDays(7, now: now, calendar).reversed().enumerated() {
            var tally = DayTally(key: day.key, start: day.start)
            tally.hottest = hottest[index]
            tally.hottestTime = day.start + 14 * 3600 + 20 * 60 + Double(index) * 60
            tally.secondsHot = hot[index]
            tally.secondsFans = fans[index]
            tally.secondsApp = app[index]
            week.days.append(tally)
        }
        return week
    }
}

extension Words {
    /// "12 min", "5 h 10 min", "0 min"; under a minute (but not nothing) "under 1 min".
    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 min" }
        if seconds < 60 { return "under 1 min" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    /// "93° · Tue 14:20": the hottest moment, English short weekday, 24-hour clock.
    public static func hottestMoment(_ degrees: Double?, at time: Double?, timeZone: TimeZone = .current) -> String {
        guard let degrees, let time else { return "–" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE HH:mm"
        return "\(Words.degrees(degrees)) \u{00B7} " + formatter.string(from: Date(timeIntervalSince1970: time))
    }

    /// "Counted since 25 Nov" while fewer than seven days have figures; otherwise nil.
    public static func countedSince(_ since: Double?, days: Int, timeZone: TimeZone = .current) -> String? {
        guard let since, days > 0, days < Week.shown else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM"
        return "Counted since " + formatter.string(from: Date(timeIntervalSince1970: since))
    }
}
