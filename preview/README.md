# HRM Read 0.2 desktop preview

Open `index.html` in a desktop browser. It is self-contained and requires no installation or build. Alternatively, from the repository run `python -m http.server 8765 --bind 127.0.0.1 --directory preview` and visit http://127.0.0.1:8765.

This recreates the SwiftUI version 0.2 screens for design review; it does not run SwiftUI or connect to Bluetooth. Native fonts, controls, scrolling and audio behavior may differ on iPhone. Keep-screen-awake and reconnection are simulated.

Use Find strap and select Garmin HRM 200. Load demo settings to populate example zones and a 150 BPM alert threshold. These are test values, not personal training recommendations. Change the heart rate slider to explore zones and the alarm. The alarm begins after two seconds above the threshold, persists at equality, and stops below it, on signal loss, disconnect, disable, or hiding the browser tab. Browser audio requires an interaction and uses the computer's audio output.

Settings persist only in this browser. Alert/display options save immediately; zone boundaries save with Save. Close discards zone edits. Reset preview clears preview settings. Nothing changes the iPhone application.

Manually verified: simulated connection, zone display, sustained maximum-HR alarm, equality retaining an active alarm, below-threshold reset, and invalid zone boundaries disabling Save.
