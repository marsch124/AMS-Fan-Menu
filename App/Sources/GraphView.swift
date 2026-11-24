import FanMenuCore
import SwiftUI

// The graphs: how the chip temperature (coral) reacted to the fan speed (blue) after the choice changed.

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
    let inset: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let xs = marks.map { inset + CGFloat(Plot.x(time: $0.time, now: now, span: span)) * (size.width - 2 * inset) }
            ZStack(alignment: .topLeading) {
                if grid {
                    Path { p in
                        for f in [0.0, 0.5, 1.0] {
                            let y = size.height - inset - CGFloat(f) * (size.height - 2 * inset)
                            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                        }
                    }.stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                }
                Path { p in
                    for x in xs { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }
                }.stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(lines.indices, id: \.self) { i in
                    linePath(pieces(samples, now: now, span: span, scale: scale, size: size, inset: inset, value: lines[i].value))
                        .stroke(lines[i].color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                if titles {
                    ForEach(Array(visibleTitles(xs).enumerated()), id: \.offset) { _, item in
                        Text(item.title).font(.caption2).foregroundStyle(.secondary).fixedSize()
                            .offset(x: item.x + 3, y: 1)
                    }
                }
            }
        }
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let span = GraphSpan.quarter.seconds
        let samples = history.samples(last: span, now: now)
        VStack(alignment: .leading, spacing: 3) {
            PlotBox(hasData: samples.count >= 2, empty: "The graph fills as time passes") {
                ZStack {
                    PlotDrawing(samples: samples, marks: history.marks(last: span, now: now),
                                lines: [PlotLine(color: Palette.heat(scheme), value: { $0.chip })], scale: Plot.temperatureScale(samples),
                                now: now, span: span)
                    PlotDrawing(samples: samples, marks: [],
                                lines: [PlotLine(color: Palette.fan(scheme), value: Plot.meanSpeed)],
                                scale: Plot.speedScale(samples, top: top), now: now, span: span)
                }
            }
            .frame(height: 58)
            Text("Last 15 minutes · tap for the large graph").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier("smallGraph")
    }
}

/// The large graph in its own window: a picker for 15 minutes / 1 hour / 6 hours, then two plots, one above the other.
struct LargeGraph: View {
    let history: History
    let now: Double
    let top: Double
    var close: () -> Void = {}
    var startSpan: GraphSpan = .hour
    @State private var span: GraphSpan?
    @Environment(\.colorScheme) private var scheme

    private var current: GraphSpan { span ?? startSpan }

    var body: some View {
        let samples = history.samples(last: current.seconds, now: now)
        let marks = history.marks(last: current.seconds, now: now)
        let tempScale = Plot.temperatureScale(samples)
        let speedScale = Plot.speedScale(samples, top: top)
        let fans = min(2, samples.map { $0.speeds.count }.max() ?? 0)
        let fanLines = (0..<max(fans, 1)).map { i in
            PlotLine(color: Palette.fan(scheme).opacity(i == 0 ? 1 : 0.55), value: { $0.speeds.indices.contains(i) ? $0.speeds[i] : nil })
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Temperature and fan speed").font(.title3.weight(.semibold))
            HStack(spacing: 6) { ForEach(GraphSpan.allCases, id: \.self) { tab($0) } }
            plot("Chip temperature", color: Palette.heat(scheme), legend: false, samples: samples, marks: marks,
                 lines: [PlotLine(color: Palette.heat(scheme), value: { $0.chip })], scale: tempScale,
                 figures: [tempScale.upperBound, (tempScale.lowerBound + tempScale.upperBound) / 2, tempScale.lowerBound].map { Words.degrees($0) },
                 titles: true, fans: fans)
            plot("Fan speed", color: Palette.fan(scheme), legend: fans == 2, samples: samples, marks: marks,
                 lines: fanLines, scale: speedScale,
                 figures: [speedScale.upperBound, (speedScale.lowerBound + speedScale.upperBound) / 2, speedScale.lowerBound].map { Words.turns($0) },
                 titles: false, fans: fans)
            HStack {
                Text(spanAgo).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("now").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.leading, 56).padding(.trailing, 8)
            HStack(spacing: 8) {
                Text("Coral = chip temperature · blue = fan speed · dashed line = you changed the choice")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
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
        .frame(width: 560, height: 470, alignment: .topLeading)
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

    private func plot(_ heading: String, color: Color, legend: Bool, samples: [Sample], marks: [ChoiceMark],
                      lines: [PlotLine], scale: ClosedRange<Double>, figures: [String], titles: Bool, fans: Int) -> some View {
        PlotBox(hasData: samples.count >= 2, empty: "No readings yet for this time") {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text(heading).font(.caption.weight(.semibold)).foregroundStyle(color)
                    if legend { legendItem("Left", 1); legendItem("Right", 0.55) }
                }
                HStack(spacing: 0) {
                    VStack(alignment: .trailing) {
                        ForEach(figures.indices, id: \.self) { i in
                            if i > 0 { Spacer(minLength: 0) }
                            Text(figures[i]).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 4).frame(width: 40)
                    PlotDrawing(samples: samples, marks: marks, lines: lines, scale: scale, now: now,
                                span: current.seconds, grid: true, titles: titles)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .frame(height: 150)
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
            history.add(Sample(time: time, chip: temp, speeds: [speed, speed + 60]))
            time += History.every
        }
        history.mark("Cool", at: coolAt)
        history.mark("Automatic", at: autoAt)
        return history
    }
}
