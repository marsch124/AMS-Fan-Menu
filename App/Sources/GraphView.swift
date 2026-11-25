import FanMenuCore
import SwiftUI

// The graphs: how the temperatures (coral) reacted to the fan speed (blue) after the choice changed, and
// where each temperature stands against the levels that mean something.

/// One line in a plot: its colour and where its value sits in a reading.
private struct PlotLine {
    let color: Color
    let value: (Sample) -> Double?
}

/// Breaks the readings into pieces of screen points: a gap in time or a missing value starts a new piece.
private func pieces(_ samples: [Sample], now: Double, span: Double, scale: ClosedRange<Double>,
                    size: CGSize, inset: CGFloat, value: (Sample) -> Double?) -> [[CGPoint]] {
    let thin = Plot.thinned(samples, limit: 180)
    let factor = thin.isEmpty ? 1 : Double(samples.count) / Double(thin.count)
    var result: [[CGPoint]] = []
    var current: [CGPoint] = []
    var previous: Sample?
    for sample in thin {
        guard let v = value(sample) else {
            if !current.isEmpty { result.append(current); current = [] }
            previous = nil
            continue
        }
        if let previous, Plot.isGap(previous, sample, thinnedBy: factor), !current.isEmpty {
            result.append(current); current = []
        }
        let x = inset + CGFloat(Plot.x(time: sample.time, now: now, span: span)) * (size.width - 2 * inset)
        let y = size.height - inset - CGFloat(Plot.y(v, in: scale)) * (size.height - 2 * inset)
        current.append(CGPoint(x: x, y: y))
        previous = sample
    }
    if !current.isEmpty { result.append(current) }
    return result
}

/// The one path builder for all plots: a line through each piece (a lone point becomes a dot).
private func linePath(_ pieces: [[CGPoint]]) -> Path {
    var path = Path()
    for piece in pieces {
        guard let first = piece.first else { continue }
        path.move(to: first)
        if piece.count == 1 { path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y)) }
        for point in piece.dropFirst() { path.addLine(to: point) }
    }
    return path
}

