import Cocoa
import Carbon.HIToolbox

// MARK: - Theme

@MainActor
enum Theme {
    static let background    = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    static let card          = NSColor(srgbRed: 0.165, green: 0.165, blue: 0.18, alpha: 1)
    static let control       = NSColor(srgbRed: 0.23, green: 0.23, blue: 0.245, alpha: 1)
    static let segmentOn     = NSColor(srgbRed: 0.24, green: 0.38, blue: 0.33, alpha: 1)
    static let mint          = NSColor(srgbRed: 0.66, green: 0.95, blue: 0.85, alpha: 1)
    static let mintDark      = NSColor(srgbRed: 0.05, green: 0.20, blue: 0.15, alpha: 1)
    static let red           = NSColor(srgbRed: 0.95, green: 0.66, blue: 0.63, alpha: 1)
    static let redDark       = NSColor(srgbRed: 0.25, green: 0.07, blue: 0.05, alpha: 1)
    static let separator     = NSColor(calibratedWhite: 1, alpha: 0.08)
    static let textPrimary   = NSColor.white
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
    49: "Space", 48: "Tab", 36: "↩", 51: "⌫", 53: "Esc",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
    101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
    123: "←", 124: "→", 125: "↓", 126: "↑",
]

let fKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113]

func isModifierKeyCode(_ k: UInt16) -> Bool {
    [54, 55, 56, 60, 58, 61, 59, 62, 57, 63].contains(k)
}

func cgFlag(forKeyCode k: UInt16) -> CGEventFlags {
    switch k {
    case 54, 55: return .maskCommand
    case 56, 60: return .maskShift
    case 58, 61: return .maskAlternate
    case 59, 62: return .maskControl
    case 57:     return .maskAlphaShift
    default:     return []
    }
}

// MARK: - Macro model

struct MacroEvent: Codable {
    var keyCode: UInt16
    var isDown: Bool
    var isModifier: Bool
    var delay: Double // seconds to wait before firing this event
}

struct Hotkey: Codable {
    var code: UInt16
    var mods: UInt // NSEvent.ModifierFlags rawValue
}

