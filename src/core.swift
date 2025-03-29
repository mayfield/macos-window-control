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


class ValidationError: MWCError { }


@propertyWrapper
struct Nullable<T: Encodable>: Encodable {
    var wrappedValue: T?

    init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let val = self.wrappedValue {
            try c.encode(val)
        } else {
            try c.encodeNil()
        }
    }
}

struct WindowDesc: Encodable {
    @Nullable var ident: String?
    @Nullable var title: String?
    @Nullable var titlebarHeightEstimate: Double?
    var focused: Bool = false
    var minimized: Bool = false
    var size: CGSize = CGSize.zero
    var position: CGPoint = CGPoint.zero
}

struct AppDesc: Encodable {
    var name: String
    var pid: Int
    var active: Bool
    var hidden: Bool
    @Nullable var bundleIdent: String?
    @Nullable var bundleURL: String?
    @Nullable var execURL: String?
    @Nullable var launchDate: String?
}


struct AppIdentifier: Codable {
    var name: String?
    var pid: Int?
}

struct WindowIdentifier: Codable {
    var main: Bool?
    var index: Int?
    var title: String?
}


// We need to maintain an NSApplication to make NSScreen stay current.
// See: https://developer.apple.com/documentation/appkit/nsscreen
var _nsapp: NSApplication? = nil
func pumpNSApp() {
    if _nsapp == nil {
        _nsapp = NSApplication.shared
    }
    RunLoop.current.run(until: Date.distantPast)
}


func getActiveScreen() -> NSScreen? {
    // That's right, .main is actually the active screen (screen of focused app)
    pumpNSApp()
    return NSScreen.main
}


func getMainScreen() -> NSScreen? {
    // Do not use `main`.  Mac os always puts the "main" screen at index 0
    pumpNSApp()
    if NSScreen.screens.count > 0 {
        return NSScreen.screens[0]
    } else {
        return nil
    }
}


