import FanMenuCore
import SwiftUI

/// The panel under the menu bar mark: the readings, then the six choices.
struct PanelView: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void = {}
    var openGraph: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let note = model.note { noteCard(note) }
            readings
            choices
            lastingLine
            mySpeed
            follow
            graph
        }
        .padding(12)
        .frame(width: 300)
        // No keyboard ring around the first button: the panel is used with the pointer.
        .focusEffectDisabled()
        .accessibilityIdentifier("panel")
    }

    private var header: some View {
        HStack(spacing: 7) {
            AppTile(size: 22)
            Text("AMS Fan Menu").font(.headline)
            Text(AppInfo.version).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("panelVersion")
            Spacer()
            Button(action: openSettings) {
                GlyphView(glyph: .gear, size: 19).foregroundStyle(.secondary).frame(width: 26, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
        }
    }

    // MARK: The amber note

    private func noteCard(_ note: AppModel.Note) -> some View {
        let amber = Palette.warn(scheme)
        return VStack(alignment: .leading, spacing: 6) {
            Text(note.text).font(.callout).foregroundStyle(amber).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("noteText")
            switch note.kind {
            case .needsOK, .needsUpdate:
                HStack(spacing: 6) {
                    wordButton(model.working ? "Waiting for your OK…" : note.kind == .needsOK ? "Allow fan control…" : "Update the helper…",
                               fill: Palette.fanFill(scheme), id: "allowButton") { model.allowFanControl() }
                    wordButton("Not now", fill: nil, id: "notNowButton") { model.dismissNote() }
                }
            case .told:
                wordButton("OK", fill: Palette.fanFill(scheme), id: "noteOKButton") { model.dismissNote() }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.pale(amber, scheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityIdentifier("note")
    }

    /// A small button with a word on it: full colour for the main one, pale for the other.
    private func wordButton(_ title: String, fill: Color?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.callout.weight(.medium))
                .foregroundStyle(fill == nil ? Palette.fan(scheme) : Color.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(fill ?? Palette.pale(Palette.fan(scheme), scheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier(id)
    }

    // MARK: Readings

    /// "Left 1,776 · Right 1,868": each figure right beside its name.
    private func line(_ parts: [(String, String)]) -> Text {
        var text = Text("")
        for (index, part) in parts.enumerated() {
            if index > 0 { text = text + Text("  ·  ").foregroundColor(.secondary) }
            text = text + Text(part.0 + " ").foregroundColor(.secondary) + Text(part.1).fontWeight(.semibold)
        }
        return text
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Fans").font(.caption.weight(.semibold)).foregroundStyle(Palette.fan(scheme))
                line(model.fans.isEmpty ? [("Fans", "–")] : model.fans.map { ($0.name, Words.turns($0.speed)) })
                    .font(.callout).monospacedDigit().accessibilityIdentifier("fanSpeeds")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Temperature").font(.caption.weight(.semibold)).foregroundStyle(Palette.heat(scheme))
                line([("Chip", Words.degrees(model.chip)), ("Graphics", Words.degrees(model.graphics)), ("Battery", Words.degrees(model.battery))])
                    .font(.callout).monospacedDigit().accessibilityIdentifier("temperatures")
            }
            Text(Words.status(model.choice, left: model.leftWords, reason: model.reason))
                .font(.callout.weight(.semibold))
                .foregroundStyle(model.choice.appDecides ? Palette.fan(scheme) : Palette.mac(scheme))
                .accessibilityIdentifier("statusLine")
        }
    }

    // MARK: Choices

    private func tint(_ choice: FanChoice) -> (words: Color, fill: Color) {
        switch choice {
        case .automatic: return (Palette.mac(scheme), Palette.macFill(scheme))
        case .follow: return (Palette.heat(scheme), Palette.heatFill(scheme))
        default: return (Palette.fan(scheme), Palette.fanFill(scheme))
        }
    }

    /// The choice in use is full colour with white words; the others are pale.
    private func choiceButton(_ choice: FanChoice, title: String? = nil) -> some View {
        let on = model.choice == choice
        let colours = tint(choice)
        return Button { model.choose(choice) } label: {
            VStack(spacing: 0) {
                Text(title ?? choice.title).font(.callout.weight(.semibold)).monospacedDigit()
                Text(hint(choice)).font(.caption2).opacity(on ? 0.92 : 0.85)
            }
            .foregroundStyle(on ? Color.white : colours.words)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(on ? colours.fill : Palette.pale(colours.words, scheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(title ?? choice.title), \(hint(choice))")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("choice-\(choice.rawValue)")
    }

    /// The few words under a button; Quiet and Cool say your own figure once you changed it in Settings.
    private func hint(_ choice: FanChoice) -> String {
        Presets.hint(choice, quiet: model.quietPercent, cool: model.coolPercent)
    }

    /// "For 10 min · 30 min · 1 hour · Until I change": how long a choice stays on before the Mac gets the
    /// fans back. The time in use is full colour.
    private var lastingLine: some View {
        HStack(spacing: 5) {
            Text("For").font(.caption).foregroundStyle(.secondary)
            ForEach(Lasting.allCases, id: \.self) { one in
                let on = model.lasting == one
                Button { model.setLasting(one) } label: {
                    Text(one.title).font(.caption.weight(.medium)).lineLimit(1).fixedSize()
                        .foregroundStyle(on ? Color.white : Palette.fan(scheme))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(on ? Palette.fanFill(scheme) : Palette.pale(Palette.fan(scheme), scheme),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("A choice stays on for: \(one.title)")
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("lasting-\(one.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("lastingLine")
    }

    /// The small graph of the last 15 minutes; a tap opens the large one.
    private var graph: some View {
        Button(action: openGraph) {
            SmallGraph(history: model.history, now: model.historyNow, top: model.topSpeed)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Graph of temperature and fan speed, last 15 minutes. Opens the large graph.")
        .accessibilityIdentifier("graphButton")
    }

    private var choices: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) { choiceButton(.automatic); choiceButton(.quiet) }
            HStack(spacing: 6) { choiceButton(.cool); choiceButton(.full) }
        }
    }

    private var mySpeed: some View {
        VStack(spacing: 5) {
            choiceButton(.mySpeed, title: "My speed \(Int(model.myPercent)) %")
            DragSlider(value: model.myPercent, range: 0...100, step: 1, tint: Palette.fanFill(scheme), id: "mySpeedSlider",
                       label: "My speed in per cent") { model.setMyPercent($0) }
        }
    }

    private var follow: some View {
        VStack(spacing: 5) {
            choiceButton(.follow)
            followRow("Start", value: model.followStart, range: Follow.startRange, id: "followStartSlider") { model.setFollow(start: $0) }
            followRow("Full", value: model.followFull, range: Follow.fullRange, id: "followFullSlider") { model.setFollow(full: $0) }
        }
    }

    private func followRow(_ name: String, value: Double, range: ClosedRange<Double>, id: String,
                           set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            (Text(name + " ").foregroundColor(.secondary) + Text(Words.degrees(value)).fontWeight(.semibold))
                .font(.callout).monospacedDigit()
                .frame(width: 70, alignment: .leading)
            DragSlider(value: value, range: range, step: Follow.step, tint: Palette.heatFill(scheme), id: id,
                       label: "\(name) temperature", set: set)
        }
    }
}

/// A slider drawn by the app: it keeps its colour while the panel is not the window in front
/// (the Mac's own slider goes grey there).
struct DragSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color
    let id: String
    let label: String
    let set: (Double) -> Void
    @Environment(\.colorScheme) private var scheme

    private let knob: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let run = max(geometry.size.width - knob, 1)
            let share = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(scheme == .dark ? 0.32 : 0.22)).frame(height: 4).padding(.horizontal, knob / 2)
                Capsule().fill(tint).frame(width: run * share + knob / 2, height: 4).padding(.leading, knob / 2 - 2)
                Circle().fill(tint).frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
                    .offset(x: run * share)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let part = min(max((drag.location.x - knob / 2) / run, 0), 1)
                let raw = range.lowerBound + part * (range.upperBound - range.lowerBound)
                set(min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound))
            })
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(min(value + step, range.upperBound))
            case .decrement: set(max(value - step, range.lowerBound))
            @unknown default: break
            }
        }
        .accessibilityIdentifier(id)
    }
}
