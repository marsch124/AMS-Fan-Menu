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
        case settings = "Settings", happened = "What happened", guide = "How it works", news = "What’s new"
        var id: String { rawValue }
    }

    @ObservedObject var model: AppModel
    var close: () -> Void = {}
    /// False only for pictures, where a scrolling area cannot be drawn.
    var scrolls = true
    /// The tab shown first.
    var startTab: Tab = .settings
    /// For checks: open with the page scrolled to its end.
    var atEnd = false
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
                    ScrollViewReader { proxy in
                        ScrollView {
                            page.padding(.trailing, 6)
                            Color.clear.frame(height: 1).id("pageEnd")
                        }
                        .onAppear {
                            guard atEnd else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo("pageEnd", anchor: .bottom) }
                        }
                    }
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
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
        case .happened: return Palette.storyFill(scheme)
        case .guide: return Palette.fanFill(scheme)
        case .news: return Palette.heatFill(scheme)
        }
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .settings: settingsPage
        case .happened: happenedPage
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Your speeds").font(.headline).foregroundStyle(Palette.fan(scheme))
                speedRow("Quiet", percent: model.quietPercent, range: Presets.quietRange, id: "quietSlider") { model.setQuietPercent($0) }
                speedRow("Cool", percent: model.coolPercent, range: Presets.coolRange, id: "coolSlider") { model.setCoolPercent($0) }
                Text("What the Quiet and Cool buttons mean. 0 % is each fan’s lowest speed, 100 % its top.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                switchRow("Quiet lets the fans stop", isOn: model.quietRest, id: "quietRestToggle", tint: Palette.fanFill(scheme),
                          words: "When the chip has been at \(Int(QuietRest.coolBelow))° or less for \(Int(QuietRest.coolFor)) seconds, Quiet gives the fans to the Mac, which stops them while it is cool. When the Mac runs them faster than your Quiet speed, the app takes them again and holds them there, for at least \(Int(QuietRest.holdAtLeast / 60)) minutes.") { model.setQuietRest($0) }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("By itself").font(.headline).foregroundStyle(Palette.mac(scheme))
                switchRow("Heat notice", isOn: model.heatNotice, id: "heatNoticeToggle",
                          words: "While the Mac decides: a notification when the chip has been at \(Int(model.heatLevel))° or more for \(Int(HeatNotice.patience / 60)) minutes, with the button “Switch to Cool”.") { model.setHeatNotice($0) }
                heatLevelRow
                switchRow("Battery heat notice", isOn: model.batteryNotice, id: "batteryNoticeToggle",
                          words: "A notification when the battery has been above 35° for 10 minutes. At most once an hour.") { model.setBatteryNotice($0) }
                switchRow("Quiet during calls", isOn: model.quietInCalls, id: "quietInCallsToggle",
                          words: "When an app has used the microphone for \(Int(CallQuiet.startAfter)) seconds, the app switches to Quiet; \(Int(CallQuiet.endAfter)) seconds after the microphone is free, your choice from before comes back. Any app that listens counts, not only calls.") { model.setQuietInCalls($0) }
                switchRow("On battery: the Mac decides", isOn: model.batteryRule, id: "batteryToggle",
                          words: "When the power cable is pulled, the fans go back to the Mac. With the cable back in, your choice comes back.") { model.setBatteryRule($0) }
                switchRow("Choice back after sleep", isOn: model.backAfterSleep, id: "backAfterSleepToggle",
                          words: "Sleep always hands the fans to the Mac. With this on, your choice comes back about 5 seconds after the Mac wakes. Restart and quit still hand the fans to the Mac.") { model.setBackAfterSleep($0) }
                switchRow("Quiet hours", isOn: model.quietHours, id: "quietHoursToggle",
                          words: "Between the two times Quiet comes on by itself. Afterwards your choice from before comes back. Your own tap during the hours wins until they are over.") { model.setQuietHours($0) }
                quietTimesRow
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

    /// "Quiet 0 %" with its slider: the figure right beside its name.
    private func speedRow(_ name: String, percent: Double, range: ClosedRange<Double>, id: String,
                          set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            (Text(name + " ").foregroundColor(.secondary) + Text("\(Int(percent)) %").fontWeight(.semibold))
                .font(.callout).monospacedDigit()
                .frame(width: 84, alignment: .leading)
            DragSlider(value: percent, range: range, step: Presets.step, tint: Palette.fanFill(scheme), id: id,
                       label: "\(name) speed in per cent", set: set)
        }
    }

    private func switchRow(_ title: String, isOn: Bool, id: String, tint: Color? = nil, words: String,
                           set: @escaping (Bool) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: Binding(get: { isOn }, set: set))
                .tint(tint ?? Palette.macFill(scheme))
                .accessibilityIdentifier(id)
            Text(words)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: What happened

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    /// "20:12" today, "23 Nov 20:12" on another day.
    private func when(_ time: Double) -> String {
        let date = Date(timeIntervalSince1970: time)
        let clock = Self.clock.string(from: date)
        return Calendar.current.isDateInToday(date) ? clock : Self.day.string(from: date) + " " + clock
    }

    /// "From 80° 85° 90° 95°": the level of the heat notice; the one in use is full colour.
    private var heatLevelRow: some View {
        HStack(spacing: 6) {
            Text("From").font(.callout).foregroundStyle(.secondary)
            ForEach(HeatNotice.levels, id: \.self) { level in
                let on = model.heatLevel == level
                Button { model.setHeatLevel(level) } label: {
                    Text("\(Int(level))°").font(.callout.weight(.medium)).monospacedDigit()
                        .foregroundStyle(on ? Color.white : Palette.heat(scheme))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(on ? Palette.heatFill(scheme) : Palette.pale(Palette.heat(scheme), scheme),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Heat notice from \(Int(level)) degrees")
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("heatLevel-\(Int(level))")
            }
            Spacer(minLength: 0)
        }
        .disabled(!model.heatNotice)
        .opacity(model.heatNotice ? 1 : 0.4)
    }

    /// "From 22:00 · To 07:00": two small time pickers, 24-hour.
    private var quietTimesRow: some View {
        HStack(spacing: 8) {
            Text("From").font(.callout).foregroundStyle(.secondary)
            timePicker(minutes: model.quietFrom, id: "quietFromPicker", label: "Quiet hours from") { model.setQuietTimes(from: $0) }
            Text("To").font(.callout).foregroundStyle(.secondary).padding(.leading, 6)
            timePicker(minutes: model.quietTo, id: "quietToPicker", label: "Quiet hours to") { model.setQuietTimes(to: $0) }
            Spacer(minLength: 0)
        }
        .disabled(!model.quietHours)
        .opacity(model.quietHours ? 1 : 0.4)
    }

    private func timePicker(minutes: Int, id: String, label: String, set: @escaping (Int) -> Void) -> some View {
        let calendar = Calendar.current
        let binding = Binding<Date>(
            get: { calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                set((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            })
        return DatePicker(label, selection: binding, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.stepperField)
            .environment(\.locale, Locale(identifier: "en_GB"))
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
    }

    /// "25 Nov" style helpers live in Core; here only the block itself.
    private var weekBlock: some View {
        // Pictures hold no clock of their own: they count from the last day of the sample.
        let now = scrolls ? Date().timeIntervalSince1970 : (model.week.days.last.map { $0.start + 43_200 } ?? Date().timeIntervalSince1970)
        let summary = model.week.summary(now: now)
        return VStack(alignment: .leading, spacing: 2) {
            Text("The last 7 days").font(.headline).foregroundStyle(Palette.story(scheme))
            if summary.isEmpty {
                Text("Figures appear here as the days pass.").font(.caption).foregroundStyle(.secondary)
            } else {
                weekRow("Hottest", Words.hottestMoment(summary.hottest, at: summary.hottestTime))
                weekRow("At 90° or more", Words.duration(summary.secondsHot))
                weekRow("Fans turning", Words.duration(summary.secondsFans))
                weekRow("A choice of yours on", Words.duration(summary.secondsApp))
                if let since = Words.countedSince(summary.since, days: summary.days) {
                    Text(since).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("weekBlock")
    }

    private func weekRow(_ name: String, _ figure: String) -> some View {
        (Text(name + " ").foregroundColor(.secondary) + Text(figure).fontWeight(.semibold))
            .font(.callout).monospacedDigit()
    }

    private var happenedPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            weekBlock.padding(.bottom, 6)
            Text("What happened").font(.headline).foregroundStyle(Palette.story(scheme))
            Text("The last \(HappenedLog.shown) things the app did, newest first.")
                .font(.caption)
                .foregroundStyle(.secondary)
            let lines = HappenedLog.forShow(model.happened)
            if lines.isEmpty {
                Text("Nothing yet. Pick a choice in the panel and it shows up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(when(line.time)).font(.callout).monospacedDigit().foregroundStyle(Palette.story(scheme))
                        .frame(width: 92, alignment: .leading)
                    Text(line.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("happenedPage")
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
        case .dashedLine:
            Path { path in
                path.move(to: CGPoint(x: 15, y: 1))
                path.addLine(to: CGPoint(x: 15, y: 17))
            }
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
        case .redLine:
            Path { path in
                path.move(to: CGPoint(x: 2, y: 9))
                path.addLine(to: CGPoint(x: 28, y: 9))
            }
            .stroke(Palette.danger(scheme), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 30, height: 18)
        case .dottedLine:
            Path { path in
                path.move(to: CGPoint(x: 2, y: 9))
                path.addLine(to: CGPoint(x: 28, y: 9))
            }
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [1.5, 3]))
            .frame(width: 30, height: 18)
        case .greyBand:
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.primary.opacity(0.10)).frame(width: 28, height: 14)
        case .teal: Circle().fill(Palette.power(scheme)).frame(width: 12, height: 12)
        case .paleBlueStretch:
            Rectangle().fill(Palette.pale(Palette.fan(scheme), scheme)).frame(width: 28, height: 16)
        case .pointerLine:
            Path { p in p.move(to: CGPoint(x: 15, y: 0)); p.addLine(to: CGPoint(x: 15, y: 18)) }
                .stroke(Color.primary.opacity(0.45), lineWidth: 1)
                .frame(width: 30, height: 18)
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
