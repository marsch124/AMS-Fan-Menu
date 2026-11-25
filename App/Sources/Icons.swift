import SwiftUI

/// The app's own hand-drawn icons, in the AMS style: a 24-point grid, one 1.9 stroke, round ends, no fill.
enum Glyph {
    case fan, gear

    static let stroke: CGFloat = 1.9

    /// One fan blade on the 24-point grid, pointing up from the hub and wider at its tip; the fan is three of them.
    /// The same numbers are the mark "fan" in the AMS Icon Library.
    private static func blade(into path: CGMutablePath, turn: CGFloat) {
        let t = CGAffineTransform(translationX: 12, y: 12).rotated(by: turn)
        path.move(to: CGPoint(x: -0.86, y: -1.73), transform: t)
        path.addCurve(to: CGPoint(x: -3.46, y: -8.64), control1: CGPoint(x: -2.11, y: -4.42), control2: CGPoint(x: -4.42, y: -6.34), transform: t)
        path.addCurve(to: CGPoint(x: 4.42, y: -7.3), control1: CGPoint(x: -2.5, y: -10.18), control2: CGPoint(x: 2.5, y: -9.98), transform: t)
        path.addCurve(to: CGPoint(x: 1.63, y: -1.06), control1: CGPoint(x: 5.18, y: -5.95), control2: CGPoint(x: 3.07, y: -3.46), transform: t)
    }

    /// The drawing on the 24-point grid, y pointing down.
    var path: CGPath {
        let p = CGMutablePath()
        switch self {
        case .fan:
            for index in 0..<3 { Glyph.blade(into: p, turn: CGFloat(index) * 2 * .pi / 3) }
            p.addEllipse(in: CGRect(x: 10, y: 10, width: 4, height: 4))
        case .gear:
            p.addEllipse(in: CGRect(x: 6, y: 6, width: 12, height: 12))
            p.addEllipse(in: CGRect(x: 9.7, y: 9.7, width: 4.6, height: 4.6))
            for index in 0..<8 {
                let angle = CGFloat(index) * .pi / 4
                p.move(to: CGPoint(x: 12 + cos(angle) * 6, y: 12 + sin(angle) * 6))
                p.addLine(to: CGPoint(x: 12 + cos(angle) * 8.6, y: 12 + sin(angle) * 8.6))
            }
        }
        return p
    }

    /// Draws the icon into an AppKit drawing (y pointing up), for the menu bar.
    func draw(in rect: CGRect, color: NSColor, context: CGContext, stroke: CGFloat = Glyph.stroke) {
        let scale = rect.width / 24
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: scale, y: -scale)
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(stroke)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }
}

/// The app's tile: a flat calm blue with the white fan.
enum TileArt {
    static let corner: CGFloat = 0.26
    static let blue = NSColor(red: 0.15, green: 0.45, blue: 0.78, alpha: 1)

    /// Draws the tile into an AppKit drawing (y pointing up). `square`: no round corners, for the app icon,
    /// which the Mac rounds itself.
    static func draw(in rect: CGRect, context: CGContext, square: Bool = false) {
        context.saveGState()
        if !square {
            let radius = rect.width * corner
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
        }
        context.setFillColor(blue.cgColor)
        context.fill(rect)
        context.restoreGState()
        let inset = rect.width * 0.13
        Glyph.fan.draw(in: rect.insetBy(dx: inset, dy: inset), color: .white, context: context, stroke: 2.1)
    }

    static func image(size: CGFloat, square: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: rect, context: context, square: square)
            return true
        }
    }
}

/// The tile as a view, for the panel's and the Settings window's header.
struct AppTile: View {
    var size: CGFloat = 22
    var body: some View {
        Image(nsImage: TileArt.image(size: size)).accessibilityHidden(true)
    }
}

/// One icon, drawn as a shape.
struct GlyphView: View {
    let glyph: Glyph
    var size: CGFloat = 18

    var body: some View {
        let scale = size / 24
        Path(glyph.path)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .stroke(style: StrokeStyle(lineWidth: Glyph.stroke * scale, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A button that gives a little when pressed. Drawn by the app, so it keeps its colour when the panel
/// is not the window in front.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The app's colours. Each means one thing: green = the Mac decides, blue = a fan speed you set,
/// coral = temperature, amber = a note that needs your eye.
enum Palette {
    /// Green words: the Mac decides.
    static func mac(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.40, green: 0.78, blue: 0.56) : Color(red: 0.11, green: 0.45, blue: 0.28)
    }
    /// Behind white words.
    static func macFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.16, green: 0.52, blue: 0.33) : Color(red: 0.13, green: 0.49, blue: 0.31)
    }
    /// Blue words: a fan speed you set.
    static func fan(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.50, green: 0.73, blue: 0.98) : Color(red: 0.12, green: 0.41, blue: 0.76)
    }
    static func fanFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.17, green: 0.46, blue: 0.80) : Color(red: 0.15, green: 0.45, blue: 0.78)
    }
    /// Coral words: temperature.
    static func heat(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.97, green: 0.58, blue: 0.44) : Color(red: 0.72, green: 0.26, blue: 0.11)
    }
    static func heatFill(_ scheme: ColorScheme) -> Color {
        Color(red: 0.77, green: 0.30, blue: 0.14)
    }
    /// Amber: a note that needs your eye.
    static func warn(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.96, green: 0.76, blue: 0.36) : Color(red: 0.56, green: 0.35, blue: 0.0)
    }
    /// Red: too hot, the line in a graph from where something protects itself. It stands for nothing else.
    static func danger(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1.0, green: 0.42, blue: 0.42) : Color(red: 0.78, green: 0.10, blue: 0.14)
    }
    /// Teal: how much power the whole Mac uses. It stands for nothing else.
    static func power(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.36, green: 0.80, blue: 0.80) : Color(red: 0.03, green: 0.44, blue: 0.47)
    }
    /// Purple: the "What happened" list and its tab. It stands for nothing else.
    static func story(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.72, green: 0.64, blue: 0.96) : Color(red: 0.42, green: 0.30, blue: 0.74)
    }
    static func storyFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.46, green: 0.36, blue: 0.78) : Color(red: 0.42, green: 0.30, blue: 0.74)
    }
    /// The pale ground of a choice that is not in use, and of a note.
    static func pale(_ color: Color, _ scheme: ColorScheme) -> Color {
        color.opacity(scheme == .dark ? 0.20 : 0.13)
    }
    /// Menu bar ink: black by day, white by night, like the Mac's own icons.
    static let inkNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }
    /// The menu bar mark while the app runs the fans: blue by day, lighter blue by night.
    static let fanNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.45, green: 0.70, blue: 1.0, alpha: 1) : NSColor(red: 0.10, green: 0.42, blue: 0.82, alpha: 1)
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
