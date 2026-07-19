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
    var points: [CGPoint] = [] { didSet { needsDisplay = true } }        // full history path (drawn dim)
    var selRange: ClosedRange<Int>? { didSet { needsDisplay = true } }   // point indices of the marked section (drawn bright)
    var loopPoints: [CGPoint] = [] { didSet { needsDisplay = true } }    // dashed leg closing the section back to its start
    var marking = false
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
            let msg = "Always recording — move with W A S D"
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

        func polyline(_ range: ClosedRange<Int>, width: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            path.lineWidth = width
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.move(to: map(points[range.lowerBound]))
            for i in (range.lowerBound + 1)...range.upperBound { path.line(to: map(points[i])) }
            return path
        }

        // Full history, dim; marked section on top, bright
        Theme.mint.withAlphaComponent(marking ? 0.5 : 0.25).setStroke()
        polyline(0...(points.count - 1), width: 2).stroke()

        guard let sel = selRange, sel.lowerBound >= 0, sel.upperBound < points.count else { return }
        Theme.mint.setStroke()
        if sel.upperBound > sel.lowerBound {
            polyline(sel, width: 2.5).stroke()
        }

        // Dashed leg: with Loop on, replay walks from the section's red end back to its green start
        if !loopPoints.isEmpty {
            let dashed = NSBezierPath()
            dashed.lineWidth = 2
            dashed.lineCapStyle = .round
            dashed.setLineDash([5, 4], count: 2, phase: 0)
            dashed.move(to: map(points[sel.upperBound]))
            for p in loopPoints { dashed.line(to: map(p)) }
            Theme.mint.withAlphaComponent(0.5).setStroke()
            dashed.stroke()
        }

        // Start (green) and end (red) markers of the marked section
        func dot(_ p: CGPoint, _ color: NSColor) {
            let r: CGFloat = 4.5
            let c = map(p)
            let path = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            color.setFill(); path.fill()
        }
        dot(points[sel.lowerBound], Theme.green)
        dot(points[sel.upperBound], Theme.red)
    }
}

// MARK: - Range slider (marks a section of the history)