enum HotkeyTarget { case click, record, play }

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    // Live controls
    var leftSegment, rightSegment: NSButton!
    var cpsNumber, intervalCaption, clicksNumber: NSTextField!
    var startContainer: NSView!
    var startLabel, badgeLabel: NSTextField!
    var clickPill, recordPill, playPill: NSButton!
    var macroStatus: NSTextField!
    var clearButton: NSButton!
    var statusDot, statusText: NSTextField!

    // Clicking
    var timer: Timer?
    var clickCount = 0
    var useRightButton = false
    let cpsSteps: [Double] = [1, 2, 5, 10, 20, 25, 50, 100]
    var cpsIndex = 3

    // Hotkeys (defaults: ⌘D click, ⌘R record, ⌘P play)
    var clickHK  = Hotkey(code: 2,  mods: NSEvent.ModifierFlags.command.rawValue)
    var recordHK = Hotkey(code: 15, mods: NSEvent.ModifierFlags.command.rawValue)
    var playHK   = Hotkey(code: 35, mods: NSEvent.ModifierFlags.command.rawValue)
    var clickRef, recordRef, playRef: EventHotKeyRef?

    var recordingTarget: HotkeyTarget? // which pill is capturing a new combo

    // Macro
    var macroEvents: [MacroEvent] = []
    var isCapturingMacro = false
    var macroArmed = false
    var macroLastTime: TimeInterval = 0

    // Playback (touched from background thread — guarded by lock)
    nonisolated(unsafe) var playbackCancelled = false
    let playbackLock = NSLock()
    var isPlaying = false

    var cps: Double { cpsSteps[cpsIndex] }
    var intervalMs: Double { 1000.0 / cps }
    var isRunning: Bool { timer != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        buildStatusItem()
        buildPopover()
        installMonitors()
        installHotkeyHandler()
        registerHotkeys()
        promptForAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopTimer()
    }

    // MARK: - Settings

    func loadSettings() {
        let d = UserDefaults.standard
        func loadHK(_ key: String, _ def: Hotkey) -> Hotkey {
            guard let data = d.data(forKey: key),
                  let hk = try? JSONDecoder().decode(Hotkey.self, from: data) else { return def }
            return hk
        }
        clickHK = loadHK("clickHK", clickHK)
        recordHK = loadHK("recordHK", recordHK)
        playHK = loadHK("playHK", playHK)
        if d.object(forKey: "cpsIndex") != nil {
            cpsIndex = min(max(d.integer(forKey: "cpsIndex"), 0), cpsSteps.count - 1)
        }
        useRightButton = d.bool(forKey: "useRightButton")
        if let data = d.data(forKey: "macro"),
           let m = try? JSONDecoder().decode([MacroEvent].self, from: data) {
            macroEvents = m
        }
    }

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(clickHK), forKey: "clickHK")
        d.set(try? JSONEncoder().encode(recordHK), forKey: "recordHK")
        d.set(try? JSONEncoder().encode(playHK), forKey: "playHK")
        d.set(cpsIndex, forKey: "cpsIndex")
        d.set(useRightButton, forKey: "useRightButton")
        d.set(try? JSONEncoder().encode(macroEvents), forKey: "macro")
    }

    // MARK: - Hotkey helpers

    func normalized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift])
    }

    func display(_ hk: Hotkey) -> String {
        let mods = NSEvent.ModifierFlags(rawValue: hk.mods)
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        s += keyNames[hk.code] ?? "Key \(hk.code)"
        return s
    }

    func carbonMods(_ raw: UInt) -> UInt32 {
        let f = NSEvent.ModifierFlags(rawValue: raw)
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    func registerHotkeys() {
        for ref in [clickRef, recordRef, playRef] where ref != nil {
            UnregisterEventHotKey(ref!)
        }
        clickRef = nil; recordRef = nil; playRef = nil
        let sig = OSType(0x41434C4B) // 'ACLK'
        func reg(_ hk: Hotkey, _ id: UInt32, _ out: inout EventHotKeyRef?) {
            RegisterEventHotKey(UInt32(hk.code), carbonMods(hk.mods),
                                EventHotKeyID(signature: sig, id: id),
                                GetApplicationEventTarget(), 0, &out)
        }
        reg(clickHK, 1, &clickRef)
        reg(recordHK, 2, &recordRef)
        reg(playHK, 3, &playRef)
    }

    func installHotkeyHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            let id = hkID.id
            MainActor.assumeIsolated { delegate.hotkeyFired(id: id) }
            return noErr
        }, 1, &spec, selfPtr, nil)
    }

    func hotkeyFired(id: UInt32) {
        guard recordingTarget == nil else { return } // don't fire while rebinding
        switch id {
        case 1: toggleClicked()
        case 2: toggleMacroRecording()
        case 3: togglePlay()
        default: break
        }
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
        recordingTarget = nil
    }

    // MARK: - UI builders

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

    func makeFlatButton(_ title: String, size: CGFloat, frame: NSRect, action: Selector) -> NSButton {
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

    func makePill(_ frame: NSRect, action: Selector) -> NSButton {
        let b = makeFlatButton("", size: 12, frame: frame, action: action)
        b.layer?.backgroundColor = Theme.card.cgColor
        b.layer?.cornerRadius = 9
        b.layer?.borderWidth = 1
        b.layer?.borderColor = NSColor.clear.cgColor
        return b
    }

    func buildPopover() {
        let width: CGFloat = 300
        let height: CGFloat = 476
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.background.cgColor
        root.appearance = NSAppearance(named: .darkAqua)

        // Segmented Left | Right
        let seg = NSView(frame: NSRect(x: 16, y: 16, width: 268, height: 38))
        seg.wantsLayer = true
        seg.layer?.backgroundColor = Theme.card.cgColor
        seg.layer?.cornerRadius = 12
        root.addSubview(seg)
        leftSegment = makeFlatButton("Left", size: 15, frame: NSRect(x: 3, y: 3, width: 131, height: 32),
                                     action: #selector(pickLeft))
        leftSegment.layer?.cornerRadius = 9
        rightSegment = makeFlatButton("Right", size: 15, frame: NSRect(x: 134, y: 3, width: 131, height: 32),
                                      action: #selector(pickRight))
        rightSegment.layer?.cornerRadius = 9
        seg.addSubview(leftSegment)
        seg.addSubview(rightSegment)

        // Speed card
        let speedCard = makeCard(frame: NSRect(x: 16, y: 66, width: 128, height: 112), in: root)
        speedCard.addSubview(makeLabel("Clicks / sec", size: 12, weight: .medium, color: Theme.textSecondary,
                                       frame: NSRect(x: 0, y: 12, width: 128, height: 16)))
        cpsNumber = makeLabel("10", size: 34, weight: .bold, color: Theme.textPrimary,
                              frame: NSRect(x: 24, y: 34, width: 80, height: 42))
        speedCard.addSubview(cpsNumber)
        intervalCaption = makeLabel("100 ms", size: 11, weight: .regular, color: Theme.textSecondary,
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

        // Clicks card
        let clicksCard = makeCard(frame: NSRect(x: 156, y: 66, width: 128, height: 112), in: root)
        clicksCard.addSubview(makeLabel("Clicks", size: 12, weight: .medium, color: Theme.textSecondary,
                                        frame: NSRect(x: 0, y: 12, width: 128, height: 16)))
        clicksNumber = makeLabel("0", size: 34, weight: .bold, color: Theme.textSecondary,
                                 frame: NSRect(x: 4, y: 34, width: 120, height: 42))
        clicksCard.addSubview(clicksNumber)

        // Start / stop bar
        startContainer = NSView(frame: NSRect(x: 16, y: 190, width: 268, height: 48))
        startContainer.wantsLayer = true
        startContainer.layer?.backgroundColor = Theme.mint.cgColor
        startContainer.layer?.cornerRadius = 14
        root.addSubview(startContainer)
        startLabel = makeLabel("Start clicking", size: 17, weight: .bold, color: Theme.mintDark,
                               frame: NSRect(x: 0, y: 14, width: 268, height: 22))
        startContainer.addSubview(startLabel)
        badgeLabel = makeLabel("⌘D", size: 12, weight: .bold, color: Theme.mintDark,
                               frame: NSRect(x: 218, y: 13, width: 38, height: 22))
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.14).cgColor
        badgeLabel.layer?.cornerRadius = 6
        startContainer.addSubview(badgeLabel)
        startContainer.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggleClicked)))

        // Click hotkey row
        root.addSubview(makeLabel("Click on / off", size: 12, weight: .medium, color: Theme.textSecondary,
                                  frame: NSRect(x: 16, y: 254, width: 140, height: 16), align: .left))
        clickPill = makePill(NSRect(x: 164, y: 248, width: 120, height: 28), action: #selector(recordClickHK))
        root.addSubview(clickPill)

        // Separator + macro heading
        let sep = NSView(frame: NSRect(x: 16, y: 288, width: 268, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = Theme.separator.cgColor
        root.addSubview(sep)
        root.addSubview(makeLabel("KEYBOARD MACRO", size: 11, weight: .bold, color: Theme.textSecondary,
                                  frame: NSRect(x: 16, y: 300, width: 200, height: 14), align: .left))

        // Record row
        root.addSubview(makeLabel("Record keys", size: 12, weight: .medium, color: Theme.textSecondary,
                                  frame: NSRect(x: 16, y: 328, width: 140, height: 16), align: .left))
        recordPill = makePill(NSRect(x: 164, y: 322, width: 120, height: 28), action: #selector(recordRecordHK))
        root.addSubview(recordPill)

        // Play row
        root.addSubview(makeLabel("Play sequence", size: 12, weight: .medium, color: Theme.textSecondary,
                                  frame: NSRect(x: 16, y: 362, width: 140, height: 16), align: .left))
        playPill = makePill(NSRect(x: 164, y: 356, width: 120, height: 28), action: #selector(recordPlayHK))
        root.addSubview(playPill)

        // Macro status + clear
        macroStatus = makeLabel("No macro recorded", size: 12, weight: .medium, color: Theme.textSecondary,
                                frame: NSRect(x: 16, y: 396, width: 190, height: 16), align: .left)
        root.addSubview(macroStatus)
        clearButton = makeFlatButton("Clear", size: 12, frame: NSRect(x: 224, y: 390, width: 60, height: 28),
                                     action: #selector(clearMacro))
        clearButton.layer?.backgroundColor = Theme.card.cgColor
        clearButton.layer?.cornerRadius = 9
        root.addSubview(clearButton)

        // Bottom status + quit
        statusDot = makeLabel("●", size: 11, weight: .bold, color: Theme.textSecondary,
                              frame: NSRect(x: 16, y: 440, width: 14, height: 16), align: .left)
        root.addSubview(statusDot)
        statusText = makeLabel("Idle", size: 12, weight: .medium, color: Theme.textSecondary,
                               frame: NSRect(x: 32, y: 439, width: 160, height: 16), align: .left)
        root.addSubview(statusText)
        let quit = makeFlatButton("Quit", size: 12, frame: NSRect(x: 224, y: 433, width: 60, height: 28),
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

    func pillTitle(_ pill: NSButton, hk: Hotkey, target: HotkeyTarget) {
        if recordingTarget == target {
            setTitle(pill, "Press keys…", size: 12, color: Theme.mint)
            pill.layer?.borderColor = Theme.mint.cgColor
        } else {
            setTitle(pill, display(hk), size: 12, color: Theme.textPrimary)
            pill.layer?.borderColor = NSColor.clear.cgColor
        }
    }

    func refreshUI() {
        leftSegment.layer?.backgroundColor = useRightButton ? NSColor.clear.cgColor : Theme.segmentOn.cgColor
        rightSegment.layer?.backgroundColor = useRightButton ? Theme.segmentOn.cgColor : NSColor.clear.cgColor
        setTitle(leftSegment, "Left", size: 15, color: useRightButton ? Theme.textSecondary : Theme.mint)
        setTitle(rightSegment, "Right", size: 15, color: useRightButton ? Theme.mint : Theme.textSecondary)

        cpsNumber.stringValue = cps == cps.rounded() ? String(format: "%.0f", cps) : String(format: "%.1f", cps)
        intervalCaption.stringValue = String(format: "%.0f ms", intervalMs)
        clicksNumber.stringValue = "\(clickCount)"
        clicksNumber.textColor = isRunning ? Theme.mint : Theme.textSecondary

        startContainer.layer?.backgroundColor = (isRunning ? Theme.red : Theme.mint).cgColor
        startLabel.stringValue = isRunning ? "Stop clicking" : "Start clicking"
        startLabel.textColor = isRunning ? Theme.redDark : Theme.mintDark
        badgeLabel.textColor = isRunning ? Theme.redDark : Theme.mintDark
        let badgeText = display(clickHK)
        badgeLabel.stringValue = badgeText
        let bw = (badgeText as NSString).size(withAttributes: [.font: badgeLabel.font!]).width + 14
        badgeLabel.frame = NSRect(x: 268 - 12 - bw, y: 13, width: bw, height: 22)

        pillTitle(clickPill, hk: clickHK, target: .click)
        pillTitle(recordPill, hk: recordHK, target: .record)
        pillTitle(playPill, hk: playHK, target: .play)

        // Macro status
        if isCapturingMacro {
            macroStatus.stringValue = "● Recording…  \(macroEvents.count) events"
            macroStatus.textColor = Theme.red
        } else if isPlaying {
            macroStatus.stringValue = "▶ Playing…"
            macroStatus.textColor = Theme.mint
        } else if macroEvents.isEmpty {
            macroStatus.stringValue = "No macro recorded"
            macroStatus.textColor = Theme.textSecondary
        } else {
            macroStatus.stringValue = "\(macroEvents.count) events recorded"
            macroStatus.textColor = Theme.textPrimary
        }

        if !AXIsProcessTrusted() {
            statusDot.textColor = .systemOrange
            statusText.stringValue = "Needs Accessibility access"
            statusText.textColor = .systemOrange
        } else if isRunning {
            statusDot.textColor = Theme.mint; statusText.stringValue = "Clicking…"; statusText.textColor = Theme.mint
        } else {
            statusDot.textColor = Theme.textSecondary; statusText.stringValue = "Idle"; statusText.textColor = Theme.textSecondary
        }

        statusItem.button?.image = NSImage(
            systemSymbolName: (isRunning || isCapturingMacro || isPlaying) ? "cursorarrow.click.badge.clock" : "cursorarrow.click",
            accessibilityDescription: "AutoClicker")
        statusItem.button?.contentTintColor = isCapturingMacro ? Theme.red : ((isRunning || isPlaying) ? Theme.mint : nil)
    }

    // MARK: - Actions

    @objc func pickLeft() { useRightButton = false; saveSettings(); refreshUI() }
    @objc func pickRight() { useRightButton = true; saveSettings(); refreshUI() }
    @objc func slower() { if cpsIndex > 0 { cpsIndex -= 1 }; saveSettings(); restartIfRunning(); refreshUI() }
    @objc func faster() { if cpsIndex < cpsSteps.count - 1 { cpsIndex += 1 }; saveSettings(); restartIfRunning(); refreshUI() }
    @objc func quitApp() { NSApp.terminate(nil) }
    @objc func clearMacro() { macroEvents = []; saveSettings(); refreshUI() }

    @objc func recordClickHK() { recordingTarget = (recordingTarget == .click) ? nil : .click; refreshUI() }
    @objc func recordRecordHK() { recordingTarget = (recordingTarget == .record) ? nil : .record; refreshUI() }
    @objc func recordPlayHK() { recordingTarget = (recordingTarget == .play) ? nil : .play; refreshUI() }

    @objc func toggleClicked() {
        if isRunning {
            stopTimer()
        } else {
            guard AXIsProcessTrusted() else { promptForAccessibilityIfNeeded(); refreshUI(); return }
            clickCount = 0
            startTimer()
        }
        refreshUI()
    }

    func restartIfRunning() { if isRunning { stopTimer(); startTimer() } }

    // MARK: - Rebinding hotkeys

    func handleHotkeyRecording(_ event: NSEvent) {
        guard let target = recordingTarget else { return }
        if event.keyCode == 53 { recordingTarget = nil; refreshUI(); return } // Esc cancels
        let mods = normalized(event.modifierFlags)
        guard fKeyCodes.contains(event.keyCode) || !mods.isEmpty else {
            if let pill = pill(for: target) { setTitle(pill, "Add ⌘/⌥/⌃/⇧…", size: 12, color: .systemOrange) }
            return
        }
        let hk = Hotkey(code: event.keyCode, mods: mods.rawValue)
        switch target {
        case .click: clickHK = hk
        case .record: recordHK = hk
        case .play: playHK = hk
        }
        recordingTarget = nil
        saveSettings()
        registerHotkeys()
        refreshUI()
    }

    func pill(for target: HotkeyTarget) -> NSButton? {
        switch target {
        case .click: return clickPill
        case .record: return recordPill
        case .play: return playPill
        }
    }

    // MARK: - Event monitors

    func installMonitors() {
        // Global: capture macro keystrokes happening in other apps
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.isCapturingMacro else { return }
                self.captureMacroEvent(event)
            }
        }
        // Local: rebinding combos + macro keystrokes typed into our own app
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                if self.recordingTarget != nil {
                    if event.type == .keyDown { self.handleHotkeyRecording(event) }
                    return nil
                }
                if self.isCapturingMacro { self.captureMacroEvent(event) }
                return event
            }
        }
    }

    // MARK: - Macro recording

    func toggleMacroRecording() {
        if isPlaying { return }
        if isCapturingMacro {
            isCapturingMacro = false
            // Drop trailing modifier noise from the stop-combo (e.g. the ⌘ of ⌘R)
            while let last = macroEvents.last, last.isModifier { macroEvents.removeLast() }
            saveSettings()
        } else {
            guard AXIsProcessTrusted() else { promptForAccessibilityIfNeeded(); refreshUI(); return }
            macroEvents = []
            isCapturingMacro = true
            // If the record hotkey uses modifiers, wait until they're released before capturing,
            // so the trigger combo itself isn't baked into the macro.
            macroArmed = NSEvent.ModifierFlags(rawValue: recordHK.mods).isEmpty
        }
        refreshUI()
    }

    func captureMacroEvent(_ event: NSEvent) {
        let mods = normalized(event.modifierFlags)
        if !macroArmed {
            if event.type == .flagsChanged && mods.isEmpty { macroArmed = true }
            return
        }
        var isDown: Bool
        var isMod = false
        switch event.type {
        case .keyDown: isDown = true
        case .keyUp: isDown = false
        case .flagsChanged:
            isMod = true
            isDown = event.modifierFlags.contains(flagFor(event.keyCode))
        default: return
        }
        let now = event.timestamp
        let delay = macroEvents.isEmpty ? 0 : min(max(now - macroLastTime, 0), 5)
        macroLastTime = now
        macroEvents.append(MacroEvent(keyCode: event.keyCode, isDown: isDown, isModifier: isMod, delay: delay))
        if popover.isShown { refreshUI() }
    }

    func flagFor(_ k: UInt16) -> NSEvent.ModifierFlags {
        switch k {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        case 57:     return .capsLock
        default:     return []
        }
    }

    // MARK: - Macro playback

    func togglePlay() {
        if isCapturingMacro { return }
        if isPlaying {
            playbackLock.lock(); playbackCancelled = true; playbackLock.unlock()
            return
        }
        guard !macroEvents.isEmpty else { return }
        guard AXIsProcessTrusted() else { promptForAccessibilityIfNeeded(); refreshUI(); return }

        isPlaying = true
        playbackLock.lock(); playbackCancelled = false; playbackLock.unlock()
        refreshUI()

        let events = macroEvents
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let src = CGEventSource(stateID: .hidSystemState)
            var flags: CGEventFlags = []
            for ev in events {
                if self.cancelled() { break }
                if ev.delay > 0 { usleep(useconds_t(ev.delay * 1_000_000)) }
                if ev.isModifier {
                    let f = cgFlag(forKeyCode: ev.keyCode)
                    if ev.isDown { flags.insert(f) } else { flags.remove(f) }
                }
                let cg = CGEvent(keyboardEventSource: src, virtualKey: ev.keyCode, keyDown: ev.isDown)
                cg?.flags = flags
                cg?.post(tap: .cghidEventTap)
            }
            DispatchQueue.main.async {
                self.isPlaying = false
                self.refreshUI()
            }
        }
    }

    nonisolated func cancelled() -> Bool {
        playbackLock.lock(); defer { playbackLock.unlock() }
        return playbackCancelled
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

    func stopTimer() { timer?.invalidate(); timer = nil }

    func performClick() {
        guard let pos = CGEvent(source: nil)?.location else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        let downType: CGEventType = useRightButton ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = useRightButton ? .rightMouseUp : .leftMouseUp
        let button: CGMouseButton = useRightButton ? .right : .left
        CGEvent(mouseEventSource: src, mouseType: downType, mouseCursorPosition: pos, mouseButton: button)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: upType, mouseCursorPosition: pos, mouseButton: button)?.post(tap: .cghidEventTap)
        clickCount += 1
        if popover.isShown { clicksNumber.stringValue = "\(clickCount)" }
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
