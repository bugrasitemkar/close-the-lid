import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Ad-hoc signed builds change signature on every rebuild, so (re)register on each launch.
    static func ensure(_ wanted: Bool) {
        let svc = SMAppService.mainApp
        let pathKey = "loginItemRegisteredPath"
        let here = Bundle.main.bundlePath
        do {
            // If the app moved (e.g. dev build → /Applications), refresh the registration.
            if wanted, svc.status == .enabled,
               UserDefaults.standard.string(forKey: pathKey) != here {
                try? svc.unregister()
            }
            if wanted, svc.status != .enabled {
                try svc.register()
                UserDefaults.standard.set(here, forKey: pathKey)
                log.info("Login item registered (status \(svc.status.rawValue))")
            } else if !wanted, svc.status == .enabled || svc.status == .requiresApproval {
                try svc.unregister()
                log.info("Login item unregistered")
            }
        } catch {
            log.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
