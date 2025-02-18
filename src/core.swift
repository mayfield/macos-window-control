import Foundation
import Cocoa


typealias SetZoomFunc = @convention(c) (Int, UnsafePointer<CGPoint>, Double, Bool) -> Void
typealias GetZoomFunc = @convention(c) (
    Int,
    UnsafeMutablePointer<CGPoint>,
    UnsafeMutablePointer<Double>,
    UnsafeMutablePointer<Bool>
) -> Void


class MWCError: Error {
    var message: String

    init(_ message: String) {
        self.message = message
    }
}


class AXPermError: MWCError {
    init() {
        super.init("Permission required: System Settings -> Privacy and Security -> Accessibility")
    }
}


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


var coreGraphicsConnId: Int? = nil
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


var setZoomFunc: SetZoomFunc? = nil
func getSetZoomFunc() throws -> SetZoomFunc {
    if setZoomFunc == nil {
        let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSSetZoomParameters")
        if fnSym == nil {
            throw MWCError("Failed to find CGSSetZoomParameters function")
        }
        setZoomFunc = unsafeBitCast(fnSym, to: SetZoomFunc.self)
    }
    return setZoomFunc!
}


var getZoomFunc: GetZoomFunc? = nil
func getGetZoomFunc() throws -> GetZoomFunc {
    if getZoomFunc == nil {
        let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSGetZoomParameters")
        if fnSym == nil {
            throw MWCError("Failed to find CGSGetZoomParameters function")
        }
        getZoomFunc = unsafeBitCast(fnSym, to: GetZoomFunc.self)
    }
    return getZoomFunc!
}


public func setZoom(_ factor: Double, center: CGPoint? = nil, smooth: Bool? = nil) throws {
    var centerFinal: CGPoint
    if center != nil {
        // X, Y get floored, round first...
        centerFinal = CGPoint(x: round(center!.x), y: round(center!.y))
    } else {
        let (_, _center, _) = try getZoom()
        centerFinal = _center
    }
    let _smooth = smooth != nil ? smooth : factor > 1
    // HACK: This private function doesn't play well with the built-in zoom feature.
    // We need to dirty the state (using inverted smooth value is sufficient) before
    // Sending our final values..  Validate this with:
    //  1. setZoom(...args)
    //  2. Accessibility shortcuts to affect zoom (i.e. ctrl + mouse scroll)
    //  3. setZoom(...args)  # ensure args are identical to step 1.
    // Expect no corruption on screen if it worked.
    let cid = try getCGSConnectionID()
    let setZoomFn = try getSetZoomFunc()
    withUnsafePointer(to: &centerFinal) {
        setZoomFn(cid, $0, factor, !_smooth!)
        setZoomFn(cid, $0, factor, _smooth!)
    }
}


public func getZoom() throws -> (Double, CGPoint, Bool) {
    let cid = try getCGSConnectionID()
    let getZoomFn = try getGetZoomFunc()
    var center = CGPoint.zero
    var factor: Double = 0.0
    var smooth: Bool = false
    withUnsafeMutablePointer(to: &center) { centerPtr in
        withUnsafeMutablePointer(to: &factor) { factorPtr in
            withUnsafeMutablePointer(to: &smooth) { smoothPtr in
                getZoomFn(cid, centerPtr, factorPtr, smoothPtr)
            }
        }
    }
    return (factor, center, smooth)
}


func getAXUIAttr<T>(_ window: AXUIElement, _ attr: String) throws -> T? {
    var _val: CFTypeRef?
    let res = AXUIElementCopyAttributeValue(window, attr as CFString, &_val)
    if res == .noValue || res == .attributeUnsupported {
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


func setWinAttrValue(_ window: AXUIElement, _ attr: String, _ value: CFTypeRef) throws {
    let res = AXUIElementSetAttributeValue(window, attr as CFString, value)
    if res != .success {
        throw MWCError("Failed to set window attr [\(attr)]: \(res.rawValue)")
    }
}


func getAppMainWindow(_ app: NSRunningApplication) throws -> AXUIElement {
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    guard let window: AXUIElement = try getAXUIAttr(appElement, kAXMainWindowAttribute) else {
        throw NotFoundError("Failed to get main window")
    }
    return window
}


func getAppByName(_ name: String) throws -> NSRunningApplication {
    let apps = NSWorkspace.shared.runningApplications
    guard let app = apps.first(where: {$0.localizedName == name}) else {
        throw NotFoundError("App not found")
    }
    return app
}


public func hasAccessibilityPermission() -> Bool {
    return AXIsProcessTrusted()
}


public func getMainScreenSize() throws -> CGSize {
    guard let screen = NSScreen.main else {
        throw MWCError("Main screen unavailable")
    }
    return CGSize(width: screen.frame.width, height: screen.frame.height)
}


public func getMenuBarHeight() throws -> Double {
    guard let screen = NSScreen.main else {
        throw MWCError("Main screen unavailable")
    }
    return screen.frame.height - screen.visibleFrame.height
}


public func getAppWindowSize(_ appName: String) throws -> CGRect {
    if !hasAccessibilityPermission() {
        throw AXPermError()
    }
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
    if !hasAccessibilityPermission() {
        throw AXPermError()
    }
    let apps = NSWorkspace.shared.runningApplications
    var winApps: [WindowApp] = []
    let start = CFAbsoluteTimeGetCurrent()
    print(CFAbsoluteTimeGetCurrent() - start, "start")
    for app in apps {
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        print(start - CFAbsoluteTimeGetCurrent(), "gotapp")
        let appAttrs = try getAXUIAttrs(appEl)
        print(start - CFAbsoluteTimeGetCurrent(), "got ALL app attrs")
        if !appAttrs.contains(kAXWindowsAttribute) {
            continue
        }
        guard let _windows: [AXUIElement] = try getAXUIAttr(appEl, kAXWindowsAttribute) else {
            print(start - CFAbsoluteTimeGetCurrent(), "got ALL app window (NONE)")
            continue
        }
        print(start - CFAbsoluteTimeGetCurrent(), "got ALL app window", _windows.count)
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
            print(start - CFAbsoluteTimeGetCurrent(), "parsed a window")
        }
        winApps.append(WindowApp(
            name: app.localizedName ?? "",
            pid: Int(app.processIdentifier),
            windows: windows
        ))
    }
    print(start - CFAbsoluteTimeGetCurrent(), "done")
    return winApps
}


public func resizeAppWindow(_ appName: String, _ size: CGSize,
                            position: CGPoint? = nil, activate: Bool? = nil) throws {
    if !hasAccessibilityPermission() {
        throw AXPermError()
    }
    let app = try getAppByName(appName)
    let window = try getAppMainWindow(app)
    // NOTE: Must do position first, side effects occur otherwise...
    if position != nil {
        // X, Y get treated like floored Ints, round first...
        var posRounded = CGPoint(x: round(position!.x), y: round(position!.y))
        try setWinAttrValue(window, kAXPositionAttribute, AXValueCreate(.cgPoint, &posRounded)!)
    }
    var _size = size
    try setWinAttrValue(window, kAXSizeAttribute, AXValueCreate(.cgSize, &_size)!)
    if activate ?? false {
        app.activate()
    }
}
