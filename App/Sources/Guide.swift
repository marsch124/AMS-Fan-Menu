import Foundation

struct GuideSection: Identifiable { let id = UUID(); let title: String; let body: String }
struct Release: Identifiable { let id = UUID(); let version: String; let date: String; let items: [String] }
/// What is drawn next to a sign's meaning.
enum SignKind { case markBlack, markBlue, buttonFull, buttonPale, green, blue, coral, amber }
struct GuideSign: Identifiable { let id = UUID(); let kind: SignKind; let name: String; let meaning: String }

enum Guide {
    static let howItWorks: [GuideSection] = [
        GuideSection(title: "What this app is for", body: "The Mac has no setting of its own for how fast its fans turn. AMS Fan Menu gives you one. It lives in the menu bar at the top of the screen and has no Dock icon.\n\nIt is made for a MacBook Pro 16-inch (2021, M1 Max). That Mac has two fans, Left and Right."),
        GuideSection(title: "The menu bar", body: "You see a small hand-drawn fan mark and no figure. The mark is black (white at night) while the Mac decides how fast the fans turn. It is blue while AMS Fan Menu runs the fans, which is true for every choice except Automatic.\n\nHover over the mark and it says which. A click opens the panel.\n\nIf the Mac ever moves the mark out of sight, to the far left, the app puts it back after 10 seconds."),
        GuideSection(title: "The panel", body: "At the top is the header: the small app tile, the name, the version number and the gear button for Settings.\n\nBelow it, a line such as \"Left 1,776 \u{00B7} Right 1,868\" shows how fast each fan turns now, in turns a minute. It is fresh every second while the panel is open.\n\nThe next line, such as \"Chip 72\u{00B0} \u{00B7} Graphics 64\u{00B0} \u{00B7} Battery 36\u{00B0}\", shows the temperatures in degrees Celsius. Chip is the average of the processor cores.\n\nA status line says \"The Mac decides\" or, for example, \"You decide: Cool\"."),
        GuideSection(title: "The six choices: the first four", body: "Under the status line you find six choices. The one in use is drawn in full colour with white words. The others are pale.\n\nAutomatic (green): the Mac decides, as if the app were not there.\n\nQuiet (blue): both fans are held at their lowest speed. The Mac gets warmer and may slow itself down.\n\nCool (blue): half speed, halfway between the lowest and the top.\n\nFull (blue): the top speed."),
        GuideSection(title: "The six choices: My speed and Follow temperature", body: "My speed (blue) has a slider with a percent figure. 0 % is the lowest speed, 100 % is the top. Both fans move together, each within its own range. Dragging the slider switches to My speed.\n\nFollow temperature (coral) has two sliders, Start (first 65\u{00B0}) and Full (first 95\u{00B0}). At or below Start the fans run at their lowest. At Full or above they run at their top. In between it is even.\n\nIt follows the Chip temperature, averaged over three readings. It changes the speed only when the change is at least 100 turns, so the fans do not keep hunting.\n\nStart can be 40\u{00B0} to 85\u{00B0} and Full 60\u{00B0} to 100\u{00B0}, in steps of 5\u{00B0}. They stay at least 10\u{00B0} apart: moving one pushes the other."),
        GuideSection(title: "Each fan's own range", body: "The app asks the Mac for each fan's own lowest and top speed. On this Mac the lowest is 1,499 for both fans. The top is 5,348 for the left fan and 5,776 for the right fan, in turns a minute.\n\n\"Lowest\" and \"top\" in every choice mean those figures, fan by fan. A speed is never below a fan's lowest or above its top."),
        GuideSection(title: "First use and the helper", body: "Setting the fans needs the Mac's deepest rights. The first time you tap a choice other than Automatic, an amber note says \"Setting the fans needs your OK once\", with a button \"Allow fan control\u{2026}\".\n\nThe Mac then asks for your Mac password. That is the Mac's own dialog. The app never sees the password.\n\nThis puts a small helper on the Mac. The helper takes orders only from AMS Fan Menu, and only fan speeds inside each fan's own range.\n\nAfter an app update the note may ask once more (\"Update the helper\u{2026}\"). In Settings, \"Remove the helper\u{2026}\" takes it away again."),
        GuideSection(title: "While a choice is on", body: "The Mac would otherwise take the fans back, so while a choice is on the app repeats it to the Mac every 3 seconds.\n\nIf you switch to Automatic, the app hands the fans straight back and the Mac decides again."),
        GuideSection(title: "Safety: four rules", body: "1. Too hot. If the hottest processor core is at 100\u{00B0} or more for 15 seconds while Quiet, Cool, My speed or Follow temperature is on, the app gives the fans back to the Mac and switches to Automatic. An amber note says, for example, \"Too hot (101\u{00B0}). The Mac has the fans again.\" and you get a notification. Full is left alone, because it is already the top speed.\n\n2. Quit, sleep and restart always hand the fans back to the Mac. After waking, the app stays on Automatic and an amber note says so. The choice in use is never remembered across a quit or a restart.\n\n3. If the app ever stops unexpectedly, the helper gives the fans back by itself after 20 seconds.\n\n4. A speed is never below a fan's lowest or above its top."),
        GuideSection(title: "What the app remembers", body: "It remembers your My speed percentage and your Start and Full temperatures.\n\nIt does not remember which choice was in use. After every start the Mac decides.\n\nThe app also keeps a diary of what it did: times, choices and speeds, nothing personal. The diary stays on this Mac only."),
        GuideSection(title: "Settings", body: "Open Settings with the gear button in the panel. It has three tabs: \"Settings\", \"How it works\" and \"What's new\".\n\nThe \"Settings\" tab has \"Open at login\". While it is on, the app also comes back by itself if it ever stops unexpectedly. It shows the state of the fan control helper, with \"Remove the helper\u{2026}\". It has \"Quit AMS Fan Menu\" and \"Done\". Escape also closes the window. The version number is shown too."),
        GuideSection(title: "Good to know: the limits", body: "The fans can never go below their own lowest speed. Quiet is the lowest they will go.\n\nQuiet makes the Mac warmer, and the Mac may slow itself down to cool off.\n\nThe Mac still protects itself. If it gets too hot, it can act on its own, whatever you chose.\n\nThe app is installed straight on the Mac, not through TestFlight.")
    ]

