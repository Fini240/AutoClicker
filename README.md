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
- **Keyboard macros** — record a sequence of key presses with their real timing (which keys, how long each is held) and replay it:
  - **Record keys** hotkey (default **⌘R**) starts/stops recording
  - **Play sequence** hotkey (default **⌘P**) replays the recording
  - Both hotkeys are rebindable, and the macro is saved across restarts
- Menu bar icon turns green while clicking or playing, red while recording

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

### Keyboard macros

1. Press the **Record keys** hotkey (default **⌘R**) — the menu bar icon turns red
2. Perform the key presses you want to capture (timing and hold duration are recorded)
3. Press **⌘R** again to stop
4. Press the **Play sequence** hotkey (default **⌘P**) to replay it; press it again to stop playback early

## License

MIT — see [LICENSE](LICENSE).
