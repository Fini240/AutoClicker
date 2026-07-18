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
    static let green         = NSColor(srgbRed: 0.45, green: 0.85, blue: 0.55, alpha: 1)
    static let separator     = NSColor(calibratedWhite: 1, alpha: 0.08)
    static let grid          = NSColor(calibratedWhite: 1, alpha: 0.05)
    static let textPrimary   = NSColor.white
    static let textSecondary = NSColor(calibratedWhite: 0.62, alpha: 1)
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Key names / codes

let keyNames: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
    11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
    34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
    18: "1", 19: "2", 20: "3", 21: "4", 22: "5", 23: "6", 25: "9", 26: "7", 28: "8", 29: "0",
    49: "Space", 48: "Tab", 36: "↩", 51: "⌫", 53: "Esc",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
    101: "F9", 109: "F10", 103: "F11", 111: "F12",
    123: "←", 124: "→", 125: "↓", 126: "↑",
]

let fKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

let keyW: UInt16 = 13, keyA: UInt16 = 0, keyS: UInt16 = 1, keyD: UInt16 = 2
let wasdKeys: Set<UInt16> = [keyW, keyA, keyS, keyD]

// MARK: - Model

struct MoveEvent: Codable {
    var keyCode: UInt16
    var isDown: Bool
    var delay: Double // seconds since previous event
}

struct Hotkey: Codable {
    var code: UInt16
    var mods: UInt
}

enum HotkeyTarget { case click, record, play }

// MARK: - Path map view

final class PathMapView: NSView {
    var points: [CGPoint] = [] { didSet { needsDisplay = true } }
    var recording = false
    override var isFlipped: Bool { true } // y grows downward: matches S = down

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        Theme.card.setFill()
        bg.fill()

        // Faint grid
        Theme.grid.setStroke()
        let step: CGFloat = 26
        let grid = NSBezierPath()
        grid.lineWidth = 1
        var gx: CGFloat = step
        while gx < bounds.width { grid.move(to: CGPoint(x: gx, y: 6)); grid.line(to: CGPoint(x: gx, y: bounds.height - 6)); gx += step }
        var gy: CGFloat = step
        while gy < bounds.height { grid.move(to: CGPoint(x: 6, y: gy)); grid.line(to: CGPoint(x: bounds.width - 6, y: gy)); gy += step }
        grid.stroke()

