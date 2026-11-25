import AppKit
import Combine
import CoreAudio
import FanMenuCore
import IOKit.ps
import UserNotifications

/// One fan as the panel shows it.
struct FanNow: Identifiable, Equatable {
    let id: Int
    let name: String
    var speed: Double?
    var range: FanRange
}

/// Is an app listening to the microphone the Mac uses? Asked without listening, so no permission is needed.
enum Microphone {
    static var inUse: Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return false }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}

enum Power {
    static var onBattery: Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        return (IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String) == kIOPSBatteryPowerValue
    }

    /// Is the battery charging right now? nil when the Mac does not say (no battery).
    static var charging: Bool? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in list {
            guard let about = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let charging = about[kIOPSIsChargingKey] as? Bool else { continue }
            return charging
        }
        return nil
    }
}

/// What the app knows and does: the readings, the choice in use, the rules that act by themselves,
/// and the line to the helper.
final class AppModel: ObservableObject {
    /// The amber note at the top of the panel.
    struct Note: Equatable {
        enum Kind { case needsOK, needsUpdate, told }
        let kind: Kind
        let text: String
    }

    /// Who asked for a choice. Your own tap wins over every rule that acts by itself.
    enum Cause { case you, outside, call, callEnd, power, wake, hours, hoursEnd }

    @Published private(set) var choice: FanChoice = .automatic
    @Published private(set) var fans: [FanNow] = []
    @Published private(set) var chip: Double?
    @Published private(set) var graphics: Double?
    @Published private(set) var battery: Double?
    // 0.5: more the Mac reports
    @Published private(set) var storage: Double?
    /// The case under the hands.
    @Published private(set) var palm: Double?
    /// What the whole Mac uses, in watts.
    @Published private(set) var power: Double?
    @Published private(set) var myPercent: Double
    @Published private(set) var followStart: Double
    @Published private(set) var followFull: Double
    @Published private(set) var helper: HelperState = .missing
    @Published private(set) var note: Note?
    /// The Mac's password dialog is open.
    @Published private(set) var working = false

    // 0.2
    /// How long a choice stays on.
    @Published private(set) var lasting: Lasting
    /// A time another app asked for with its wish (0.3.1), while it runs; nil = the "For" line rules.
    @Published private(set) var ownSeconds: Double?
    /// "8 min left" while a choice has an end.
    @Published private(set) var leftWords: String?
    /// Why the choice is what it is, when a rule set it: "during a call", "on battery".
    @Published private(set) var reason: String?
    @Published private(set) var quietPercent: Double
    @Published private(set) var coolPercent: Double
    @Published private(set) var heatNotice: Bool
    @Published private(set) var quietInCalls: Bool
    @Published private(set) var batteryRule: Bool
    @Published private(set) var backAfterSleep: Bool
    // 0.3
    /// Quiet gives the fans to the Mac while the chip is cool, so they can stop.
    @Published private(set) var quietRest: Bool
    /// Quiet is on and the Mac has the fans, because it is cool.
    @Published private(set) var resting = false
    @Published private(set) var happened: [Happening] = []
    /// The readings behind the graphs, and the time of the newest one.
    @Published private(set) var history = History()
    @Published private(set) var historyNow = Date().timeIntervalSince1970
    // 0.4
    /// The chip temperature at which the Mac itself was last seen to take the fans to full; nil = not seen yet.
    @Published private(set) var fullSeenAt: Double?
    // 0.5
    /// The chip temperature from which the heat notice counts: 80, 85, 90 or 95.
    @Published private(set) var heatLevel: Double
    @Published private(set) var batteryNotice: Bool
    @Published private(set) var quietHours: Bool
    /// Quiet hours, in minutes since midnight.
    @Published private(set) var quietFrom: Int
    @Published private(set) var quietTo: Int
    /// The last days in figures.
    @Published private(set) var week = Week()
    // 0.6
    /// Which temperature the small graph in the panel shows: chip, battery or the case.
    @Published private(set) var smallGraph: Sensor
    /// A notification when a timed choice ends.
    @Published private(set) var timedWord: Bool

    /// Only an open panel needs fresh readings every second.
    var panelOpen = false {
        didSet {
            guard panelOpen != oldValue else { return }
            if panelOpen { read() }
            retime()
        }
    }

    /// The fastest fan's top speed, for the graph's scale.
    var topSpeed: Double { fans.map(\.range.top).max() ?? 6000 }

    /// False for pictures with sample data: nothing is read, nothing is set.
    private let live: Bool
    private let smc: SMC?
    private let client = HelperClient()
    private var timer: Timer?
    private var timerEvery = 0.0
    private var chipReadings: [Double] = []
    private var hottest: Double?
    private var hotSince: Double?
    /// The speeds last sent to the helper, and when.
    private var sent: [Double]?
    private var lastSend = 0.0
    /// The choice tapped while the helper was not ready; it starts once the helper is.
    private var waiting: FanChoice?
    private var sendSoon: DispatchWorkItem?
    private var askedForNotes = false
    /// When the choice in use ends (seconds since 1970); nil = until you change it.
    private var endsAt: Double?
    private var choiceSince = Date().timeIntervalSince1970
    private var gaveBackAtStart = false
    // The heat notice
    private var warmSince: Double?
    private var lastHeatNotice: Double?
    // Quiet during calls
    private var micInUseSince: Double?
    private var micFreeSince: Double?
    private var callActive = false
    private var callBefore: FanChoice = .automatic
    /// This call already ended in "too hot" or in your own tap: leave the fans alone until it is over.
    private var callSpent = false
    // On battery
    private var wasOnBattery = false
    private var parked: FanChoice?
    // Sleep
    private var beforeSleep: FanChoice?
    // For checks: pretend the cable is pulled, or a call is on.
    private var pretendBattery: Bool?
    private var pretendCall: Bool?
    // Quiet lets the fans stop
    private var coolSince: Double?
    private var overSince: Double?
    /// When the app last took the fans back from a rest.
    private var heldSince: Double?
    /// For checks: pretend the chip has this temperature (only for the rest, nothing else).
    private var pretendChip: Double?
    private var lastHistorySave = 0.0
    /// The fans were at full on the reading before (or the app ran them): nothing new to learn until they slow.
    private var wasFull = true
    // 0.5
    /// The battery heat notice
    private var batteryWarmSince: Double?
    private var lastBatteryNotice: Double?
    /// Quiet hours: Quiet is on because of them; what was on before; and "leave the fans alone until these
    /// hours are over" (your own tap, or too hot).
    private var hoursActive = false
    private var hoursBefore: FanChoice = .automatic
    private var hoursSpent = false
    /// For checks: pretend it is this time of day (minutes since midnight).
    private var pretendMinute: Int?
    /// The graphics temperature as just read; nil while that part sleeps (the graph then has a gap).
    private var graphicsReading: Double?
    /// For checks: pretend the battery has this temperature (for the battery heat notice only).
    private var pretendBatteryTemp: Double?
    /// Was the choice worth it: the chip when the choice in use began.
    private var worthFrom: Double?
    /// The week in figures
    private var lastWeekTime: Double?
    private static var weekFile: URL { supportFolder.appendingPathComponent("week.json") }

