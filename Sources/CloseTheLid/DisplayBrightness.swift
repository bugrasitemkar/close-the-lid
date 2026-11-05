import CoreGraphics
import Foundation

/// Built-in display brightness via the private DisplayServices framework.
/// Every call is a safe no-op if the framework or symbols are unavailable.
enum DisplayBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn: GetFn? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn: SetFn? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFn.self) }

    static var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// 0.0 ... 1.0, or nil if unavailable.
    static func get() -> Float? {
        guard let getFn, let id = builtInDisplay else { return nil }
        var v: Float = 0
        return getFn(id, &v) == 0 ? v : nil
    }

    @discardableResult
    static func set(_ value: Float) -> Bool {
        guard let setFn, let id = builtInDisplay else { return false }
        let ok = setFn(id, min(1, max(0, value))) == 0
        if !ok { log.error("Setting brightness failed") }
        return ok
    }
}
