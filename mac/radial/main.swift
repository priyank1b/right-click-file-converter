// Right-Click File Converter for macOS - radial ring menu
//
//   RadialMenu --tray            menu-bar app; press Control+Option+C in Finder to open the ring
//   RadialMenu --pick <files>    show the ring for these files (used by the Finder Quick Action)
//
// Build:  swiftc -O main.swift -o RadialMenu        (needs the Xcode Command Line Tools)
// All conversion work is done by convert.sh; this app only shows the ring.

import Cocoa
import Carbon.HIToolbox

let appDir = NSHomeDirectory() + "/Library/Application Support/RightClickConverter"
let convertScript = appDir + "/convert.sh"
let launchAgentPath = NSHomeDirectory() + "/Library/LaunchAgents/com.rightclickconverter.radial.plist"

// MARK: - helpers

func runCapture(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

func finderSelection() -> [String] {
    let script = "tell application \"Finder\"\n" +
        "set out to \"\"\n" +
        "repeat with f in (get selection)\n" +
        "set out to out & POSIX path of (f as alias) & linefeed\n" +
        "end repeat\n" +
        "return out\n" +
        "end tell"
    let text = runCapture("/usr/bin/osascript", ["-e", script])
    return text.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
}

func isFile(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
}

// MARK: - the ring

final class RingView: NSView {
    static let innerR: CGFloat = 62
    static let outerR: CGFloat = 150
    static let pad: CGFloat = 14
    static var side: CGFloat { return (outerR + pad) * 2 }

    let targets: [String]
    let subtitle: String
    var hover: Int = -1 { didSet { if hover != oldValue { needsDisplay = true } } }
    var onChoose: ((String?) -> Void)?

    init(targets: [String], subtitle: String) {
        self.targets = targets
        self.subtitle = subtitle
        super.init(frame: NSRect(x: 0, y: 0, width: RingView.side, height: RingView.side))
        let blur = NSVisualEffectView(frame: bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        let pad = RingView.pad
        blur.maskImage = NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: pad, dy: pad)).fill()
            return true
        }
        addSubview(blur)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    var center: NSPoint { return NSPoint(x: bounds.midX, y: bounds.midY) }
    var step: CGFloat { return 360.0 / CGFloat(max(targets.count, 1)) }

    func hitIndex(_ p: NSPoint) -> Int {
        let dx = p.x - center.x, dy = p.y - center.y
        let dist = (dx * dx + dy * dy).squareRoot()
        if dist < RingView.innerR || dist > RingView.outerR { return -1 }
        let angle = atan2(dy, dx) * 180 / CGFloat.pi          // 0 = east, counter-clockwise
        var theta = 90 - angle                                  // 0 = north, clockwise
        while theta < 0 { theta += 360 }
        while theta >= 360 { theta -= 360 }
        let i = Int(theta / step)
        return min(i, targets.count - 1)
    }

    func slicePath(_ i: Int) -> NSBezierPath {
        let gap: CGFloat = 1.2
        let a0 = 90 - CGFloat(i) * step - gap / 2
        let a1 = 90 - CGFloat(i + 1) * step + gap / 2
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: RingView.outerR, startAngle: a0, endAngle: a1, clockwise: true)
        path.appendArc(withCenter: center, radius: RingView.innerR, startAngle: a1, endAngle: a0, clockwise: false)
        path.close()
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<targets.count {
            let path = slicePath(i)
            if i == hover {
                NSColor.controlAccentColor.withAlphaComponent(0.88).setFill()
            } else {
                NSColor.white.withAlphaComponent(0.10).setFill()
            }
            path.fill()
            NSColor.white.withAlphaComponent(i == hover ? 0.5 : 0.18).setStroke()
            path.lineWidth = 1
            path.stroke()

            let mid = (90 - (CGFloat(i) + 0.5) * step) * CGFloat.pi / 180
            let r = (RingView.innerR + RingView.outerR) / 2
            let p = NSPoint(x: center.x + cos(mid) * r, y: center.y + sin(mid) * r)
            drawText(targets[i].uppercased(), at: p, size: 13, weight: .semibold, alpha: 1)
        }
        // outer rim and inner hub
        NSColor.white.withAlphaComponent(0.3).setStroke()
        let rim = NSBezierPath(ovalIn: NSRect(x: center.x - RingView.outerR, y: center.y - RingView.outerR,
                                              width: RingView.outerR * 2, height: RingView.outerR * 2))
        rim.lineWidth = 1.2
        rim.stroke()
        let hub = NSBezierPath(ovalIn: NSRect(x: center.x - RingView.innerR + 6, y: center.y - RingView.innerR + 6,
                                              width: (RingView.innerR - 6) * 2, height: (RingView.innerR - 6) * 2))
        NSColor.black.withAlphaComponent(0.25).setFill()
        hub.fill()

        drawText(subtitle, at: NSPoint(x: center.x, y: center.y + 22), size: 11, weight: .regular, alpha: 0.7)
        let big = hover >= 0 ? targets[hover].uppercased() : "Convert to"
        drawText(big, at: NSPoint(x: center.x, y: center.y + 2), size: hover >= 0 ? 20 : 15, weight: .bold, alpha: 1)
        drawText(hover >= 0 ? "Click to convert" : "Pick a format", at: NSPoint(x: center.x, y: center.y - 20),
                 size: 10, weight: .regular, alpha: 0.7)
    }

    func drawText(_ s: String, at p: NSPoint, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha)
        ]
        let str = NSAttributedString(string: s, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2))
    }

    override func mouseMoved(with event: NSEvent) { hover = hitIndex(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hover = -1 }

    override func mouseDown(with event: NSEvent) {
        let i = hitIndex(convert(event.locationInWindow, from: nil))
        if i >= 0 { onChoose?(targets[i]) } else if i == -1 {
            let p = convert(event.locationInWindow, from: nil)
            let dx = p.x - center.x, dy = p.y - center.y
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist > RingView.outerR { onChoose?(nil) }   // click outside the ring cancels; the hub does nothing
        }
    }
    override func rightMouseDown(with event: NSEvent) { onChoose?(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onChoose?(nil) } else { super.keyDown(with: event) }   // Esc
    }
}

