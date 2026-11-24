import Foundation

/// What the app may ask the helper to do. Nothing else: only fan speeds, never anything else on the Mac.
@objc protocol FanHelperProtocol {
    /// The helper's own version, so the app notices an old one.
    func version(reply: @escaping (String) -> Void)
    /// One speed per fan, in turns a minute. The helper keeps each inside that fan's own range.
    /// The app repeats this every few seconds; when it goes silent the helper gives the fans back.
    func setSpeeds(_ speeds: [NSNumber], reply: @escaping (Bool, String) -> Void)
    /// The Mac decides again.
    func giveBack(reply: @escaping (Bool, String) -> Void)
}

enum HelperInfo {
    /// Also the helper's file name and the name of its start order.
    static let label = "com.schabbauer.AMSFanMenu.helper"
    /// Raised whenever the helper's own code changes; the app then offers "Update the helper…".
    static let version = "2"
    static let appID = "com.schabbauer.AMSFanMenu"
    static let team = "D24ENP83QQ"
    static let toolPath = "/Library/PrivilegedHelperTools/\(label)"
    static let orderPath = "/Library/LaunchDaemons/\(label).plist"
    static let logPath = "/Library/Logs/AMS Fan Menu/helper.log"

    /// Only the real app, signed by its maker, may talk to the helper.
    static var appRequirement: String {
        "identifier \"\(appID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }
    /// Only the real helper is the one the app talks to.
    static var helperRequirement: String {
        "identifier \"\(label)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }
}
