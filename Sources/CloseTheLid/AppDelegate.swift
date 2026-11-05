import AppKit
import UserNotifications

enum LidState: Equatable {
    case passive
    case active(until: Date?)

    var isActive: Bool { if case .active = self { return true } else { return false } }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Keys {
        static let startAtLogin = "startAtLogin"
        static let batteryCutoff = "batteryCutoffEnabled"
        static let batteryThreshold = "batteryThreshold"
        static let dimScreen = "dimScreenWhenActive"
        static let savedBrightness = "savedBrightness"
    }

    private static let durations: [(String, TimeInterval?)] = [
        ("Indefinitely", nil),
        ("5 Minutes", 5 * 60),
        ("10 Minutes", 10 * 60),
        ("15 Minutes", 15 * 60),
        ("30 Minutes", 30 * 60),
        ("1 Hour", 60 * 60),
        ("2 Hours", 2 * 60 * 60),
        ("5 Hours", 5 * 60 * 60),
    ]

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var durationItems: [NSMenuItem] = []
    private var deactivateItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var batteryItem: NSMenuItem!
    private var dimItem: NSMenuItem!

    private var state: LidState = .passive
    private var selectedDurationIndex: Int?
    private var tickTimer: Timer?
    private var tickCount = 0
    private var isDeactivating = false
    private var activity: NSObjectProtocol?
    private let battery = BatteryMonitor()
    private var signalSources: [DispatchSourceSignal] = []
    private let defaults = UserDefaults.standard

    private var batteryThreshold: Int {
        let v = defaults.integer(forKey: Keys.batteryThreshold)
        return v > 0 ? v : 10
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [Keys.startAtLogin: true, Keys.batteryCutoff: true, Keys.batteryThreshold: 10, Keys.dimScreen: true])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeft
        buildMenu()
        statusItem.menu = menu

        // Always start passive. Only touch pmset if sleep is currently disabled
        // (e.g. after a crash) and never prompt for a password here.
        if PowerController.isSleepDisabled() {
            log.info("Sleep was disabled at launch; resetting")
            if !PowerController.setSleepDisabled(false) {
                // Could not reset silently: reflect reality so the user can deactivate.
                state = .active(until: nil)
            }
        }
        // Restore brightness if a previous run dimmed the screen and never restored it.
        restoreBrightness()
        refreshUI()

        LoginItem.ensure(defaults.bool(forKey: Keys.startAtLogin))

