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


public struct WindowApp: Encodable {
    struct Window: Encodable {
        var title: String = ""
        var focused: Bool = false
        var minimized: Bool = false
        var size: CGSize = CGSize.zero
        var position: CGPoint = CGPoint.zero
    }

    var name: String
    var pid: Int
    var windows: [Window]
}


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
    var mainWindow: CFTypeRef?
    let res = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow)
    if res != .success {
        if (res == .apiDisabled) {
            throw PermError("Enable this tool in System Settings -> Privacy and Security -> Accessibility")
        }
        throw MWCError("Failed to get main window: \(String(describing: res))")
    }
    guard let window = mainWindow as! AXUIElement? else {
        throw MWCError("Unexpected unwrap error")
    }
    return window
}


func getAXUIAttr<T>(_ window: AXUIElement, _ attr: String) throws -> T? {
    var _val: CFTypeRef?
    let res = AXUIElementCopyAttributeValue(window, attr as CFString, &_val)
    if res == .noValue {
        return nil
    }
    if res != .success {
        throw MWCError("Failed to get window attr [\(attr)]: \(String(describing: res))")
    }
    if let val = _val as? T {
        return val
    } else {
        throw MWCError("Window attr [\(attr)] is NULL")
    }
}


func setWinAttrValue(_ window: AXUIElement, _ attr: String, _ value: CFTypeRef) throws {
    let res = AXUIElementSetAttributeValue(window, attr as CFString, value)
    if res != .success {
        throw MWCError("Failed to set window attr [\(attr)]: \(res.rawValue)")
    }
}


func getAXUIAttrs(_ element: AXUIElement) throws -> [String] {
    var _attrs: CFArray?
    let res = AXUIElementCopyAttributeNames(element, &_attrs)
    if res != .success {
        // NOTE: .apiDisabled does not always mean perm error, some apps block us
        // and this is the response.
        if res == .cannotComplete || res == .notImplemented || res == .apiDisabled {
            return []
        }
        throw MWCError("Failed to get element attrs: \(String(describing: res))")
    }
    if let attrs = _attrs as? [String] {
        return attrs
    } else {
        throw MWCError("Element attrs is NULL")
    }
}


func getAppByName(_ name: String) throws -> NSRunningApplication {
    let apps = NSWorkspace.shared.runningApplications
    guard let app = apps.first(where: {$0.localizedName == name}) else {
        throw NotFoundError("App not found")
    }
    return app
}


public func getAppWindowSize(_ appName: String) throws -> CGRect {
    let app = try getAppByName(appName)
    let window = try getAppMainWindow(app)
    var rect = CGRect.zero
    if let pos: AXValue = try getAXUIAttr(window, kAXPositionAttribute),
       let size: AXValue = try getAXUIAttr(window, kAXSizeAttribute) {
        if !AXValueGetValue(pos, .cgPoint, &rect.origin) ||
           !AXValueGetValue(size, .cgSize, &rect.size) {
            throw MWCError("Invalid window info")
        }
    }
    return rect
}


public func getWindowApps(windows: Bool? = nil) throws -> [WindowApp] {
    let apps = NSWorkspace.shared.runningApplications
    var winApps: [WindowApp] = []
    for app in apps {
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        let appAttrs = try getAXUIAttrs(appEl)
        if !appAttrs.contains(kAXWindowsAttribute) {
            continue
        }
        guard let _windows: [AXUIElement] = try getAXUIAttr(appEl, kAXWindowsAttribute) else {
            continue
        }
        if _windows.count == 0 {
            continue
        }
        var windows: [WindowApp.Window] = []
        for win in _windows {
            var window = WindowApp.Window()
            do {
                window.title = try getAXUIAttr(win, kAXTitleAttribute) ?? ""
                window.focused = try getAXUIAttr(win, kAXFocusedAttribute) ?? false
                window.minimized = try getAXUIAttr(win, kAXMinimizedAttribute) ?? false
                if let _position: AXValue = try getAXUIAttr(win, kAXPositionAttribute) {
                    AXValueGetValue(_position, .cgPoint, &window.position)
                }
                if let _size: AXValue = try getAXUIAttr(win, kAXSizeAttribute) {
                    AXValueGetValue(_size, .cgSize, &window.size)
                }
            } catch let e as MWCError {
                print("Unexpected window attribute error:", e, e.message)
                continue
            }
            windows.append(window)
        }
        winApps.append(WindowApp(
            name: app.localizedName ?? "",
            pid: Int(app.processIdentifier),
            windows: windows
        ))
    }
    return winApps
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

