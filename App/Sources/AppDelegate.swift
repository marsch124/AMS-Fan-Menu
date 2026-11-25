import AppKit
import FanMenuCore
import ServiceManagement
import SwiftUI
import UserNotifications

@main
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var model: AppModel?
    private var status: StatusItemController?
    private var settingsWindow: NSWindow?
    private var graphWindow: NSWindow?
    private var stopSignal: DispatchSourceSignal?

    private static let chooseName = Notification.Name("com.schabbauer.AMSFanMenu.choose")
    private static let pretendWakeName = Notification.Name("com.schabbauer.AMSFanMenu.pretendWake")
    private static let pretendBatteryName = Notification.Name("com.schabbauer.AMSFanMenu.pretendBattery")
    private static let pretendCallName = Notification.Name("com.schabbauer.AMSFanMenu.pretendCall")
    private static let pretendChipName = Notification.Name("com.schabbauer.AMSFanMenu.pretendChip")
    private static let pretendClockName = Notification.Name("com.schabbauer.AMSFanMenu.pretendClock")
    private static let pretendBatteryTempName = Notification.Name("com.schabbauer.AMSFanMenu.pretendBatteryTemp")

    /// Tells the running copy something, then quits. A moment for the message to leave: quitting at once lost it.
    private func tellRunningCopy(_ name: Notification.Name, _ word: String?) {
        DistributedNotificationCenter.default().postNotificationName(name, object: word, userInfo: nil, deliverImmediately: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        // For checks: pictures of every screen with sample data, by day and by night.
        if let index = arguments.firstIndex(of: "--snapshots"), index + 1 < arguments.count {
            Snapshots.write(to: URL(fileURLWithPath: arguments[index + 1]))
            NSApp.terminate(nil)
            return
        }
        // For checks: pictures of the large graph with the readings really kept on this Mac. Changes nothing.
        if let index = arguments.firstIndex(of: "--graph-pictures"), index + 1 < arguments.count {
            Snapshots.writeRealGraphs(to: URL(fileURLWithPath: arguments[index + 1]))
            NSApp.terminate(nil)
            return
        }
        // For checks: prints the fans and temperatures as the Mac reports them, then quits. Changes nothing.
        if arguments.contains("--read") {
            print(AppModel(readOnly: true).readout())
            Diary.finish()
            NSApp.terminate(nil)
            return
        }
        // For checks and for rescue: asks the helper to give every fan back to the Mac, whatever the app
        // believes, then quits.
        if arguments.contains("--give-back") {
            print("fans given back:", HelperClient().giveBackAndWait(seconds: 5) ? "yes" : "no word from the helper")
            NSApp.terminate(nil)
            return
        }
        // For checks: asks the helper for these speeds ("--try-speeds 3000,3000") once a second for a few
        // seconds ("--seconds 6"), prints every answer, then gives the fans back and quits.
        if let index = arguments.firstIndex(of: "--try-speeds"), index + 1 < arguments.count {
            let speeds = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
            let rounds = arguments.firstIndex(of: "--seconds").flatMap { $0 + 1 < arguments.count ? Int(arguments[$0 + 1]) : nil } ?? 6
            let client = HelperClient()
            func round(_ number: Int) {
                guard number <= rounds else {
                    client.giveBack { fine, text in
                        print("give back:", fine, text)
                        NSApp.terminate(nil)
                    }
                    return
                }
                client.setSpeeds(speeds) { fine, text in
                    print("round \(number):", fine, text)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { round(number + 1) }
                }
            }
            round(1)
            return
        }
        // For checks: prints what would run with the Mac's deepest rights when you allow fan control.
        if arguments.contains("--helper-script") {
            print(HelperInstaller.installScript(tool: HelperInstaller.bundledTool, order: HelperInstaller.bundledOrder ?? "missing"))
            NSApp.terminate(nil)
            return
        }
        // For checks: tells the running copy to switch to a choice ("--choose cool"), then quits.
        if let index = arguments.firstIndex(of: "--choose"), index + 1 < arguments.count {
            tellRunningCopy(Self.chooseName, arguments[index + 1])
            return
        }
        // For checks: the running copy behaves as if the Mac slept and woke ("--pretend-wake"), as if the power
        // cable were pulled ("--pretend-battery on", "off", or "real" to look at the real thing again), or as if
        // a call were on ("--pretend-call on|off|real"), or as if the chip had a temperature, for Quiet's rest only
        // ("--pretend-chip 55", or "real").
        if arguments.contains("--pretend-wake") {
            tellRunningCopy(Self.pretendWakeName, nil)
            return
        }
        for (flag, name) in [("--pretend-battery", Self.pretendBatteryName), ("--pretend-call", Self.pretendCallName),
                             ("--pretend-chip", Self.pretendChipName),
                             // 0.5: "--pretend-clock 22:30|real" for quiet hours, "--pretend-battery-temp 37|real"
                             // for the battery heat notice.
                             ("--pretend-clock", Self.pretendClockName), ("--pretend-battery-temp", Self.pretendBatteryTempName)] {
            if let index = arguments.firstIndex(of: flag), index + 1 < arguments.count {
                tellRunningCopy(name, arguments[index + 1])
                return
            }
        }
        // Switches "Open at login" on or off from outside, then quits: "--open-at-login on". "status" only looks.
        if let index = arguments.firstIndex(of: "--open-at-login"), index + 1 < arguments.count {
            if arguments[index + 1] == "on" {
                try? SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: LoginItem.wantedKey)
                KeeperJob.writeFile()
            } else if arguments[index + 1] == "off" {
                try? SMAppService.mainApp.unregister()
                UserDefaults.standard.set(false, forKey: LoginItem.wantedKey)
                KeeperJob.remove()
            }
            print("open at login:", SMAppService.mainApp.status == .enabled ? "on" : "off",
                  "· asked for:", UserDefaults.standard.object(forKey: LoginItem.wantedKey) as? Bool ?? "never said",
                  "·", KeeperJob.stateLine())
            NSApp.terminate(nil)
            return
        }
        // Only one copy in the menu bar: the one that started first stays.
        if KeeperJob.mustQuitForEarlierCopy() {
            NSApp.terminate(nil)
            return
        }
        // "Open at login" is on: the app runs as the keeper's copy, so the Mac opens it again when it stops
        // unexpectedly. A copy opened by hand, or by the Mac's login list, gives way to that copy.
        var keeperNote = ""
        if Keeper.handsOver(wanted: KeeperJob.wanted, openedByKeeper: KeeperJob.openedByKeeper,
                            plain: KeeperJob.plain, inApplications: KeeperJob.inApplications) {
            if KeeperJob.handOver() {
                Diary.note("Opened by hand or by the Mac's login list; handed over to the keeper")
                Diary.finish()
                NSApp.terminate(nil)
                return
            }
            keeperNote = "; the keeper did not answer in 3 s, carrying on without it"
        } else if KeeperJob.openedByKeeper {
            KeeperJob.writeFile()
        }
        // A polite stop from outside (the Mac shutting down, an update) ends the app cleanly, like Quit,
        // so the fans go back to the Mac first.
        signal(SIGTERM, SIG_IGN)
        let stop = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        stop.setEventHandler { NSApp.terminate(nil) }
        stop.resume()
        stopSignal = stop

        let model = AppModel()
        self.model = model
        Diary.note("Started \(AppInfo.version) (\(AppInfo.build)), \(Int(ProcessInfo.processInfo.systemUptime)) s of Mac time since the Mac started; "
                   + (KeeperJob.openedByKeeper ? "opened by the keeper" : "opened by hand or by the Mac's login list") + keeperNote + "; "
                   + LoginItem.checkAtStart() + "; " + KeeperJob.stateLine() + "; "
                   + model.fans.map { "\($0.name) \(Words.turns($0.speed))" }.joined(separator: ", "))
        status = StatusItemController(model: model, openSettings: { [weak self] in self?.openSettings() },
                                      openGraph: { [weak self] in self?.openGraph() })

        let center = DistributedNotificationCenter.default()
        // Lets a check from outside open Settings, so the real window can be photographed.
        center.addObserver(self, selector: #selector(showSettings),
                           name: Notification.Name("com.schabbauer.AMSFanMenu.openSettings"), object: nil)
        center.addObserver(self, selector: #selector(chooseFromOutside(_:)), name: Self.chooseName, object: nil)
        center.addObserver(self, selector: #selector(showGraph),
                           name: Notification.Name("com.schabbauer.AMSFanMenu.openGraph"), object: nil)
        center.addObserver(self, selector: #selector(pretendWake), name: Self.pretendWakeName, object: nil)
        center.addObserver(self, selector: #selector(pretendBattery(_:)), name: Self.pretendBatteryName, object: nil)
        center.addObserver(self, selector: #selector(pretendCall(_:)), name: Self.pretendCallName, object: nil)
        center.addObserver(self, selector: #selector(pretendChip(_:)), name: Self.pretendChipName, object: nil)
        center.addObserver(self, selector: #selector(pretendClock(_:)), name: Self.pretendClockName, object: nil)
        center.addObserver(self, selector: #selector(pretendBatteryTemp(_:)), name: Self.pretendBatteryTempName, object: nil)
        let notes = UNUserNotificationCenter.current()
        notes.delegate = self
        // The heat notice carries a button.
        let cool = UNNotificationAction(identifier: AppModel.switchToCoolAction, title: "Switch to Cool")
        notes.setNotificationCategories([UNNotificationCategory(identifier: AppModel.heatCategory, actions: [cool], intentIdentifiers: [])])
        if model.heatNotice { model.askForNotes() }
    }

    @objc private func showSettings() { openSettings() }
    @objc private func showGraph() { openGraph() }
    @objc private func pretendWake() { model?.pretendSleepAndWake() }
    @objc private func pretendClock(_ notification: Notification) { model?.pretend(clock: notification.object as? String ?? "real") }
    @objc private func pretendBatteryTemp(_ notification: Notification) {
        model?.pretend(battery: (notification.object as? String).flatMap(Double.init))
    }
    @objc private func pretendBattery(_ notification: Notification) { model?.pretend(battery: notification.object as? String ?? "real") }
    @objc private func pretendCall(_ notification: Notification) { model?.pretend(call: notification.object as? String ?? "real") }
    @objc private func pretendChip(_ notification: Notification) { model?.pretend(chip: notification.object as? String ?? "real") }

    @objc private func chooseFromOutside(_ notification: Notification) {
        guard let word = notification.object as? String, let wish = OutsideAsk.parse(word) else { return }
        Diary.note("Asked from outside to switch to \(wish.choice.title)"
                   + (wish.seconds.map { " for \(OutsideAsk.words(seconds: $0))" } ?? ""))
        model?.choose(wish.choice, by: .outside, forSeconds: wish.seconds)
    }

    /// The large graph in its own window; it stays fresh while it is open.
    private func openGraph() {
        guard let model else { return }
        let content = NSHostingController(rootView: GraphWindow(model: model, close: { [weak self] in
            self?.graphWindow?.close()
        }))
        if let graphWindow {
            graphWindow.contentViewController = content
        } else {
            let window = NSWindow(contentViewController: content)
            window.title = "Graph"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            graphWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        graphWindow?.makeKeyAndOrderFront(nil)
        graphWindow?.orderFrontRegardless()
    }

    private func openSettings() {
        guard let model else { return }
        model.checkHelper()
        let content = NSHostingController(rootView: SettingsView(model: model, close: { [weak self] in
            self?.settingsWindow?.close()
        }))
        if let settingsWindow {
            settingsWindow.contentViewController = content
        } else {
            let window = NSWindow(contentViewController: content)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    /// Quitting hands the fans back to the Mac.
    func applicationWillTerminate(_ notification: Notification) {
        model?.quitting()
    }

    // Show the note even while the panel or Settings is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// The heat notice's button "Switch to Cool".
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            if action == AppModel.switchToCoolAction { self.model?.choose(.cool) }
        }
        completionHandler()
    }
}

/// The large graph, kept fresh while its window is open.
struct GraphWindow: View {
    @ObservedObject var model: AppModel
    var close: () -> Void = {}

    var body: some View {
        LargeGraph(history: model.history, now: model.historyNow, top: model.topSpeed, fullSeenAt: model.fullSeenAt,
                   heatNotice: model.heatNotice ? model.heatLevel : nil, close: close)
    }
}

/// Pictures of the panel and Settings with sample data, by day and by night, for checking the look.
enum Snapshots {
    @MainActor
    static func write(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let needsOK = AppModel.Note(kind: .needsOK, text: "Setting the fans needs your OK once. The Mac will ask for your Mac password.")
        let tooHot = AppModel.Note(kind: .told, text: "Too hot (101°). The Mac has the fans again.")
        for (scheme, tag) in [(ColorScheme.light, "day"), (ColorScheme.dark, "night")] {
            let back = scheme == .dark ? Color(white: 0.16) : Color(white: 0.96)
            let panels: [(String, AppModel)] = [
                ("panel-automatic", .sample(.automatic)),
                ("panel-cool", .sample(.cool)),
                ("panel-myspeed", .sample(.mySpeed)),
                ("panel-follow", .sample(.follow)),
                ("panel-timed", .sample(.cool, lasting: .tenMinutes, left: "8 min left")),
                ("panel-call", .sample(.quiet, reason: "during a call")),
                ("panel-resting", .sample(.quiet, resting: true)),
                ("panel-needs-ok", .sample(.automatic, note: needsOK, helper: .missing)),
                ("panel-too-hot", .sample(.automatic, note: tooHot)),
            ]
            for (name, model) in panels {
                save(PanelView(model: model).background(back).environment(\.colorScheme, scheme),
                     folder.appendingPathComponent("\(name)-\(tag).png"))
            }
            let sample = AppModel.sample(.automatic)
            save(LargeGraph(history: sample.history, now: sample.historyNow, top: sample.topSpeed).background(back)
                    .environment(\.colorScheme, scheme), folder.appendingPathComponent("graph-\(tag).png"))
            save(LargeGraph(history: sample.history, now: sample.historyNow, top: sample.topSpeed, fullSeenAt: 97).background(back)
                    .environment(\.colorScheme, scheme), folder.appendingPathComponent("graph-seen-\(tag).png"))
            save(LargeGraph(history: History(), now: sample.historyNow, top: sample.topSpeed, startSpan: .quarter).background(back)
                    .environment(\.colorScheme, scheme), folder.appendingPathComponent("graph-empty-\(tag).png"))
            // The whole Settings tab, however long, so every switch can be seen in a picture.
            save(SettingsView(model: .sample(.automatic), scrolls: false, startTab: .settings).frame(height: 900).background(back)
                    .environment(\.colorScheme, scheme), folder.appendingPathComponent("settings-whole-\(tag).png"))
            for (tab, name) in [(SettingsView.Tab.settings, "settings"), (.happened, "settings-happened"), (.guide, "settings-guide"), (.news, "settings-news")] {
                save(SettingsView(model: .sample(.automatic), scrolls: false, startTab: tab).background(back).environment(\.colorScheme, scheme),
                     folder.appendingPathComponent("\(name)-\(tag).png"))
            }
            // The whole guide and the signs, however long, so every line can be read in a picture.
            save(SettingsView(model: .sample(.automatic), scrolls: false, startTab: .guide).frame(height: 5600).background(back)
                    .environment(\.colorScheme, scheme), folder.appendingPathComponent("settings-guide-whole-\(tag).png"))
            let dark = scheme == .dark
            for (name, decides) in [("mac-decides", false), ("you-decide", true)] {
                save(bar(StatusItemController.image(appDecides: decides), dark: dark), folder.appendingPathComponent("menubar-\(name)-\(tag).png"))
            }
        }
        // The tile on its own, large, to judge the drawing.
        save(Image(nsImage: TileArt.image(size: 256)), folder.appendingPathComponent("tile-256.png"))
    }

    /// The large graph as it is on this Mac now: the kept readings, each time span, by day and by night.
    @MainActor
    static func writeRealGraphs(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let history = AppModel.keptHistory(), let last = history.samples.last else { return }
        let seen = AppModel.keptFullSeenAt()
        for (scheme, tag) in [(ColorScheme.light, "day"), (ColorScheme.dark, "night")] {
            let back = scheme == .dark ? Color(white: 0.16) : Color(white: 0.96)
            for span in GraphSpan.allCases {
                save(LargeGraph(history: history, now: last.time, top: 5776, fullSeenAt: seen, startSpan: span).background(back)
                        .environment(\.colorScheme, scheme), folder.appendingPathComponent("real-\(span.rawValue)-\(tag).png"))
            }
        }
    }

    /// The menu bar item on a piece of menu bar, drawn for day or for night.
    private static func bar(_ image: NSImage, dark: Bool) -> some View {
        Image(nsImage: settled(image, dark: dark)).padding(.horizontal, 10).padding(.vertical, 4)
            .background(dark ? Color(white: 0.2) : Color(white: 0.88))
    }

    /// The menu bar picture picks its colours when drawn; this draws it once, as day or as night.
    private static func settled(_ image: NSImage, dark: Bool) -> NSImage {
        let out = NSImage(size: image.size)
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 4),
                                             pixelsHigh: Int(image.size.height * 4), bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0) else { return }
            rep.size = image.size
            guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            out.addRepresentation(rep)
        }
        return out
    }

    @MainActor
    private static func save<V: View>(_ view: V, _ url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
