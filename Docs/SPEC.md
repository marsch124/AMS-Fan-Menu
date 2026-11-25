# AMS Fan Menu 0.4 (build 6, 25 Nov 2026) - Specification

## Purpose

macOS has no built-in setting for fan speed. AMS Fan Menu is a Mac-only menu bar app (no Dock icon) that lets the owner choose how the fans run, shows the fan speeds and temperatures live, and always hands the fans back to the Mac when something looks unsafe. The well-known reference app is Macs Fan Control.

It is installed directly on the Mac, not through TestFlight, because a sandboxed app cannot set fans.

## Hardware it is made for

- MacBook Pro 16-inch 2021 (MacBookPro18,2, M1 Max), with two fans. Apple Silicon, macOS 15 or later.
- Measured 24 Nov 2026: in Automatic this Mac stops both fans completely (speed 0, hand-over state 3, target 0) when the chip is cool (seen at about 63°), and runs them at about 1,500 to 1,900 when it is warm (70° to 80°). So the lowest speed the app can set (1,499) is the lowest RUNNING speed. Up to 0.2 this made Automatic quieter than Quiet; from 0.3 Quiet can let the fans rest (see "Quiet lets the fans stop"). The panel and the graph show the true 0.
- The speed ranges are read from the Mac, not fixed. On this Mac the lowest speed is 1,499 turns a minute for both fans. The top speed is 5,348 for the left fan (fan 0) and 5,776 for the right fan (fan 1).

## Menu bar item

- A hand-drawn fan mark only, no figure.
- Black (white at night) means the Mac decides. Blue means your choice is on: AMS Fan Menu runs the fans (any choice except Automatic), also while Quiet lets the fans rest (0.3).
- Hover text: "Fans: the Mac decides" or "Fans: you decide (Cool)" (with the name of the choice in use). From 0.2 a second line gives the figures, for example "Left 1,776 · Right 1,868 · Chip 72°". The mark itself stays without a figure.
- A click opens the panel. The panel does not take the keyboard away from the app in front.
- The item has the autosave name "fanMenu". If the Mac moves its saved place to the far left (a value above 1000) and the item is out of sight for 10 seconds, the app puts it back at its home place, 190 points from the right edge.

## Panel

From top to bottom:

1. Header: app tile, name, version, and a gear that opens Settings.
2. Fan speeds, for example "Left 1,776 - Right 1,868", live, updated once a second while the panel is open.
3. Temperatures, for example "Chip 72° · Graphics 64° · Battery 36°" (Celsius).
   - Chip is the average of the processor core sensors Tp01, Tp05, Tp09, Tp0D, Tp0H, Tp0L, Tp0P, Tp0T, Tp0X, Tp0b.
   - Graphics is the average of Tg05, Tg0D, Tg0L, Tg0T.
   - Battery is the average of TB1T, TB2T.
   - Values outside 5 to 130 are ignored.
4. Status line: "The Mac decides" or "You decide: Cool" (with the choice in use).
5. The six choices.
6. The line "For" (0.2): 10 min, 30 min, 1 hour, Until I change.
7. When needed, an amber note (helper approval, too hot, after wake, helper update).
8. At the bottom, the small graph of the last 15 minutes (0.2).

The choice in use is shown in full colour with white words. The others are pale.

## The six choices

| Choice | Colour | What it does |
|---|---|---|
| Automatic | green | The Mac decides. |
| Quiet | blue | Lowest speed by default; from 0.2 the owner's own Quiet percentage (0 % to 40 %, default 0 % = lowest speed). From 0.3, while the chip is cool, the fans may rest (see below); the Quiet speed is held again as soon as the Mac runs them faster. |
| Cool | blue | Half speed by default (50 % of the way from lowest to top); from 0.2 the owner's own Cool percentage (30 % to 90 %, default 50 %). |
| Full | blue | Top speed. |
| My speed N % | blue | A slider. 0 % is lowest, 100 % is top. Both fans together, each on its own range. Dragging the slider switches to My speed. |
| Follow temperature | coral | The speed follows the chip temperature, with two sliders (below). |

