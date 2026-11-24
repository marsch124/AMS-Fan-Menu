import AppKit
import Combine
import FanMenuCore
import SwiftUI

/// The item in the menu bar — the fan mark, black while the Mac decides and blue while you do — and the
/// panel under it.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private var item: NSStatusItem!
    private var placeTimer: Timer?
    /// Since when the item has been out of sight (nil while it is seen).
    private var unseenSince: Date?
    private var repairing = false
    private let popover = NSPopover()
    private let model: AppModel
    private var bag = Set<AnyCancellable>()
    private var lastDrawn: FanChoice?
    /// The app that had the keyboard when the panel opened; it gets it back when the panel closes.
    private var previousApp: NSRunningApplication?
    private var outsideClicks: Any?

    static let autosaveName = "fanMenu"
    static let placeKey = "NSStatusItem Preferred Position \(autosaveName)"

    init(model: AppModel, openSettings: @escaping () -> Void, openGraph: @escaping () -> Void) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: PanelView(model: model, openSettings: { [weak self] in
            self?.popover.performClose(nil)
            openSettings()
        }, openGraph: { [weak self] in
            self?.popover.performClose(nil)
            openGraph()
        }))
        // The panel grows and shrinks with its note and stays under the menu bar.
        host.sizingOptions = [.preferredContentSize]
        // The panel opens without coming to the front, so its very first click must already count
        // (by default a first click only wakes a window up).
        if let viewClass = object_getClass(host.view) {
            let always: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
            class_replaceMethod(viewClass, #selector(NSView.acceptsFirstMouse(for:)), imp_implementationWithBlock(always), "B@:@")
        }
        popover.contentViewController = host
        // The very first start: a place in sight, not behind the notch where a new item would land.
        if UserDefaults.standard.object(forKey: Self.placeKey) == nil {
            UserDefaults.standard.set(BarPlace.home, forKey: Self.placeKey)
        }
        makeItem()
        let placeTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.keepInSight() }
        placeTimer.tolerance = 1
        RunLoop.main.add(placeTimer, forMode: .common)
        self.placeTimer = placeTimer
        // Every redraw of a menu bar item costs the Mac a little, so the mark is drawn only when the
        // choice changes from "the Mac decides" to "you decide" or back.
        model.$choice.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redraw(force: false) }
            .store(in: &bag)
        // Hovering over the mark says the figures; they are refreshed with every reading (words only, no redraw).
        model.$fans.map { _ in () }.merge(with: model.$chip.map { _ in () })
            .throttle(for: .seconds(4), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.redraw(force: false) }
            .store(in: &bag)
        redraw(force: true)
        // Lets a check from outside open the panel, so the real thing can be photographed.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(toggle),
                                                            name: Notification.Name("com.schabbauer.AMSFanMenu.togglePanel"), object: nil)
    }

    private func makeItem() {
        // The new item gets its name before the old one (after a repair) is let go:
        // letting go of an old item whose name is not in use any more makes the Mac forget the saved place.
        let fresh = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        fresh.autosaveName = Self.autosaveName
        item = fresh
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.setAccessibilityIdentifier("fanMenuStatusItem")
        }
    }

    /// The Mac can move the item's saved place to the far left of the bar, where it is out of sight
    /// (behind the notch or in AMS Tidy Bar's hidden part). After 10 seconds unseen it goes back.
    private func keepInSight() {
        guard !repairing else { return }
        guard !popover.isShown else { unseenSince = nil; return }
        let visible = item.button?.window?.occlusionState.contains(.visible) == true
        if visible { unseenSince = nil } else if unseenSince == nil { unseenSince = Date() }
        let saved = (UserDefaults.standard.object(forKey: Self.placeKey) as? NSNumber)?.doubleValue
        let unseen = unseenSince.map { Date().timeIntervalSince($0) } ?? 0
        guard BarPlace.needsRepair(saved: saved, visible: visible, unseenSeconds: unseen) else { return }
        Diary.note("The menu bar mark was out of sight (saved place \(Int(saved ?? 0))); putting it back")
        NSStatusBar.system.removeStatusItem(item)
        repairing = true
        unseenSince = nil
        // The Mac forgets a removed item's place a moment after removing it; write the place after that.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            // Let go of the old item first: that is when the Mac forgets its place.
            autoreleasepool { self.item = nil }
            UserDefaults.standard.set(BarPlace.home, forKey: Self.placeKey)
            self.makeItem()
            self.repairing = false
            self.redraw(force: true)
        }
    }

    /// Opens or closes the panel. The panel does not come to the front: the app you work in keeps the keyboard.
    @objc func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button, button.window != nil {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            model.panelOpen = popover.isShown
            guard popover.isShown, outsideClicks == nil else { return }
            // Not in front, the panel does not hear about clicks elsewhere by itself.
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.panelOpen = false
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        // A click in the panel brought this app to the front: hand the keyboard back, unless Settings is open.
        let ownWindowOpen = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        if NSApp.isActive, !ownWindowOpen { previousApp?.activate() }
        previousApp = nil
    }

    private func redraw(force: Bool) {
        guard let button = item?.button else { return }
        let choice = model.choice
        let words = Words.hover(choice, fans: model.fans.map { ($0.name, $0.speed) }, chip: model.chip)
        if button.toolTip != words { button.toolTip = words }
        button.setAccessibilityLabel(Words.hover(choice))
        guard force || lastDrawn?.appDecides != choice.appDecides else { return }
        lastDrawn = choice
        button.image = StatusItemController.image(appDecides: choice.appDecides)
    }

    /// The fan mark: black (white at night) while the Mac decides, blue while the app runs the fans.
    /// The colours settle when the Mac draws it, so one picture is right by day and by night.
    static func image(appDecides: Bool) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // A slightly heavier line than in the panel, so the small mark stays clear.
            Glyph.fan.draw(in: rect.insetBy(dx: 0.5, dy: 0.5), color: appDecides ? Palette.fanNS : Palette.inkNS,
                           context: context, stroke: 2.0)
            return true
        }
        image.isTemplate = false
        return image
    }
}
