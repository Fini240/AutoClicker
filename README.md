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
- Menu bar icon turns green while clicking

## Install

Download `AutoClicker.app.zip` from the [latest release](../../releases/latest), unzip, and move `AutoClicker.app` wherever you like (e.g. `/Applications`).

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

## License

MIT — see [LICENSE](LICENSE).
