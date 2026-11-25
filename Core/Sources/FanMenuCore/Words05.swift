import Foundation

public extension Words {
    /// "42 W": whole watts.
    static func watts(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "\u{2013}" }
        return "\(Int(value.rounded())) W"
    }
}
