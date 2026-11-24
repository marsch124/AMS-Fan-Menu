import CoreGraphics
import Foundation

// Prints the fan as ONE filled outline (SVG path data) on a square canvas: the drawn line turned into a shape.
// The Mac's layered app icon fills whatever it is given, so a plain line drawing would come out as blobs.
// Used by make-icon.py:  swift Tools/fan-outline.swift <canvas> <share of the canvas> <line weight on the 24 grid>
// The blade numbers are the same as in App/Sources/Icons.swift and in the AMS Icon Library mark "fan".

let arguments = CommandLine.arguments
guard arguments.count == 4, let size = Double(arguments[1]), let share = Double(arguments[2]), let weight = Double(arguments[3]) else {
    FileHandle.standardError.write("usage: fan-outline.swift <canvas> <share> <line weight>\n".data(using: .utf8)!)
    exit(2)
}

let fan = CGMutablePath()
for index in 0..<3 {
    let t = CGAffineTransform(translationX: 12, y: 12).rotated(by: CGFloat(index) * 2 * .pi / 3)
    fan.move(to: CGPoint(x: -0.86, y: -1.73), transform: t)
    fan.addCurve(to: CGPoint(x: -3.46, y: -8.64), control1: CGPoint(x: -2.11, y: -4.42), control2: CGPoint(x: -4.42, y: -6.34), transform: t)
    fan.addCurve(to: CGPoint(x: 4.42, y: -7.3), control1: CGPoint(x: -2.5, y: -10.18), control2: CGPoint(x: 2.5, y: -9.98), transform: t)
    fan.addCurve(to: CGPoint(x: 1.63, y: -1.06), control1: CGPoint(x: 5.18, y: -5.95), control2: CGPoint(x: 3.07, y: -3.46), transform: t)
}
fan.addEllipse(in: CGRect(x: 10, y: 10, width: 4, height: 4))

let k = CGFloat(size * share / 24)
let o = CGFloat(size) / 2 - 12 * k
var place = CGAffineTransform(translationX: o, y: o).scaledBy(x: k, y: k)
guard let placed = fan.copy(using: &place) else { exit(1) }
let outline = placed.copy(strokingWithWidth: CGFloat(weight) * k, lineCap: .round, lineJoin: .round, miterLimit: 10)
    .normalized(using: .winding)

var d = ""
func p(_ point: CGPoint) -> String { String(format: "%.2f %.2f", point.x, point.y) }
outline.applyWithBlock { element in
    let points = element.pointee.points
    switch element.pointee.type {
    case .moveToPoint: d += "M" + p(points[0])
    case .addLineToPoint: d += "L" + p(points[0])
    case .addQuadCurveToPoint: d += "Q" + p(points[0]) + " " + p(points[1])
    case .addCurveToPoint: d += "C" + p(points[0]) + " " + p(points[1]) + " " + p(points[2])
    case .closeSubpath: d += "Z"
    @unknown default: break
    }
}
print(d)
