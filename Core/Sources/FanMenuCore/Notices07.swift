import Foundation

/// 0.7: which app works hardest, from the lines of `ps -Ao pcpu=,comm=` (share of one core, then the
/// program's full path). Helpers inside an app (Chrome's, Xcode's tools) count for that app.
public enum BusiestApp {
    /// Below this share of one core nothing stands out.
    public static let atLeast = 20.0
    /// Not an app: the Mac's own work (kernel_task is how the Mac slows itself when hot), and this app itself.
    public static let skipped: Set<String> = ["kernel_task", "AMS Fan Menu", "ps", "launchd"]

    /// The app's name for one program path: the first "….app" in the path, otherwise the last part.
    public static func appName(path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        if let app = parts.first(where: { $0.hasSuffix(".app") }) { return String(app.dropLast(4)) }
        return parts.last ?? path
    }

    /// The name and summed share of the busiest app, or nil when nothing works hard.
    public static func busiest(psOutput: String) -> (name: String, share: Double)? {
        var shares: [String: Double] = [:]
        for line in psOutput.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let share = Double(trimmed[..<space].replacingOccurrences(of: ",", with: ".")) else { continue }
            let name = appName(path: trimmed[space...].trimmingCharacters(in: .whitespaces))
            guard !name.isEmpty, !skipped.contains(name) else { continue }
            shares[name, default: 0] += share
        }
        guard let top = shares.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }),
              top.value >= atLeast else { return nil }
        return (top.key, top.value)
    }

    /// The words added to a heat notice.
    public static func words(_ name: String?) -> String? {
        name.map { "Working hardest: \($0)." }
    }
}

/// 0.7: the fan check-up — each fan runs to its top for a short while; did it get there?
public enum FanCheck {
    /// Seconds the fans are asked for their top.
    public static let seconds = 10.0
    /// A fan that got to 90 % of its top is fine.
    public static let fineShare = 0.9

    public static func fine(best: Double, top: Double) -> Bool {
        top > 0 && best >= top * fineShare
    }

    /// "Both fans fine · Left 5,310 of 5,348 · Right 5,750 of 5,776", or which fell short.
    public static func words(names: [String], best: [Double], tops: [Double]) -> String {
        let count = min(names.count, best.count, tops.count)
        guard count > 0 else { return "No fans to check" }
        let short = (0..<count).filter { !fine(best: best[$0], top: tops[$0]) }
        let head: String
        if short.isEmpty {
            head = count == 1 ? "The fan is fine" : count == 2 ? "Both fans fine" : "All fans fine"
        } else if short.count == count {
            head = count == 1 ? "The fan fell short" : count == 2 ? "Both fans fell short" : "All fans fell short"
        } else {
            head = short.map { "\(names[$0]) fan" }.joined(separator: " and ") + " fell short"
        }
        let figures = (0..<count).map { "\(names[$0]) \(Words.turns(best[$0])) of \(Words.turns(tops[$0]))" }
        return ([head] + figures).joined(separator: " \u{00B7} ")
    }
}

/// 0.7: a fan that stays well below the speed the app asked for.
public enum FanShort {
    /// A fan below this share of what was asked counts as short.
    public static let share = 0.8
    /// …for this many seconds (time enough to speed up).
    public static let patience = 30.0
    /// At most one notice in this many seconds.
    public static let pause = 6 * 60 * 60.0

    /// The fans that are short now.
    public static func short(asked: [Double]?, actual: [Double?]) -> [Int] {
        guard let asked else { return [] }
        return asked.indices.filter { index in
            guard asked[index] > 0, index < actual.count, let now = actual[index] else { return false }
            return now < asked[index] * share
        }
    }

    /// Since when some fan has been short, nil when none is.
    public static func shortSince(short: [Int], now: Double, since: Double?) -> Double? {
        short.isEmpty ? nil : (since ?? now)
    }

    public static func due(shortSince: Double?, now: Double, lastTold: Double?) -> Bool {
        guard let shortSince, now - shortSince >= patience else { return false }
        return lastTold.map { now - $0 >= pause } ?? true
    }

    /// "The Right fan turned at 2,100 though 3,600 was asked, for 30 seconds."
    public static func words(name: String, actual: Double, asked: Double) -> String {
        "The \(name) fan turned at \(Words.turns(actual)) though \(Words.turns(asked)) was asked, for \(Int(patience)) seconds. Dust or wear can do that; the fan check-up in Settings tells more."
    }

    /// The short line for the dot in the Fan speed graph and for What happened.
    public static func mark(name: String, actual: Double, asked: Double) -> String {
        "\(name) fan fell short: \(Words.turns(actual)) of \(Words.turns(asked)) asked"
    }
}