/// The drawing inside a plot box: faint grid, dashed marks, the lines, and optionally the mark titles.
private struct PlotDrawing: View {
    let samples: [Sample]
    let marks: [ChoiceMark]
    let lines: [PlotLine]
    let scale: ClosedRange<Double>
    let now: Double
    let span: Double
    var grid = false
    var titles = false
    /// Flat lines at temperatures that mean something, each with its words at the right end.
    var levels: [Level] = []
    /// The usual range on this Mac: a soft grey band.
    var usual: ClosedRange<Double>?
    /// Pale stretches behind everything: the time a choice other than Automatic was on.
    var stretches: [Stretch] = []
    /// 0.6: pale teal stretches behind the line: the time the battery was charging (Battery graph only).
    var charging: [Stretch] = []
    /// 0.6: the stretches without readings whose reason is known; each gets its word in the middle of the gap.
    var pauses: [Pause] = []
    /// Where the pointer is (seconds since 1970) and the reading nearest to it, if there is one near enough.
    var point: Double?
    var pointSample: Sample?
    let inset: CGFloat = 4
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let xs = marks.map { inset + CGFloat(Plot.x(time: $0.time, now: now, span: span)) * (size.width - 2 * inset) }
            let shown = levels.filter { scale.contains($0.degrees) }.sorted { $0.degrees > $1.degrees }
            ZStack(alignment: .topLeading) {
                ForEach(stretches.indices, id: \.self) { i in
                    let left = inset + CGFloat(Plot.x(time: stretches[i].from, now: now, span: span)) * (size.width - 2 * inset)
                    let right = inset + CGFloat(Plot.x(time: stretches[i].to, now: now, span: span)) * (size.width - 2 * inset)
                    Rectangle().fill(Palette.pale(Palette.fan(scheme), scheme))
                        .frame(width: max(right - left, 1), height: size.height).offset(x: left)
                }
                ForEach(charging.indices, id: \.self) { i in
                    let left = inset + CGFloat(Plot.x(time: charging[i].from, now: now, span: span)) * (size.width - 2 * inset)
                    let right = inset + CGFloat(Plot.x(time: charging[i].to, now: now, span: span)) * (size.width - 2 * inset)
                    Rectangle().fill(Palette.pale(Palette.power(scheme), scheme))
                        .frame(width: max(right - left, 1), height: size.height).offset(x: left)
                }
                if let usual, usual.upperBound > scale.lowerBound, usual.lowerBound < scale.upperBound {
                    let top = height(usual.upperBound, size), bottom = height(usual.lowerBound, size)
                    Rectangle().fill(Color.primary.opacity(0.08))
                        .frame(width: size.width, height: max(bottom - top, 2)).offset(y: top)
                }
                if grid {
                    Path { p in
                        for f in [0.0, 0.5, 1.0] {
                            let y = size.height - inset - CGFloat(f) * (size.height - 2 * inset)
                            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                        }
                    }.stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                }
                ForEach(shown.indices, id: \.self) { i in
                    Path { p in
                        let y = height(shown[i].degrees, size)
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                    }.stroke(levelColor(shown[i].kind, scheme).opacity(0.85),
                             style: shown[i].kind == .report ? StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1.5, 3]) : StrokeStyle(lineWidth: 1))
                }
                Path { p in
                    for x in xs { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }
                }.stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(lines.indices, id: \.self) { i in
                    linePath(pieces(samples, now: now, span: span, scale: scale, size: size, inset: inset, value: lines[i].value))
                        .stroke(lines[i].color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                if let point {
                    let moment = pointSample?.time ?? point
                    let x = inset + CGFloat(Plot.x(time: moment, now: now, span: span)) * (size.width - 2 * inset)
                    Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }
                        .stroke(Color.primary.opacity(0.45), lineWidth: 1)
                    if let pointSample {
                        ForEach(lines.indices, id: \.self) { i in
                            if let v = lines[i].value(pointSample) {
                                let y = size.height - inset - CGFloat(Plot.y(v, in: scale)) * (size.height - 2 * inset)
                                Circle().fill(Color.primary.opacity(0.45)).frame(width: 5, height: 5)
                                    .position(x: x, y: y)
                            }
                        }
                    }
                }
                // 0.6: a gap says why: the word in the middle of it, when the gap is wide enough to hold it.
                ForEach(pauses.indices, id: \.self) { i in
                    if let shares = Plot.pauseShares(pauses[i], now: now, span: span) {
                        let left = inset + CGFloat(shares.lowerBound) * (size.width - 2 * inset)
                        let wide = CGFloat(shares.upperBound - shares.lowerBound) * (size.width - 2 * inset)
                        if wide >= 56 {
                            Text(pauses[i].why).font(.caption2).foregroundStyle(Color.secondary).fixedSize()
                                .frame(width: wide).offset(x: left, y: size.height * 0.62)
                        }
                    }
                }
                if titles {
                    ForEach(Array(visibleTitles(xs).enumerated()), id: \.offset) { _, item in
                        Text(item.title).font(.caption2).foregroundStyle(.secondary).fixedSize()
                            .offset(x: item.x + 3, y: 1)
                    }
                }
                // True figures have their words at the right end, rough ones from reports at the left end.
                ForEach(Array(levelWords(shown.filter { $0.kind != .report }, size).enumerated()), id: \.offset) { _, item in
                    words(item.level)
                        .frame(width: max(size.width - 2 - item.inFromEdge, 0), alignment: .trailing)
                        .offset(y: item.y)
                }
                ForEach(Array(levelWords(shown.filter { $0.kind == .report }, size).enumerated()), id: \.offset) { _, item in
                    words(item.level).offset(x: 2 + item.inFromEdge, y: item.y)
                }
            }
        }
    }

    private func words(_ level: Level) -> some View {
        Text(level.words).font(.caption2.weight(.medium)).foregroundStyle(levelColor(level.kind, scheme))
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .windowBackgroundColor).opacity(0.7)))
            .fixedSize()
    }

    /// Where a temperature sits, in points from the top of the drawing.
    private func height(_ degrees: Double, _ size: CGSize) -> CGFloat {
        size.height - inset - CGFloat(Plot.y(degrees, in: scale)) * (size.height - 2 * inset)
    }

    /// The words of each level line at one end of the graph: above the line when there is room. A line closer
    /// than a line of words to the one above has its words below it, and if those are taken too, further in
    /// from that end.
    private func levelWords(_ shown: [Level], _ size: CGSize) -> [(level: Level, y: CGFloat, inFromEdge: CGFloat)] {
        var out: [(level: Level, y: CGFloat, inFromEdge: CGFloat)] = []
        var lastLine: CGFloat?
        var lastBelow = false
        var taken: CGFloat = 0
        for level in shown {
            let line = height(level.degrees, size)
            let crowded = lastLine.map { line - $0 < 13 } ?? false
            let below = crowded || line < 14
            if crowded, lastBelow, let before = out.last {
                taken += CGFloat(before.level.words.count) * 5.6 + 14
            } else {
                taken = 0
            }
            out.append((level, below ? line + 1 : line - 14, taken))
            lastLine = line
            lastBelow = below
        }
        return out
    }

    /// Each mark's title, skipping one that would start less than 44 points after the previous one.
    private func visibleTitles(_ xs: [CGFloat]) -> [(x: CGFloat, title: String)] {
        var out: [(x: CGFloat, title: String)] = []
        for (x, mark) in zip(xs, marks) where out.last.map({ x - $0.x >= 44 }) ?? true {
            out.append((x, mark.title))
        }
        return out
    }
}

