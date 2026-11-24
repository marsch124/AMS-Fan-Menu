# AMS Fan Menu

AMS Fan Menu is a small Mac menu bar app that lets you choose how fast the fans of your MacBook Pro turn. macOS has no setting for this (Macs Fan Control is the well-known app that does it). You pick one of six choices: let the Mac decide, quiet, cool, full, a speed of your own, or follow the temperature. The app also shows the fan speeds and temperatures live, and it gives the fans back to the Mac whenever anything looks unsafe.

It is a personal app, made for an Apple Silicon MacBook Pro (a 16-inch 2021, two fans), macOS 15 or later. Use it at your own risk.

## What you see

- A hand-drawn fan mark in the menu bar: black (white at night) when the Mac decides, blue when AMS Fan Menu runs the fans. No Dock icon.
- A panel that opens on click, with the live speed of the left and right fan and the chip, graphics and battery temperatures.
- Six choices: Automatic, Quiet, Cool, Full, My speed (slider), Follow temperature (two sliders).
- A Settings window with Open at login, the helper, "How it works" and "What's new".

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
