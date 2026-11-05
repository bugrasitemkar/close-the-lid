import Foundation
import os

let log = Logger(subsystem: "com.bugrasitemkar.closethelid", category: "app")

/// Wraps `pmset -a disablesleep 0|1`, executed through `sudo -n` thanks to the
/// narrow sudoers rule installed by `PrivilegeInstaller`.
enum PowerController {
    static let pmset = "/usr/bin/pmset"
    static let sudo = "/usr/bin/sudo"

    struct Result {
        let status: Int32
        let output: String
    }

    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            log.error("Failed to launch \(launchPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return Result(status: -1, output: "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(status: p.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// True when sudo will run our pmset commands without asking for a password.
    static func hasPrivilege() -> Bool {
        run(sudo, ["-n", "-l", pmset, "-a", "disablesleep", "1"]).status == 0
            && run(sudo, ["-n", "-l", pmset, "-a", "disablesleep", "0"]).status == 0
    }

    /// Runs `sudo -n pmset -a disablesleep N`. Never prompts.
    @discardableResult
    static func setSleepDisabled(_ disabled: Bool) -> Bool {
        let r = run(sudo, ["-n", pmset, "-a", "disablesleep", disabled ? "1" : "0"])
        if r.status != 0 {
            log.error("pmset disablesleep \(disabled ? 1 : 0) failed (\(r.status)): \(r.output, privacy: .public)")
        } else {
            log.info("pmset disablesleep \(disabled ? 1 : 0) OK")
        }
        return r.status == 0
    }

    /// Reads the current system-wide SleepDisabled flag.
    /// `pmset -g` only lists `SleepDisabled` once it has been set, so a missing
    /// key means "not disabled". Falls back to the PowerManagement plist.
    static func isSleepDisabled() -> Bool {
        let out = run(pmset, ["-g"]).output
        for line in out.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if let i = parts.firstIndex(where: { $0.lowercased() == "sleepdisabled" }), i + 1 < parts.count {
                return parts[i + 1] == "1"
            }
        }
        let plist = "/Library/Preferences/com.apple.PowerManagement.plist"
        if let dict = NSDictionary(contentsOfFile: plist),
           let sys = dict["SystemPowerSettings"] as? [String: Any],
           let v = sys["SleepDisabled"] {
            if let b = v as? Bool { return b }
            if let n = v as? NSNumber { return n.intValue != 0 }
        }
        return false
    }
}
