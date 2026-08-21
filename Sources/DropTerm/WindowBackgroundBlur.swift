import AppKit
import Darwin

enum WindowBackgroundBlur {
    private typealias CGSConnectionID = UInt32
    private typealias CGSWindowID = UInt32
    private typealias CGError = Int32
    private typealias CGSDefaultConnectionForThreadFunction = @convention(c) () -> CGSConnectionID
    private typealias CGSSetWindowBackgroundBlurRadiusFunction =
        @convention(c) (CGSConnectionID, CGSWindowID, UInt32) -> CGError

    private static let symbols = loadSymbols()

    @MainActor
    static func setRadius(_ radius: UInt32, for window: NSWindow) {
        guard
            window.windowNumber >= 0,
            let connection = symbols.connection,
            let setBlurRadius = symbols.setBlurRadius
        else { return }

        let clampedRadius = min(radius, 80)
        _ = setBlurRadius(
            connection(),
            CGSWindowID(window.windowNumber),
            clampedRadius
        )
    }

    private static func loadSymbols() -> (
        connection: CGSDefaultConnectionForThreadFunction?,
        setBlurRadius: CGSSetWindowBackgroundBlurRadiusFunction?
    ) {
        let handle = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            RTLD_LAZY
        )
        guard let handle else { return (nil, nil) }

        let connection = dlsym(handle, "CGSDefaultConnectionForThread").map {
            unsafeBitCast($0, to: CGSDefaultConnectionForThreadFunction.self)
        }
        let setBlurRadius = dlsym(handle, "CGSSetWindowBackgroundBlurRadius").map {
            unsafeBitCast($0, to: CGSSetWindowBackgroundBlurRadiusFunction.self)
        }
        return (connection, setBlurRadius)
    }
}
