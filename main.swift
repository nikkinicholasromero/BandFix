import Cocoa
import ServiceManagement

// BandFix — keeps the built-in display out of the drive range where its band
// fault appears, by scaling a display-wide transfer table. It never looks at
// the screen. See NOTES.md for the measurements behind this.

// ---------------------------------------------------------------- settings

let K_ON  = "enabled"
let K_CAP = "capPercent"

let DEF_CAP = 70        // the highest level confirmed for every colour tested
let MIN_CAP = 50        // a bad stored value must not be able to black out the screen
let MAX_CAP = 100

/// How far the live table's peak may exceed the expected peak before the cap
/// counts as lost. Covers rounding when the system stores the table.
let TOLERANCE: Float = 0.01

func clampCap(_ value: Int) -> Int { min(MAX_CAP, max(MIN_CAP, value)) }

// ---------------------------------------------------------------- table

struct GammaTable {
    var red: [CGGammaValue]
    var green: [CGGammaValue]
    var blue: [CGGammaValue]

    var peak: Float { max(red.max() ?? 0, green.max() ?? 0, blue.max() ?? 0) }

    /// Scales rather than clips, so highlights stay distinct from each other.
    func capped(at percent: Int) -> GammaTable {
        let k = Float(clampCap(percent)) / 100
        return GammaTable(red: red.map { $0 * k },
                          green: green.map { $0 * k },
                          blue: blue.map { $0 * k })
    }

    /// The cap has been lost when the live peak is above what it should be.
    /// Only ever true for a table that is not capped, which is what stops a
    /// reapply from compounding the dimming.
    func hasLostCap(expectedPeak: Float) -> Bool { peak > expectedPeak + TOLERANCE }

    static func read(_ display: CGDirectDisplayID) -> GammaTable? {
        let capacity: UInt32 = 1024
        var r = [CGGammaValue](repeating: 0, count: Int(capacity))
        var g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, capacity, &r, &g, &b, &count) == .success,
              count > 0 else { return nil }
        let n = Int(count)
        return GammaTable(red: Array(r[0..<n]), green: Array(g[0..<n]), blue: Array(b[0..<n]))
    }

    func write(_ display: CGDirectDisplayID) -> Bool {
        CGSetDisplayTransferByTable(display, UInt32(red.count), red, green, blue) == .success
    }
}

func builtInDisplay() -> CGDirectDisplayID? {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
    return ids[0..<Int(count)].first { CGDisplayIsBuiltin($0) != 0 }
}

// ---------------------------------------------------------------- command line

func runCheck() -> Int32 {
    var failed = 0
    func expect(_ ok: Bool, _ name: String) {
        print((ok ? "ok    " : "FAIL  ") + name)
        if !ok { failed += 1 }
    }
    let ramp = (0..<256).map { CGGammaValue($0) / 255 }
    let identity = GammaTable(red: ramp, green: ramp, blue: ramp)
    let c70 = identity.capped(at: 70)

    expect(abs(c70.peak - 0.70) < 0.0001, "70% cap gives a peak of 0.70")
    expect(c70.red[0] == 0, "black stays black")
    expect(abs(c70.green[128] - identity.green[128] * 0.7) < 0.0001, "mid values scale, not clip")
    expect(zip(c70.blue, c70.blue.dropFirst()).allSatisfy { $0 < $1 }, "levels stay distinct")
    expect(abs(identity.capped(at: 100).peak - 1) < 0.0001, "100% leaves the table unchanged")
    expect(abs(identity.capped(at: 5).peak - 0.50) < 0.0001, "a low cap is held at 50%")
    expect(abs(identity.capped(at: 500).peak - 1) < 0.0001, "a high cap is held at 100%")
    expect(identity.hasLostCap(expectedPeak: 0.7), "an uncapped table counts as lost")
    expect(!c70.hasLostCap(expectedPeak: 0.7), "a capped table does not")
    expect(!c70.capped(at: 70).hasLostCap(expectedPeak: 0.7),
           "a table capped twice is not reapplied again")
    return failed == 0 ? 0 : 1
}

func runRead() -> Int32 {
    guard let id = builtInDisplay(), let t = GammaTable.read(id) else {
        print("could not read the built-in display's table"); return 1
    }
    print(String(format: "entries %d  peak %.4f  r %.4f  g %.4f  b %.4f",
                 t.red.count, t.peak, t.red.last ?? 0, t.green.last ?? 0, t.blue.last ?? 0))
    return 0
}

func runSelfTest() -> Int32 {
    guard let id = builtInDisplay(), let original = GammaTable.read(id) else {
        print("could not read the built-in display's table"); return 1
    }
    let wanted = original.capped(at: DEF_CAP)
    guard wanted.write(id) else { print("could not write the table"); return 1 }
    usleep(300_000)
    let live = GammaTable.read(id)
    let restored = original.write(id)
    usleep(100_000)
    let after = GammaTable.read(id)

    let capHeld = live.map { abs($0.peak - wanted.peak) <= TOLERANCE } ?? false
    let back = after.map { abs($0.peak - original.peak) <= TOLERANCE } ?? false
    print(String(format: "original peak %.4f", original.peak))
    print(String(format: "expected peak %.4f, live peak %.4f: %@",
                 wanted.peak, live?.peak ?? -1, capHeld ? "ok" : "FAIL"))
    print(String(format: "after restore %.4f: %@", after?.peak ?? -1, restored && back ? "ok" : "FAIL"))
    return capHeld && restored && back ? 0 : 1
}