final class RangeSliderView: NSView {
    var lo: CGFloat = 0, hi: CGFloat = 1 // fractions of the history timeline
    var hasHistory = false
    var onChange: ((CGFloat, CGFloat) -> Void)?
    private(set) var isDragging = false
    private var activeHandle = 0 // 1 = lo, 2 = hi
    private let inset: CGFloat = 12
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let midY = bounds.height / 2
        let track = NSBezierPath(roundedRect: NSRect(x: inset, y: midY - 2, width: bounds.width - 2 * inset, height: 4), xRadius: 2, yRadius: 2)
        Theme.control.setFill(); track.fill()
        let accent = hasHistory ? Theme.mint : Theme.textSecondary
        let xl = xFor(lo), xr = xFor(hi)
        let fill = NSBezierPath(roundedRect: NSRect(x: xl, y: midY - 2, width: max(xr - xl, 0), height: 4), xRadius: 2, yRadius: 2)
        accent.withAlphaComponent(0.45).setFill(); fill.fill()
        for x in [xl, xr] {
            let r: CGFloat = 7
            accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: x - r, y: midY - r, width: 2 * r, height: 2 * r)).fill()
        }
    }

    private func xFor(_ f: CGFloat) -> CGFloat { inset + f * (bounds.width - 2 * inset) }
    private func frac(at x: CGFloat) -> CGFloat { max(0, min(1, (x - inset) / (bounds.width - 2 * inset))) }

    override func mouseDown(with event: NSEvent) {
        guard hasHistory else { return }
        let x = convert(event.locationInWindow, from: nil).x
        activeHandle = abs(x - xFor(lo)) <= abs(x - xFor(hi)) ? 1 : 2
        isDragging = true
        drag(to: x)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        drag(to: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) { isDragging = false; activeHandle = 0 }

    private func drag(to x: CGFloat) {
        let f = frac(at: x)
        if activeHandle == 1 { lo = min(f, hi) } else { hi = max(f, lo) }
        needsDisplay = true
        onChange?(lo, hi)
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

    // Movement recording: always-on rolling history + a marked section of it
    var history: [MoveEvent] = []
    var historyDuration: Double = 0
    let historyCap: Double = 180 // keep the last 3 minutes
    var moves: [MoveEvent] = []  // materialized marked section (what replay plays)
    var selStart = -1, selEnd = -1 // event-index range of the marked section in history
    var isMarking = false
    var markStartIdx = 0
    var heldKeys: Set<UInt16> = []
    var lastMoveTime: TimeInterval = 0
    var eventTap: CFMachPort?
    var tapRunLoopSource: CFRunLoopSource?
    var tapRetryTimer: Timer?
    var closeLoop = false
    var loopToggle: NSButton!
    var rangeSlider: RangeSliderView!

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
        startAlwaysOnCapture()
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
        closeLoop = d.bool(forKey: "closeLoop")
        if let data = d.data(forKey: "moves"),
           let m = try? JSONDecoder().decode([MoveEvent].self, from: data) {
            moves = m
        }
        if let data = d.data(forKey: "history"),
           let h = try? JSONDecoder().decode([MoveEvent].self, from: data) {
            history = h
            historyDuration = h.reduce(0) { $0 + $1.delay }
        }
        selStart = d.object(forKey: "selStart") != nil ? d.integer(forKey: "selStart") : -1
        selEnd = d.object(forKey: "selEnd") != nil ? d.integer(forKey: "selEnd") : -1
        if selStart < 0 || selEnd < selStart || selEnd >= history.count { selStart = -1; selEnd = -1 }
    }

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(clickHK), forKey: "clickHK")
        d.set(try? JSONEncoder().encode(recordHK), forKey: "recordHK")
        d.set(try? JSONEncoder().encode(playHK), forKey: "playHK")
        d.set(cpsIndex, forKey: "cpsIndex")
        d.set(useRightButton, forKey: "useRightButton")
        d.set(closeLoop, forKey: "closeLoop")
        d.set(try? JSONEncoder().encode(moves), forKey: "moves")
        d.set(try? JSONEncoder().encode(history), forKey: "history")
        d.set(selStart, forKey: "selStart")
        d.set(selEnd, forKey: "selEnd")
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
        case 2: toggleMarking()
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
        let height: CGFloat = 658
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

        // Loop toggle, overlaid on the map's top-right corner
        loopToggle = makeFlatButton("⟳ Loop", size: 11, frame: NSRect(x: 206, y: 332, width: 70, height: 24), action: #selector(toggleLoop))
        loopToggle.layer?.cornerRadius = 8
        root.addSubview(loopToggle)

        // Section slider: drag the handles to mark out the part of the history to replay
        rangeSlider = RangeSliderView(frame: NSRect(x: 16, y: 500, width: 268, height: 28))
        rangeSlider.onChange = { [weak self] lo, hi in self?.sliderChanged(lo: lo, hi: hi) }
        root.addSubview(rangeSlider)

        // Mark + play rows
        root.addSubview(makeLabel("Mark section", size: 12, weight: .medium, color: Theme.textSecondary, frame: NSRect(x: 16, y: 540, width: 140, height: 16), align: .left))
        recordPill = makePill(NSRect(x: 164, y: 534, width: 120, height: 28), action: #selector(recordRecordHK))
        root.addSubview(recordPill)
        root.addSubview(makeLabel("Replay section", size: 12, weight: .medium, color: Theme.textSecondary, frame: NSRect(x: 16, y: 574, width: 140, height: 16), align: .left))
        playPill = makePill(NSRect(x: 164, y: 568, width: 120, height: 28), action: #selector(recordPlayHK))
        root.addSubview(playPill)

        // Status + clear + quit
        pathStatus = makeLabel("No section marked", size: 12, weight: .medium, color: Theme.textSecondary, frame: NSRect(x: 16, y: 608, width: 150, height: 16), align: .left)
        root.addSubview(pathStatus)
        let clear = makeFlatButton("Clear", size: 12, frame: NSRect(x: 160, y: 602, width: 56, height: 28), action: #selector(clearPath))
        clear.layer?.backgroundColor = Theme.card.cgColor; clear.layer?.cornerRadius = 9
        root.addSubview(clear)
        let quit = makeFlatButton("Quit", size: 12, frame: NSRect(x: 224, y: 602, width: 60, height: 28), action: #selector(quitApp))
        quit.layer?.backgroundColor = Theme.card.cgColor; quit.layer?.cornerRadius = 9
        root.addSubview(quit)

        statusDot = makeLabel("●", size: 10, weight: .bold, color: Theme.textSecondary, frame: NSRect(x: 16, y: 634, width: 12, height: 14), align: .left)
        root.addSubview(statusDot)
        statusText = makeLabel("Idle", size: 11, weight: .medium, color: Theme.textSecondary, frame: NSRect(x: 30, y: 633, width: 254, height: 14), align: .left)
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

        mapView.marking = isMarking
        mapView.needsDisplay = true

        if !rangeSlider.isDragging {
            rangeSlider.hasHistory = history.count > 1
            if selStart >= 0, selEnd >= selStart, selEnd < history.count, historyDuration > 0 {
                var t = 0.0
                var times: [Double] = []
                times.reserveCapacity(history.count)
                for ev in history { t += ev.delay; times.append(t) }
                rangeSlider.lo = CGFloat((times[selStart] - history[selStart].delay) / historyDuration)
                rangeSlider.hi = CGFloat(times[selEnd] / historyDuration)
            } else {
                rangeSlider.lo = 0; rangeSlider.hi = 1
            }
            rangeSlider.needsDisplay = true
        }

        if closeLoop {
            loopToggle.layer?.backgroundColor = Theme.segmentOn.cgColor
            setTitle(loopToggle, "⟳ Loop", size: 11, color: Theme.mint)
        } else {
            loopToggle.layer?.backgroundColor = Theme.control.cgColor
            setTitle(loopToggle, "⟳ Loop", size: 11, color: Theme.textSecondary)
        }

        // Path status
        let presses = moves.filter { $0.isDown }.count
        let duration = moves.reduce(0.0) { $0 + $1.delay }
        if isMarking {
            pathStatus.stringValue = "● Marking… move now"
            pathStatus.textColor = Theme.red
        } else if isReplaying {
            pathStatus.stringValue = "▶ Replaying…"
            pathStatus.textColor = Theme.mint
        } else if moves.isEmpty {
            pathStatus.stringValue = history.isEmpty ? "Waiting for movement…" : "No section marked"
            pathStatus.textColor = Theme.textSecondary
        } else {
            pathStatus.stringValue = String(format: "Section %.1fs · %d moves", duration, presses)
            pathStatus.textColor = Theme.textPrimary
        }

        if !AXIsProcessTrusted() {
            statusDot.textColor = .systemOrange; statusText.stringValue = "Needs Accessibility access"; statusText.textColor = .systemOrange
        } else if isRunning {
            statusDot.textColor = Theme.mint; statusText.stringValue = "Clicking…"; statusText.textColor = Theme.mint
        } else {
            statusDot.textColor = Theme.textSecondary
            statusText.stringValue = history.isEmpty ? "Idle · recording WASD" : String(format: "Idle · %.0fs of history", historyDuration)
            statusText.textColor = Theme.textSecondary
        }

        statusItem.button?.image = NSImage(
            systemSymbolName: (isRunning || isMarking || isReplaying) ? "cursorarrow.click.badge.clock" : "cursorarrow.click",
            accessibilityDescription: "AutoClicker")
        statusItem.button?.contentTintColor = isMarking ? Theme.red : ((isRunning || isReplaying) ? Theme.mint : nil)
    }

    // MARK: - Path building

    let pathSpeed = 100.0

    // Integrate WASD holds into a 2D path; returns the polyline, the final position,
    // and for each event the index of the point reached after it.
    func integrate(_ evs: [MoveEvent]) -> (points: [CGPoint], end: CGPoint, eventPoint: [Int]) {
        var pos = CGPoint.zero
        var pts: [CGPoint] = [pos]
        var eventPoint: [Int] = []
        eventPoint.reserveCapacity(evs.count)
        var held: Set<UInt16> = []
        for ev in evs {
            let dt = ev.delay
            if dt > 0 && !held.isEmpty {
                var dx = 0.0, dy = 0.0
                if held.contains(keyW) { dy -= 1 }
                if held.contains(keyS) { dy += 1 }
                if held.contains(keyA) { dx -= 1 }
                if held.contains(keyD) { dx += 1 }
                pos.x += dx * pathSpeed * dt
                pos.y += dy * pathSpeed * dt
                pts.append(pos)
            }
            if ev.isDown { held.insert(ev.keyCode) } else { held.remove(ev.keyCode) }
            eventPoint.append(pts.count - 1)
        }
        return (pts, pos, eventPoint)
    }

    // WASD presses that walk from `end` back to the origin: X axis first, then Y.
    func returnMoves(end: CGPoint) -> [MoveEvent] {
        var evs: [MoveEvent] = []
        let tx = abs(end.x) / pathSpeed
        let ty = abs(end.y) / pathSpeed
        if tx > 0.02 {
            let key = end.x > 0 ? keyA : keyD
            evs.append(MoveEvent(keyCode: key, isDown: true, delay: 0.08))
            evs.append(MoveEvent(keyCode: key, isDown: false, delay: tx))
        }
        if ty > 0.02 {
            let key = end.y > 0 ? keyW : keyS
            evs.append(MoveEvent(keyCode: key, isDown: true, delay: 0.08))
            evs.append(MoveEvent(keyCode: key, isDown: false, delay: ty))
        }
        return evs
    }

    func rebuildPath() {
        let (pts, _, eventPoint) = integrate(history)
        guard pts.count > 1 else {
            mapView.points = []; mapView.selRange = nil; mapView.loopPoints = []
            return
        }
        mapView.points = pts
        guard selStart >= 0, selEnd >= selStart, selEnd < history.count else {
            mapView.selRange = nil; mapView.loopPoints = []
            return
        }
        let lo = selStart == 0 ? 0 : eventPoint[selStart - 1]
        let hi = eventPoint[selEnd]
        mapView.selRange = lo...hi
        let start = pts[lo], end = pts[hi]
        if closeLoop && (abs(end.x - start.x) > 0.5 || abs(end.y - start.y) > 0.5) {
            mapView.loopPoints = [CGPoint(x: start.x, y: end.y), start] // X corrected, then Y → back at section start
        } else {
            mapView.loopPoints = []
        }
    }

    // Copy the marked slice of history into a self-contained event list: keys already
    // held when the section starts get synthesized presses, keys still held at the end
    // get released, so replay can't start mid-hold or leave a key stuck down.
    func materializeSelection() {
        guard selStart >= 0, selEnd >= selStart, selEnd < history.count else { moves = []; return }
        var slice = Array(history[selStart...selEnd])
        slice[0].delay = 0
        var held: Set<UInt16> = []
        for ev in history[..<selStart] {
            if ev.isDown { held.insert(ev.keyCode) } else { held.remove(ev.keyCode) }
        }
        let lead = held.map { MoveEvent(keyCode: $0, isDown: true, delay: 0) }
        for ev in slice {
            if ev.isDown { held.insert(ev.keyCode) } else { held.remove(ev.keyCode) }
        }
        let tail = held.map { MoveEvent(keyCode: $0, isDown: false, delay: 0) }
        moves = lead + slice + tail
    }

    func index(atFraction f: CGFloat) -> Int {
        guard !history.isEmpty, historyDuration > 0 else { return -1 }
        let target = Double(f) * historyDuration
        var t = 0.0
        for (i, ev) in history.enumerated() {
            t += ev.delay
            if t >= target { return i }
        }
        return history.count - 1
    }

    func sliderChanged(lo: CGFloat, hi: CGFloat) {
        selStart = index(atFraction: lo)
        selEnd = index(atFraction: hi)
        if selStart < 0 || selEnd < selStart { selStart = -1; selEnd = -1 }
        materializeSelection()
        rebuildPath()
        saveSettings()
        refreshUI()
    }

    // MARK: - Actions

    @objc func pickLeft() { useRightButton = false; saveSettings(); refreshUI() }
    @objc func pickRight() { useRightButton = true; saveSettings(); refreshUI() }
    @objc func slower() { if cpsIndex > 0 { cpsIndex -= 1 }; saveSettings(); restartIfRunning(); refreshUI() }
    @objc func faster() { if cpsIndex < cpsSteps.count - 1 { cpsIndex += 1 }; saveSettings(); restartIfRunning(); refreshUI() }
    @objc func quitApp() { NSApp.terminate(nil) }
    @objc func clearPath() {
        history = []; historyDuration = 0
        moves = []; selStart = -1; selEnd = -1; isMarking = false
        rebuildPath(); saveSettings(); refreshUI()
    }
    @objc func toggleLoop() { closeLoop.toggle(); saveSettings(); rebuildPath(); refreshUI() }

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
                    let time = Double(event.timestamp) / 1_000_000_000 // hardware timestamp, ns → s
                    DispatchQueue.main.async { delegate.captureMove(keyCode: keyCode, isDown: isDown, at: time) }
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

    // MARK: - Movement recording (always on)

    // Capture runs from launch; retry until Accessibility is granted, then the tap sticks.
    func startAlwaysOnCapture() {
        if AXIsProcessTrusted(), startEventTap() { return }
        tapRetryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if AXIsProcessTrusted(), self.startEventTap() {
                    self.tapRetryTimer?.invalidate(); self.tapRetryTimer = nil
                    self.refreshUI()
                }
            }
        }
    }

    // ⌘R marks a section live: press once at the start, again at the end.
    func toggleMarking() {
        if isReplaying { return }
        if isMarking {
            isMarking = false
            selStart = markStartIdx
            selEnd = history.count - 1
            if selEnd < selStart { selStart = -1; selEnd = -1 }
            materializeSelection()
            rebuildPath()
            saveSettings()
        } else {
            guard AXIsProcessTrusted(), startEventTap() else {
                promptForAccessibilityIfNeeded(); refreshUI(); return
            }
            markStartIdx = history.count
            isMarking = true
        }
        refreshUI()
    }

    func captureMove(keyCode: UInt16, isDown: Bool, at time: TimeInterval) {
        guard !isReplaying, wasdKeys.contains(keyCode) else { return }
        // Ignore auto-repeat keyDowns for a key already held
        if isDown && heldKeys.contains(keyCode) { return }
        if !isDown && !heldKeys.contains(keyCode) { return }

        let delay = history.isEmpty ? 0 : min(max(time - lastMoveTime, 0), 5)
        lastMoveTime = time
        history.append(MoveEvent(keyCode: keyCode, isDown: isDown, delay: delay))
        historyDuration += delay
        trimHistory()
        if isDown { heldKeys.insert(keyCode) } else { heldKeys.remove(keyCode) }
        rebuildPath()
        if popover.isShown { refreshUI() }
    }

    // Cap the rolling history; the marked section and mark-in-progress shift with it.
    func trimHistory() {
        while historyDuration > historyCap && history.count > 1 {
            historyDuration -= history.removeFirst().delay
            selStart -= 1; selEnd -= 1
            markStartIdx = max(markStartIdx - 1, 0)
            if selStart < 0 || selEnd < 0 { selStart = -1; selEnd = -1 }
        }
    }

    // MARK: - Replay

    func toggleReplay() {
        if isMarking { return }
        if isReplaying {
            replayLock.lock(); replayCancelled = true; replayLock.unlock()
            return
        }
        guard !moves.isEmpty else { return }
        guard AXIsProcessTrusted() else { promptForAccessibilityIfNeeded(); refreshUI(); return }

        isReplaying = true
        replayLock.lock(); replayCancelled = false; replayLock.unlock()
        refreshUI()

        var events = moves
        if closeLoop {
            let (_, end, _) = integrate(moves)
            // Reposition from the recorded end point back to the start FIRST, then run the
            // loop — so replay always traces the original path from the original start point,
            // repeating without drift even when the recording doesn't end where it began.
            events = returnMoves(end: end) + moves
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let src = CGEventSource(stateID: .hidSystemState)
            // Schedule against one absolute timeline: each sleep targets start + cumulative
            // delay, so per-sleep overshoot can't accumulate and shift later events.
            let start = ProcessInfo.processInfo.systemUptime
            var due = 0.0
            for ev in events {
                if self.cancelled() { break }
                due += ev.delay
                let remaining = start + due - ProcessInfo.processInfo.systemUptime
                if remaining > 0 { usleep(useconds_t(remaining * 1_000_000)) }
                let e = CGEvent(keyboardEventSource: src, virtualKey: ev.keyCode, keyDown: ev.isDown)
                e?.flags = [] // don't inherit the still-held replay hotkey modifiers (e.g. ⌘)
                e?.post(tap: .cghidEventTap)
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
