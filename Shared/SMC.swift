import Foundation
import IOKit

/// The Mac's own little controller for fans and temperature sensors. Reading works for any app;
/// writing only works for the helper, which runs with the Mac's deepest rights.
final class SMC {
    private struct Version { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0; var length: UInt16 = 0; var cpu: UInt32 = 0; var gpu: UInt32 = 0; var mem: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
    private typealias Bytes32 = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    /// 80 bytes, laid out as the Mac expects.
    private struct Param {
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    struct Value {
        let type: String
        let bytes: [UInt8]

        /// The value as a number, whatever kind the Mac stores it as.
        var number: Double? {
            switch type {
            case "flt ":
                guard bytes.count == 4 else { return nil }
                return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
            case "ui8 ": return bytes.first.map(Double.init)
            case "ui16": return bytes.count == 2 ? Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) : nil
            case "ui32": return bytes.count == 4 ? Double(bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) : nil
            default: return nil
            }
        }
    }

    private var connection: io_connect_t = 0
    /// Size and kind of each value asked for so far; they never change while the Mac runs.
    private var known: [String: (size: UInt32, type: String)] = [:]

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    private static func code(_ key: String) -> UInt32 { key.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
    private static func text(_ code: UInt32) -> String {
        String(bytes: [UInt8(code >> 24 & 0xff), UInt8(code >> 16 & 0xff), UInt8(code >> 8 & 0xff), UInt8(code & 0xff)],
               encoding: .ascii) ?? "????"
    }

    /// One question to the controller. Returns the answer and the controller's own result code (0 = fine).
    private func call(_ input: inout Param) -> (out: Param, code: UInt8)? {
        var output = Param()
        var size = MemoryLayout<Param>.stride
        guard IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<Param>.stride, &output, &size) == kIOReturnSuccess else {
            return nil
        }
        return (output, output.result)
    }

    private func info(_ key: String) -> (size: UInt32, type: String)? {
        if let have = known[key] { return have }
        var ask = Param()
        ask.key = SMC.code(key)
        ask.data8 = 9
        guard let answer = call(&ask), answer.code == 0, answer.out.keyInfo.dataSize > 0, answer.out.keyInfo.dataSize <= 32 else { return nil }
        let found = (answer.out.keyInfo.dataSize, SMC.text(answer.out.keyInfo.dataType))
        known[key] = found
        return found
    }

    func read(_ key: String) -> Value? {
        guard key.utf8.count == 4, let info = info(key) else { return nil }
        var ask = Param()
        ask.key = SMC.code(key)
        ask.keyInfo.dataSize = info.size
        ask.data8 = 5
        guard let answer = call(&ask), answer.code == 0 else { return nil }
        let all = withUnsafeBytes(of: answer.out.bytes) { Array($0) }
        return Value(type: info.type, bytes: Array(all.prefix(Int(info.size))))
    }

    func number(_ key: String) -> Double? { read(key)?.number }

    /// Writes a value. Returns the controller's result code (0 = taken), or nil when the value does not exist
    /// or the Mac would not even pass the question on (no rights).
    func write(_ key: String, bytes new: [UInt8]) -> UInt8? {
        guard key.utf8.count == 4, let info = info(key), Int(info.size) == new.count else { return nil }
        var ask = Param()
        ask.key = SMC.code(key)
        ask.keyInfo.dataSize = info.size
        ask.data8 = 6
        withUnsafeMutableBytes(of: &ask.bytes) { raw in
            for (index, byte) in new.enumerated() { raw[index] = byte }
        }
        return call(&ask)?.code
    }

    /// A number written the way this value is stored (a whole number or a decimal one).
    func write(_ key: String, number: Double) -> UInt8? {
        guard let info = info(key) else { return nil }
        switch info.type {
        case "flt ":
            return write(key, bytes: withUnsafeBytes(of: Float32(number)) { Array($0) })
        case "ui8 ":
            return write(key, bytes: [UInt8(max(0, min(255, number)))])
        default:
            return nil
        }
    }

    func exists(_ key: String) -> Bool { info(key) != nil }
}

/// The fans, as numbers.
enum FanKeys {
    static func count(_ smc: SMC) -> Int { Int(smc.number("FNum") ?? 0) }
    static func now(_ index: Int) -> String { "F\(index)Ac" }
    static func lowest(_ index: Int) -> String { "F\(index)Mn" }
    static func top(_ index: Int) -> String { "F\(index)Mx" }
    static func target(_ index: Int) -> String { "F\(index)Tg" }
    /// 0 = the Mac decides, 1 = forced. Newer Macs spell it with a small m.
    static func mode(_ index: Int, smc: SMC) -> String {
        let usual = "F\(index)Md"
        return smc.exists(usual) ? usual : "F\(index)md"
    }
    static let unlock = "Ftst"
}

/// The temperature sensors that mean something on an M1 Pro / Max MacBook Pro.
enum SensorKeys {
    static let cores = ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0T", "Tp0X", "Tp0b"]
    static let graphics = ["Tg05", "Tg0D", "Tg0L", "Tg0T"]
    static let battery = ["TB1T", "TB2T"]
}
