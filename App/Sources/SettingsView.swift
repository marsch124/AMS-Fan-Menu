import FanMenuCore
import ServiceManagement
import SwiftUI

/// "Open at login" looks after itself: what you asked for is remembered, and put right at every start.
enum LoginItem {
    static let wantedKey = "wantsOpenAtLogin"

    /// Returns one line for the diary.
    static func checkAtStart() -> String {
        let store = UserDefaults.standard
        let status = SMAppService.mainApp.status
        // The first start with this check: what is set now is what you asked for.
        if store.object(forKey: wantedKey) == nil { store.set(status == .enabled, forKey: wantedKey) }
        guard store.bool(forKey: wantedKey) else { return "open at login: off" }
        switch status {
        case .enabled: return "open at login: on"
        case .requiresApproval: return "open at login: waits for your yes in System Settings, Login Items"
        default:
            try? SMAppService.mainApp.register()
            return SMAppService.mainApp.status == .enabled
                ? "open at login: the Mac had dropped it; switched on again"
                : "open at login: the Mac had dropped it and switching it on again did not work"
        }
    }

    static func set(_ wanted: Bool) {
        UserDefaults.standard.set(wanted, forKey: wantedKey)
        if wanted { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        // The keeper follows the switch: its start order is written or removed with it.
        if wanted { KeeperJob.writeFile() } else { KeeperJob.remove() }
    }
}

/// Settings in three tabs: the settings themselves, How it works, What's new.
/// The header and the bottom line (version, Quit, Done) stay on every tab.
struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case settings = "Settings", guide = "How it works", news = "What’s new"
        var id: String { rawValue }
    }

    @ObservedObject var model: AppModel
    var close: () -> Void = {}
    /// False only for pictures, where a scrolling area cannot be drawn.
    var scrolls = true
    /// The tab shown first.
    var startTab: Tab = .settings
    @State private var picked: Tab?
    @State private var openAtLogin = UserDefaults.standard.bool(forKey: LoginItem.wantedKey)
    @Environment(\.colorScheme) private var scheme

    private var tab: Tab { picked ?? startTab }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AppTile(size: 26)
                Text("AMS Fan Menu").font(.title3.weight(.semibold))
                Text(AppInfo.version).font(.callout).foregroundStyle(.secondary)
            }
            tabs

            Group {
                if scrolls {
                    ScrollView { page.padding(.trailing, 6) }
                } else {
                    page.frame(maxHeight: .infinity, alignment: .top).clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 8) {
                Text("Version \(AppInfo.version) (\(AppInfo.build))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settingsVersion")
                Spacer()
                bottomButton("Quit AMS Fan Menu", fill: nil, id: "quitButton") { NSApp.terminate(nil) }
                bottomButton("Done", fill: Palette.fanFill(scheme), id: "doneButton", action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 440, height: 560)
        .accessibilityIdentifier("settings")
    }

    /// Drawn by the app, so the main button keeps its full colour whatever window is in front.
    private func bottomButton(_ title: String, fill: Color?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.callout.weight(.medium))
                .foregroundStyle(fill == nil ? Palette.fan(scheme) : Color.white)
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(fill ?? Palette.pale(Palette.fan(scheme), scheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier(id)
    }

    /// Three drawn tab buttons: the one in use is full colour, in the colour of its page.
    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { one in
                let selected = one == tab
                Button { picked = one } label: {
                    Text(one.rawValue)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(selected ? fill(one) : Color.primary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("tab-\(one.id)")
            }
        }
    }

    private func fill(_ tab: Tab) -> Color {
        switch tab {
        case .settings: return Palette.macFill(scheme)
        case .guide: return Palette.fanFill(scheme)
        case .news: return Palette.heatFill(scheme)
        }
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .settings: settingsPage
        case .guide: guidePage
        case .news: newsPage
        }
    }

    // MARK: Settings

    private var helperWords: String {
        switch model.helper {
        case .ready: return "In place. AMS Fan Menu can set the fans."
        case .missing: return "Not in place yet. The app shows the fans and temperatures, but cannot set a speed until you allow it once."
        case .outdated: return "In place, but from an older version. It needs your OK once more."
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Open at login", isOn: $openAtLogin)
                    .tint(Palette.macFill(scheme))
                    .onChange(of: openAtLogin) { _, wanted in LoginItem.set(wanted) }
                    .accessibilityIdentifier("openAtLoginToggle")
                Text("While this is on, the app also comes back by itself if it ever stops unexpectedly. After a restart the Mac decides the fans until you pick a choice again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Fan control helper").font(.headline).foregroundStyle(Palette.fan(scheme))
                Text(helperWords)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("helperState")
                if model.helper == .ready {
                    bottomButton(model.working ? "Waiting for your OK…" : "Remove the helper…", fill: nil, id: "removeHelperButton") {
                        model.removeHelper()
                    }
                } else {
                    bottomButton(model.working ? "Waiting for your OK…" : model.helper == .missing ? "Allow fan control…" : "Update the helper…",
                                 fill: Palette.fanFill(scheme), id: "allowHelperButton") { model.allowFanControl() }
                }
                Text("The helper is the small part that is allowed to set the fan speed. It listens only to AMS Fan Menu and takes only speeds inside each fan’s own range. The Mac asks for your Mac password in its own dialog; the app never sees it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Safety").font(.headline).foregroundStyle(Palette.heat(scheme))
                Text("Quit, sleep and restart always hand the fans back to the Mac. So does a processor core at \(Int(HeatGuard.limit))° or more for \(Int(HeatGuard.patience)) seconds, except in Full.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("settingsPage")
    }

    // MARK: How it works, with the signs

    private var guidePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Guide.howItWorks) { section in
                // Short paragraphs, a little air between them: a blank line in the text starts a new one.
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.fan(scheme))
                    ForEach(Array(section.body.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Signs in this app").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.fan(scheme))
                ForEach(Guide.signs) { sign in
                    HStack(alignment: .center, spacing: 8) {
                        swatch(sign.kind).frame(width: 30, height: 18)
                        (Text(sign.name).fontWeight(.semibold) + Text(": " + sign.meaning))
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityIdentifier("signs")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("guidePage")
    }

    /// The sign itself, drawn as it looks in the app.
    @ViewBuilder private func swatch(_ kind: SignKind) -> some View {
        let box = RoundedRectangle(cornerRadius: 5, style: .continuous)
        switch kind {
        case .markBlack: GlyphView(glyph: .fan, size: 18).foregroundStyle(Color.primary)
        case .markBlue: GlyphView(glyph: .fan, size: 18).foregroundStyle(Palette.fan(scheme))
        case .buttonFull: box.fill(Palette.fanFill(scheme)).frame(width: 28, height: 14)
        case .buttonPale: box.fill(Palette.pale(Palette.fan(scheme), scheme)).frame(width: 28, height: 14)
        case .green: Circle().fill(Palette.macFill(scheme)).frame(width: 12, height: 12)
        case .blue: Circle().fill(Palette.fanFill(scheme)).frame(width: 12, height: 12)
        case .coral: Circle().fill(Palette.heatFill(scheme)).frame(width: 12, height: 12)
        case .amber: Circle().fill(Palette.warn(scheme)).frame(width: 12, height: 12)
        }
    }

    private var newsPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Guide.whatsNew) { release in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(release.version) · \(release.date)").font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.heat(scheme))
                    ForEach(release.items, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("–").foregroundStyle(.secondary)
                            Text(item).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("newsPage")
    }
}
