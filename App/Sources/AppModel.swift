import AppKit
import Combine
import FanMenuCore
import UserNotifications

/// One fan as the panel shows it.
struct FanNow: Identifiable, Equatable {
    let id: Int
    let name: String
    var speed: Double?
    var range: FanRange
}

/// What the app knows and does: the readings, the choice in use, and the line to the helper.
final class AppModel: ObservableObject {
    /// The amber note at the top of the panel.
    struct Note: Equatable {
        enum Kind { case needsOK, needsUpdate, told }
        let kind: Kind
        let text: String
    }

    @Published private(set) var choice: FanChoice = .automatic
    @Published private(set) var fans: [FanNow] = []
    @Published private(set) var chip: Double?
    @Published private(set) var graphics: Double?
    @Published private(set) var battery: Double?
    @Published private(set) var myPercent: Double
    @Published private(set) var followStart: Double
    @Published private(set) var followFull: Double
    @Published private(set) var helper: HelperState = .missing
    @Published private(set) var note: Note?
    /// The Mac's password dialog is open.
    @Published private(set) var working = false

    /// Only an open panel needs fresh readings every second.
    var panelOpen = false {
        didSet {
            guard panelOpen != oldValue else { return }
            if panelOpen { read() }
            retime()
        }
    }

    /// False for pictures with sample data: nothing is read, nothing is set.
    private let live: Bool
    private let smc: SMC?
    private let client = HelperClient()
    private var timer: Timer?
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

    private static let percentKey = "mySpeedPercent", startKey = "followStart", fullKey = "followFull"
    static let notificationCategory = "fans"

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    init(live: Bool = true) {
        self.live = live
        let store = UserDefaults.standard
        myPercent = min(max(store.object(forKey: Self.percentKey) as? Double ?? 45, 0), 100)
        let pair = Follow.settled(start: store.object(forKey: Self.startKey) as? Double ?? Follow.defaultStart,
                                  full: store.object(forKey: Self.fullKey) as? Double ?? Follow.defaultFull, movedStart: true)
        followStart = pair.start
        followFull = pair.full
        smc = live ? SMC() : nil
        guard live else { return }
        read()
        checkHelper()
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
        let graphicsNow = Reading.average(SensorKeys.graphics.compactMap { smc.number($0) })
        let batteryNow = Reading.average(SensorKeys.battery.compactMap { smc.number($0) })
        // Whole degrees are what the panel shows; anything finer would only redraw it for nothing.
        if chipNow?.rounded() != chip?.rounded() { chip = chipNow }
        if graphicsNow?.rounded() != graphics?.rounded() { graphics = graphicsNow }
        if batteryNow?.rounded() != battery?.rounded() { battery = batteryNow }
    }

