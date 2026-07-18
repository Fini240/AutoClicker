import Cocoa
import Carbon.HIToolbox

// MARK: - Theme

@MainActor
enum Theme {
    static let background   = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    static let card         = NSColor(srgbRed: 0.165, green: 0.165, blue: 0.18, alpha: 1)
    static let control      = NSColor(srgbRed: 0.23, green: 0.23, blue: 0.245, alpha: 1)
    static let segmentOn    = NSColor(srgbRed: 0.24, green: 0.38, blue: 0.33, alpha: 1)
    static let mint         = NSColor(srgbRed: 0.66, green: 0.95, blue: 0.85, alpha: 1)
    static let mintDark     = NSColor(srgbRed: 0.05, green: 0.20, blue: 0.15, alpha: 1)
    static let red          = NSColor(srgbRed: 0.95, green: 0.66, blue: 0.63, alpha: 1)
    static let redDark      = NSColor(srgbRed: 0.25, green: 0.07, blue: 0.05, alpha: 1)
    static let textPrimary  = NSColor.white
    static let textSecondary = NSColor(calibratedWhite: 0.62, alpha: 1)
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Key names

let keyNames: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
    11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
    34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
    18: "1", 19: "2", 20: "3", 21: "4", 22: "5", 23: "6", 25: "9", 26: "7", 28: "8", 29: "0",
    27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`", 42: "\\",
    49: "Space", 48: "Tab",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
    101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
    123: "←", 124: "→", 125: "↓", 126: "↑",
]

let fKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113]

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    // Controls that need live updates
    var leftSegment: NSButton!
    var rightSegment: NSButton!
    var cpsNumber: NSTextField!
    var intervalCaption: NSTextField!
    var clicksNumber: NSTextField!
    var startContainer: NSView!
    var startLabel: NSTextField!
    var badgeLabel: NSTextField!
    var shortcutPill: NSButton!
    var statusDot: NSTextField!
    var statusText: NSTextField!

    var timer: Timer?
    var clickCount = 0
    var useRightButton = false

    let cpsSteps: [Double] = [1, 2, 5, 10, 20, 25, 50, 100]
    var cpsIndex = 3 // 10 clicks/sec

    // Hotkey (default: Command + D)
    var hotKeyCode: UInt16 = 2
    var hotKeyMods: NSEvent.ModifierFlags = [.command]
    var hotKeyRef: EventHotKeyRef?
    var isRecording = false

    var cps: Double { cpsSteps[cpsIndex] }
    var intervalMs: Double { 1000.0 / cps }
    var isRunning: Bool { timer != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        buildStatusItem()
        buildPopover()
        installRecordingMonitor()
        installHotkeyHandler()
        registerHotkey()
        promptForAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopTimer()
    }

    // MARK: - Settings

    func loadSettings() {
        let d = UserDefaults.standard
        if d.object(forKey: "hotKeyCode") != nil {
            hotKeyCode = UInt16(d.integer(forKey: "hotKeyCode"))
            hotKeyMods = NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: "hotKeyMods")))
        }
        if d.object(forKey: "cpsIndex") != nil {
            cpsIndex = min(max(d.integer(forKey: "cpsIndex"), 0), cpsSteps.count - 1)
        }
        useRightButton = d.bool(forKey: "useRightButton")
    }

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(Int(hotKeyCode), forKey: "hotKeyCode")
        d.set(Int(hotKeyMods.rawValue), forKey: "hotKeyMods")
        d.set(cpsIndex, forKey: "cpsIndex")
        d.set(useRightButton, forKey: "useRightButton")
    }

    // MARK: - Hotkey helpers

    func normalized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift])
    }

    func shortcutDisplay() -> String {
        var s = ""
        if hotKeyMods.contains(.control) { s += "⌃" }
        if hotKeyMods.contains(.option) { s += "⌥" }
        if hotKeyMods.contains(.shift) { s += "⇧" }
        if hotKeyMods.contains(.command) { s += "⌘" }
        s += keyNames[hotKeyCode] ?? "Key \(hotKeyCode)"
        return s
    }

    func matchesHotkey(_ event: NSEvent) -> Bool {
        event.keyCode == hotKeyCode && normalized(event.modifierFlags) == hotKeyMods
    }

    // MARK: - Status item

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cursorarrow.click",
                                           accessibilityDescription: "AutoClicker")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refreshUI()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        isRecording = false
    }

    // MARK: - Popover UI

    func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight,
                   color: NSColor, frame: NSRect, align: NSTextAlignment = .center) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.alignment = align
        l.frame = frame
        return l
    }

    func makeCard(frame: NSRect, in parent: NSView) -> NSView {
        let v = NSView(frame: frame)
        v.wantsLayer = true
        v.layer?.backgroundColor = Theme.card.cgColor
        v.layer?.cornerRadius = 14
        parent.addSubview(v)
        return v
    }

    func makeFlatButton(_ title: String, size: CGFloat, frame: NSRect,
                        action: Selector) -> NSButton {
        let b = NSButton(frame: frame)
        b.isBordered = false
        b.wantsLayer = true
        b.target = self
        b.action = action
        setTitle(b, title, size: size, color: Theme.textSecondary)
        return b
    }

    func setTitle(_ b: NSButton, _ title: String, size: CGFloat, color: NSColor,
                  weight: NSFont.Weight = .semibold) {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: p,
        ])
    }

    func buildPopover() {
        let width: CGFloat = 300
        let height: CGFloat = 338
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.background.cgColor
        root.appearance = NSAppearance(named: .darkAqua)

        // Segmented pill: Left | Right
        let segContainer = NSView(frame: NSRect(x: 16, y: 16, width: 268, height: 38))
        segContainer.wantsLayer = true
        segContainer.layer?.backgroundColor = Theme.card.cgColor
        segContainer.layer?.cornerRadius = 12
        root.addSubview(segContainer)

        leftSegment = makeFlatButton("Left", size: 15, frame: NSRect(x: 3, y: 3, width: 131, height: 32),
                                     action: #selector(pickLeft))
        leftSegment.layer?.cornerRadius = 9
        rightSegment = makeFlatButton("Right", size: 15, frame: NSRect(x: 134, y: 3, width: 131, height: 32),
                                      action: #selector(pickRight))
        rightSegment.layer?.cornerRadius = 9
        segContainer.addSubview(leftSegment)
        segContainer.addSubview(rightSegment)

        // Card 1: clicks per second with - / +
        let speedCard = makeCard(frame: NSRect(x: 16, y: 66, width: 128, height: 112), in: root)
        speedCard.addSubview(makeLabel("Clicks / sec", size: 12, weight: .medium,
                                       color: Theme.textSecondary,
                                       frame: NSRect(x: 0, y: 12, width: 128, height: 16)))
        cpsNumber = makeLabel("10", size: 34, weight: .bold, color: Theme.textPrimary,
                              frame: NSRect(x: 24, y: 34, width: 80, height: 42))
        speedCard.addSubview(cpsNumber)
        intervalCaption = makeLabel("100 ms", size: 11, weight: .regular,
                                    color: Theme.textSecondary,
                                    frame: NSRect(x: 0, y: 82, width: 128, height: 14))
        speedCard.addSubview(intervalCaption)

        let minus = makeFlatButton("−", size: 15, frame: NSRect(x: 8, y: 44, width: 24, height: 24),
                                   action: #selector(slower))
        minus.layer?.backgroundColor = Theme.control.cgColor
        minus.layer?.cornerRadius = 12
        speedCard.addSubview(minus)

        let plus = makeFlatButton("+", size: 15, frame: NSRect(x: 96, y: 44, width: 24, height: 24),
                                  action: #selector(faster))
        plus.layer?.backgroundColor = Theme.control.cgColor
        plus.layer?.cornerRadius = 12
        speedCard.addSubview(plus)

        // Card 2: live click counter
        let clicksCard = makeCard(frame: NSRect(x: 156, y: 66, width: 128, height: 112), in: root)
        clicksCard.addSubview(makeLabel("Clicks", size: 12, weight: .medium,
                                        color: Theme.textSecondary,
                                        frame: NSRect(x: 0, y: 12, width: 128, height: 16)))
        clicksNumber = makeLabel("0", size: 34, weight: .bold,
                                 color: Theme.textSecondary,
                                 frame: NSRect(x: 4, y: 34, width: 120, height: 42))
        clicksCard.addSubview(clicksNumber)

        // Start / stop bar
        startContainer = NSView(frame: NSRect(x: 16, y: 190, width: 268, height: 48))
        startContainer.wantsLayer = true
        startContainer.layer?.backgroundColor = Theme.mint.cgColor
        startContainer.layer?.cornerRadius = 14
        root.addSubview(startContainer)

        startLabel = makeLabel("Start clicking", size: 17, weight: .bold,
                               color: Theme.mintDark,
                               frame: NSRect(x: 0, y: 14, width: 268, height: 22))
        startContainer.addSubview(startLabel)

        badgeLabel = makeLabel("⌘D", size: 12, weight: .bold, color: Theme.mintDark,
                               frame: NSRect(x: 218, y: 13, width: 38, height: 22))
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.14).cgColor
        badgeLabel.layer?.cornerRadius = 6
        startContainer.addSubview(badgeLabel)

        let clickGR = NSClickGestureRecognizer(target: self, action: #selector(toggleClicked))
        startContainer.addGestureRecognizer(clickGR)

        // Shortcut row
        root.addSubview(makeLabel("Shortcut", size: 12, weight: .medium, color: Theme.textSecondary,
                                  frame: NSRect(x: 16, y: 256, width: 100, height: 16), align: .left))
        shortcutPill = makeFlatButton("⌘D", size: 12, frame: NSRect(x: 164, y: 250, width: 120, height: 28),
                                      action: #selector(beginRecording))
        shortcutPill.layer?.backgroundColor = Theme.card.cgColor
        shortcutPill.layer?.cornerRadius = 9
        shortcutPill.layer?.borderWidth = 1
        shortcutPill.layer?.borderColor = NSColor.clear.cgColor
        root.addSubview(shortcutPill)

        // Bottom row: status + quit
        statusDot = makeLabel("●", size: 11, weight: .bold, color: Theme.textSecondary,
                              frame: NSRect(x: 16, y: 302, width: 14, height: 16), align: .left)
        root.addSubview(statusDot)
        statusText = makeLabel("Idle", size: 12, weight: .medium, color: Theme.textSecondary,
                               frame: NSRect(x: 32, y: 301, width: 160, height: 16), align: .left)
        root.addSubview(statusText)

        let quit = makeFlatButton("Quit", size: 12, frame: NSRect(x: 224, y: 295, width: 60, height: 28),
                                  action: #selector(quitApp))
        quit.layer?.backgroundColor = Theme.card.cgColor
        quit.layer?.cornerRadius = 9
        root.addSubview(quit)

        let vc = NSViewController()
        vc.view = root
        popover = NSPopover()
        popover.contentViewController = vc
        popover.contentSize = NSSize(width: width, height: height)
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        refreshUI()
    }

    // MARK: - UI state

    func refreshUI() {
        // Segments
        leftSegment.layer?.backgroundColor = useRightButton ? NSColor.clear.cgColor : Theme.segmentOn.cgColor
        rightSegment.layer?.backgroundColor = useRightButton ? Theme.segmentOn.cgColor : NSColor.clear.cgColor
        setTitle(leftSegment, "Left", size: 15, color: useRightButton ? Theme.textSecondary : Theme.mint)
        setTitle(rightSegment, "Right", size: 15, color: useRightButton ? Theme.mint : Theme.textSecondary)

        // Speed card
        cpsNumber.stringValue = cps == cps.rounded() ? String(format: "%.0f", cps) : String(format: "%.1f", cps)
        intervalCaption.stringValue = String(format: "%.0f ms", intervalMs)

        // Clicks card
        clicksNumber.stringValue = "\(clickCount)"
        clicksNumber.textColor = isRunning ? Theme.mint : Theme.textSecondary

        // Start bar + hotkey badge
        startContainer.layer?.backgroundColor = (isRunning ? Theme.red : Theme.mint).cgColor
        startLabel.stringValue = isRunning ? "Stop clicking" : "Start clicking"
        startLabel.textColor = isRunning ? Theme.redDark : Theme.mintDark
        badgeLabel.textColor = isRunning ? Theme.redDark : Theme.mintDark
        let badgeText = shortcutDisplay()
        badgeLabel.stringValue = badgeText
        let badgeWidth = (badgeText as NSString).size(withAttributes: [.font: badgeLabel.font!]).width + 14
        badgeLabel.frame = NSRect(x: 268 - 12 - badgeWidth, y: 13, width: badgeWidth, height: 22)

        // Shortcut pill
        if isRecording {
            setTitle(shortcutPill, "Press keys…", size: 12, color: Theme.mint)
            shortcutPill.layer?.borderColor = Theme.mint.cgColor
        } else {
            setTitle(shortcutPill, shortcutDisplay(), size: 12, color: Theme.textPrimary)
            shortcutPill.layer?.borderColor = NSColor.clear.cgColor
        }

        // Status row
        if !AXIsProcessTrusted() {
            statusDot.textColor = .systemOrange
            statusText.stringValue = "Needs Accessibility access"
            statusText.textColor = .systemOrange
        } else if isRunning {
            statusDot.textColor = Theme.mint
            statusText.stringValue = "Clicking…"
            statusText.textColor = Theme.mint
        } else {
            statusDot.textColor = Theme.textSecondary
            statusText.stringValue = "Idle"
            statusText.textColor = Theme.textSecondary
        }

        // Menu bar icon
        statusItem.button?.image = NSImage(
            systemSymbolName: isRunning ? "cursorarrow.click.badge.clock" : "cursorarrow.click",
            accessibilityDescription: "AutoClicker")
        statusItem.button?.contentTintColor = isRunning ? Theme.mint : nil
    }

    // MARK: - Actions

    @objc func pickLeft() { useRightButton = false; saveSettings(); refreshUI() }
    @objc func pickRight() { useRightButton = true; saveSettings(); refreshUI() }

    @objc func slower() {
        if cpsIndex > 0 { cpsIndex -= 1 }
        saveSettings()
        restartIfRunning()
        refreshUI()
    }

    @objc func faster() {
        if cpsIndex < cpsSteps.count - 1 { cpsIndex += 1 }
        saveSettings()
        restartIfRunning()
        refreshUI()
    }

    @objc func beginRecording() {
        isRecording.toggle()
        refreshUI()
    }

    @objc func quitApp() { NSApp.terminate(nil) }

    @objc func toggleClicked() {
        if isRunning {
            stopTimer()
        } else {
            guard AXIsProcessTrusted() else {
                promptForAccessibilityIfNeeded()
                refreshUI()
                return
            }
            clickCount = 0
            startTimer()
        }
        refreshUI()
    }

    func restartIfRunning() {
        if isRunning {
            stopTimer()
            startTimer()
        }
    }

    // MARK: - Global hotkey (Carbon RegisterEventHotKey — works system-wide, no permission needed)

    func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    func registerHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x41434C4B), id: 1) // 'ACLK'
        RegisterEventHotKey(UInt32(hotKeyCode), carbonModifiers(hotKeyMods), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func installHotkeyHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated {
                delegate.hotkeyPressed()
            }
            return noErr
        }, 1, &eventType, selfPtr, nil)
    }

    func hotkeyPressed() {
        if isRecording {
            // Pressing the current combo while recording keeps it and just ends recording
            isRecording = false
            refreshUI()
            return
        }
        toggleClicked()
    }

    // Local monitor only captures keystrokes while recording a new shortcut
    func installRecordingMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                if self.isRecording {
                    self.handleRecording(event)
                    return nil
                }
                return event
            }
        }
    }

    func handleRecording(_ event: NSEvent) {
        if event.keyCode == 53 { // Esc cancels
            isRecording = false
            refreshUI()
            return
        }
        let mods = normalized(event.modifierFlags)
        // Plain keys would trigger while typing — require a modifier, except for F-keys
        guard fKeyCodes.contains(event.keyCode) || !mods.isEmpty else {
            setTitle(shortcutPill, "Add ⌘/⌥/⌃/⇧…", size: 12, color: .systemOrange)
            return
        }
        hotKeyCode = event.keyCode
        hotKeyMods = mods
        isRecording = false
        saveSettings()
        registerHotkey()
        refreshUI()
    }

    // MARK: - Permissions

    func promptForAccessibilityIfNeeded() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Clicking

    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: intervalMs / 1000.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.performClick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func performClick() {
        guard let pos = CGEvent(source: nil)?.location else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        let downType: CGEventType = useRightButton ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = useRightButton ? .rightMouseUp : .leftMouseUp
        let button: CGMouseButton = useRightButton ? .right : .left

        CGEvent(mouseEventSource: src, mouseType: downType,
                mouseCursorPosition: pos, mouseButton: button)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: upType,
                mouseCursorPosition: pos, mouseButton: button)?.post(tap: .cghidEventTap)

        clickCount += 1
        if popover.isShown {
            clicksNumber.stringValue = "\(clickCount)"
        }
    }
}

@main
@MainActor
struct AutoClickerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