    private enum Key {
        static let percent = "mySpeedPercent", start = "followStart", full = "followFull"
        static let lasting = "lasting", quiet = "quietPercent", cool = "coolPercent"
        static let heatNotice = "heatNotice", quietInCalls = "quietInCalls", batteryRule = "batteryRule", backAfterSleep = "backAfterSleep"
        static let quietRest = "quietRest"
        static let happened = "happened"
        static let fullSeenAt = "fullSeenAt"
        static let heatLevel = "heatLevel", batteryNotice = "batteryNotice"
        static let quietHours = "quietHours", quietFrom = "quietFrom", quietTo = "quietTo"
        static let smallGraph = "smallGraph", timedWord = "timedWord"
    }
    static let heatCategory = "heat"
    static let switchToCoolAction = "switchToCool"
    static let changedName = Notification.Name("com.schabbauer.AMSFanMenu.changed")

    /// Runs on while the Mac sleeps? No: seconds the Mac was awake. Good for "for 15 seconds".
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    /// The clock on the wall, for everything that has a time of day or must survive sleep.
    private var wall: Double { Date().timeIntervalSince1970 }

    static var supportFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AMS Fan Menu")
    }
    private static var historyFile: URL { supportFolder.appendingPathComponent("history.json") }
    static var stateFile: URL { supportFolder.appendingPathComponent("state.json") }

    /// For checks: the readings as they are kept on this Mac. Only reads.
    static func keptHistory() -> History? {
        guard let data = try? Data(contentsOf: historyFile) else { return nil }
        return try? JSONDecoder().decode(History.self, from: data)
    }

    /// For checks: where the Mac was last seen to take the fans to full, if ever. Only reads.
    static func keptFullSeenAt() -> Double? {
        UserDefaults.standard.object(forKey: Key.fullSeenAt) as? Double
    }

    /// `readOnly`: only looks at the fans and temperatures once, for a check from outside. It changes nothing:
    /// no helper, no state file, no history. (0.2 found this the hard way: a check overwrote the state file.)
    init(live: Bool = true, readOnly: Bool = false) {
        self.live = live && !readOnly
        let store = UserDefaults.standard
        myPercent = min(max(store.object(forKey: Key.percent) as? Double ?? 45, 0), 100)
        let pair = Follow.settled(start: store.object(forKey: Key.start) as? Double ?? Follow.defaultStart,
                                  full: store.object(forKey: Key.full) as? Double ?? Follow.defaultFull, movedStart: true)
        followStart = pair.start
        followFull = pair.full
        lasting = Lasting(rawValue: store.string(forKey: Key.lasting) ?? "") ?? .untilChanged
        quietPercent = Presets.cleanQuiet(store.object(forKey: Key.quiet) as? Double ?? Presets.defaultQuiet)
        coolPercent = Presets.cleanCool(store.object(forKey: Key.cool) as? Double ?? Presets.defaultCool)
        heatNotice = store.object(forKey: Key.heatNotice) as? Bool ?? true
        quietInCalls = store.object(forKey: Key.quietInCalls) as? Bool ?? false
        batteryRule = store.object(forKey: Key.batteryRule) as? Bool ?? true
        backAfterSleep = store.object(forKey: Key.backAfterSleep) as? Bool ?? false
        quietRest = store.object(forKey: Key.quietRest) as? Bool ?? true
        fullSeenAt = store.object(forKey: Key.fullSeenAt) as? Double
        heatLevel = HeatNotice.clean(store.object(forKey: Key.heatLevel) as? Double ?? HeatNotice.limit)
        batteryNotice = store.object(forKey: Key.batteryNotice) as? Bool ?? true
        quietHours = store.object(forKey: Key.quietHours) as? Bool ?? false
        quietFrom = QuietHours.clean(store.object(forKey: Key.quietFrom) as? Int ?? QuietHours.defaultFrom)
        quietTo = QuietHours.clean(store.object(forKey: Key.quietTo) as? Int ?? QuietHours.defaultTo)
        smallGraph = Self.smallGraphPicks.first { $0.rawValue == store.string(forKey: Key.smallGraph) } ?? .chip
        timedWord = store.object(forKey: Key.timedWord) as? Bool ?? false
        smc = live || readOnly ? SMC() : nil
        guard self.live else {
            if readOnly { read() }
            return
        }
        if let data = store.data(forKey: Key.happened), let list = try? JSONDecoder().decode([Happening].self, from: data) {
            happened = list
        }
        if let data = try? Data(contentsOf: Self.historyFile), var old = try? JSONDecoder().decode(History.self, from: data) {
            old.trim(now: wall)
            history = old.withoutFalseGraphics()
        }
        if let data = try? Data(contentsOf: Self.weekFile), let old = try? JSONDecoder().decode(Week.self, from: data) {
            week = old
        }
        wasOnBattery = Power.onBattery
        read()
        addSample()
        writeState()
        checkHelper()
        retime()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    // MARK: Reading

    /// Fan speeds and temperatures, straight from the Mac.
    func read() {
        guard let smc else { return }
        let count = FanKeys.count(smc)
        let fresh = (0..<count).map { index in
            // A speed of 0 is true: in Automatic the Mac stops the fans completely when it is cool.
            FanNow(id: index, name: Words.fanName(index: index, count: count), speed: smc.number(FanKeys.now(index)),
                   range: FanRange(lowest: smc.number(FanKeys.lowest(index)) ?? 0, top: smc.number(FanKeys.top(index)) ?? 0))
        }
        if fresh != fans { fans = fresh }
        let cores = SensorKeys.cores.compactMap { smc.number($0) }
        let chipNow = Reading.average(cores)
        hottest = Reading.hottest(cores)
        if let chipNow {
            chipReadings.append(chipNow)
            if chipReadings.count > Follow.smoothOver { chipReadings.removeFirst(chipReadings.count - Follow.smoothOver) }
        }
        // Asleep, the graphics part answers about 9°: no reading. The panel keeps the last true figure.
        let graphicsNow = Reading.average(SensorKeys.graphics.compactMap { smc.number($0) }, floor: Reading.graphicsFloor)
        graphicsReading = graphicsNow
        let batteryNow = Reading.average(SensorKeys.battery.compactMap { smc.number($0) })
        // Whole degrees are what the panel shows; anything finer would only redraw it for nothing.
        if chipNow?.rounded() != chip?.rounded() { chip = chipNow }
        if let graphicsNow, graphicsNow.rounded() != graphics?.rounded() { graphics = graphicsNow }
        if batteryNow?.rounded() != battery?.rounded() { battery = batteryNow }
        let storageNow = Reading.average(MoreKeys.storage.compactMap { smc.number($0) })
        let palmNow = Reading.average(MoreKeys.palm.compactMap { smc.number($0) })
        let powerNow = smc.number(MoreKeys.power).flatMap { $0.isFinite && $0 >= 0 && $0 < 500 ? $0 : nil }
        if storageNow?.rounded() != storage?.rounded() { storage = storageNow }
        if palmNow?.rounded() != palm?.rounded() { palm = palmNow }
        if powerNow?.rounded() != power?.rounded() { power = powerNow }
    }

    /// 0.5: what else this Mac reports. The names are the ones fan tools commonly use; Apple documents none of them.
    enum MoreKeys {
        /// The storage (flash) chips.
        static let storage = ["TH0a", "TH0b"]
        /// The case under the hands, left and right of the trackpad.
        static let palm = ["Ts0P", "Ts1P"]
        /// What the whole Mac uses, in watts.
        static let power = "PSTR"
    }

    /// The readings in a few lines, for a check from outside.
    func readout() -> String {
        var lines = fans.map { "\($0.name): \(Words.turns($0.speed)) (lowest \(Words.turns($0.range.lowest)), top \(Words.turns($0.range.top)))" }
        lines.append("Chip \(Words.degrees(chip)) · hottest core \(Words.degrees(hottest)) · Graphics \(Words.degrees(graphics)) · Battery \(Words.degrees(battery))")
        lines.append("Storage \(Words.degrees(storage)) \u{00B7} Case \(Words.degrees(palm)) \u{00B7} Power \(Words.watts(power))")
        lines.append("Helper in place: \(HelperInstaller.installed ? "yes" : "no") · on battery: \(Power.onBattery ? "yes" : "no") · microphone in use: \(Microphone.inUse ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }

    /// Once a second while the panel is open or the app runs the fans; otherwise every five seconds,
    /// for the graphs and the rules that act by themselves.
    private func retime() {
        guard live else { return }
        let every = (panelOpen || choice.appDecides) ? 1.0 : History.every
        guard timer == nil || every != timerEvery else { return }
        timer?.invalidate()
        let new = Timer(timeInterval: every, repeats: true) { [weak self] _ in self?.tick() }
        new.tolerance = every * 0.2
        RunLoop.main.add(new, forMode: .common)
        timer = new
        timerEvery = every
    }

    /// One reading every five seconds goes into the history behind the graphs.
    private func addSample() {
        let time = wall
        guard history.add(Sample(time: time, chip: chip, speeds: fans.compactMap(\.speed),
                                 graphics: graphicsReading, battery: battery, storage: storage, palm: palm, power: power,
                                 charging: Power.charging)) else { return }
        historyNow = time
        learnFull()
        week.add(time: time, chip: chip, fansTurning: fans.contains { ($0.speed ?? 0) > 0 },
                 appRuns: choice.appDecides && !resting, seconds: min(max(time - (lastWeekTime ?? time), 0), 15))
        lastWeekTime = time
        if now - lastHistorySave > 300 { saveHistory() }
    }

    /// Where the Mac itself takes the fans to full: the chip temperature on the reading where that begins.
    private func learnFull() {
        let speeds = fans.compactMap(\.speed)
        let full = speeds.count == fans.count && FullSeen.isFull(speeds: speeds, tops: fans.map(\.range.top))
        let step = FullSeen.step(macHasFans: !choice.appDecides || resting, full: full, wasFull: wasFull, chip: chip)
        wasFull = step.wasFull
        guard let seen = step.seenAt else { return }
        fullSeenAt = seen
        UserDefaults.standard.set(seen, forKey: Key.fullSeenAt)
        Diary.note("The Mac itself took the fans to full with the chip at \(Words.degrees(seen))")
    }

    private func saveWeek() {
        guard let data = try? JSONEncoder().encode(week) else { return }
        try? FileManager.default.createDirectory(at: Self.supportFolder, withIntermediateDirectories: true)
        try? data.write(to: Self.weekFile, options: .atomic)
    }

    private func saveHistory() {
        lastHistorySave = now
        saveWeek()
        let copy = history
        let file = Self.historyFile
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(copy) { try? data.write(to: file, options: .atomic) }
        }
    }

    private func tick() {
        read()
        addSample()
        coolSince = QuietRest.coolSince(chip: restChip, now: now, since: coolSince)
        checkPower()
        checkCall()
        checkHours()
        checkBattery()
        guard choice.appDecides else {
            checkWarmth()
            return
        }
        hotSince = HeatGuard.hotSince(hottest: hottest, now: now, since: hotSince)
        if HeatGuard.handsBack(choice: choice, hotSince: hotSince, now: now) {
            let degrees = Words.degrees(hottest)
            if callActive { callSpent = true }
            if hoursActive { hoursSpent = true }
            handBack(telling: "Too hot (\(degrees)). The Mac has the fans again.", why: "too hot while \(choice.title) was on",
                     story: "Too hot (\(degrees)): the Mac has the fans again")
            notify("Too hot (\(degrees)). The Mac has the fans again.")
            return
        }
        if Lasting.isOver(endsAt: endsAt, now: wall) {
            handBack(telling: nil, why: "the time was up", story: "The time was up: the Mac has the fans again")
            return
        }
        let left = Lasting.leftWords(endsAt: endsAt, now: wall)
        if left != leftWords { leftWords = left }
        checkRest()
        // The Mac takes the fans back when it hears nothing, so the choice is repeated; Follow also moves with the heat.
        if !resting, now - lastSend >= DeadMan.repeatEvery { send() }
    }

    // MARK: Choosing

    /// The speeds the choice in use asks for, one per fan.
    private func wantedSpeeds() -> [Double]? {
        guard let share = FanPlan.share(choice: choice, myPercent: myPercent, chip: Follow.smoothed(chipReadings),
                                        start: followStart, full: followFull, quietPercent: quietPercent, coolPercent: coolPercent),
              !fans.isEmpty else { return nil }
        let fresh = fans.map { $0.range.speed(share: share) }
        // Follow does not chase every degree: a new speed only when it is worth it.
        if choice == .follow, let sent, sent.count == fresh.count,
           !Follow.worthSending(new: fresh[0], last: sent[0], atAnEnd: share <= 0 || share >= 1) {
            return sent
        }
        return fresh
    }

    /// `forSeconds`: a time of its own for this one choice (a wish from another app); the pick in the
    /// "For" line stays as it is.
    func choose(_ new: FanChoice, by cause: Cause = .you, forSeconds: Double? = nil) {
        guard live else { choice = new; return }
        let yours = cause == .you || cause == .outside
        if yours {
            // Your own tap wins: nothing is put back later behind your back.
            if callActive { callSpent = true }
            callActive = false
            // A tap during quiet hours ends them for this night.
            if quietHours, QuietHours.inside(minute: minuteNow, from: quietFrom, to: quietTo) { hoursSpent = true }
            hoursActive = false
            parked = nil
            beforeSleep = nil
        }
        if new == .automatic {
            handBack(telling: nil, why: yours ? "Automatic chosen" : "put back to Automatic",
                     story: yours ? "Automatic: the Mac has the fans again" : nil)
            return
        }
        guard helper == .ready else {
            guard yours else { return }
            waiting = new
            showHelperNote()
            // The state may be old (the helper was put in place by another copy): look again.
            checkHelper()
            return
        }
        let before = choice
        if before.appDecides, before != new { tellWorth(of: before) }
        choice = new
        waiting = nil
        hotSince = nil
        sent = nil
        resting = false
        heldSince = nil
        overSince = nil
        reason = cause == .call ? "during a call" : cause == .hours ? "quiet hours" : nil
        // Quiet during a call lasts as long as the call, and quiet hours as long as the hours, not as long
        // as the "For" line says.
        let byRule = cause == .call || cause == .hours
        ownSeconds = byRule ? nil : forSeconds
        endsAt = byRule ? nil : (forSeconds.map { wall + $0 } ?? lasting.endsAt(from: wall))
        leftWords = Lasting.leftWords(endsAt: endsAt, now: wall)
        if note?.kind == .told { note = nil }
        if before != new || yours {
            let howLong = forSeconds.map(OutsideAsk.words(seconds:)) ?? lasting.words
            Diary.note("Choice: \(new.title)" + (endsAt != nil ? " for \(howLong ?? lasting.title)" : ""))
            if yours { tell(new.title + (howLong.map { " for \($0)" } ?? "")) }
            changed(to: new)
        }
        // Quiet on a Mac that is already cool: straight to the rest, without a second at the lowest speed first.
        if new == .quiet, QuietRest.step(enabled: quietRest, resting: false, coolSince: coolSince, overSince: nil,
                                         heldSince: nil, now: now) == .rest {
            beginRest()
        } else {
            send()
        }
        retime()
        askForNotes()
    }

    /// The choice changed: a dashed line in the graphs, and word to other apps.
    private func changed(to new: FanChoice) {
        choiceSince = wall
        worthFrom = new.appDecides ? chip : nil
        history.mark(new.title, at: choiceSince)
        historyNow = choiceSince
        writeState()
    }

    private func send() {
        guard choice.appDecides, !resting, let speeds = wantedSpeeds() else { return }
        let first = sent == nil
        let changed = sent != speeds
        sent = speeds
        lastSend = now
        let asked = choice
        if changed { Diary.note("\(asked.title): asking for \(speeds.map { Words.turns($0) }.joined(separator: " and "))") }
        client.setSpeeds(speeds) { [weak self] fine, text in
            guard let self, self.choice == asked else { return }
            if !fine {
                self.failed(text)
            } else if !text.isEmpty {
                Diary.note("The helper: \(text)")
                if !first { self.tell("The Mac had taken a fan back: the helper took it over again") }
            }
        }
    }

    private func failed(_ why: String) {
        Diary.note("The fans did not take the speed: \(why)")
        handBack(telling: "The fans did not take the speed, so the Mac has them again. (\(why))", why: "the helper said no",
                 story: "The fans did not take the speed: the Mac has them again")
        checkHelper()
    }

    /// The Mac decides again. `telling`: an amber note that says why, when it was not your own tap.
    /// `story`: the line for the "What happened" list.
    private func handBack(telling: String?, why: String, story: String?) {
        let was = choice
        sendSoon?.cancel()
        choice = .automatic
        waiting = nil
        sent = nil
        hotSince = nil
        endsAt = nil
        ownSeconds = nil
        leftWords = nil
        reason = nil
        callActive = false
        hoursActive = false
        resting = false
        heldSince = nil
        overSince = nil
        if was.appDecides {
            client.giveBack { fine, text in
                if !fine { Diary.note("Giving the fans back: \(text)") }
            }
            Diary.note("Automatic (\(why)); before: \(was.title)")
            tellWorth(of: was)
            if let story { tell(story) }
            changed(to: .automatic)
        }
        if let telling {
            note = Note(kind: .told, text: telling)
        } else {
            note = nil
        }
        retime()
    }

    /// Quitting: the fans go back to the Mac, and the app waits a moment for the helper's word.
    func quitting() {
        guard live else { return }
        if choice.appDecides {
            let fine = client.giveBackAndWait()
            Diary.note("Quit while \(choice.title) was on; fans given back: \(fine ? "yes" : "no word from the helper, it gives them back by itself within \(Int(DeadMan.seconds)) s")")
            tell("The app quit: the Mac has the fans again")
            choice = .automatic
            endsAt = nil
            history.mark(FanChoice.automatic.title, at: wall)
            writeState()
        }
        if let data = try? JSONEncoder().encode(history) {
            try? FileManager.default.createDirectory(at: Self.supportFolder, withIntermediateDirectories: true)
            try? data.write(to: Self.historyFile, options: .atomic)
        }
        saveWeek()
        Diary.finish()
    }

    func setMyPercent(_ value: Double) {
        let whole = min(max(value.rounded(), 0), 100)
        guard whole != myPercent || choice != .mySpeed else { return }
        myPercent = whole
        UserDefaults.standard.set(whole, forKey: Key.percent)
        if choice != .mySpeed {
            choose(.mySpeed)
        } else {
            sendAfterAMoment()
        }
    }

    func setFollow(start: Double? = nil, full: Double? = nil) {
        let pair = Follow.settled(start: start ?? followStart, full: full ?? followFull, movedStart: start != nil)
        guard pair.start != followStart || pair.full != followFull else { return }
        followStart = pair.start
        followFull = pair.full
        UserDefaults.standard.set(pair.start, forKey: Key.start)
        UserDefaults.standard.set(pair.full, forKey: Key.full)
        if choice == .follow {
            sent = nil
            sendAfterAMoment()
        }
    }

    /// While a slider is dragged: one message to the helper a few times a second, not one per point.
    private func sendAfterAMoment() {
        guard live else { return }
        sendSoon?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.send() }
        sendSoon = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: 0.2 — a choice for a limited time, your own speeds, the switches

    /// The "For" line. A new time starts afresh for the choice in use.
    func setLasting(_ new: Lasting) {
        // A time of its own is running: his tap on the line takes over, also on the pick he already had.
        guard new != lasting || ownSeconds != nil else { return }
        ownSeconds = nil
        lasting = new
        UserDefaults.standard.set(new.rawValue, forKey: Key.lasting)
        guard live, choice.appDecides, !callActive else { return }
        endsAt = new.endsAt(from: wall)
        leftWords = Lasting.leftWords(endsAt: endsAt, now: wall)
        tell(choice.title + (new.words.map { " for \($0)" } ?? ": until you change it"))
        writeState()
    }

    func setQuietPercent(_ value: Double) {
        let clean = Presets.cleanQuiet(value)
        guard clean != quietPercent else { return }
        quietPercent = clean
        UserDefaults.standard.set(clean, forKey: Key.quiet)
        if choice == .quiet { sendAfterAMoment() }
    }

    func setCoolPercent(_ value: Double) {
        let clean = Presets.cleanCool(value)
        guard clean != coolPercent else { return }
        coolPercent = clean
        UserDefaults.standard.set(clean, forKey: Key.cool)
        if choice == .cool { sendAfterAMoment() }
    }

    func setHeatNotice(_ on: Bool) {
        heatNotice = on
        UserDefaults.standard.set(on, forKey: Key.heatNotice)
        if on { askForNotes() }
    }

    func setQuietInCalls(_ on: Bool) {
        quietInCalls = on
        UserDefaults.standard.set(on, forKey: Key.quietInCalls)
        micInUseSince = nil
        micFreeSince = nil
        callSpent = false
    }

    func setBatteryRule(_ on: Bool) {
        batteryRule = on
        UserDefaults.standard.set(on, forKey: Key.batteryRule)
    }

    // MARK: 0.5 — your own heat notice level, the battery heat notice, quiet hours

    func setHeatLevel(_ value: Double) {
        let clean = HeatNotice.clean(value)
        guard clean != heatLevel else { return }
        heatLevel = clean
        UserDefaults.standard.set(clean, forKey: Key.heatLevel)
        warmSince = nil
    }

    /// What the small graph in the panel may show.
    static let smallGraphPicks: [Sensor] = [.chip, .battery, .palm]

    func setSmallGraph(_ sensor: Sensor) {
        guard Self.smallGraphPicks.contains(sensor) else { return }
        smallGraph = sensor
        UserDefaults.standard.set(sensor.rawValue, forKey: Key.smallGraph)
    }

    func setTimedWord(_ on: Bool) {
        timedWord = on
        UserDefaults.standard.set(on, forKey: Key.timedWord)
        if on { askForNotes() }
    }

    func setBatteryNotice(_ on: Bool) {
        batteryNotice = on
        UserDefaults.standard.set(on, forKey: Key.batteryNotice)
        if on { askForNotes() }
    }

    func setQuietHours(_ on: Bool) {
        quietHours = on
        UserDefaults.standard.set(on, forKey: Key.quietHours)
    }

    func setQuietTimes(from: Int? = nil, to: Int? = nil) {
        quietFrom = QuietHours.clean(from ?? quietFrom)
        quietTo = QuietHours.clean(to ?? quietTo)
        UserDefaults.standard.set(quietFrom, forKey: Key.quietFrom)
        UserDefaults.standard.set(quietTo, forKey: Key.quietTo)
    }

    func setBackAfterSleep(_ on: Bool) {
        backAfterSleep = on
        UserDefaults.standard.set(on, forKey: Key.backAfterSleep)
    }

    // MARK: 0.3 — Quiet lets the fans stop

    /// The chip temperature the rest goes by: the average of the newest readings.
    private var restChip: Double? { pretendChip ?? Follow.smoothed(chipReadings) }

    /// While Quiet is on: cool for a while → the Mac gets the fans and may stop them; the Mac wants them
    /// faster than Quiet → the app takes them again and holds them at Quiet's speed.
    private func checkRest() {
        guard choice == .quiet else { return }
        if resting {
            let share = min(max(quietPercent, 0), 100) / 100
            overSince = QuietRest.overSince(speeds: fans.map(\.speed), quiet: fans.map { $0.range.speed(share: share) },
                                            now: now, since: overSince)
        }
        switch QuietRest.step(enabled: quietRest, resting: resting, coolSince: coolSince, overSince: overSince,
                              heldSince: heldSince, now: now) {
        case .nothing: break
        case .rest: beginRest()
        case .hold: endRest()
        }
    }

    private func beginRest() {
        resting = true
        sent = nil
        overSince = nil
        sendSoon?.cancel()
        client.giveBack { fine, text in
            if !fine { Diary.note("Quiet, giving the fans to the Mac for a rest: \(text)") }
        }
        Diary.note("Quiet: the chip is cool (\(Words.degrees(restChip))); the Mac has the fans and may stop them")
        writeState()
    }

    private func endRest() {
        let speeds = fans.map { Words.turns($0.speed) }.joined(separator: " and ")
        resting = false
        heldSince = now
        overSince = nil
        Diary.note(quietRest ? "Quiet: the Mac ran the fans faster than Quiet (\(speeds)); the app holds them at Quiet's speed again"
                             : "Quiet: \"Quiet lets the fans stop\" was switched off; the app holds the fans at Quiet's speed again")
        writeState()
        send()
    }

    func setQuietRest(_ on: Bool) {
        quietRest = on
        UserDefaults.standard.set(on, forKey: Key.quietRest)
        if live { checkRest() }
    }

    /// For checks: a number pretends the chip has that temperature (for the rest only); anything else looks
    /// at the real one again.
    func pretend(chip word: String) {
        pretendChip = Double(word)
        coolSince = nil
        Diary.note("Asked from outside to pretend: chip \(word)")
    }

    // MARK: 0.2 — the rules that act by themselves

    /// While the Mac decides: the chip at 90° or more for five minutes is worth a word.
    private func checkWarmth() {
        warmSince = HeatNotice.hotSince(chip: chip, level: heatLevel, now: now, since: warmSince)
        guard HeatNotice.due(enabled: heatNotice, appDecides: choice.appDecides, hotSince: warmSince, now: now, lastTold: lastHeatNotice) else { return }
        lastHeatNotice = now
        let text = "The chip has been at \(Int(heatLevel))° or more for \(Int(HeatNotice.patience / 60)) minutes."
        tell("Heat notice: the chip was at \(Int(heatLevel))° or more for \(Int(HeatNotice.patience / 60)) minutes")
        Diary.note("Heat notice sent (chip \(Words.degrees(chip)))")
        notify(text, category: Self.heatCategory)
    }

    /// Quiet while an app listens to the microphone for a while, and the choice from before back afterwards.
    private func checkCall() {
        guard quietInCalls || callActive else { return }
        let inUse = pretendCall ?? Microphone.inUse
        if inUse {
            if micInUseSince == nil { micInUseSince = now }
            micFreeSince = nil
        } else {
            if micFreeSince == nil { micFreeSince = now }
            micInUseSince = nil
            // The call is over: the next one counts afresh.
            if !callActive, let micFreeSince, now - micFreeSince >= CallQuiet.endAfter { callSpent = false }
        }
        switch CallQuiet.step(enabled: quietInCalls, inUseSince: micInUseSince, freeSince: micFreeSince, now: now, active: callActive) {
        case .nothing:
            break
        case .goQuiet:
            guard !callSpent, helper == .ready, choice != .quiet, parked == nil else { return }
            callBefore = choice
            callActive = true
            tell("A call began: Quiet")
            Diary.note("Microphone in use for \(Int(CallQuiet.startAfter)) s: Quiet (before: \(callBefore.title))")
            choose(.quiet, by: .call)
        case .putBack:
            let back = callBefore
            callActive = false
            callSpent = false
            Diary.note("Microphone free again: back to \(back.title)")
            tell(back.appDecides ? "The call ended: \(back.title) again" : "The call ended: the Mac has the fans again")
            if back.appDecides {
                choose(back, by: .callEnd)
            } else {
                handBack(telling: nil, why: "the call ended", story: nil)
            }
        }
    }

    /// On battery the Mac decides; with the cable back in, your choice comes back.
    private func checkPower() {
        let onBattery = pretendBattery ?? Power.onBattery
        defer { wasOnBattery = onBattery }
        switch BatteryRule.step(enabled: batteryRule, onBattery: onBattery, wasOnBattery: wasOnBattery,
                                appDecides: choice.appDecides, parked: parked != nil) {
        case .nothing:
            break
        case .handBack:
            // A call's Quiet is not worth putting back; what you had before the call is.
            let keep = callActive ? callBefore : hoursActive ? hoursBefore : choice
            handBack(telling: nil, why: "on battery", story: "On battery: the Mac has the fans again")
            if keep.appDecides {
                parked = keep
                reason = "on battery"
                writeState()
            }
        case .putBack:
            guard let back = parked else { return }
            parked = nil
            reason = nil
            tell("Power is back: \(back.title) again")
            Diary.note("Power is back: \(back.title) again")
            choose(back, by: .power)
        }
    }

    @objc private func willSleep() {
        guard choice.appDecides else { return }
        let keep = callActive ? callBefore : hoursActive ? hoursBefore : choice
        beforeSleep = backAfterSleep && keep.appDecides ? keep : nil
        // With "Choice back after sleep" on, the choice returns by itself, so there is nothing to tell.
        handBack(telling: beforeSleep == nil ? "The Mac went to sleep, so it has the fans again." : nil,
                 why: "the Mac went to sleep", story: "The Mac went to sleep: it has the fans again")
        saveHistory()
    }

    @objc private func didWake() {
        Diary.note("Woke from sleep; the Mac decides" + (beforeSleep.map { "; \($0.title) comes back in 5 s" } ?? ""))
        read()
        checkHelper()
        // The Mac needs a moment after waking before it hands the fans over again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, let back = self.beforeSleep else { return }
            self.beforeSleep = nil
            guard self.backAfterSleep, self.choice == .automatic else { return }
            self.tell("Awake again: \(back.title) is back")
            self.choose(back, by: .wake)
        }
    }

    /// For checks: behaves as if the Mac went to sleep and woke at once.
    func pretendSleepAndWake() {
        willSleep()
        didWake()
    }

    /// For checks: "on"/"off" pretends, anything else looks at the real thing again.
    func pretend(battery word: String) {
        pretendBattery = word == "on" ? true : word == "off" ? false : nil
        Diary.note("Asked from outside to pretend: on battery \(word)")
        checkPower()
    }

    func pretend(call word: String) {
        pretendCall = word == "on" ? true : word == "off" ? false : nil
        Diary.note("Asked from outside to pretend: call \(word)")
        checkCall()
    }

    // MARK: 0.5 — quiet hours, the battery heat notice, was the choice worth it

    private var minuteNow: Int { pretendMinute ?? QuietHours.minute(of: wall) }

    /// Between the two times Quiet comes on by itself; afterwards the choice from before comes back.
    private func checkHours() {
        guard quietHours || hoursActive else { return }
        let inside = QuietHours.inside(minute: minuteNow, from: quietFrom, to: quietTo)
        if !inside { hoursSpent = false }
        switch QuietHours.step(enabled: quietHours, inside: inside, active: hoursActive) {
        case .nothing:
            break
        case .goQuiet:
            // On battery, during a call, or without the helper: not now; the next reading asks again.
            guard !hoursSpent, helper == .ready, parked == nil, !callActive else { return }
            // Quiet is on already, by your own tap: yours it stays.
            guard choice != .quiet else { hoursSpent = true; return }
            // Just woken: what "Choice back after sleep" was about to bring back is what comes back after the hours.
            hoursBefore = beforeSleep ?? choice
            beforeSleep = nil
            hoursActive = true
            tell("Quiet hours began: Quiet")
            Diary.note("Quiet hours (\(QuietHours.words(quietFrom)) to \(QuietHours.words(quietTo))): Quiet (before: \(hoursBefore.title))")
            choose(.quiet, by: .hours)
            // The helper said no, or something else kept Quiet from starting: do not ask every second.
            if choice != .quiet { hoursActive = false; hoursSpent = true }
        case .putBack:
            let back = hoursBefore
            hoursActive = false
            Diary.note("Quiet hours are over: back to \(back.title)")
            tell(back.appDecides ? "Quiet hours ended: \(back.title) again" : "Quiet hours ended: the Mac has the fans again")
            if back.appDecides {
                choose(back, by: .hoursEnd)
            } else {
                handBack(telling: nil, why: "quiet hours ended", story: nil)
            }
        }
    }

    /// The battery above 35° for ten minutes is worth a word, whoever has the fans.
    private func checkBattery() {
        batteryWarmSince = BatteryNotice.hotSince(battery: pretendBatteryTemp ?? battery, now: now, since: batteryWarmSince)
        guard BatteryNotice.due(enabled: batteryNotice, hotSince: batteryWarmSince, now: now, lastTold: lastBatteryNotice) else { return }
        lastBatteryNotice = now
        let minutes = Int(BatteryNotice.patience / 60)
        tell("Battery heat notice: the battery was above \(Int(BatteryNotice.limit))° for \(minutes) minutes")
        Diary.note("Battery heat notice sent (battery \(Words.degrees(battery)))")
        // "Switch to Cool" only makes sense while the Mac decides.
        notify("The battery has been above \(Int(BatteryNotice.limit))° for \(minutes) minutes (now \(Words.degrees(battery))).",
               category: choice.appDecides ? nil : Self.heatCategory)
    }

    /// A choice of yours ends: what it did to the chip goes into "What happened".
    private func tellWorth(of was: FanChoice) {
        guard let text = Worth.words(title: was.title, seconds: wall - choiceSince, from: worthFrom, to: chip) else { return }
        tell(text)
    }

    /// For checks: "22:30" pretends it is that time of day (for quiet hours only); anything else looks at the clock again.
    func pretend(clock word: String) {
        let parts = word.split(separator: ":").compactMap { Int($0) }
        pretendMinute = parts.count == 2 ? QuietHours.clean(parts[0] * 60 + parts[1]) : nil
        Diary.note("Asked from outside to pretend: the time is \(word)")
        checkHours()
    }

    /// For checks: a number pretends the battery has that temperature until the next real reading differs.
    func pretend(battery degrees: Double?) {
        pretendBatteryTemp = degrees
        Diary.note("Asked from outside to pretend: battery \(degrees.map { Words.degrees($0) } ?? "real")")
    }

    // MARK: 0.2 — what happened, and word to other apps

    /// One line for the "What happened" list in Settings.
    private func tell(_ text: String) {
        guard live else { return }
        happened = HappenedLog.adding(Happening(time: wall, text: text), to: happened)
        if let data = try? JSONEncoder().encode(happened) { UserDefaults.standard.set(data, forKey: Key.happened) }
    }

    /// The app's state in a small file, and a note to whoever listens (AMS Deck Mate's fan keys).
    private func writeState() {
        guard live else { return }
        var state: [String: Any] = ["choice": choice.rawValue, "title": choice.title, "appDecides": choice.appDecides,
                                    "since": choiceSince, "version": AppInfo.version]
        if let endsAt { state["endsAt"] = endsAt }
        if let reason { state["reason"] = reason }
        state["resting"] = resting
        try? FileManager.default.createDirectory(at: Self.supportFolder, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Self.stateFile, options: .atomic)
        }
        DistributedNotificationCenter.default().postNotificationName(Self.changedName, object: choice.rawValue,
                                                                     userInfo: nil, deliverImmediately: true)
    }

    // MARK: The helper

    private func showHelperNote() {
        switch helper {
        case .missing:
            note = Note(kind: .needsOK, text: "Setting the fans needs your OK once. The Mac will ask for your Mac password.")
        case .outdated:
            note = Note(kind: .needsUpdate, text: "The fan helper is from an older version. It needs your OK once more.")
        case .ready:
            if note?.kind != .told { note = nil }
        }
    }

    /// Is the helper there, and is it the right one? Then starts a choice that was waiting for it.
    func checkHelper() {
        guard live else { return }
        guard HelperInstaller.installed else {
            setHelper(.missing)
            return
        }
        client.version { [weak self] version in
            // There but silent counts as old: putting it in place again cures both.
            self?.setHelper(HelperCheck.state(installed: version ?? "no answer", wanted: HelperInfo.version))
        }
    }

    private func setHelper(_ state: HelperState) {
        if helper != state {
            helper = state
            Diary.note("Helper: \(state == .ready ? "ready" : state == .missing ? "not in place" : "needs an update")")
        }
        if state == .ready {
            if note?.kind == .needsOK || note?.kind == .needsUpdate { note = nil }
            // The app starts on Automatic. If it had stopped unexpectedly, the helper may still hold the fans
            // at the old speed: ask it to give them back, so that the screen and the fans agree.
            if !gaveBackAtStart {
                gaveBackAtStart = true
                if !choice.appDecides, waiting == nil {
                    client.giveBack { [weak self] _, text in
                        guard text == "given back" else { return }
                        Diary.note("At start the helper still held the fans; given back to the Mac")
                        self?.tell("The app had stopped unexpectedly: the fans were given back to the Mac")
                    }
                }
            }
            if let waiting { choose(waiting) }
        } else if waiting != nil || note?.kind == .needsOK || note?.kind == .needsUpdate {
            showHelperNote()
        }
    }

    /// "Allow fan control…" / "Update the helper…": the Mac asks for the password in its own dialog.
    func allowFanControl() {
        guard live, !working else { return }
        working = true
        Diary.note("Asking the Mac to put the helper in place")
        HelperInstaller.install { [weak self] outcome in
            guard let self else { return }
            self.working = false
            self.client.reset()
            switch outcome {
            case .done:
                Diary.note("The helper is in place")
                self.tell("Fan control allowed: the helper is in place")
                // The Mac needs a moment before the fresh helper answers.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.checkHelper() }
            case .cancelled:
                Diary.note("The password dialog was cancelled")
                self.waiting = nil
            case .failed(let why):
                Diary.note("Putting the helper in place failed: \(why)")
                self.waiting = nil
                self.note = Note(kind: .needsOK, text: "That did not work, so nothing was changed. (\(why))")
            }
        }
    }

    func removeHelper() {
        guard live, !working else { return }
        if choice.appDecides { handBack(telling: nil, why: "the helper is being removed", story: nil) }
        working = true
        HelperInstaller.remove { [weak self] outcome in
            guard let self else { return }
            self.working = false
            self.client.reset()
            Diary.note("Removing the helper: \(outcome == .done ? "done" : outcome == .cancelled ? "cancelled" : "failed")")
            if outcome == .done { self.tell("The helper was removed") }
            self.checkHelper()
        }
    }

    // MARK: Notes

    /// The amber note's "OK".
    func dismissNote() {
        waiting = nil
        note = nil
    }

    /// Asked the first time there can be anything to tell.
    func askForNotes() {
        guard live, !askedForNotes else { return }
        askedForNotes = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ text: String, category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "AMS Fan Menu"
        content.body = text
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "fans-\(UUID().uuidString)", content: content, trigger: nil))
    }

    // MARK: Sample data for pictures

    static func sample(_ choice: FanChoice = .automatic, note: Note? = nil, helper: HelperState = .ready,
                       lasting: Lasting = .untilChanged, left: String? = nil, reason: String? = nil,
                       resting: Bool = false) -> AppModel {
        let model = AppModel(live: false)
        let hard = choice == .full || choice == .cool
        model.fans = [
            FanNow(id: 0, name: "Left", speed: resting ? 0 : choice == .automatic ? 1776 : hard ? 3424 : 1499, range: FanRange(lowest: 1499, top: 5348)),
            FanNow(id: 1, name: "Right", speed: resting ? 0 : choice == .automatic ? 1868 : hard ? 3638 : 1499, range: FanRange(lowest: 1499, top: 5776)),
        ]
        model.resting = resting
        model.quietRest = true
        model.chip = resting ? 56 : 72
        model.graphics = 64
        model.battery = 36
        model.storage = 41
        model.palm = 31
        model.power = 42
        model.heatLevel = 90
        model.batteryNotice = true
        model.quietHours = false
        model.quietFrom = QuietHours.defaultFrom
        model.quietTo = QuietHours.defaultTo
        model.week = Week.sample(now: 1_795_000_000)
        model.smallGraph = .chip
        model.timedWord = false
        model.myPercent = 45
        model.followStart = 65
        model.followFull = 95
        model.quietPercent = 0
        model.coolPercent = 50
        model.choice = choice
        model.helper = helper
        model.note = note
        model.lasting = lasting
        model.leftWords = left
        model.reason = reason
        model.heatNotice = true
        model.quietInCalls = false
        model.batteryRule = true
        model.backAfterSleep = false
        let now = 1_795_000_000.0
        model.history = History.sample(now: now, minutes: 60)
        model.historyNow = now
        model.happened = [
            Happening(time: now - 3300, text: "Cool for 10 minutes"),
            Happening(time: now - 2700, text: "The time was up: the Mac has the fans again"),
            Happening(time: now - 1500, text: "A call began: Quiet"),
            Happening(time: now - 900, text: "Too hot (101°): the Mac has the fans again"),
            Happening(time: now - 300, text: "On battery: the Mac has the fans again"),
            Happening(time: now - 60, text: "Power is back: Cool again"),
        ]
        return model
    }
}
