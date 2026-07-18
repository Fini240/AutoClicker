# AutoClicker

A tiny native macOS menu bar autoclicker. No dependencies, ~100 KB, written in a single Swift file with AppKit.

## Features

- Lives in the menu bar — no Dock icon, no window clutter
- Dark themed popover panel with:
  - **Left / Right** mouse button selector
  - **Clicks per second** stepper (1–100 CPS)
  - Live click counter
  - Mint **Start / Stop** button
- Customizable global hotkey to start/stop from anywhere (default **⌘D**) — click the shortcut pill in the popover and press a new combo
- Clicks wherever your cursor currently is
- **WASD movement map** — record your W/A/S/D key presses with their real timing, see the resulting path drawn as a live 2D map, then replay the exact movement:
  - **Record path** hotkey (default **⌘R**) starts/stops recording; the map updates live as you move
  - **Replay path** hotkey (default **⌘P**) replays the movement with the original timing and hold durations
  - Green dot marks the start of the path, red dot the end
  - **Loop** toggle (on the map) closes the path: after replaying, it automatically walks back to the starting point, so the movement repeats as a closed loop. The return leg is shown as a dashed line on the map.
  - Both hotkeys are rebindable, and the recorded path is saved across restarts
- Menu bar icon turns green while clicking or replaying, red while recording

## Install

Download `AutoClicker.dmg` from the [latest release](../../releases/latest), open it, and drag **AutoClicker** into the **Applications** folder. (A plain `AutoClicker.app.zip` is also attached if you prefer.)

Because the app is not notarized, macOS may block the first launch — right-click the app and choose **Open** once.

### Accessibility permission (required)

macOS requires Accessibility access before any app may simulate mouse clicks:

1. Launch AutoClicker (a prompt should appear on first start)
2. Open **System Settings → Privacy & Security → Accessibility**
3. Enable **AutoClicker**
4. Quit and relaunch the app

## Build from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh
open build/AutoClicker.app
```

## Usage

1. Click the cursor icon in the menu bar
2. Pick mouse button and speed
3. Press **Start clicking** (or the hotkey, default **⌘D**), then point your cursor where you want the clicks
4. Press the hotkey again to stop

### WASD movement map

1. Press the **Record path** hotkey (default **⌘R**) — the menu bar icon turns red
2. Move with **W / A / S / D**; the map in the popover draws your path in real time (W = up, S = down, A = left, D = right), and hold duration determines distance
3. Press **⌘R** again to stop
4. Press the **Replay path** hotkey (default **⌘P**) to replay the movement; press it again to stop early
5. Optional: turn on **Loop** (top-right of the map) to make replay return to the starting point, closing the path into a repeatable loop

The path is a visualization of the recorded key timing — replay re-sends the same W/A/S/D key presses, so it works in any app or game that reads those keys.

## License

MIT — see [LICENSE](LICENSE).
