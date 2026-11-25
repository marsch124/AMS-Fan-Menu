# AMS Fan Menu

AMS Fan Menu is a small Mac menu bar app that lets you choose how fast the fans of your MacBook Pro turn. macOS has no setting for this (Macs Fan Control is the well-known app that does it). You pick one of six choices: let the Mac decide, quiet, cool, full, a speed of your own, or follow the temperature. The app also shows the fan speeds and temperatures live, and it gives the fans back to the Mac whenever anything looks unsafe.

It is a personal app, made for an Apple Silicon MacBook Pro (a 16-inch 2021, two fans), macOS 15 or later. Use it at your own risk.

## What you see

- A hand-drawn fan mark in the menu bar: black (white at night) when the Mac decides, blue when AMS Fan Menu runs the fans. No Dock icon.
- Hovering over the mark also gives the figures (fan speeds and chip temperature).
- A panel that opens on click, with the live speed of the left and right fan and the chip, graphics and battery temperatures.
- Six choices: Automatic, Quiet, Cool, Full, My speed (slider), Follow temperature (two sliders). A "For" line makes a choice last 10 min, 30 min, 1 hour or until you change it.
- A small graph of the last 15 minutes; a tap opens a large window (15 minutes, 1 hour or 6 hours) with four graphs: chip, graphics and battery temperature, and fan speed (0.4). Level lines show where a temperature needs your eye, where it is too hot, and (learned on your Mac) where the Mac itself takes the fans to full.
- Hover the large graph: a line follows the pointer in every graph and each heading gives the figure at that moment (0.5). Pick which of six graphs show, including Storage and Case temperature. A pale blue stretch marks when a choice of yours was on.
- Power ("Whole Mac 42 W") and a second temperature line (storage and case) in the panel (0.5).
- "What happened" starts with "The last 7 days" (hottest, time at 90° or more, fans turning, your choice on) and tells whether a choice was worth it (0.5).
- Rules that act by themselves: heat notice with a level of your pick (80° to 95°), a battery heat notice, and quiet hours (Quiet between two times) (0.5).
- Charging shows in the Battery graph as a pale teal stretch; a gap in any graph says "asleep" or "not running" (0.6).
- The small graph in the panel can show the chip, battery or case temperature (Settings, "Small graph") (0.6).
- An optional notification when a timed choice ends, with the chip temperature before and after (0.6).
- Writes its newest figures to a small file every 5 seconds, so AMS Deck Mate 0.21 can show "Chip 56°" on a key (0.6).
- A Settings window with four tabs (Settings, What happened, How it works, What's new): Open at login, your own Quiet and Cool speeds, a heat notice, Quiet during calls, the Mac decides on battery, choice back after sleep, and the helper.

## Build and install

```
xcodegen generate
xcodebuild -scheme "AMS Fan Menu" -configuration Release -derivedDataPath build build
Tools/install.sh
```

Fan control needs a one-time approval with the Mac password (the first time you choose anything other than Automatic).

## Rule tests

```
swift test --package-path Core
```

The full specification is in `Docs/SPEC.md`.
