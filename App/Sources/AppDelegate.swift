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
    private var stopSignal: DispatchSourceSignal?

    private static let chooseName = Notification.Name("com.schabbauer.AMSFanMenu.choose")

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
        // For checks: prints the fans and temperatures as the Mac reports them, then quits. Changes nothing.
        if arguments.contains("--read") {
            print(AppModel(live: true).readout())
            Diary.finish()
            NSApp.terminate(nil)
            return
        }
        // For checks: tells the running copy to switch to a choice ("--choose cool"), then quits.
        if let index = arguments.firstIndex(of: "--choose"), index + 1 < arguments.count {
            DistributedNotificationCenter.default().postNotificationName(Self.chooseName, object: arguments[index + 1],
                                                                         userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
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
        status = StatusItemController(model: model) { [weak self] in self?.openSettings() }

        let center = DistributedNotificationCenter.default()
        // Lets a check from outside open Settings, so the real window can be photographed.
        center.addObserver(self, selector: #selector(showSettings),
                           name: Notification.Name("com.schabbauer.AMSFanMenu.openSettings"), object: nil)
        center.addObserver(self, selector: #selector(chooseFromOutside(_:)), name: Self.chooseName, object: nil)
        UNUserNotificationCenter.current().delegate = self
    }

    @objc private func showSettings() { openSettings() }

    @objc private func chooseFromOutside(_ notification: Notification) {
        guard let word = notification.object as? String, let choice = FanChoice(rawValue: word) else { return }
        Diary.note("Asked from outside to switch to \(choice.title)")
        model?.choose(choice)
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
                ("panel-needs-ok", .sample(.automatic, note: needsOK, helper: .missing)),
                ("panel-too-hot", .sample(.automatic, note: tooHot)),
            ]
            for (name, model) in panels {
                save(PanelView(model: model).background(back).environment(\.colorScheme, scheme),
                     folder.appendingPathComponent("\(name)-\(tag).png"))
            }
            for (tab, name) in [(SettingsView.Tab.settings, "settings"), (.guide, "settings-guide"), (.news, "settings-news")] {
                save(SettingsView(model: .sample(.automatic), scrolls: false, startTab: tab).background(back).environment(\.colorScheme, scheme),
                     folder.appendingPathComponent("\(name)-\(tag).png"))
            }
            // The whole guide and the signs, however long, so every line can be read in a picture.
            save(SettingsView(model: .sample(.automatic), scrolls: false, startTab: .guide).frame(height: 2600).background(back)
                    .environment(\.colorScheme, scheme), folder.appendingPathComponent("settings-guide-whole-\(tag).png"))
            let dark = scheme == .dark
            for (name, decides) in [("mac-decides", false), ("you-decide", true)] {
                save(bar(StatusItemController.image(appDecides: decides), dark: dark), folder.appendingPathComponent("menubar-\(name)-\(tag).png"))
            }
        }
        // The tile on its own, large, to judge the drawing.
        save(Image(nsImage: TileArt.image(size: 256)), folder.appendingPathComponent("tile-256.png"))
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
