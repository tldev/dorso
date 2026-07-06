import AppKit
import CoreGraphics

// MARK: - Private API Loading
// Private CoreGraphics APIs for enhanced blur effect (not available in App Store builds)

#if !APP_STORE
let cgsMainConnectionID: (@convention(c) () -> UInt32)? = {
    guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
    guard let sym = dlsym(handle, "CGSMainConnectionID") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) () -> UInt32).self)
}()

let cgsSetWindowBackgroundBlurRadius: (@convention(c) (UInt32, UInt32, Int32) -> Int32)? = {
    guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
    guard let sym = dlsym(handle, "CGSSetWindowBackgroundBlurRadius") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (UInt32, UInt32, Int32) -> Int32).self)
}()
#else
// App Store build: no private APIs available
#endif
