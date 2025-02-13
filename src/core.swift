import Foundation
import Cocoa

var coreGraphicsConnId: Int? = nil


class MWCError: Error {
    var message: String

    init(_ message: String) {
        self.message = message
    }
}


class PermError: MWCError { }


class NotFoundError: MWCError { }


func getCGSConnectionID() throws -> Int {
    if coreGraphicsConnId == nil {
        let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSMainConnectionID")
        if fnSym == nil {
            throw MWCError("Failed to find CGSMainConnectionID function")
        }
        typealias Args = @convention(c) (UnsafeRawPointer?) -> Int
        let fn = unsafeBitCast(fnSym, to: Args.self)
        coreGraphicsConnId = fn(nil)
    }
    return coreGraphicsConnId!
}


public func setZoom(_ factor: Double, cx: Double, cy: Double, smooth: Bool? = nil) throws {
    let cid = try getCGSConnectionID()
    let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSSetZoomParameters")
    if fnSym == nil {
        throw MWCError("Failed to find CGSSetZoomParameters function")
    }
    typealias Args = @convention(c) (Int, UnsafePointer<CGPoint>, Double, Bool) -> Void
    let fn = unsafeBitCast(fnSym, to: Args.self)
    // X, Y get floored, round first...
    var origin = CGPoint(x: round(cx), y: round(cy))
    let _smooth = smooth != nil ? smooth : factor > 1
    // HACK: This private function doesn't play well with the built-in zoom feature.
    // We need to dirty the state (using inverted smooth value is sufficient) before
    // Sending our final values..  Validate this with:
    //  1. setZoom(...args)
    //  2. Accessibility shortcuts to affect zoom (i.e. ctrl + mouse scroll)
    //  3. setZoom(...args)  # ensure args are identical to step 1.
    // Expect no corruption on screen if it worked.
    withUnsafePointer(to: &origin) { originPtr in
        fn(cid, originPtr, factor, !_smooth!)
    }
    withUnsafePointer(to: &origin) { originPtr in
        fn(cid, originPtr, factor, _smooth!)
    }
}


public func getZoom() throws -> (Double, CGPoint, Bool) {
    let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSGetZoomParameters")
    if fnSym == nil {
        throw MWCError("Failed to find CGSGetZoomParameters function")
    }
    typealias Args = @convention(c) (
        Int,
        UnsafeMutablePointer<CGPoint>,
        UnsafeMutablePointer<Double>,
        UnsafeMutablePointer<Bool>
    ) -> Void
    let fn = unsafeBitCast(fnSym, to: Args.self)
    let cid = try getCGSConnectionID()
    var origin = CGPoint.zero
    var factor: Double = 0.0
    var smooth: Bool = false
    withUnsafeMutablePointer(to: &origin) { originPtr in
        withUnsafeMutablePointer(to: &factor) { factorPtr in
            withUnsafeMutablePointer(to: &smooth) { smoothPtr in
                fn(cid, originPtr, factorPtr, smoothPtr)
            }
        }
    }
    return (factor, origin, smooth)
}


public func getMainScreenSize() throws -> (Double, Double) {
    guard let screen = NSScreen.main else {
        throw MWCError("Main screen unavailable")
    }
    return (screen.frame.width, screen.frame.height)
}


public func getMenuBarHeight() throws -> Double {
    guard let screen = NSScreen.main else {
        throw MWCError("Main screen unavailable")
    }
    return screen.frame.height - screen.visibleFrame.height
}


func getAppMainWindow(_ app: NSRunningApplication) throws -> AXUIElement {
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var mainWindow: AnyObject?
    var axRes: AXError
    axRes = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow)
    if axRes != .success {
        if (axRes == AXError.apiDisabled) {
            throw PermError("Enable this tool in System Settings -> Privacy and Security -> Accessibility")
        }
        throw MWCError("Failed to get main window: \(axRes.rawValue)")
    }
    guard let window = mainWindow as! AXUIElement? else {
        throw MWCError("Unexpected unwrap error")
    }
    return window
}


func getWinAttrValue(_ window: AXUIElement, _ attr: String) throws -> AnyObject {
    var _val: AnyObject?
    let res = AXUIElementCopyAttributeValue(window, attr as CFString, &_val)
    if res != .success {
        throw MWCError("Failed to get window attr [\(attr)]: \(res.rawValue)")
    }
    if let val = _val {
        return val
    } else {
        throw MWCError("Window attr [\(attr)] is NULL")
    }
}


func setWinAttrValue(_ window: AXUIElement, _ attr: String, _ value: AnyObject) throws {
    let res = AXUIElementSetAttributeValue(window, attr as CFString, value)
    if res != .success {
        throw MWCError("Failed to set window attr [\(attr)]: \(res.rawValue)")
    }
}


func getAppByName(_ name: String) throws -> NSRunningApplication {
    let runningApps = NSWorkspace.shared.runningApplications
    guard let app = runningApps.first(where: {$0.localizedName == name}) else {
        throw NotFoundError("App not found")
    }
    return app
}


public func getAppWindowSize(_ appName: String) throws -> CGRect {
    let app = try getAppByName(appName)
    let window = try getAppMainWindow(app)
    let _pos = try getWinAttrValue(window, kAXPositionAttribute)
    let _size = try getWinAttrValue(window, kAXSizeAttribute)
    var rect = CGRect.zero
    if !AXValueGetValue(_pos as! AXValue, .cgPoint, &rect.origin) ||
       !AXValueGetValue(_size as! AXValue, .cgSize, &rect.size) {
        throw MWCError("Invalid window info")
    }
    return rect
}


public func resizeAppWindow(_ appName: String, _ width: Double, _ height: Double,
                            x: Double? = nil, y: Double? = nil, activate: Bool? = nil) throws {
    let app = try getAppByName(appName)
    let window = try getAppMainWindow(app)
    // X, Y get treated like floored Ints, round first...
    var pos = CGPoint(x: CGFloat(round(x ?? 0)), y: CGFloat(round(y ?? 0)))
    var size = CGSize(width: CGFloat(width), height: CGFloat(height))
    try setWinAttrValue(window, kAXPositionAttribute, AXValueCreate(.cgPoint, &pos)!)
    try setWinAttrValue(window, kAXSizeAttribute, AXValueCreate(.cgSize, &size)!)
    if activate ?? false {
        app.activate()
    }
}