        battery.onChange = { [weak self] in self?.checkBattery() }
        battery.start()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(systemWoke), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(systemWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(willPowerOff), name: NSWorkspace.willPowerOffNotification, object: nil)

        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }

        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if state.isActive || PowerController.isSleepDisabled() {
            log.info("Quitting: re-enabling sleep")
            PowerController.setSleepDisabled(false)
        }
        restoreBrightness()
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.delegate = self
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Activate for:", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for (i, (title, _)) in Self.durations.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(activateChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.indentationLevel = 1
            menu.addItem(item)
            durationItems.append(item)
        }

        deactivateItem = NSMenuItem(title: "Deactivate", action: #selector(deactivateChosen), keyEquivalent: "d")
        deactivateItem.target = self
        menu.addItem(deactivateItem)
        menu.addItem(.separator())

        loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        dimItem = NSMenuItem(title: "Limit Screen Brightness to 50% When Active", action: #selector(toggleDim), keyEquivalent: "")
        dimItem.target = self
        menu.addItem(dimItem)

        batteryItem = NSMenuItem(title: "", action: #selector(toggleBattery), keyEquivalent: "")
        batteryItem.target = self
        menu.addItem(batteryItem)

        let uninstall = NSMenuItem(title: "Remove Sudo Rule…", action: #selector(removeRule), keyEquivalent: "")
        uninstall.target = self
        menu.addItem(uninstall)

        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Close The Lid", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshUI()
    }

    private func refreshUI() {
        guard let button = statusItem?.button else { return }
        switch state {
        case .passive:
            button.image = Icons.passive
            button.title = ""
            statusLine.title = "Passive — Mac sleeps normally"
        case .active(let until):
            button.image = Icons.active
            if let until {
                let left = max(0, until.timeIntervalSinceNow)
                button.title = " " + Self.shortFormat(left)
                statusLine.title = "Active — \(Self.longFormat(left)) left"
            } else {
                button.title = ""
                statusLine.title = "Active — lid can be closed (indefinitely)"
            }
        }
        button.toolTip = statusLine.title

        for item in durationItems {
            item.state = (state.isActive && item.tag == selectedDurationIndex) ? .on : .off
        }
        deactivateItem.isEnabled = state.isActive
        deactivateItem.isHidden = !state.isActive

        loginItem.state = LoginItem.isEnabled ? .on : .off
        if LoginItem.requiresApproval {
            loginItem.title = "Start at Login (needs approval)"
        } else {
            loginItem.title = "Start at Login"
        }
        batteryItem.title = "Deactivate on Low Battery (\(batteryThreshold)%)"
        batteryItem.state = defaults.bool(forKey: Keys.batteryCutoff) ? .on : .off
        dimItem.state = defaults.bool(forKey: Keys.dimScreen) ? .on : .off
    }

    private static func shortFormat(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        if s < 60 { return "\(s)s" }
        let m = (s + 59) / 60
        if m < 60 { return "\(m)m" }
        return String(format: "%dh%02dm", m / 60, m % 60)
    }

    private static func longFormat(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // MARK: - Actions

    @objc private func activateChosen(_ sender: NSMenuItem) {
        let duration = Self.durations[sender.tag].1
        activate(for: duration, index: sender.tag)
    }

    @objc private func deactivateChosen() {
        deactivate(reason: nil)
    }

    @objc private func toggleLogin() {
        if LoginItem.requiresApproval {
            LoginItem.openSettings()
            return
        }
        let wanted = !LoginItem.isEnabled
        defaults.set(wanted, forKey: Keys.startAtLogin)
        LoginItem.ensure(wanted)
        if wanted && LoginItem.requiresApproval { LoginItem.openSettings() }
        refreshUI()
    }

    @objc private func toggleDim() {
        let on = !defaults.bool(forKey: Keys.dimScreen)
        defaults.set(on, forKey: Keys.dimScreen)
        if state.isActive { on ? dimBrightness() : restoreBrightness() }
        refreshUI()
    }

    @objc private func toggleBattery() {
        defaults.set(!defaults.bool(forKey: Keys.batteryCutoff), forKey: Keys.batteryCutoff)
        refreshUI()
        checkBattery()
    }

    @objc private func removeRule() {
        if state.isActive { deactivate(reason: nil) }
        switch PrivilegeInstaller.uninstall() {
        case .success:
            alert("Sudo rule removed", "Close The Lid will ask for your password again next time you activate it.")
        case .cancelled:
            break
        case .failed(let msg):
            alert("Could not remove the sudo rule", msg)
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Keeps your Mac awake with the lid closed."),
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func showSetupDetails() {
        let d = NSAlert()
        d.messageText = "What the setup does"
        d.informativeText = """
        Close The Lid runs “sudo pmset -a disablesleep 1” to activate and “sudo pmset -a disablesleep 0” \
        to deactivate. To avoid asking for your password every time, it installs a rule in \
        \(PrivilegeInstaller.rulePath) that lets your account run only those two commands without a password.

        The rule is validated with visudo before it is installed. “Remove Sudo Rule…” in the menu deletes it.
        """
        d.runModal()
    }

    // MARK: - State transitions

    private func ensurePrivilege() -> Bool {
        if PowerController.hasPrivilege() { return true }

        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "One-time setup"
        a.informativeText = "You'll be asked for your administrator password once. You can remove this permission later from the menu."
        let details = NSButton(title: "Details…", target: self, action: #selector(showSetupDetails))
        details.isBordered = false
        details.attributedTitle = NSAttributedString(string: "Details…", attributes: [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
        details.sizeToFit()
        a.accessoryView = details
        a.addButton(withTitle: "Continue")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return false }

        switch PrivilegeInstaller.install() {
        case .success:
            if PowerController.hasPrivilege() { return true }
            alert("Setup incomplete", "The rule was installed but sudo still requires a password. Check \(PrivilegeInstaller.rulePath).")
            return false
        case .cancelled:
            return false
        case .failed(let msg):
            alert("Setup failed", msg)
            return false
        }
    }

    private func activate(for duration: TimeInterval?, index: Int) {
        if !state.isActive {
            guard ensurePrivilege() else { return }
            guard PowerController.setSleepDisabled(true) else {
                alert("Could not activate", "pmset -a disablesleep 1 failed. See Console for details.")
                return
            }
            if !PowerController.isSleepDisabled() {
                log.warning("pmset reported success but SleepDisabled does not read back as 1")
            }
            beginActivity()
            if defaults.bool(forKey: Keys.dimScreen) { dimBrightness() }
        }
        selectedDurationIndex = index
        state = .active(until: duration.map { Date().addingTimeInterval($0) })
        log.info("Activated (\(duration.map { "\(Int($0))s" } ?? "indefinitely", privacy: .public))")
        startTimer()
        refreshUI()
        checkBattery()
    }

    private func deactivate(reason: String?) {
        // Stop ticking first: the timer runs in .common mode and would otherwise
        // re-enter here while an admin prompt or alert is modal.
        guard !isDeactivating else { return }
        isDeactivating = true
        defer { isDeactivating = false }
        stopTimer()

        var ok = PowerController.setSleepDisabled(false)
        if !ok {
            // Rule missing or broken: fall back to a one-off admin prompt so we never leave sleep disabled.
            if case .success = PrivilegeInstaller.runPmsetAsAdmin(disabled: false) { ok = true }
        }
        if !ok {
            // Stay active without a timer so the user can retry Deactivate manually.
            state = .active(until: nil)
            refreshUI()
            alert("Could not deactivate", "Run “sudo pmset -a disablesleep 0” in Terminal to re-enable sleep.")
            return
        }
        endActivity()
        restoreBrightness()
        state = .passive
        selectedDurationIndex = nil
        log.info("Deactivated\(reason.map { ": \($0)" } ?? "", privacy: .public)")
        refreshUI()
        if let reason { notify("Close The Lid deactivated", reason) }
    }

    // MARK: - Timer / activity

    private func startTimer() {
        tickTimer?.invalidate()
        tickCount = 0
        let t = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    private func stopTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    @objc private func tick() {
        tickCount += 1
        guard case .active(let until) = state else { return }
        if let until, Date() >= until {
            deactivate(reason: "Timer finished — your Mac will sleep normally again.")
            return
        }
        if tickCount % 30 == 0 { checkBattery() }
        refreshUI()
    }

    @objc private func systemWoke() {
        tick()
    }

    @objc private func willPowerOff() {
        if state.isActive { deactivate(reason: nil) }
    }

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Close The Lid timer must fire on time while the lid is closed")
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    // MARK: - Brightness

    /// Caps the built-in display at 50% brightness. If it's already at or below 50%,
    /// it's left alone. The original level is persisted so it can be restored after a crash.
    private func dimBrightness() {
        guard defaults.object(forKey: Keys.savedBrightness) == nil,
              let current = DisplayBrightness.get(), current > 0.5 else { return }
        defaults.set(Double(current), forKey: Keys.savedBrightness)
        DisplayBrightness.set(0.5)
        log.info("Dimmed brightness \(current) → 0.5")
    }

    private func restoreBrightness() {
        guard let saved = defaults.object(forKey: Keys.savedBrightness) as? Double else { return }
        DisplayBrightness.set(Float(saved))
        defaults.removeObject(forKey: Keys.savedBrightness)
        log.info("Restored brightness \(saved)")
    }

    // MARK: - Battery

    private func checkBattery() {
        guard state.isActive, defaults.bool(forKey: Keys.batteryCutoff),
              let s = BatteryMonitor.current(), s.onBattery, s.percent <= batteryThreshold
        else { return }
        deactivate(reason: "Battery at \(s.percent)% — sleep re-enabled to protect your Mac.")
    }

    // MARK: - Helpers

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    private func notify(_ title: String, _ body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