    /// The readings in a few lines, for a check from outside.
    func readout() -> String {
        var lines = fans.map { "\($0.name): \(Words.turns($0.speed)) (lowest \(Words.turns($0.range.lowest)), top \(Words.turns($0.range.top)))" }
        lines.append("Chip \(Words.degrees(chip)) · hottest core \(Words.degrees(hottest)) · Graphics \(Words.degrees(graphics)) · Battery \(Words.degrees(battery))")
        lines.append("Helper in place: \(HelperInstaller.installed ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }

    /// Once a second while the panel is open or the app runs the fans; not at all otherwise.
    private func retime() {
        let needed = live && (panelOpen || choice.appDecides)
        if needed, timer == nil {
            let new = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            new.tolerance = 0.2
            RunLoop.main.add(new, forMode: .common)
            timer = new
        } else if !needed {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        read()
        guard choice.appDecides else { return }
        hotSince = HeatGuard.hotSince(hottest: hottest, now: now, since: hotSince)
        if HeatGuard.handsBack(choice: choice, hotSince: hotSince, now: now) {
            let text = "Too hot (\(Words.degrees(hottest))). The Mac has the fans again."
            handBack(telling: text, why: "too hot while \(choice.title) was on")
            notify(text)
            return
        }
        // The Mac takes the fans back when it hears nothing, so the choice is repeated; Follow also moves with the heat.
        if now - lastSend >= DeadMan.repeatEvery { send() }
    }

    // MARK: Choosing

    /// The speeds the choice in use asks for, one per fan.
    private func wantedSpeeds() -> [Double]? {
        guard let share = FanPlan.share(choice: choice, myPercent: myPercent, chip: Follow.smoothed(chipReadings),
                                        start: followStart, full: followFull), !fans.isEmpty else { return nil }
        let fresh = fans.map { $0.range.speed(share: share) }
        // Follow does not chase every degree: a new speed only when it is worth it.
        if choice == .follow, let sent, sent.count == fresh.count,
           !Follow.worthSending(new: fresh[0], last: sent[0], atAnEnd: share <= 0 || share >= 1) {
            return sent
        }
        return fresh
    }

    func choose(_ new: FanChoice) {
        guard live else { choice = new; return }
        if new == .automatic {
            handBack(telling: nil, why: "Automatic chosen")
            return
        }
        guard helper == .ready else {
            waiting = new
            showHelperNote()
            // The state may be old (the helper was put in place by another copy): look again.
            checkHelper()
            return
        }
        let before = choice
        choice = new
        waiting = nil
        hotSince = nil
        sent = nil
        if note?.kind == .told { note = nil }
        if before != new { Diary.note("Choice: \(new.title)") }
        send()
        retime()
        askForNotes()
    }

    private func send() {
        guard choice.appDecides, let speeds = wantedSpeeds() else { return }
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
            } else if first, !text.isEmpty {
                Diary.note("The helper: \(text)")
            }
        }
    }

    private func failed(_ why: String) {
        Diary.note("The fans did not take the speed: \(why)")
        handBack(telling: "The fans did not take the speed, so the Mac has them again. (\(why))", why: "the helper said no")
        checkHelper()
    }

    /// The Mac decides again. `telling`: an amber note that says why, when it was not your own tap.
    private func handBack(telling: String?, why: String) {
        let was = choice
        sendSoon?.cancel()
        choice = .automatic
        waiting = nil
        sent = nil
        hotSince = nil
        if was.appDecides {
            client.giveBack { fine, text in
                if !fine { Diary.note("Giving the fans back: \(text)") }
            }
            Diary.note("Automatic (\(why)); before: \(was.title)")
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
        guard live, choice.appDecides else { return }
        let fine = client.giveBackAndWait()
        Diary.note("Quit while \(choice.title) was on; fans given back: \(fine ? "yes" : "no word from the helper, it gives them back by itself within \(Int(DeadMan.seconds)) s")")
        Diary.finish()
    }

    func setMyPercent(_ value: Double) {
        let whole = min(max(value.rounded(), 0), 100)
        guard whole != myPercent || choice != .mySpeed else { return }
        myPercent = whole
        UserDefaults.standard.set(whole, forKey: Self.percentKey)
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
        UserDefaults.standard.set(pair.start, forKey: Self.startKey)
        UserDefaults.standard.set(pair.full, forKey: Self.fullKey)
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
        if choice.appDecides { handBack(telling: nil, why: "the helper is being removed") }
        working = true
        HelperInstaller.remove { [weak self] outcome in
            guard let self else { return }
            self.working = false
            self.client.reset()
            Diary.note("Removing the helper: \(outcome == .done ? "done" : outcome == .cancelled ? "cancelled" : "failed")")
            self.checkHelper()
        }
    }

    // MARK: Sleep, notes

    @objc private func willSleep() {
        guard choice.appDecides else { return }
        handBack(telling: "The Mac went to sleep, so it has the fans again.", why: "the Mac went to sleep")
    }

    @objc private func didWake() {
        Diary.note("Woke from sleep; the Mac decides")
        read()
        checkHelper()
    }

    /// The amber note's "OK".
    func dismissNote() {
        waiting = nil
        note = nil
    }

    /// Asked the first time a choice is switched on, because only then can there be anything to tell.
    private func askForNotes() {
        guard !askedForNotes else { return }
        askedForNotes = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ text: String) {
        let content = UNMutableNotificationContent()
        content.title = "AMS Fan Menu"
        content.body = text
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "fans-\(UUID().uuidString)", content: content, trigger: nil))
    }

    // MARK: Sample data for pictures

    static func sample(_ choice: FanChoice = .automatic, note: Note? = nil, helper: HelperState = .ready) -> AppModel {
        let model = AppModel(live: false)
        let hard = choice == .full || choice == .cool
        model.fans = [
            FanNow(id: 0, name: "Left", speed: choice == .automatic ? 1776 : hard ? 3424 : 1499, range: FanRange(lowest: 1499, top: 5348)),
            FanNow(id: 1, name: "Right", speed: choice == .automatic ? 1868 : hard ? 3638 : 1499, range: FanRange(lowest: 1499, top: 5776)),
        ]
        model.chip = 72
        model.graphics = 64
        model.battery = 36
        model.myPercent = 45
        model.followStart = 65
        model.followFull = 95
        model.choice = choice
        model.helper = helper
        model.note = note
        return model
    }
}
