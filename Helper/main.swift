import FanMenuCore
import Foundation

// The helper of AMS Fan Menu. It runs with the Mac's deepest rights, so it does as little as possible:
// it sets fan speeds inside each fan's own range, and gives the fans back to the Mac. It listens only to
// the AMS Fan Menu app, and gives the fans back by itself when the app goes silent.

/// A short log anybody on this Mac can read: what was set and when. Only the newest lines are kept.
enum HelperLog {
    private static let keep = 300
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func note(_ text: String) {
        let url = URL(fileURLWithPath: HelperInfo.logPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o755])
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        lines.append(stamp.string(from: Date()) + "  " + text)
        if lines.count > keep { lines.removeFirst(lines.count - keep) }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }
}

/// Everything that touches the fans, one thing at a time.
final class FanWriter {
    static let shared = FanWriter()
    let queue = DispatchQueue(label: "com.schabbauer.AMSFanMenu.helper.fans")
    private let smc = SMC()
    /// The helper is holding the fans.
    private var running = false
    private var usedUnlock = false
    private var lastWord = Date().timeIntervalSinceReferenceDate
    /// What was last written, so the log only notes changes.
    private var lastSet: [Double] = []
    private var timer: DispatchSourceTimer?

    private var now: Double { Date().timeIntervalSinceReferenceDate }

    func start() {
        HelperLog.note("Helper \(HelperInfo.version) started" + (smc == nil ? "; the fan controller did not open" : ""))
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.look() }
        timer.resume()
        self.timer = timer
    }

    /// Every 5 seconds: has the app gone silent? Is there nothing left to do?
    private func look() {
        if DeadMan.expired(running: running, lastWord: lastWord, now: now) {
            let answer = giveBackNow()
            HelperLog.note("No word from the app for \(Int(DeadMan.seconds)) s; fans given back to the Mac (\(answer.1))")
        }
        if DeadMan.mayEnd(running: running, lastWord: lastWord, now: now) {
            HelperLog.note("Nothing to do; ending until the app asks again")
            exit(0)
        }
    }

    /// Asks for one fan and waits until the Mac has really handed it over. Returns how it went.
    ///
    /// The Mac hands a fan over a few hundredths of a second AFTER it is asked (measured 24 Nov 2026 on an
    /// M1 Max: 10 to 30 ms). Version 1 looked at once, saw "not yet", gave up — and left the fan held.
    private func force(_ index: Int, smc: SMC) -> (Bool, String) {
        let key = FanKeys.mode(index, smc: smc)
        if smc.number(key) == 1 { return (true, "") }
        var code = smc.write(key, number: 1)
        if let waited = waitForHandOver(key, smc: smc, seconds: 1.5, code: &code) {
            return (true, String(format: "handed over after %.2f s", waited))
        }
        // Newer Macs want to be unlocked first, and then take a few seconds.
        if smc.exists(FanKeys.unlock) {
            _ = smc.write(FanKeys.unlock, number: 1)
            usedUnlock = true
            if let waited = waitForHandOver(key, smc: smc, seconds: 6, code: &code) {
                return (true, String(format: "handed over after unlocking, %.2f s", waited))
            }
        }
        return (false, "the Mac did not hand over fan \(index + 1) (answer \(code.map { String($0, radix: 16) } ?? "none"), reads \(smc.number(key).map { String(Int($0)) } ?? "nothing"))")
    }

    /// Looks every hundredth of a second whether the fan is handed over, and asks again every 0.3 s.
    /// Returns after how many seconds it was, or nil when the time ran out.
    private func waitForHandOver(_ key: String, smc: SMC, seconds: Double, code: inout UInt8?) -> Double? {
        let began = now
        var asked = began
        while now - began < seconds {
            if smc.number(key) == 1 { return now - began }
            usleep(10_000)
            if now - asked >= 0.3 {
                code = smc.write(key, number: 1)
                asked = now
            }
        }
        return smc.number(key) == 1 ? now - began : nil
    }

    func setSpeeds(_ asked: [Double]) -> (Bool, String) {
        lastWord = now
        guard let smc else { return (false, "the fan controller did not open") }
        let count = FanKeys.count(smc)
        guard count > 0, asked.count == count else { return (false, "this Mac has \(count) fans, the app sent \(asked.count) speeds") }
        // Every speed inside its fan's own range, before anything is touched.
        var speeds: [Double] = []
        for index in 0..<count {
            guard let lowest = smc.number(FanKeys.lowest(index)), let top = smc.number(FanKeys.top(index)),
                  lowest > 0, top >= lowest else {
                _ = giveBackNow()
                return (false, "fan \(index + 1) did not tell its range")
            }
            speeds.append(FanRange(lowest: lowest, top: top).kept(asked[index]))
        }
        // All fans handed over first, and only then the speeds: never one fan fast and one left behind.
        var notes: [String] = []
        for index in 0..<count {
            let forced = force(index, smc: smc)
            guard forced.0 else {
                let back = giveBackNow()
                HelperLog.note(forced.1 + "; fans: " + back.1)
                return (false, forced.1)
            }
            if !forced.1.isEmpty {
                // While the helper holds the fans this means the Mac had taken one back in between.
                notes.append("fan \(index + 1) \(forced.1)" + (running ? " (the Mac had taken it back)" : ""))
            }
        }
        for index in 0..<count {
            let speed = speeds[index]
            var code = smc.write(FanKeys.target(index), number: speed)
            // Some Macs answer with a complaint and take the speed all the same: what counts is what is set.
            var reads = smc.number(FanKeys.target(index)) ?? -1
            let began = now
            while abs(reads - speed) >= 2, now - began < 1 {
                usleep(20_000)
                reads = smc.number(FanKeys.target(index)) ?? -1
                if abs(reads - speed) >= 2, now - began > 0.3 { code = smc.write(FanKeys.target(index), number: speed) }
            }
            guard abs(reads - speed) < 2 else {
                let back = giveBackNow()
                let why = "fan \(index + 1) did not take the speed \(Int(speed)) (answer \(code.map { String($0, radix: 16) } ?? "none"), set \(Int(reads)))"
                HelperLog.note(why + "; fans: " + back.1)
                return (false, why)
            }
        }
        running = true
        if speeds != lastSet || !notes.isEmpty {
            HelperLog.note("Speeds set: " + speeds.map { String(Int($0)) }.joined(separator: ", ")
                           + (notes.isEmpty ? "" : " (" + notes.joined(separator: "; ") + ")"))
            lastSet = speeds
        }
        return (true, notes.joined(separator: "; "))
    }

    /// The Mac decides again. Thorough: every fan is given back, then the helper keeps looking for a second
    /// and gives back again any fan that turns up as held late (a hand-over that was still on its way).
    func giveBackNow() -> (Bool, String) {
        lastWord = now
        guard let smc else { return (false, "the fan controller did not open") }
        let keys = (0..<FanKeys.count(smc)).map { FanKeys.mode($0, smc: smc) }
        var gaveBack = 0
        // 0 = the Mac decides; some Macs then show 3 ("looked after by the Mac"), which is the same thing.
        for key in keys where smc.number(key) == 1 {
            _ = smc.write(key, number: 0)
            gaveBack += 1
        }
        let began = now
        var calmSince = now
        while now - began < 1, now - calmSince < 0.25 {
            usleep(20_000)
            for key in keys where smc.number(key) == 1 {
                _ = smc.write(key, number: 0)
                gaveBack += 1
                calmSince = now
            }
        }
        if usedUnlock {
            _ = smc.write(FanKeys.unlock, number: 0)
            usedUnlock = false
        }
        let fine = !keys.contains { smc.number($0) == 1 }
        running = false
        lastSet = []
        return (fine, fine ? (gaveBack > 0 ? "given back" : "the Mac already had them") : "a fan did not go back")
    }
}

