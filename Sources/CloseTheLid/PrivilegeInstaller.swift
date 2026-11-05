import Foundation

/// Installs / removes `/etc/sudoers.d/close-the-lid`, which lets the current
/// user run exactly `pmset -a disablesleep 0` and `pmset -a disablesleep 1`
/// as root without a password. Uses the standard macOS admin password dialog.
enum PrivilegeInstaller {
    static let rulePath = "/etc/sudoers.d/close-the-lid"

    enum Outcome { case success, cancelled, failed(String) }

    static var ruleLine: String {
        // Quote the short user name; escape characters special inside sudoers quotes.
        let user = NSUserName()
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(user)\" ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
    }

    static func install() -> Outcome {
        // Single-quote the rule for the shell.
        let quotedRule = "'" + ruleLine.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = """
        set -e
        TMP=$(/usr/bin/mktemp /tmp/closethelid.XXXXXX)
        trap '/bin/rm -f "$TMP"' EXIT
        /usr/bin/printf '%s\\n' \(quotedRule) > "$TMP"
        /usr/sbin/visudo -cf "$TMP" >/dev/null
        /bin/mkdir -p /etc/sudoers.d
        /usr/bin/install -m 0440 -o root -g wheel "$TMP" \(rulePath)
        """
        return runAsAdmin(script, prompt: "Close The Lid needs to allow itself to toggle sleep (pmset disablesleep) without asking again.")
    }

    static func uninstall() -> Outcome {
        runAsAdmin("/bin/rm -f \(rulePath)", prompt: "Close The Lid wants to remove its sudo rule.")
    }

    /// Fallback for when the rule is missing but we must re-enable sleep.
    static func runPmsetAsAdmin(disabled: Bool) -> Outcome {
        runAsAdmin("/usr/bin/pmset -a disablesleep \(disabled ? 1 : 0)", prompt: "Close The Lid needs to change the sleep setting.")
    }

    static func ruleExists() -> Bool {
        FileManager.default.fileExists(atPath: rulePath)
    }

    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAsAdmin(_ shell: String, prompt: String) -> Outcome {
        let source = "do shell script \"\(appleScriptEscape(shell))\" with prompt \"\(appleScriptEscape(prompt))\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else { return .failed("Could not build AppleScript") }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -128 { return .cancelled }
            let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error (\(code))"
            log.error("Admin script failed: \(msg, privacy: .public)")
            return .failed(msg)
        }
        return .success
    }
}