    static let signs: [GuideSign] = [
        GuideSign(kind: .markBlack, name: "Black fan mark (white at night)", meaning: "The Mac decides how fast the fans turn."),
        GuideSign(kind: .markBlue, name: "Blue fan mark", meaning: "AMS Fan Menu runs the fans."),
        GuideSign(kind: .buttonFull, name: "A button in full colour", meaning: "The choice in use now."),
        GuideSign(kind: .buttonPale, name: "A pale button", meaning: "A choice you can tap."),
        GuideSign(kind: .green, name: "Green", meaning: "The Mac decides (Automatic)."),
        GuideSign(kind: .blue, name: "Blue", meaning: "A fan speed you set."),
        GuideSign(kind: .coral, name: "Coral", meaning: "Temperature."),
        GuideSign(kind: .amber, name: "Amber", meaning: "A note that needs your eye, sometimes with a button.")
    ]

    static let whatsNew: [Release] = [
        Release(version: "0.1", date: "24 Nov 2026", items: [
            "New: the first version. AMS Fan Menu lives in the menu bar of your Mac and lets you choose how fast the fans turn. The Mac has no setting of its own for this.",
            "New: the menu bar shows a small hand-drawn fan mark. It is black (white at night) while the Mac decides and blue while the app runs the fans. Hovering says which.",
            "New: if the Mac moves the mark out of sight to the far left, the app puts it back after 10 seconds.",
            "New: the panel shows how fast each fan turns now, for example \"Left 1,776 \u{00B7} Right 1,868\", fresh every second while the panel is open.",
            "New: the panel shows the temperatures of the chip, the graphics and the battery, and a status line such as \"The Mac decides\" or \"You decide: Cool\".",
            "New: six choices: Automatic, Quiet, Cool, Full, My speed and Follow temperature. The one in use is in full colour with white words, and the others are pale.",
            "New: My speed has a slider from 0 % (lowest) to 100 % (top). Both fans move together, each within its own range.",
            "New: Follow temperature has two sliders, Start (first 65\u{00B0}) and Full (first 95\u{00B0}), in steps of 5\u{00B0} and always at least 10\u{00B0} apart. It changes speed only when the change is at least 100 turns, so the fans do not keep hunting.",
            "New: setting the fans needs your OK once. An amber note with a button \"Allow fan control\u{2026}\" asks for your Mac password in the Mac's own dialog, and installs a small helper that takes orders only from this app. Settings can remove it again.",
            "New: four safety rules. Too hot (100\u{00B0} or more for 15 seconds) hands the fans back and sends a notification. Quit, sleep and restart hand them back. If the app stops unexpectedly, the helper gives them back after 20 seconds. A speed stays inside each fan's own range.",
            "New: the app repeats the choice in use to the Mac every 3 seconds, because the Mac would otherwise take the fans back.",
            "New: the app remembers your My speed percentage and your Start and Full temperatures. The choice in use is never remembered.",
            "New: Settings has three tabs (Settings, How it works, What's new), \"Open at login\", the helper's state with \"Remove the helper\u{2026}\", Quit and Done. The version number is shown.",
            "New: a diary of what the app did (times, choices, speeds, nothing personal) is kept on this Mac only."
        ])
    ]
}