        guard points.count > 1 else {
            let msg = recording ? "Move with W A S D…" : "Press Record, then move with W A S D"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: Theme.textSecondary,
            ]
            let size = (msg as NSString).size(withAttributes: attrs)
            (msg as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2,
                                               y: (bounds.height - size.height) / 2), withAttributes: attrs)
            return
        }

        // Fit path into view with padding
        let pad: CGFloat = 18
        let xs = points.map { $0.x }, ys = points.map { $0.y }
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let spanX = max(maxX - minX, 1), spanY = max(maxY - minY, 1)
        let drawW = bounds.width - 2 * pad, drawH = bounds.height - 2 * pad
        let scale = min(drawW / spanX, drawH / spanY)
        let offX = pad + (drawW - spanX * scale) / 2
        let offY = pad + (drawH - spanY * scale) / 2
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: offX + (p.x - minX) * scale, y: offY + (p.y - minY) * scale)
        }

        let line = NSBezierPath()
        line.lineWidth = 2.5
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        line.move(to: map(points[0]))
        for p in points.dropFirst() { line.line(to: map(p)) }
        Theme.mint.setStroke()
        line.stroke()

        // Start (green) and end (red) markers
        func dot(_ p: CGPoint, _ color: NSColor) {
            let r: CGFloat = 4.5
            let c = map(p)
            let path = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            color.setFill(); path.fill()
        }
        dot(points.first!, Theme.green)
        dot(points.last!, Theme.red)
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    var leftSegment, rightSegment: NSButton!
    var cpsNumber, intervalCaption, clicksNumber: NSTextField!
    var startContainer: NSView!
    var startLabel, badgeLabel: NSTextField!
    var clickPill, recordPill, playPill: NSButton!
    var mapView: PathMapView!
    var pathStatus: NSTextField!
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
    var recordingTarget: HotkeyTarget?

    // Movement recording
    var moves: [MoveEvent] = []
    var isRecordingPath = false
    var heldKeys: Set<UInt16> = []
    var lastMoveTime: TimeInterval = 0
    var eventTap: CFMachPort?
    var tapRunLoopSource: CFRunLoopSource?

    // Replay
    nonisolated(unsafe) var replayCancelled = false
    let replayLock = NSLock()
    var isReplaying = false

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

    func applicationWillTerminate(_ notification: Notification) { stopTimer() }

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
        if let data = d.data(forKey: "moves"),
           let m = try? JSONDecoder().decode([MoveEvent].self, from: data) {
            moves = m
        }
    }

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(clickHK), forKey: "clickHK")
        d.set(try? JSONEncoder().encode(recordHK), forKey: "recordHK")
        d.set(try? JSONEncoder().encode(playHK), forKey: "playHK")
        d.set(cpsIndex, forKey: "cpsIndex")
        d.set(useRightButton, forKey: "useRightButton")
        d.set(try? JSONEncoder().encode(moves), forKey: "moves")
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
        for ref in [clickRef, recordRef, playRef] where ref != nil { UnregisterEventHotKey(ref!) }
        clickRef = nil; recordRef = nil; playRef = nil
        let sig = OSType(0x41434C4B)
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
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
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
        guard recordingTarget == nil else { return }
        switch id {
        case 1: toggleClicked()
        case 2: toggleRecording()
        case 3: toggleReplay()
        default: break
        }
    }

    // MARK: - Status item

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cursorarrow.click", accessibilityDescription: "AutoClicker")
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

    func popoverDidClose(_ notification: Notification) { recordingTarget = nil }

    // MARK: - UI builders

    func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight,
                   color: NSColor, frame: NSRect, align: NSTextAlignment = .center) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color; l.alignment = align; l.frame = frame
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
        b.isBordered = false; b.wantsLayer = true; b.target = self; b.action = action
        setTitle(b, title, size: size, color: Theme.textSecondary)
        return b
    }

    func setTitle(_ b: NSButton, _ title: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .semibold) {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color, .paragraphStyle: p,
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
        let height: CGFloat = 628
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
        leftSegment = makeFlatButton("Left", size: 15, frame: NSRect(x: 3, y: 3, width: 131, height: 32), action: #selector(pickLeft))
        leftSegment.layer?.cornerRadius = 9
        rightSegment = makeFlatButton("Right", size: 15, frame: NSRect(x: 134, y: 3, width: 131, height: 32), action: #selector(pickRight))
        rightSegment.layer?.cornerRadius = 9
        seg.addSubview(leftSegment); seg.addSubview(rightSegment)

        // Speed + clicks cards
        let speedCard = makeCard(frame: NSRect(x: 16, y: 66, width: 128, height: 112), in: root)
        speedCard.addSubview(makeLabel("Clicks / sec", size: 12, weight: .medium, color: Theme.textSecondary, frame: NSRect(x: 0, y: 12, width: 128, height: 16)))
        cpsNumber = makeLabel("10", size: 34, weight: .bold, color: Theme.textPrimary, frame: NSRect(x: 24, y: 34, width: 80, height: 42))
        speedCard.addSubview(cpsNumber)
        intervalCaption = makeLabel("100 ms", size: 11, weight: .regular, color: Theme.textSecondary, frame: NSRect(x: 0, y: 82, width: 128, height: 14))
        speedCard.addSubview(intervalCaption)
        let minus = makeFlatButton("−", size: 15, frame: NSRect(x: 8, y: 44, width: 24, height: 24), action: #selector(slower))
        minus.layer?.backgroundColor = Theme.control.cgColor; minus.layer?.cornerRadius = 12
        speedCard.addSubview(minus)
        let plus = makeFlatButton("+", size: 15, frame: NSRect(x: 96, y: 44, width: 24, height: 24), action: #selector(faster))
        plus.layer?.backgroundColor = Theme.control.cgColor; plus.layer?.cornerRadius = 12
        speedCard.addSubview(plus)

        let clicksCard = makeCard(frame: NSRect(x: 156, y: 66, width: 128, height: 112), in: root)
        clicksCard.addSubview(makeLabel("Clicks", size: 12, weight: .medium, color: Theme.textSecondary, frame: NSRect(x: 0, y: 12, width: 128, height: 16)))
        clicksNumber = makeLabel("0", size: 34, weight: .bold, color: Theme.textSecondary, frame: NSRect(x: 4, y: 34, width: 120, height: 42))
        clicksCard.addSubview(clicksNumber)

        // Start / stop bar
        startContainer = NSView(frame: NSRect(x: 16, y: 190, width: 268, height: 48))
        startContainer.wantsLayer = true
        startContainer.layer?.backgroundColor = Theme.mint.cgColor
        startContainer.layer?.cornerRadius = 14
        root.addSubview(startContainer)
        startLabel = makeLabel("Start clicking", size: 17, weight: .bold, color: Theme.mintDark, frame: NSRect(x: 0, y: 14, width: 268, height: 22))
        startContainer.addSubview(startLabel)
        badgeLabel = makeLabel("⌘D", size: 12, weight: .bold, color: Theme.mintDark, frame: NSRect(x: 218, y: 13, width: 38, height: 22))
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.14).cgColor
        badgeLabel.layer?.cornerRadius = 6
        startContainer.addSubview(badgeLabel)
        startContainer.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggleClicked)))

        // Click hotkey row
        root.addSubview(makeLabel("Click on / off", size: 12, weight: .medium, color: Theme.textSecondary, frame: NSRect(x: 16, y: 254, width: 140, height: 16), align: .left))
        clickPill = makePill(NSRect(x: 164, y: 248, width: 120, height: 28), action: #selector(recordClickHK))
        root.addSubview(clickPill)

        // Separator + heading
        let sep = NSView(frame: NSRect(x: 16, y: 290, width: 268, height: 1))
        sep.wantsLayer = true; sep.layer?.backgroundColor = Theme.separator.cgColor
        root.addSubview(sep)
        root.addSubview(makeLabel("WASD MOVEMENT MAP", size: 11, weight: .bold, color: Theme.textSecondary, frame: NSRect(x: 16, y: 302, width: 220, height: 14), align: .left))

        // Map canvas
        mapView = PathMapView(frame: NSRect(x: 16, y: 324, width: 268, height: 172))
        mapView.wantsLayer = true
        root.addSubview(mapView)

        // Record + play rows
        root.addSubview(makeLabel("Record path", size: 12, weight: .medium, color: Theme.textSecondary, frame: NSRect(x: 16, y: 510, width: 140, height: 16), align: .left))
        recordPill = makePill(NSRect(x: 164, y: 504, width: 120, height: 28), action: #selector(recordRecordHK))
        root.addSubview(recordPill)
        root.addSubview(makeLabel("Replay path", size: 12, weight: .medium, color: Theme.textSecondary, frame: NSRect(x: 16, y: 544, width: 140, height: 16), align: .left))
        playPill = makePill(NSRect(x: 164, y: 538, width: 120, height: 28), action: #selector(recordPlayHK))
        root.addSubview(playPill)

        // Status + clear + quit
        pathStatus = makeLabel("No path recorded", size: 12, weight: .medium, color: Theme.textSecondary, frame: NSRect(x: 16, y: 578, width: 150, height: 16), align: .left)
        root.addSubview(pathStatus)
        let clear = makeFlatButton("Clear", size: 12, frame: NSRect(x: 160, y: 572, width: 56, height: 28), action: #selector(clearPath))
        clear.layer?.backgroundColor = Theme.card.cgColor; clear.layer?.cornerRadius = 9
        root.addSubview(clear)
        let quit = makeFlatButton("Quit", size: 12, frame: NSRect(x: 224, y: 572, width: 60, height: 28), action: #selector(quitApp))
        quit.layer?.backgroundColor = Theme.card.cgColor; quit.layer?.cornerRadius = 9
        root.addSubview(quit)

        statusDot = makeLabel("●", size: 10, weight: .bold, color: Theme.textSecondary, frame: NSRect(x: 16, y: 604, width: 12, height: 14), align: .left)
        root.addSubview(statusDot)
        statusText = makeLabel("Idle", size: 11, weight: .medium, color: Theme.textSecondary, frame: NSRect(x: 30, y: 603, width: 254, height: 14), align: .left)
        root.addSubview(statusText)

        let vc = NSViewController()
        vc.view = root
        popover = NSPopover()
        popover.contentViewController = vc
        popover.contentSize = NSSize(width: width, height: height)
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        rebuildPath()
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

        mapView.recording = isRecordingPath

        // Path status
        let presses = moves.filter { $0.isDown }.count
        let duration = moves.reduce(0.0) { $0 + $1.delay }
        if isRecordingPath {
            pathStatus.stringValue = "● Recording…  \(presses) moves"
            pathStatus.textColor = Theme.red
        } else if isReplaying {
            pathStatus.stringValue = "▶ Replaying…"
            pathStatus.textColor = Theme.mint
        } else if moves.isEmpty {
            pathStatus.stringValue = "No path recorded"
            pathStatus.textColor = Theme.textSecondary
        } else {
            pathStatus.stringValue = String(format: "%.1fs · %d moves", duration, presses)
            pathStatus.textColor = Theme.textPrimary
        }

        if !AXIsProcessTrusted() {
            statusDot.textColor = .systemOrange; statusText.stringValue = "Needs Accessibility access"; statusText.textColor = .systemOrange
        } else if isRunning {
            statusDot.textColor = Theme.mint; statusText.stringValue = "Clicking…"; statusText.textColor = Theme.mint
        } else {
            statusDot.textColor = Theme.textSecondary; statusText.stringValue = "Idle"; statusText.textColor = Theme.textSecondary
        }

        statusItem.button?.image = NSImage(
            systemSymbolName: (isRunning || isRecordingPath || isReplaying) ? "cursorarrow.click.badge.clock" : "cursorarrow.click",
            accessibilityDescription: "AutoClicker")
        statusItem.button?.contentTintColor = isRecordingPath ? Theme.red : ((isRunning || isReplaying) ? Theme.mint : nil)
    }

    // MARK: - Path building

    func rebuildPath() {
        var pos = CGPoint.zero
        var pts: [CGPoint] = [pos]
        var held: Set<UInt16> = []
        let speed = 100.0
        for ev in moves {
            let dt = ev.delay
            if dt > 0 && !held.isEmpty {
                var dx = 0.0, dy = 0.0
                if held.contains(keyW) { dy -= 1 }
                if held.contains(keyS) { dy += 1 }
                if held.contains(keyA) { dx -= 1 }
                if held.contains(keyD) { dx += 1 }
                pos.x += dx * speed * dt
                pos.y += dy * speed * dt
                pts.append(pos)
            }
            if ev.isDown { held.insert(ev.keyCode) } else { held.remove(ev.keyCode) }
        }
        mapView.points = pts.count > 1 ? pts : []
    }

    // MARK: - Actions

    @objc func pickLeft() { useRightButton = false; saveSettings(); refreshUI() }
    @objc func pickRight() { useRightButton = true; saveSettings(); refreshUI() }
    @objc func slower() { if cpsIndex > 0 { cpsIndex -= 1 }; saveSettings(); restartIfRunning(); refreshUI() }
    @objc func faster() { if cpsIndex < cpsSteps.count - 1 { cpsIndex += 1 }; saveSettings(); restartIfRunning(); refreshUI() }
    @objc func quitApp() { NSApp.terminate(nil) }
    @objc func clearPath() { moves = []; rebuildPath(); saveSettings(); refreshUI() }

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
        if event.keyCode == 53 { recordingTarget = nil; refreshUI(); return }
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

    // MARK: - Monitors

    func installMonitors() {
        // Local monitor is only for capturing a new hotkey combo typed into our popover.
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                if self.recordingTarget != nil {
                    if event.type == .keyDown { self.handleHotkeyRecording(event) }
                    return nil
                }
                return event
            }
        }
    }

    // MARK: - Global key capture (CGEvent tap — works even when our app is in the background)

    func startEventTap() -> Bool {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true); return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    MainActor.assumeIsolated {
                        if let t = delegate.eventTap { CGEvent.tapEnable(tap: t, enable: true) }
                    }
                    return Unmanaged.passUnretained(event)
                }
                if type == .keyDown || type == .keyUp {
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let isDown = (type == .keyDown)
                    DispatchQueue.main.async { delegate.captureMove(keyCode: keyCode, isDown: isDown) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else { return false }
        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapRunLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stopEventTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    // MARK: - Movement recording

    func toggleRecording() {
        if isReplaying { return }
        if isRecordingPath {
            // Release any keys still held, so replay doesn't leave a key stuck down
            for k in heldKeys { moves.append(MoveEvent(keyCode: k, isDown: false, delay: 0)) }
            heldKeys.removeAll()
            isRecordingPath = false
            stopEventTap()
            rebuildPath()
            saveSettings()
        } else {
            guard AXIsProcessTrusted(), startEventTap() else {
                promptForAccessibilityIfNeeded(); refreshUI(); return
            }
            moves = []
            heldKeys.removeAll()
            isRecordingPath = true
            rebuildPath()
        }
        refreshUI()
    }

    func captureMove(keyCode: UInt16, isDown: Bool) {
        guard isRecordingPath, wasdKeys.contains(keyCode) else { return }
        // Ignore auto-repeat keyDowns for a key already held
        if isDown && heldKeys.contains(keyCode) { return }
        if !isDown && !heldKeys.contains(keyCode) { return }

        let now = ProcessInfo.processInfo.systemUptime
        let delay = moves.isEmpty ? 0 : min(max(now - lastMoveTime, 0), 5)
        lastMoveTime = now
        moves.append(MoveEvent(keyCode: keyCode, isDown: isDown, delay: delay))
        if isDown { heldKeys.insert(keyCode) } else { heldKeys.remove(keyCode) }
        rebuildPath()
        if popover.isShown { refreshUI() }
    }

    // MARK: - Replay

    func toggleReplay() {
        if isRecordingPath { return }
        if isReplaying {
            replayLock.lock(); replayCancelled = true; replayLock.unlock()
            return
        }
        guard !moves.isEmpty else { return }
        guard AXIsProcessTrusted() else { promptForAccessibilityIfNeeded(); refreshUI(); return }

        isReplaying = true
        replayLock.lock(); replayCancelled = false; replayLock.unlock()
        refreshUI()

        let events = moves
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let src = CGEventSource(stateID: .hidSystemState)
            for ev in events {
                if self.cancelled() { break }
                if ev.delay > 0 { usleep(useconds_t(ev.delay * 1_000_000)) }
                CGEvent(keyboardEventSource: src, virtualKey: ev.keyCode, keyDown: ev.isDown)?.post(tap: .cghidEventTap)
            }
            // Safety: make sure no WASD key is left pressed
            for k in wasdKeys {
                CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: false)?.post(tap: .cghidEventTap)
            }
            DispatchQueue.main.async { self.isReplaying = false; self.refreshUI() }
        }
    }

    nonisolated func cancelled() -> Bool {
        replayLock.lock(); defer { replayLock.unlock() }
        return replayCancelled
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