/// Amber = from here it needs your eye; red = too hot, something protects itself; green = the Mac itself
/// took the fans to full here; grey (dotted) = a rough figure from other owners' reports.
private func levelColor(_ kind: Level.Kind, _ scheme: ColorScheme) -> Color {
    switch kind {
    case .watch: return Palette.warn(scheme)
    case .tooHot: return Palette.danger(scheme)
    case .macFull: return Palette.mac(scheme)
    case .report: return Color.secondary
    }
}

/// The faint rounded box behind a plot.
private struct PlotBox<Content: View>: View {
    let hasData: Bool
    let empty: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05))
            if hasData { content } else { Text(empty).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// The small graph at the bottom of the panel: the last 15 minutes, both lines in one box.
struct SmallGraph: View {
    let history: History
    let now: Double
    let top: Double
    /// 0.6: which temperature the coral line shows (chip, battery or the case).
    var sensor: Sensor = .chip
    @Environment(\.colorScheme) private var scheme

    /// The words before "last 15 minutes": which temperature the coral line is.
    private var name: String {
        switch sensor {
        case .battery: return "Battery"
        case .palm: return "Case"
        default: return "Chip"
        }
    }

    var body: some View {
        let span = GraphSpan.quarter.seconds
        let samples = history.samples(last: span, now: now)
        let scale = sensor == .chip ? Plot.temperatureScale(samples) : Plot.tensScale(samples.compactMap { sensor.value(in: $0) })
        VStack(alignment: .leading, spacing: 3) {
            PlotBox(hasData: samples.count >= 2, empty: "The graph fills as time passes") {
                ZStack {
                    PlotDrawing(samples: samples, marks: history.marks(last: span, now: now),
                                lines: [PlotLine(color: Palette.heat(scheme), value: { sensor.value(in: $0) })], scale: scale,
                                now: now, span: span)
                    PlotDrawing(samples: samples, marks: [],
                                lines: [PlotLine(color: Palette.fan(scheme), value: Plot.meanSpeed)],
                                scale: Plot.speedScale(samples, top: top), now: now, span: span)
                }
            }
            .frame(height: 58)
            Text("\(name), last 15 minutes · tap for the large graph").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier("smallGraph")
    }
}

/// The large graph in its own window: a picker for 15 minutes / 1 hour / 6 hours, then four plots, one above
/// the other: the three temperatures with their level lines, and the fan speed.
struct LargeGraph: View {
    let history: History
    let now: Double
    let top: Double
    /// The chip temperature at which the Mac itself was last seen to take the fans to full; nil = not seen yet.
    var fullSeenAt: Double?
    /// The level of the heat notice; nil = the notice is switched off, so no amber line.
    var heatNotice: Double? = HeatNotice.limit
    var close: () -> Void = {}
    var startSpan: GraphSpan = .hour
    /// For pictures: which graphs show (nil = the remembered pick, kept in UserDefaults under `shownGraphs`).
    var shown: [GraphPick]?
    /// For pictures: the moment the pointer is at, in seconds since 1970 (nil = where the pointer really is).
    var pointAt: Double?
    @State private var span: GraphSpan?
    @State private var picked: [GraphPick]?
    @State private var hover: Double?
    @Environment(\.colorScheme) private var scheme

    private var current: GraphSpan { span ?? startSpan }
    private var shownNow: [GraphPick] {
        picked ?? shown ?? ShownGraphs.parse(UserDefaults.standard.string(forKey: "shownGraphs"))
    }
    private var pointing: Double? { pointAt ?? hover }

    var body: some View {
        let samples = history.samples(last: current.seconds, now: now)
        let marks = history.marks(last: current.seconds, now: now)
        let speedScale = Plot.speedScale(samples, top: top)
        let fans = min(2, samples.map { $0.speeds.count }.max() ?? 0)
        let fanLines = (0..<max(fans, 1)).map { i in
            PlotLine(color: Palette.fan(scheme).opacity(i == 0 ? 1 : 0.55), value: { $0.speeds.indices.contains(i) ? $0.speeds[i] : nil })
        }
        let picks = shownNow
        let heights = ShownGraphs.heights(for: picks, room: 570, spacing: 8)
        let reach = Plot.pointReach(span: current.seconds)
        let paused = pointing.flatMap { history.pause(at: $0) }
        let near = paused != nil ? nil : pointing.flatMap { Plot.nearest(samples, to: $0, within: reach) }
        let clock = pointing.map { "at " + Words.clock(near?.time ?? $0, seconds: current == .quarter) }
        VStack(alignment: .leading, spacing: 8) {
            Text("Temperature and fan speed").font(.title3.weight(.semibold))
            HStack(spacing: 6) { ForEach(GraphSpan.allCases, id: \.self) { tab($0) } }
            HStack(spacing: 6) {
                Text("Show").font(.caption).foregroundStyle(.secondary)
                ForEach(GraphPick.allCases, id: \.self) { showButton($0, on: picks.contains($0)) }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(picks.enumerated()), id: \.element) { index, pick in
                    if let sensor = pick.sensor {
                        temperature(sensor, samples: samples, marks: marks, height: heights[index], near: near, clock: clock, paused: paused)
                    } else {
                        fanPlot(samples: samples, marks: marks, scale: speedScale, lines: fanLines, fans: fans,
                                height: heights[index], near: near, clock: clock, paused: paused)
                    }
                }
            }
            .frame(height: 570, alignment: .top)
            HStack {
                Text(spanAgo).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("now").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.leading, 56).padding(.trailing, 8)
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Coral = temperature \u{00B7} blue = fan speed \u{00B7} dashed line = you changed the choice")
                    Text("Dotted grey = owners' reports, not Apple \u{00B7} no figure for when the Mac turns itself off")
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button(action: close) {
                    Text("Done").font(.callout.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.fanFill(scheme)))
                }
                .buttonStyle(PressStyle()).keyboardShortcut(.cancelAction).accessibilityIdentifier("graphDoneButton")
            }
        }
        .padding(14)
        .frame(width: 560, height: 768, alignment: .topLeading)
        .accessibilityIdentifier("largeGraph")
    }

    private var spanAgo: String {
        switch current {
        case .quarter: return "15 min ago"
        case .hour: return "1 hour ago"
        case .sixHours: return "6 hours ago"
        }
    }

    private func tab(_ item: GraphSpan) -> some View {
        let on = item == current
        return Button { span = item } label: {
            Text(item.title).font(.callout.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 12).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Palette.fanFill(scheme) : Color.primary.opacity(0.07)))
        }
        .buttonStyle(PressStyle()).accessibilityIdentifier("span-\(item.rawValue == "sixHours" ? "six" : item.rawValue)")
    }

    /// One temperature: its name with the figure now and the usual range beside it, then the line over its
    /// level lines and the grey band of what is usual on this Mac.
    private func temperature(_ sensor: Sensor, samples: [Sample], marks: [ChoiceMark], height: Double,
                             near: Sample?, clock: String?, paused: Pause?) -> some View {
        let values = samples.compactMap { sensor.value(in: $0) }
        let scale = Levels.scale(sensor, samples)
        let usual = Usual.band(history.samples.compactMap { sensor.value(in: $0) })
        var extras: [String] = []
        if let usual { extras.append(Usual.words(usual)) }
        if sensor == .chip, fullSeenAt == nil { extras.append("fans at full in Automatic: not seen yet") }
        let charging = sensor == .battery ? history.chargingStretches(last: current.seconds, now: now) : []
        let chargingNow = samples.last?.charging == true
        return PlotBox(hasData: values.count >= 2, empty: "No \(sensor.title.lowercased()) readings yet for this time") {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(sensor.title).font(.caption.weight(.semibold)).foregroundStyle(Palette.heat(scheme))
                    if let paused {
                        Text(paused.why).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("now-\(sensor.rawValue)")
                    } else {
                        Text(Words.degrees(clock == nil ? values.last : near.flatMap { sensor.value(in: $0) }))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .accessibilityIdentifier("now-\(sensor.rawValue)")
                    }
                    if let clock { Text(clock).font(.caption).foregroundStyle(.secondary) }
                    if usual != nil {
                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.16)).frame(width: 12, height: 8)
                            .padding(.leading, 4)
                    }
                    if !extras.isEmpty {
                        Text(extras.joined(separator: " \u{00B7} ")).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    if !charging.isEmpty {
                        RoundedRectangle(cornerRadius: 2).fill(Palette.power(scheme).opacity(0.35)).frame(width: 12, height: 8)
                            .padding(.leading, 4)
                        Text(chargingNow ? "charging now" : "charging").font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).fixedSize()
                    }
                }
                axisAndDrawing(figures: [scale.upperBound, (scale.lowerBound + scale.upperBound) / 2, scale.lowerBound].map { Words.degrees($0) }) {
                    PlotDrawing(samples: samples, marks: marks,
                                lines: [PlotLine(color: Palette.heat(scheme), value: { sensor.value(in: $0) })],
                                scale: scale, now: now, span: current.seconds, grid: true,
                                levels: Levels.of(sensor, fullSeenAt: fullSeenAt, heatNotice: heatNotice), usual: usual,
                                charging: charging, pauses: history.pauses(last: current.seconds, now: now),
                                point: pointing, pointSample: near)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        // The chip graph carries the most level lines, so it is the tallest (see GraphPick.weight).
        .frame(height: height)
        .accessibilityIdentifier("plot-\(sensor.rawValue)")
    }

    /// The fan speed: the legend (and, while pointing, both speeds at that moment), then the lines over the
    /// pale stretches in which a choice was on.
    private func fanPlot(samples: [Sample], marks: [ChoiceMark], scale: ClosedRange<Double>, lines: [PlotLine],
                         fans: Int, height: Double, near: Sample?, clock: String?, paused: Pause?) -> some View {
        PlotBox(hasData: samples.count >= 2, empty: "No readings yet for this time") {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text("Fan speed").font(.caption.weight(.semibold)).foregroundStyle(Palette.fan(scheme))
                    if fans == 2 { legendItem("Left", 1); legendItem("Right", 0.55) }
                    if let paused {
                        Text(paused.why + " ").font(.caption).foregroundStyle(.secondary)
                            + Text(clock ?? "").font(.caption).foregroundColor(.secondary)
                    } else if let clock {
                        let speeds = near?.speeds ?? []
                        let figures = fans == 2
                            ? "Left \(Words.turns(speeds.first)) \u{00B7} Right \(Words.turns(speeds.count > 1 ? speeds[1] : nil))"
                            : Words.turns(speeds.first)
                        Text(figures + " ").font(.caption.weight(.semibold).monospacedDigit())
                            + Text(clock).font(.caption).foregroundColor(.secondary)
                    }
                }
                axisAndDrawing(figures: [scale.upperBound, (scale.lowerBound + scale.upperBound) / 2, scale.lowerBound].map { Words.turns($0) }) {
                    PlotDrawing(samples: samples, marks: marks, lines: lines, scale: scale, now: now,
                                span: current.seconds, grid: true, titles: true,
                                stretches: history.stretches(last: current.seconds, now: now),
                                pauses: history.pauses(last: current.seconds, now: now),
                                point: pointing, pointSample: near)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .frame(height: height)
        .accessibilityIdentifier("plot-fans")
    }

    /// One small pick button of the "Show" row: full colour when its graph shows, pale when it is hidden.
    private func showButton(_ pick: GraphPick, on: Bool) -> some View {
        let fill = pick == .fans ? Palette.fanFill(scheme) : Palette.heatFill(scheme)
        return Button {
            let next = ShownGraphs.toggled(pick, in: shownNow)
            picked = next
            if shown == nil { UserDefaults.standard.set(ShownGraphs.stored(next), forKey: "shownGraphs") }
        } label: {
            Text(pick.title).font(.caption.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 9).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? fill : Color.primary.opacity(0.07)))
        }
        .buttonStyle(PressStyle()).accessibilityIdentifier("show-\(pick.rawValue)")
    }

    /// The figures of the scale at the left (top, middle, bottom), then the drawing; the pointer over the
    /// drawing sets the moment all graphs point at.
    private func axisAndDrawing<Drawing: View>(figures: [String], @ViewBuilder drawing: () -> Drawing) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .trailing) {
                ForEach(figures.indices, id: \.self) { i in
                    if i > 0 { Spacer(minLength: 0) }
                    Text(figures[i]).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 4).frame(width: 40)
            drawing().overlay(
                GeometryReader { geo in
                    Color.clear.contentShape(Rectangle()).onContinuousHover { phase in
                        switch phase {
                        case .active(let place):
                            let width = max(geo.size.width - 8, 1)
                            hover = Plot.time(share: Double((place.x - 4) / width), now: now, span: current.seconds)
                        case .ended:
                            hover = nil
                        }
                    }
                })
        }
    }

    private func legendItem(_ name: String, _ opacity: Double) -> some View {
        HStack(spacing: 4) {
            Path { p in p.move(to: CGPoint(x: 0, y: 3)); p.addLine(to: CGPoint(x: 14, y: 3)) }
                .stroke(Palette.fan(scheme).opacity(opacity), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: 14, height: 6)
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

extension History {
    /// Sample data for pictures: `minutes` of readings ending at `now`; the choice changes to Cool a third of the way in
    /// and back to Automatic two thirds in; the temperature falls after Cool and rises again after.
    static func sample(now: Double, minutes: Double = 60) -> History {
        var history = History()
        let total = minutes * 60
        let start = now - total
        let coolAt = start + total / 3, autoAt = start + 2 * total / 3
        var time = start
        while time <= now {
            let wobble = sin(time / 37) * 1.5
            let temp: Double, speed: Double
            if time < coolAt { temp = 74 + wobble; speed = 2100 + wobble * 40 }
            else if time < autoAt {
                let k = 1 - exp(-(time - coolAt) / (total / 12))
                temp = 74 - 24 * k + wobble; speed = 3100
            } else {
                let k = 1 - exp(-(time - autoAt) / (total / 10))
                temp = 50 + 22 * k + wobble; speed = 2100 + wobble * 40
            }
            // 0.6: charging for the first 25 minutes; asleep for 8 minutes at 40 minutes in (wide enough for its word in the one-hour graph) (no readings then).
            if time >= start + 40 * 60 && time < start + 48 * 60 { time += History.every; continue }
            history.add(Sample(time: time, chip: temp, speeds: [speed, speed + 60],
                               graphics: temp - 8 + cos(time / 53), battery: 29 + (time - start) / total * 4 + sin(time / 91) * 0.4,
                               storage: 38 + (temp - 50) / 8 + sin(time / 140) * 0.5, palm: 30 + (temp - 50) / 12,
                               power: 14 + (temp - 50) * 1.3 + sin(time / 23) * 3,
                               charging: time < start + 25 * 60))
            time += History.every
        }
        history.pause(from: start + 40 * 60, to: start + 48 * 60, why: Pause.asleep)
        history.mark("Cool", at: coolAt)
        history.mark("Automatic", at: autoAt)
        return history
    }
}