func runApplyAndExit() -> Int32 {
    guard let id = builtInDisplay(), let t = GammaTable.read(id),
          t.capped(at: DEF_CAP).write(id) else { print("could not apply the cap"); return 1 }
    print("applied; exiting without restoring")
    return 0
}

if CommandLine.arguments.count > 1 {
    switch CommandLine.arguments[1] {
    case "--check": exit(runCheck())
    case "--read": exit(runRead())
    case "--selftest": exit(runSelfTest())
    case "--apply-and-exit": exit(runApplyAndExit())
    default:
        print("usage: bandfix [--check | --read | --selftest | --apply-and-exit]")
        exit(2)
    }
}

// ---------------------------------------------------------------- slider row

final class SliderRow: NSView {
    let label = NSTextField(labelWithString: "")
    let slider = NSSlider()
    var onChange: ((Int) -> Void)?

    init(value: Int) {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 48))

        label.frame = NSRect(x: 16, y: 26, width: 208, height: 16)
        label.font = .systemFont(ofSize: 12)
        addSubview(label)

        slider.frame = NSRect(x: 14, y: 4, width: 212, height: 20)
        slider.minValue = Double(MIN_CAP)
        slider.maxValue = Double(MAX_CAP)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(moved)
        addSubview(slider)

        show(value)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ value: Int) {
        slider.doubleValue = Double(value)
        label.stringValue = "Maximum drive: \(value)%"
    }

    @objc private func moved() {
        let value = Int(slider.doubleValue.rounded())
        show(value)
        onChange?(value)
    }
}

// ---------------------------------------------------------------- controller

final class Controller: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let defaults = UserDefaults.standard
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    var enabledItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var sliderRow: SliderRow!

    var on = true
    var cap = DEF_CAP

    /// The table as it was before capping, and which display it belongs to.
    var original: GammaTable?
    var originalDisplay: CGDirectDisplayID?
    var watchdog: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        // two copies would each treat the other's capped table as the original
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }

        on = defaults.object(forKey: K_ON) == nil ? true : defaults.bool(forKey: K_ON)
        cap = defaults.object(forKey: K_CAP) == nil
            ? DEF_CAP : clampCap(defaults.integer(forKey: K_CAP))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        updateIcon()

        NotificationCenter.default.addObserver(
            self, selector: #selector(systemChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [NSWorkspace.didWakeNotification,
                                          NSWorkspace.screensDidWakeNotification,
                                          NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(systemChanged), name: name, object: nil)
        }

        apply()
    }

    func applicationWillTerminate(_ note: Notification) { removeCap() }

    // ------------------------------------------------------------ menu

    func buildMenu() {
        menu.delegate = self

        enabledItem = NSMenuItem(title: "Cap Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)

        sliderRow = SliderRow(value: cap)
        sliderRow.onChange = { [weak self] value in self?.setCap(value) }
        let sliderItem = NSMenuItem()
        sliderItem.view = sliderRow
        menu.addItem(sliderItem)

        menu.addItem(.separator())

        loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit BandFix",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        enabledItem.state = on ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        sliderRow.show(cap)
    }

    func updateIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: on ? "sun.max.fill" : "sun.max",
                                           accessibilityDescription: "BandFix")
    }

    @objc func toggleEnabled() {
        on.toggle()
        defaults.set(on, forKey: K_ON)
        updateIcon()
        apply()
    }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            NSLog("BandFix: login item change failed: %@", error.localizedDescription)
        }
    }

    func setCap(_ value: Int) {
        cap = clampCap(value)
        defaults.set(cap, forKey: K_CAP)
        if on { writeCap() }
    }

    // ------------------------------------------------------------ the cap

    func apply() {
        if on {
            enforce()
            startWatchdog()
        } else {
            watchdog?.invalidate()
            watchdog = nil
            removeCap()
        }
    }

    /// macOS can reset the table on its own, for example on wake or when the
    /// colour profile changes. A table above the expected peak is therefore
    /// the system's current one: adopt it as the new original and cap that,
    /// which also picks up a changed profile.
    func enforce() {
        guard on, let id = builtInDisplay(), let live = GammaTable.read(id) else { return }
        if let base = original, originalDisplay == id,
           !live.hasLostCap(expectedPeak: base.capped(at: cap).peak) {
            return
        }
        original = live
        originalDisplay = id
        writeCap()
    }

    func writeCap() {
        guard let base = original, let id = originalDisplay else { return }
        if !base.capped(at: cap).write(id) {
            NSLog("BandFix: could not write the transfer table")
        }
    }

    func removeCap() {
        if let base = original, let id = originalDisplay, !base.write(id) {
            NSLog("BandFix: could not restore the transfer table")
        }
        original = nil
        originalDisplay = nil
    }

    /// Only reads a small table, and the tolerance lets macOS group the wakeup
    /// with other work.
    func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.enforce() }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    @objc func systemChanged() {
        // the display may still be settling when these arrive
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.enforce() }
    }
}

// ---------------------------------------------------------------- launch

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