Follow temperature in detail:

- Sliders: Start (default 65, range 40 to 85) and Full (default 95, range 60 to 100). Steps of 5. They are always at least 10 apart; moving one pushes the other.
- Share = (chip - Start) / (Full - Start), limited to 0 to 1. The speed runs from lowest to top by that share.
- The chip temperature is smoothed over the last 3 readings.
- A new speed is sent only if it differs from the last one by 100 turns or more.

## Your own Quiet and Cool (0.2)

Settings has "Your speeds": Quiet from 0 % to 40 % (default 0 % = lowest speed) and Cool from 30 % to 90 % (default 50 % = half speed), in steps of 5. The percentage is the share of the way from each fan's own lowest to its own top. The words under the two buttons follow: "lowest speed", "half speed", or for example "40 % speed".

## Quiet lets the fans stop (0.3)

Before 0.3 Quiet always held both fans at the Quiet speed (at least the lowest running speed, 1,499 on this Mac), while the Mac in Automatic stops its fans (0 turns) when the chip is cool (about 63°). So Automatic could be quieter than Quiet. From 0.3 the fans may stop while Quiet is on.

- The app can never set a fan below its lowest running speed, so a rest is done by giving the fans to the Mac, which stops them when it finds it cool enough. The status line then says "You decide: Quiet · fans resting". The Quiet button stays in full colour and the menu bar mark stays blue (blue = the choice is on, here Quiet including its rest). The choice in use stays Quiet.
- Rest begins: while Quiet is on and held, the chip has been at 60° or less for 30 seconds (`coolBelow` 60, `coolFor` 30 s). The app gives the fans to the Mac.
- Rest ends: the Mac runs a fan more than 150 turns faster than the Quiet speed for 4 seconds (`overBy` 150, `overFor` 4 s). The app then takes the fans again and holds them at the Quiet speed, exactly as before 0.3, so Quiet is never louder than in 0.2.
- After taking the fans again, the app holds them for at least 5 minutes (`holdAtLeast` 300 s) before a rest may begin again, so the fans do not switch back and forth.
- The rule constants are in `Core/Sources/FanMenuCore/More.swift` as `enum QuietRest` (coolBelow 60, coolFor 30 s, overBy 150 turns, overFor 4 s, holdAtLeast 300 s). One new rule test covers it.
- Switch in Settings, in "Your speeds": "Quiet lets the fans stop". On by default. Stored setting name: `quietRest` (true/false in the app's defaults). Off = Quiet behaves as in 0.2: always the Quiet speed, never stopped. Switching it off in the middle of a rest takes the fans again at once and holds the Quiet speed.
- Same with "Quiet during calls" (it switches to Quiet, so the fans may rest then too) and with the owner's own Quiet speed.
- Unchanged: all safety rules (too hot: 100° for 15 s hands back to the Mac), the "For" time still ends Quiet, battery, sleep, quit. The helper is unchanged (version 2); no new password.
- Graphs: a rest shows as the speed line going down to 0 while Quiet is on. This is true, not a fault.
- Check hook: `--pretend-chip <degrees>|real` makes the app use that chip temperature for the rest rule (instead of the real one), so a rest can be tried without waiting for a cool Mac; `real` goes back to the real reading.

## A choice for a limited time (0.2)

- The line "For" under the buttons: 10 min, 30 min, 1 hour, Until I change. It applies to every choice except Automatic. The pick in use is drawn in full colour.
- When the time is up the app gives the fans back, switches to Automatic and notes it in What happened ("The time was up: the Mac has the fans again"). The status line counts down, for example "You decide: Cool · 8 min left".
- Tapping a choice, or a time, starts the time afresh.
- The pick is remembered (default Until I change).
- A time of its own (0.3.1): a wish from another app may carry its own time (see "For other apps"). It applies to that one choice only: the end is set from it instead of from the pick, the pick in UserDefaults is not touched, and the "For" line draws the time that runs in full colour (the one of the four with the same number of seconds; none when it is not one of them) until the choice ends or changes. Rule `OutsideAsk.shown`. A tap on a time in the line while such a time runs takes over at once, also on the pick already stored. The time of its own is dropped when the fans go back to the Mac, when a call switches to Quiet, and when a choice comes back after battery, a call or sleep (those follow the pick).

## Graphs (0.2, 0.4)

- Small graph at the bottom of the panel: the last 15 minutes. Coral line = chip temperature. Blue line = fan speed (average of both fans). Dashed line at every moment the choice changed. Unchanged in 0.4 (chip + fan speed, 15 minutes).
- A tap opens the large graph in its own window, 560 x 690 points (0.4; taller than before): 15 minutes, 1 hour or 6 hours. Four graphs, top to bottom: "Chip temperature", "Graphics temperature", "Battery temperature", "Fan speed" (the speed of each fan, Left and Right). "Done" or Escape closes it. Before 0.4 there were two graphs (chip, fan speed).
- Each temperature heading shows the figure now right beside its name, then a small grey mark (the same grey as the band) with the usual range, for example "Chip temperature 56°" and "usual here 41° to 78°". The band itself carries no word. While the green line has not been learned, the Chip heading ends with the grey words "fans at full in Automatic: not seen yet".
- Words of a level line: at the right end, above the line, on a faint ground so the temperature line cannot hide them. A level line less than 13 points under the one above has its words below the line, and if that place is taken too, further in from the right.
- The names of the changes (for example "Cool", "Automatic") at the dashed lines are drawn in the Fan speed graph (0.4; before, in the Chip graph), to leave room for the level words. Dashed lines stand upright and mean the moment the choice changed; level lines are solid and flat, so the two cannot be mixed up.
- Scale (0.4): the Chip and Graphics graphs always reach up to at least 110°, the Battery graph up to at least 50° (the top is raised to fit higher readings), so the level lines are always in view. Before, the scale fitted the readings only.
- One reading every 5 seconds, also while the panel is closed, of all three temperatures (chip, graphics, battery, from 0.4) and the fan speed. Six hours are kept. The readings are saved to a file on this Mac only (`history.json`) and survive quitting the app. Readings kept before 0.4 have only the chip (`graphics` and `battery` are missing), so those graphs start empty and fill from the update on. While the Mac sleeps or the app is not running there are no readings, and the line has a gap there.

### Level lines (0.4)

Thin solid flat lines across a temperature graph, each with its words at the right end.

| Graph | Colour | Words | Where the figure comes from |
|---|---|---|---|
| Chip | amber | "Heat notice 90°" | The app's own heat notice: from 90° the notice counts its 5 minutes. |
| Chip | red | "Too hot 100°" | The app's own safety rule 1: hottest core at 100° for 15 seconds, not in Full, gives the fans back to the Mac. |
| Chip | green | "Fans at full in Automatic · seen at N°" | Learned on this Mac (below). |
| Battery | amber | "Apple's limit for the room 35°" | Apple Support, "Mac laptops operating temperature": use a Mac laptop where the surrounding air is 10 to 35 degrees. That is the room, not the battery itself, but it is the only figure Apple gives. |
| Battery | red | "Charging may stop about 44°" | Charging stopped at 44 degrees on the battery sensor in one test by Howard Oakley (eclecticlight.co, Jan 2021) on an M1 MacBook Air. An independent measurement on another Apple laptop, not an Apple figure, hence "about". |
| Graphics | none | | Apple gives no figures and the app has no rule for it. |

- The learned green line: "full" = the average fan speed (both fans) is at or above 90 % of the average top speed. The app notes the chip temperature on the reading where that first becomes true while the MAC has the fans (Automatic, or Quiet while it lets the fans rest), not while the app holds a speed. Each new time replaces the old figure. It is kept in the setting `fullSeenAt` (degrees, absent until it has happened). Until then there is no green line, and grey words beside the Chip heading say "fans at full in Automatic: not seen yet".
- The "usual" band, in all three temperature graphs: a soft grey band from the 10th to the 90th percentile of all readings kept (up to six hours), that is the range that holds the middle 80 %. It needs 360 readings (30 minutes at one every 5 seconds); before that there is no band and no "usual here" words.
- Colours: amber = a temperature that needs your eye; red = too hot, from here something protects itself (the app gives the fans back, or the battery may stop charging), used nowhere else in the app; green = the Mac decides, here the Mac itself took the fans to full; coral = temperature, the line of all three graphs; the grey band = the usual range on this Mac.
- Honest limits: Apple publishes no figure for the temperature at which the chip slows itself, at which the Mac takes the fans to full, or at which the Mac turns itself off. So there is no line for "the Mac turns itself off", because any figure would be made up. The window says so in one line at the bottom: "Apple gives no figure for when the Mac turns itself off, so there is no line for it." Measured on this Mac on 25 Nov 2026: in Automatic the fans were still at about 1,590 turns a minute with the chip at 90° to 93°.
- The helper did not change (version 2); no new password.

## Heat notice (0.2)

While the Mac decides (Automatic): when the chip has been at 90 degrees or more for 5 minutes, a notification says so, with the button "Switch to Cool". At most once every 30 minutes. Switch in Settings "Heat notice", on by default.

## Quiet during calls (0.2)

- Switch in Settings, off by default.
- When an app has used the microphone for 15 seconds (a video call; a short dictation does not count), the app switches to Quiet. Status line: "You decide: Quiet (during a call)".
- When the microphone has been free for 30 seconds, the choice from before comes back (Automatic too).
- If the owner taps a choice during the call, the tap wins and nothing is put back.
- From 0.3 the fans may rest during the call too (the call switches to Quiet; see "Quiet lets the fans stop").
- A video call warms the Mac; with the fans at their lowest it may reach the too-hot limit (safety rule 1), and then the Mac gets the fans back as always.

## On battery: the Mac decides (0.2)

Switch in Settings, on by default. When the power cable is pulled while a choice is on, the fans go back to the Mac (status line "The Mac decides (on battery)"). When the cable is back in, the choice comes back. If the owner taps a choice while on battery, the tap wins.

## What happened (0.2)

The fourth Settings tab lists the last 20 things the app did, newest first, each with its time, in plain words, for example "Cool for 10 minutes", "The time was up: the Mac has the fans again", "Too hot (101°): the Mac has the fans again", "A call began: Quiet", "On battery: the Mac has the fans again". Kept on this Mac only.

## Choice back after sleep (0.2)

Switch in Settings, off by default. Sleep still hands the fans to the Mac. With the switch on, the app puts the choice back about 5 seconds after the Mac wakes. Restart and quit always hand the fans to the Mac.

## First use and the helper

Setting fans needs administrator rights, so a small helper tool runs in the background.

- The first tap on any choice other than Automatic shows an amber note "Setting the fans needs your OK once" with the button "Allow fan control...".
- The app then shows the Mac's own password dialog. Once approved, the helper is installed and loaded. This happens once.
- If the helper is older or newer than the app expects (helper version 2 is expected from 0.1.1), the amber note "The fan helper is from an older version. It needs your OK once more." offers "Update the helper..." (the password is asked once more).
- Settings can remove the helper again (the password is asked again).

## Safety rules

1. Too hot: if the hottest processor core is at 100 degrees or more for 15 seconds while Quiet (also while it rests the fans, from 0.3), Cool, My speed or Follow is on, the app gives the fans back, switches to Automatic, shows the amber note "Too hot (101 deg). The Mac has the fans again." (with the real value) and sends a notification. Full is exempt.
2. Quit, sleep, restart: on Quit (also a polite stop signal), sleep or restart, the fans are given back. After wake the app stays on Automatic with an amber note, unless the switch "Choice back after sleep" is on (then the choice returns about 5 seconds after wake). Quit and restart always leave the app on Automatic. The choice in use is never stored.
3. Dead man's switch: the app repeats its choice every 3 seconds. If the helper hears nothing for 20 seconds it gives the fans back. With nothing to do for 60 seconds the helper ends, and the Mac starts it again when needed. From 0.2 the app also asks the helper to give the fans back the moment it starts, so after an unexpected stop the screen ("The Mac decides") and the fans agree (before, the helper could hold the old speed for up to 20 seconds).
4. Speeds are limited twice: in the app and again in the helper, each fan to its own lowest and top speed.

## What is remembered

Stored on the Mac (UserDefaults): the My speed percentage, Start, Full, the wish for Open at login, the time picked in the "For" line, the Quiet and Cool percentages, the switch `quietRest` (Quiet lets the fans stop, 0.3, default on), and the four switches (Heat notice, Quiet during calls, On battery: the Mac decides, Choice back after sleep), and from 0.4 `fullSeenAt` (the chip temperature at which the Mac last took the fans to full in Automatic; absent until it has happened). Also on this Mac only: the history file `history.json` with the graph readings (six hours; from 0.4 each reading carries the chip, `graphics` and `battery` temperatures, the fan speeds and the choice) and the What happened list (last 20). The choice in use is never stored, so the app always starts on Automatic.

## Settings window

440 x 560 points, with four drawn tabs: Settings (green), What happened, How it works (blue), What's new (coral).

- Settings: Open at login, "Your speeds" (Quiet and Cool, and from 0.3 the switch "Quiet lets the fans stop"), the four switches (Heat notice, Quiet during calls, On battery: the Mac decides, Choice back after sleep), the helper state with "Remove the helper...", the version, "Quit AMS Fan Menu", and "Done" (Escape closes the window).
- What happened: the last 20 things the app did (see above).
- Open at login uses the "keeper": a LaunchAgent, `com.schabbauer.AMSFanMenu.keeper`, that opens the app at login and after an unexpected stop, but not after Quit.
- How it works: a guide to the whole app, including the section "Signs in this app" (every mark and colour with its meaning).
- What's new: every version, newest first.

Only one copy of the app runs: the copy that started first stays.

## Diary and check hooks

- Diary: `~/Library/Logs/AMS Fan Menu/diary.log`. It keeps the newest 300 lines: starts, choices, speeds sent, notes. Nothing personal.
- Helper log: `/Library/Logs/AMS Fan Menu/helper.log`.
- Command line checks:
  - `--snapshots <folder>`: pictures of the panel, settings and menu bar states, day and night, with sample data.
  - `--graph-pictures <folder>` (0.4): pictures of the large graph with the readings really kept on this Mac, for 15 minutes, 1 hour and 6 hours, day and night. It only reads.
  - `--read`: prints the fans and temperatures, then quits.
  - `--helper-script` prints the exact steps that run with the Mac's deepest rights when fan control is allowed, then quits. It changes nothing.
  - `--choose <automatic|quiet|cool|full|mySpeed|follow>`: tells the running copy to switch, waits a moment so the message really arrives, then quits.
  - `--give-back`: asks the helper to give every fan back to the Mac, whatever the app believes, then quits.
  - `--try-speeds 3000,3000 --seconds 6`: asks the helper for these speeds once a second for that many seconds, prints each answer, gives the fans back, then quits.
  - `--open-at-login on|off|status`.
  - `--pretend-chip <degrees>|real` (0.3): makes the app use that chip temperature for the Quiet rest rule, or the real reading with `real`. For tests.
  - `--pretend-wake`, `--pretend-battery on|off`, `--pretend-call on|off` (0.2): send a distributed notification to the running copy that acts as if the Mac woke, the power cable was pulled or put back, or a call began or ended. For tests.
  - Distributed notifications: `com.schabbauer.AMSFanMenu.togglePanel` and `com.schabbauer.AMSFanMenu.openSettings`.

## For other apps (0.2)

On every change the app writes its state to `~/Library/Application Support/AMS Fan Menu/state.json` (the choice, its title, whether the app decides, when it began, when it ends, and from 0.3 `resting`, true or false: true while Quiet lets the fans rest; `choice` stays "quiet" during a rest) and posts the distributed notification `com.schabbauer.AMSFanMenu.changed`. `--choose <choice>` switches. AMS Deck Mate's fan keys use this.

The wish itself (0.3.1): the distributed notification `com.schabbauer.AMSFanMenu.choose` with the choice word as its object, `cool`, or the word, a colon and a number of seconds, `cool:600` = Cool for 600 seconds, then Automatic. Rule `OutsideAsk.parse`: the seconds are kept between 60 and 14,400 (four hours); Automatic never has a time; anything else (an unknown word, no number, zero or less, a second colon) is ignored. A wish without a time follows the pick in the "For" line, as before 0.3.1. `--choose cool:600` passes the same wish on. The diary notes "Asked from outside to switch to Cool for 10 minutes" and What happened lists "Cool for 10 minutes". AMS Deck Mate 0.19 asks for `cool:600` and `full:600`.

## How it is built

- XcodeGen (`project.yml`) generates the Xcode project. Signed with an Apple Development certificate. macOS 15 or later.
- AppKit status item with a SwiftUI popover.
- `Core/`: a Swift package, `FanMenuCore`, with the rules that need no hardware (Cool, My speed, Follow, smoothing, safety, and from 0.3 the Quiet rest rule `QuietRest`). Tested with `swift test --package-path Core`.
- `Shared/`: reading the Mac's sensors and fans, and the helper's protocol. Compiled into both the app and the helper.
- `Helper/`: the root helper tool.
- Install by the app: the Mac's password dialog (osascript, "with administrator privileges") copies the helper from `Contents/Library/HelperTools/com.schabbauer.AMSFanMenu.helper` to `/Library/PrivilegedHelperTools/`, writes `/Library/LaunchDaemons/com.schabbauer.AMSFanMenu.helper.plist` (started on demand through its Mach service) and loads it.
- The helper accepts connections only from the app (code-signing requirement: identifier com.schabbauer.AMSFanMenu, Apple-anchored, team D24ENP83QQ).
- The helper offers three calls: version, set speeds (one per fan, limited to each fan's own lowest and top), give back. Helper version: "2".
- To set fans the helper first hands over ALL fans (writes F<n>Md = 1, forced), and only then writes F<n>Tg = speed (a 4-byte float) for each. The Mac hands a fan over a few hundredths of a second after it is asked, so the helper waits for the hand-over: it looks every 0.01 s for up to 1.5 s and asks again every 0.3 s. If the mode write is still refused it may write the unlock key Ftst = 1 (this Mac has no Ftst key and needs none).
- If the Mac takes a fan back by itself, the helper notices on the next order, takes it over again and notes it in its log.
- Giving back is thorough: it writes F<n>Md = 0 for every fan (and Ftst = 0 if it was used), keeps looking for 1 more second, and gives back again any fan that turned up as held late.
- Icons: all drawn as shapes in the app (no emoji, no stock icons). App icon: a flat calm blue tile with a white hand-drawn three-blade fan.

## What is proven and what is not yet

Proven on this Mac on 24 Nov 2026 (0.1.1): a fan takes a forced speed directly, with no unlock key (this Mac has no Ftst key). Test: the left fan took 3,000 and went from about 1,520 to about 2,360 turns a minute within two seconds.

Not proven yet:

- A full choice held for minutes with both fans.
- What happens across a real sleep.
- Open at login across a real restart.
- The too-hot hand-back.
- The green line "Fans at full in Automatic" has never been seen for real: the Mac has not taken the fans to full since 0.4. Only its rule test has run.

## Version history

- 0.1 (build 1, 24 Nov 2026): first version. Menu bar fan mark, panel with live fan speeds and temperatures, six choices, one-time helper approval, safety rules, Settings with guide and What's new, diary, check hooks, rule tests.

- 0.1.1 (build 2, 24 Nov 2026): fix. Cause: in 0.1 no choice could be switched on ("the Mac refused to hand over fan 1 (answer 0)"), because the Mac hands a fan over a few hundredths of a second after the helper asks and the helper looked at once and gave up; the fan it had asked for was then left held at its last speed without the app knowing (the right fan stayed at about 1,643 turns a minute for about a minute until given back by hand). Fix: helper version 2 waits for the hand-over (every 0.01 s up to 1.5 s, asks again every 0.3 s), hands over all fans before setting speeds, gives back thoroughly (every fan, 1 more second of looking, again for any late one) and takes a fan over again if the Mac took it back. New hooks `--give-back` and `--try-speeds`; `--choose` now waits a moment before quitting. The app asks once more for the Mac's password (helper update).

- 0.2 (build 3, 24 Nov 2026): graphs (small in the panel, large in its own window with 15 minutes / 1 hour / 6 hours, readings every 5 seconds, six hours kept, saved on this Mac); a choice for a limited time ("For" line); figures on hover; own Quiet (0 to 40 %) and Cool (30 to 90 %); heat notice (90 degrees for 5 minutes, at most every 30 minutes); Quiet during calls (microphone 15 seconds on, 30 seconds off); on battery the Mac decides; What happened tab (last 20); choice back after sleep (about 5 seconds after wake); four settings tabs; new sign (dashed line); state.json and the `changed` notification for other apps; hooks `--pretend-wake`, `--pretend-battery`, `--pretend-call`. Fixed: after an unexpected stop the app said "The Mac decides" while the helper held the old speed for up to 20 seconds; the app now asks the helper to give the fans back at start. The helper did not change (version 2), so no password is needed.

- 0.3 (build 4, 24 Nov 2026): Quiet lets the fans stop. While Quiet is on and the chip has been at 60° or less for 30 seconds, the app gives the fans to the Mac, which stops them; if the Mac runs a fan more than 150 turns above the Quiet speed for 4 seconds, the app takes them again at the Quiet speed and holds them at least 5 minutes before another rest. Status line "You decide: Quiet · fans resting"; button and menu bar mark stay in full colour / blue. New switch "Quiet lets the fans stop" in "Your speeds" (setting `quietRest`, on by default; off = as in 0.2, switching off during a rest brings the Quiet speed back at once). `enum QuietRest` in `Core/Sources/FanMenuCore/More.swift`, one new rule test, `resting` key in state.json, hook `--pretend-chip <degrees>|real`. The helper did not change (version 2), so no password is needed.

- 0.3.1 (build 5, 25 Nov 2026): a wish from another app may carry a time of its own (`cool:600`), for the Cool and Full keys of AMS Deck Mate 0.19 that last 10 minutes; the "For" line shows the time that runs; the pick is never changed by it; rule `OutsideAsk` with one data test (26 rule tests). The helper did not change (version 2), so no password is needed.
- 0.4 (build 6, 25 Nov 2026): graphs for all three temperatures. History keeps chip, graphics and battery (six hours, every 5 seconds). The large graph window has four graphs (Chip, Graphics, Battery temperature, Fan speed), 560 x 690 points. Level lines: chip amber 90° and red 100°, battery amber 35° and red about 44°, a green chip line learned where the Mac itself takes the fans to full (setting `fullSeenAt`); a grey "usual" band (10th to 90th percentile, after 360 readings); scale tops 110° and 50°; choice names moved to the Fan speed graph; one line saying there is no line for when the Mac turns itself off. New signs: red line, grey band. The helper did not change (version 2), so no password is needed.

## Icon files

The fan is drawn once as numbers (three blades around a hub on a 24-point grid) and used in three places: `App/Sources/Icons.swift` (panel, menu bar, signs), `Tools/make-icon.py` with `Tools/fan-outline.swift` (the app icon; the line is turned into a filled outline because the Mac's layered icon fills whatever it is given), and the mark `fan` in the AMS Icon Library.