var _coreGraphicsConnId: Int? = nil
func getCGSConnectionID() throws -> Int {
    if _coreGraphicsConnId == nil {
        let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSMainConnectionID")
        if fnSym == nil {
            throw MWCError("Failed to find CGSMainConnectionID function")
        }
        typealias Sig = @convention(c) (UnsafeRawPointer?) -> Int
        let fn = unsafeBitCast(fnSym, to: Sig.self)
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


func setZoom(_ scale: Double, center: CGPoint? = nil, smooth: Bool? = nil) throws {
    var _center: CGPoint
    if let center = center {
        // X, Y get floored, round first...
        _center = CGPoint(x: round(center.x), y: round(center.y))
    } else {
        let (_, center, _) = try getZoom()
        _center = center
    }
    var _smooth: Bool
    if let smooth = smooth {
        _smooth = smooth
    } else {
        _smooth = scale > 1
    }
    // HACK: This private function doesn't play well with the built-in zoom feature.
    // We need to dirty the state (using inverted smooth value is sufficient) before
    // Sending our final values..  Validate this with:
    //  1. setZoom(...args)
    //  2. Accessibility shortcuts to affect zoom (i.e. ctrl + mouse scroll)
    //  3. setZoom(...args)  # ensure args are identical to step 1.
    // Expect no corruption on screen if it worked.
    let cid = try getCGSConnectionID()
    let setZoomFn = try getSetZoomFunc()
    withUnsafePointer(to: &_center) {
        setZoomFn(cid, $0, scale, !_smooth)
        setZoomFn(cid, $0, scale, _smooth)
    }
}


func getZoom() throws -> (Double, CGPoint, Bool) {
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

func getAXUIParamAttrSafe<T>(_ element: AXUIElement, _ attr: String, _ param: CFTypeRef) throws -> T? {
    var _val: CFTypeRef?
    let res = AXUIElementCopyParameterizedAttributeValue(element, attr as CFString, param, &_val)
    if res != .success || _val == nil {
        return nil
    }
    guard let val = _val as? T else {
        throw MWCError("Invalid type for attr [\(attr)]: \(T.self) != \(String(describing: _val!))")
    }
    return val
}


func getAXUIParamAttr<T>(_ element: AXUIElement, _ attr: String, _ param: CFTypeRef?) -> T? {
    do {
        return try getAXUIParamAttrSafe(element, attr, param ?? CFArrayCreate(nil, nil, 0, nil))
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


func setAXUIAttr(_ element: AXUIElement, _ attr: String, _ value: CFTypeRef) throws {
    let res = AXUIElementSetAttributeValue(element, attr as CFString, value)
    if res != .success {
        throw MWCError("Failed to set attr [\(attr)]: \(res.rawValue)")
    }
}


func getAXUIElementSize(_ element: AXUIElement) -> CGRect? {
    var rect = CGRect.zero
    if let pos: AXValue = getAXUIAttr(element, kAXPositionAttribute),
       let size: AXValue = getAXUIAttr(element, kAXSizeAttribute) {
        if AXValueGetValue(pos, .cgPoint, &rect.origin) &&
           AXValueGetValue(size, .cgSize, &rect.size) {
            return rect
        }
    }
    return nil
}


enum AXUIFindCriteria {
    case role(String)
    case subrole(String)
}

func findAXUIElement(_ parent: AXUIElement, _ criteria: AXUIFindCriteria) -> AXUIElement? {
    // BFS for an AXUIElement...
    var queue: [AXUIElement] = [parent]
    let check: ([AXUIElement]) -> AXUIElement? = {
        for x in $0 {
            switch criteria {
                case .role(let crit):
                    if let test: String = getAXUIAttr(x, kAXRoleAttribute), test == crit {
                        return x
                    }
                case .subrole(let crit):
                    if let test: String = getAXUIAttr(x, kAXSubroleAttribute), test == crit {
                        return x
                    }
            }
            queue.append(x)
        }
        return nil
    }
    while queue.count > 0 {
        let element = queue.removeFirst()
        if let children: [AXUIElement] = getAXUIAttr(element, kAXChildrenAttribute),
           let match = check(children) {
            return match
        }
    }
    return nil
}


func validateAppWindowQuery(_ appIdent: AppIdentifier, _ winIdent: WindowIdentifier? = nil) throws {
    if appIdent.name == nil && appIdent.pid == nil {
        throw ValidationError("app 'name' or 'pid' must be set")
    }
    if appIdent.name != nil && appIdent.pid != nil {
        throw ValidationError("app 'name' and 'pid' are exclusive")
    }
    if let window = winIdent {
        let keysSet = ([window.main, window.index, window.title] as [Any?]).compactMap({$0}).count
        if keysSet == 0 {
            throw ValidationError("window.(main, index or title) must be set")
        } else if keysSet > 1 {
            throw ValidationError("window properties are mutually exclusive")
        }
        if let x = window.main, !x {
            throw ValidationError("window.main must be omitted or true")
        }
    }
}


func getApp(_ appIdent: AppIdentifier) throws -> NSRunningApplication {
    var _app: NSRunningApplication?
    let apps = NSWorkspace.shared.runningApplications
    if let name = appIdent.name {
        _app = apps.first(where: {$0.localizedName == name})
    } else if let pid = appIdent.pid {
        _app = apps.first(where: {$0.processIdentifier == pid})
    }
    guard let app = _app else {
        throw NotFoundError("App not found")
    }
    return app
}


func getAppWindow(_ appIdent: AppIdentifier) throws -> (NSRunningApplication, AXUIElement) {
    return try getAppWindow(appIdent, nil);
}


func getAppWindow(_ appIdent: AppIdentifier, _ winIdent: WindowIdentifier?) throws
               -> (NSRunningApplication, AXUIElement) {
    try validateAppWindowQuery(appIdent, winIdent)
    let app = try getApp(appIdent)
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    var _windowEl: AXUIElement?
    let wIdent = winIdent ?? WindowIdentifier(main: true)
    if wIdent.main == true {
        _windowEl = try getAXUIAttrSafe(appEl, kAXMainWindowAttribute)
        // in rare cases an app has a window(s) but none are marked main, just pick first one...
        if _windowEl == nil,
           let windowEls: [AXUIElement] = getAXUIAttr(appEl, kAXWindowsAttribute),
           windowEls.count > 0 {
            _windowEl = windowEls[0]
        }
    } else if let index = wIdent.index {
        if let windowEls: [AXUIElement] = getAXUIAttr(appEl, kAXWindowsAttribute),
           windowEls.indices.contains(index) {
            _windowEl = windowEls[index]
        }
    } else if let title = wIdent.title {
        if let windowEls: [AXUIElement] = getAXUIAttr(appEl, kAXWindowsAttribute) {
            _windowEl = windowEls.first(where: {getAXUIAttr($0, kAXTitleAttribute) == title})
        }
    } else {
        throw MWCError("Invalid widow identifier")
    }
    guard let windowEl = _windowEl else {
        throw NotFoundError("Window not found")
    }
    return (app, windowEl)
}


func getTitlebarHeightEstimate(_ window: AXUIElement) -> Double {
    // I've wasted a few days looking for consistent ways to measure the NSTitlebar[Container]View
    // to no avail.  The best I can consistently do is find the close button, which every app I've
    // tested does expose, then make an assumption that it's centered on a menu bar.
    if let btn = findAXUIElement(window, .subrole("AXCloseButton")),
       let winSize = getAXUIElementSize(window),
       let btnSize = getAXUIElementSize(btn) {
        let height = (btnSize.origin.y - winSize.origin.y) * 2 + btnSize.size.height
        // Paranoid sanity checks just in case the app in question is odd...
        if height >= 0 && height < 60 {
            return height
        } else {
            print("Oddly sized close button:", btnSize, "win-size:", winSize, "est-height:", height)
        }
    }
    return 0
}


func hasAccessibilityPermission() -> Bool {
    return AXIsProcessTrusted()
}


func getMainScreenSize() throws -> CGRect {
    guard let screen = getMainScreen() else {
        throw MWCError("Main screen unavailable")
    }
    return screen.frame
}


func getActiveScreenSize() throws -> CGRect {
    guard let screen = getActiveScreen() else {
        throw MWCError("Active screen unavailable")
    }
    return screen.frame
}


func getScreenSizes() -> [CGRect] {
    pumpNSApp()
    return NSScreen.screens.map({$0.frame})
}


func getMenuBarHeight() throws -> Double {
    guard let screen = getMainScreen() else {
        throw MWCError("Main screen unavailable")
    }
    return screen.frame.height - screen.visibleFrame.height
}


func getWindowSize(_ appIdent: AppIdentifier) throws -> CGRect {
    return try getWindowSize(appIdent, nil);
}


func getWindowSize(_ appIdent: AppIdentifier, _ winIdent: WindowIdentifier?) throws -> CGRect {
    if !hasAccessibilityPermission() {
        throw AXPermError()
    }
    let (_, window) = try getAppWindow(appIdent, winIdent)
    guard let rect = getAXUIElementSize(window) else {
        throw MWCError("Invalid window info")
    }
    return rect
}


func getAppDescs() throws -> [AppDesc] {
    if !hasAccessibilityPermission() {
        throw AXPermError()
    }
    let apps = NSWorkspace.shared.runningApplications.filter({$0.isFinishedLaunching})
    return apps.map { app in
        AppDesc(
            name: app.localizedName ?? "",
            pid: Int(app.processIdentifier),
            active: app.isActive,
            hidden: app.isHidden,
            bundleIdent: app.bundleIdentifier,
            bundleURL: app.bundleURL?.absoluteString,
            execURL: app.executableURL?.absoluteString,
            launchDate: (app.launchDate != nil) ? toISODateTime(app.launchDate!) : nil
        )
    }
}


func getWindowDesc(_ winEl: AXUIElement, focused: Bool? = nil) -> WindowDesc {
    var window = WindowDesc(
        ident: getAXUIAttr(winEl, kAXIdentifierAttribute),
        title: getAXUIAttr(winEl, kAXTitleAttribute) ?? nil,
        titlebarHeightEstimate: getTitlebarHeightEstimate(winEl),
        focused: focused ?? false,
        minimized: getAXUIAttr(winEl, kAXMinimizedAttribute) ?? false
    )
    if let _position: AXValue = getAXUIAttr(winEl, kAXPositionAttribute) {
        AXValueGetValue(_position, .cgPoint, &window.position)
    }
    if let _size: AXValue = getAXUIAttr(winEl, kAXSizeAttribute) {
        AXValueGetValue(_size, .cgSize, &window.size)
    }
    return window
}


func getWindowDescs(_ appIdent: AppIdentifier) throws -> [WindowDesc] {
    try validateAppWindowQuery(appIdent)
    if !hasAccessibilityPermission() {
        throw AXPermError()
    }
    let app = try getApp(appIdent)
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    var windows: [WindowDesc] = []
    if let windowEls: [AXUIElement] = getAXUIAttr(appEl, kAXWindowsAttribute),
       windowEls.count > 0 {
        let focusedWindowEl: AXUIElement? = app.isActive ? getAXUIAttr(appEl, kAXFocusedWindowAttribute) : nil
        for winEl in windowEls {
            windows.append(getWindowDesc(winEl, focused: winEl == focusedWindowEl))
        }
    }
    return windows
}


func activateWindow(_ appIdent: AppIdentifier, _ winIdent: WindowIdentifier? = nil) throws {
    let (app, window) = try getAppWindow(appIdent, winIdent)
    if app.isHidden {
        app.unhide();
    }
    if #available(macOS 14, *) {
        // Required in some cases (i.e. ZwiftAppSilicon) but it's unclear why..
        NSApplication.shared.yieldActivation(to: app)
    }
    app.activate()
    let res = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    if res != .success {
        try setAXUIAttr(window, kAXMainAttribute, kCFBooleanTrue)
        //throw MWCError("Failed to raise window: \(res.rawValue)")
    }
}


func setWindowSize(_ appIdent: AppIdentifier, _ size: CGSize, position: CGPoint? = nil) throws {
    return try setWindowSize(appIdent, nil, size, position: position)
}


func setWindowSize(_ appIdent: AppIdentifier, _ winIdent: WindowIdentifier?,
                   _ size: CGSize, position: CGPoint? = nil) throws {
    if !hasAccessibilityPermission() {
        throw AXPermError()
    }
    let (_, window) = try getAppWindow(appIdent, winIdent)
    // NOTE: Must do position first, side effects occur otherwise...
    if position != nil {
        // X, Y get treated like floored Ints, round first...
        var posRounded = CGPoint(x: round(position!.x), y: round(position!.y))
        try setAXUIAttr(window, kAXPositionAttribute, AXValueCreate(.cgPoint, &posRounded)!)
    }
    var _size = size
    try setAXUIAttr(window, kAXSizeAttribute, AXValueCreate(.cgSize, &_size)!)
}
