import Foundation
import Cocoa


typealias SetZoomFunc = @convention(c) (Int, UnsafePointer<CGPoint>, Double, Bool) -> Void
typealias GetZoomFunc = @convention(c) (
    Int,
    UnsafeMutablePointer<CGPoint>,
    UnsafeMutablePointer<Double>,
    UnsafeMutablePointer<Bool>
) -> Void


// AX API can be insanely slow, exclude known time sinks that do nothing for us...
let ignoredBundleIds = [
    "com.apple.WebKit.WebContent",
]


class MWCError: Error {
    var message: String
    var stack: [String] = Thread.callStackSymbols

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
    var active: Bool
    var hidden: Bool
    var bundleIdent: String?
    var bundleURL: String?
    var execURL: String?
    var launchDate: String?
    var windows: [Window]
}


var _coreGraphicsConnId: Int? = nil
func getCGSConnectionID() throws -> Int {
    if _coreGraphicsConnId == nil {
        let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSMainConnectionID")
        if fnSym == nil {
            throw MWCError("Failed to find CGSMainConnectionID function")
        }
        typealias Args = @convention(c) (UnsafeRawPointer?) -> Int
        let fn = unsafeBitCast(fnSym, to: Args.self)
        _coreGraphicsConnId = fn(nil)
    }
    return _coreGraphicsConnId!
}


var _setZoomFunc: SetZoomFunc? = nil
func getSetZoomFunc() throws -> SetZoomFunc {
    if _setZoomFunc == nil {
        let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSSetZoomParameters")
        if fnSym == nil {
            throw MWCError("Failed to find CGSSetZoomParameters function")
        }
        _setZoomFunc = unsafeBitCast(fnSym, to: SetZoomFunc.self)
    }
    return _setZoomFunc!
}


var _getZoomFunc: GetZoomFunc? = nil
func getGetZoomFunc() throws -> GetZoomFunc {
    if _getZoomFunc == nil {
        let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSGetZoomParameters")
        if fnSym == nil {
            throw MWCError("Failed to find CGSGetZoomParameters function")
        }
        _getZoomFunc = unsafeBitCast(fnSym, to: GetZoomFunc.self)
    }
    return _getZoomFunc!
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


var _isoDateFmt: ISO8601DateFormatter? = nil
func toISODateTime(_ date: Date) -> String {
    if _isoDateFmt == nil {
        _isoDateFmt = ISO8601DateFormatter()
        _isoDateFmt!.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    return _isoDateFmt!.string(from: date)
}


func getAXUIAttrSafe<T>(_ element: AXUIElement, _ attr: String) throws -> T? {
    var _val: CFTypeRef?
    let res = AXUIElementCopyAttributeValue(element, attr as CFString, &_val)
    if res != .success || _val == nil {
        return nil
    }
    guard let val = _val as? T else {
        throw MWCError("Invalid type for attr [\(attr)]: \(T.self) != \(String(describing: _val!))")
    }
    return val
}


func getAXUIAttr<T>(_ element: AXUIElement, _ attr: String) -> T? {
    do {
        return try getAXUIAttrSafe(element, attr)
    } catch let e as MWCError {
        print("Internal type error:", e.message)
        return nil
    } catch {
        return nil
    }
}


func hasAXUIAttr(_ element: AXUIElement, _ attr: String) -> Bool {
    var count: CFIndex = 0
    let res = AXUIElementGetAttributeValueCount(element, attr as CFString, &count)
    if res != .success {
        return false
    }
    return count > 0
}


func listAXUIAttrs(_ element: AXUIElement) -> [String] {
    var _attrs: CFArray?
    let res = AXUIElementCopyAttributeNames(element, &_attrs)
    if res != .success || _attrs == nil {
        return []
    }
    guard let attrs = _attrs as? [String] else {
        return []
    }
    return attrs
}


func listAXUIActions(_ element: AXUIElement) -> [String] {
    var _actions: CFArray?
    let res = AXUIElementCopyActionNames(element, &_actions)
    if res != .success {
        return []
    }
    guard let actions = _actions as? [String] else {
        return []
    }
    return actions
}


func listAXUIParamAttrs(_ element: AXUIElement) -> [String] {
    var _attrs: CFArray?
    let res = AXUIElementCopyParameterizedAttributeNames(element, &_attrs)
    if res != .success {
        return []
    }
    guard let attrs = _attrs as? [String] else {
        return []
    }
    return attrs
}


func setAXUIAttr(_ el: AXUIElement, _ attr: String, _ value: CFTypeRef) throws {
    let res = AXUIElementSetAttributeValue(el, attr as CFString, value)
    if res != .success {
        throw MWCError("Failed to set attr [\(attr)]: \(res.rawValue)")
    }
}


func getAppMainWindow(_ app: NSRunningApplication) throws -> AXUIElement {
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    guard let window: AXUIElement = try getAXUIAttrSafe(appElement, kAXMainWindowAttribute) else {
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
    if let pos: AXValue = try getAXUIAttrSafe(window, kAXPositionAttribute),
       let size: AXValue = try getAXUIAttrSafe(window, kAXSizeAttribute) {
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
    let apps = NSWorkspace.shared.runningApplications.filter {
        return $0.isFinishedLaunching && !ignoredBundleIds.contains($0.bundleIdentifier ?? "")
    }
    var winApps: [WindowApp] = []
    let queue = OperationQueue()
    for app in apps {
        queue.addOperation {
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            guard let windowEls: [AXUIElement] = getAXUIAttr(appEl, kAXWindowsAttribute) else {
                return
            }
            if windowEls.count == 0 {
                return
            }
            let focusedWindowEl: AXUIElement? = app.isActive ? getAXUIAttr(appEl, kAXFocusedWindowAttribute) : nil
            var windows: [WindowApp.Window] = []
            for winEl in windowEls {
                var window = WindowApp.Window()
                window.focused = winEl == focusedWindowEl
                window.title = getAXUIAttr(winEl, kAXTitleAttribute) ?? ""
                window.minimized = getAXUIAttr(winEl, kAXMinimizedAttribute) ?? false
                if let _position: AXValue = getAXUIAttr(winEl, kAXPositionAttribute) {
                    AXValueGetValue(_position, .cgPoint, &window.position)
                }
                if let _size: AXValue = getAXUIAttr(winEl, kAXSizeAttribute) {
                    AXValueGetValue(_size, .cgSize, &window.size)
                }
                windows.append(window)
            }
            queue.addBarrierBlock {
                winApps.append(WindowApp(
                    name: app.localizedName ?? "",
                    pid: Int(app.processIdentifier),
                    active: app.isActive,
                    hidden: app.isHidden,
                    bundleIdent: app.bundleIdentifier,
                    bundleURL: app.bundleURL?.absoluteString,
                    execURL: app.executableURL?.absoluteString,
                    launchDate: (app.launchDate != nil) ? toISODateTime(app.launchDate!) : nil,
                    windows: windows
                ))
            }
        }
    }
    queue.waitUntilAllOperationsAreFinished()
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
        try setAXUIAttr(window, kAXPositionAttribute, AXValueCreate(.cgPoint, &posRounded)!)
    }
    var _size = size
    try setAXUIAttr(window, kAXSizeAttribute, AXValueCreate(.cgSize, &_size)!)
    if activate ?? false {
        app.activate()
    }
}