final class Service: NSObject, NSXPCListenerDelegate, FanHelperProtocol {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func version(reply: @escaping (String) -> Void) { reply(HelperInfo.version) }

    func setSpeeds(_ speeds: [NSNumber], reply: @escaping (Bool, String) -> Void) {
        let asked = speeds.map(\.doubleValue)
        FanWriter.shared.queue.async {
            let answer = FanWriter.shared.setSpeeds(asked)
            reply(answer.0, answer.1)
        }
    }

    func giveBack(reply: @escaping (Bool, String) -> Void) {
        FanWriter.shared.queue.async {
            let answer = FanWriter.shared.giveBackNow()
            HelperLog.note("The app gave the fans back to the Mac (\(answer.1))")
            reply(answer.0, answer.1)
        }
    }
}

// A polite stop (the Mac shutting down, an update, a removal): the fans go back first.
signal(SIGTERM, SIG_IGN)
let stop = DispatchSource.makeSignalSource(signal: SIGTERM, queue: FanWriter.shared.queue)
stop.setEventHandler {
    let answer = FanWriter.shared.giveBackNow()
    HelperLog.note("Asked to stop; fans: \(answer.1)")
    exit(0)
}
stop.resume()

let service = Service()
let listener = NSXPCListener(machServiceName: HelperInfo.label)
// The Mac itself turns away every caller that is not the real app, signed by its maker.
listener.setConnectionCodeSigningRequirement(HelperInfo.appRequirement)
listener.delegate = service
FanWriter.shared.start()
listener.resume()
dispatchMain()