final class RingWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return false }
}

// MARK: - app

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var pickFiles: [String]? = nil          // set in --pick mode
    var statusItem: NSStatusItem?
    var window: RingWindow?
    var globalMonitor: Any?
    var busy = false
    var running: [Process] = []
    var hotKeyRef: EventHotKeyRef?

    var pickMode: Bool { return pickFiles != nil }

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let files = pickFiles {
            show(files: files)
            if window == nil && !busy { NSApp.terminate(nil) }
        } else {
            setUpTray()
            registerHotKey()
        }
    }

    // ---- tray + hotkey
    func setUpTray() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "\u{27F3}"
        let menu = NSMenu()
        menu.addItem(withTitle: "Convert selected Finder files   \u{2303}\u{2325}C", action: #selector(menuConvert), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        let login = NSMenuItem(title: "Start at login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = FileManager.default.fileExists(atPath: launchAgentPath) ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc func menuConvert() { hotkeyPressed() }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        if FileManager.default.fileExists(atPath: launchAgentPath) {
            _ = runCapture("/bin/launchctl", ["unload", launchAgentPath])
            try? FileManager.default.removeItem(atPath: launchAgentPath)
            sender.state = .off
        } else {
            let exe = appDir + "/RadialMenu"
            let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n" +
                "<plist version=\"1.0\"><dict>\n" +
                "<key>Label</key><string>com.rightclickconverter.radial</string>\n" +
                "<key>ProgramArguments</key><array><string>\(exe)</string><string>--tray</string></array>\n" +
                "<key>RunAtLoad</key><true/>\n" +
                "</dict></plist>\n"
            try? plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
            sender.state = .on
        }
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.hotkeyPressed()
            }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x52434331), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            showError("Hotkey unavailable",
                      "Control+Option+C is already used by another app. You can still use the menu-bar icon or the right-click Quick Action.")
        }
    }

    func hotkeyPressed() {
        if window != nil { closeRing(); return }
        let files = finderSelection()
        if files.isEmpty {
            showError("Convert to...", "Select one or more files in Finder first, then press Control+Option+C.")
            return
        }
        show(files: files)
    }

    // ---- showing things
    func show(files rawFiles: [String]) {
        if busy || window != nil { return }
        let files = rawFiles.filter { isFile($0) }
        if files.isEmpty { showError("Convert to...", "No file was selected."); return }
        busy = true
        let out = runCapture("/bin/bash", [convertScript, "--targets"] + files)
        busy = false
        let line = out.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last(where: { !$0.isEmpty }) ?? ""
        let parts = line.components(separatedBy: "|")
        if parts.count >= 2 && parts[0] == "err" {
            showError("Convert to...", parts[1])
            return
        }
        guard parts.count >= 3, parts[0] == "ok" else {
            showError("Convert to...", "The converter did not respond. Run install.sh again.")
            return
        }
        let targets = parts[2].split(separator: " ").map(String.init)
        let sub = files.count == 1 ? (files[0] as NSString).lastPathComponent : "\(files.count) files"
        present(targets: targets, subtitle: sub, files: files)
    }

    func present(targets: [String], subtitle: String, files: [String]) {
        let view = RingView(targets: targets, subtitle: subtitle)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let side = RingView.side
        var x = mouse.x - side / 2, y = mouse.y - side / 2
        x = min(max(x, vis.minX), vis.maxX - side)
        y = min(max(y, vis.minY), vis.maxY - side)
        let w = RingWindow(contentRect: NSRect(x: x, y: y, width: side, height: side),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .popUpMenu
        w.contentView = view
        w.acceptsMouseMovedEvents = true
        w.delegate = self
        w.alphaValue = 0
        view.onChoose = { [weak self] choice in
            guard let self = self else { return }
            self.closeRing()
            if let t = choice { self.convert(files: files, to: t) } else { self.finishIfPick() }
        }
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(view)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            w.animator().alphaValue = 1
        }, completionHandler: nil)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeRing(); self?.finishIfPick()
        }
    }

    func closeRing() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let w = window { w.delegate = nil; w.orderOut(nil) }
        window = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        if window != nil { closeRing(); finishIfPick() }
    }

    func showError(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.window.level = .floating
        alert.runModal()
        finishIfPick()
    }

    // ---- converting
    func convert(files: [String], to target: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [convertScript, "--target", target] + files
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.running.removeAll(where: { $0 === proc })
                self?.finishIfPick()
            }
        }
        do { try p.run(); running.append(p) } catch {
            showError("Convert to...", "Could not start the converter. Run install.sh again.")
        }
    }

    func finishIfPick() {
        if pickMode && window == nil && running.isEmpty && !busy { NSApp.terminate(nil) }
    }
}

// MARK: - entry point

let app = NSApplication.shared
let delegate = AppDelegate()
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--pick" { delegate.pickFiles = Array(args.dropFirst()) }
app.delegate = delegate
app.run()
