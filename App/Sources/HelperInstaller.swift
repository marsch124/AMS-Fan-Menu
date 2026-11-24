import Foundation

/// Puts the helper in place, or takes it away. Both need the Mac's deepest rights, so the Mac asks for the
/// password in its own dialog; the app never sees it.
enum HelperInstaller {
    enum Outcome: Equatable {
        case done
        /// The password dialog was closed with Cancel.
        case cancelled
        case failed(String)
    }

    /// The helper as it travels inside the app.
    static var bundledTool: String { Bundle.main.bundlePath + "/Contents/Library/HelperTools/" + HelperInfo.label }
    static var bundledOrder: String? { Bundle.main.path(forResource: HelperInfo.label, ofType: "plist") }

    static var installed: Bool {
        FileManager.default.fileExists(atPath: HelperInfo.toolPath) && FileManager.default.fileExists(atPath: HelperInfo.orderPath)
    }

    /// What runs with the Mac's deepest rights when you allow fan control. In order: check that the helper
    /// inside the app is the real one, stop an older helper, copy the new one where only the Mac's
    /// administrator can change it, and tell the Mac to start it whenever the app asks.
    static func installScript(tool: String, order: String) -> String {
        let label = HelperInfo.label
        return [
            "/usr/bin/codesign -v -R='\(HelperInfo.helperRequirement)' '\(tool)'",
            "/bin/mkdir -p /Library/PrivilegedHelperTools",
            "{ /bin/launchctl bootout system/\(label) 2>/dev/null && /bin/sleep 1; /usr/bin/true; }",
            "/bin/cp -f '\(tool)' '\(HelperInfo.toolPath)'",
            "/usr/sbin/chown root:wheel '\(HelperInfo.toolPath)'",
            "/bin/chmod 755 '\(HelperInfo.toolPath)'",
            "/bin/cp -f '\(order)' '\(HelperInfo.orderPath)'",
            "/usr/sbin/chown root:wheel '\(HelperInfo.orderPath)'",
            "/bin/chmod 644 '\(HelperInfo.orderPath)'",
            "/bin/launchctl bootstrap system '\(HelperInfo.orderPath)'",
        ].joined(separator: " && ")
    }

    static var removeScript: String {
        "{ /bin/launchctl bootout system/\(HelperInfo.label) 2>/dev/null; /usr/bin/true; } && "
            + "/bin/rm -f '\(HelperInfo.toolPath)' '\(HelperInfo.orderPath)'"
    }

    static func install(_ done: @escaping (Outcome) -> Void) {
        let tool = bundledTool
        guard FileManager.default.fileExists(atPath: tool), let order = bundledOrder,
              !tool.contains("'"), !order.contains("'") else {
            done(.failed("the helper is missing from the app"))
            return
        }
        asAdministrator(installScript(tool: tool, order: order),
                        prompt: "AMS Fan Menu needs your OK once, so it can set the fan speed.", done)
    }

    static func remove(_ done: @escaping (Outcome) -> Void) {
        asAdministrator(removeScript, prompt: "AMS Fan Menu will remove its fan control helper.", done)
    }

    /// Text inside an AppleScript string.
    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func asAdministrator(_ shell: String, prompt: String, _ done: @escaping (Outcome) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "do shell script \(quoted(shell)) with prompt \(quoted(prompt)) with administrator privileges"]
        let complaints = Pipe()
        task.standardError = complaints
        task.standardOutput = FileHandle.nullDevice
        task.terminationHandler = { finished in
            let said = String(data: complaints.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let outcome: Outcome
            if finished.terminationStatus == 0 {
                outcome = .done
            } else if said.contains("-128") || said.localizedCaseInsensitiveContains("cancel") {
                outcome = .cancelled
            } else {
                outcome = .failed(said.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            DispatchQueue.main.async { done(outcome) }
        }
        do { try task.run() } catch { done(.failed(error.localizedDescription)) }
    }
}
