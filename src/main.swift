import Foundation
import Cocoa


class CmdError: Error {
    var message: String
    let code: Int32

    init(_ message: String, code: Int32? = 127) {
        self.message = message
        self.code = code!
    }
}

class PermError: CmdError {
    init(_ message: String) {
        super.init(message, code: 128)
    }
}

class NotFoundError: CmdError {
    init(_ message: String) {
        super.init(message, code: 129)
    }
}


func getCGSConnectionID() throws -> Int {
    let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSMainConnectionID")
    if fnSym == nil {
        throw CmdError("Failed to find CGSMainConnectionID function")
    }
    typealias Args = @convention(c) (UnsafeRawPointer?) -> Int
    let fn = unsafeBitCast(fnSym, to: Args.self)
    return fn(nil)
}


func setZoom(_ cid: Int, _ factor: Double, cx: Double, cy: Double, smooth: Bool? = nil) throws {
    let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSSetZoomParameters")
    if fnSym == nil {
        throw CmdError("Failed to find CGSSetZoomParameters function")
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
    //  2. Accessablity shortcuts to affect zoom (i.e. ctrl + mouse scroll)
    //  3. setZoom(...args)  # ensure args are identical to step 1.
    // Expect no corruption on screen if it worked.
    withUnsafePointer(to: &origin) { originPtr in
        fn(cid, originPtr, factor, !_smooth!)
    }
    withUnsafePointer(to: &origin) { originPtr in
        fn(cid, originPtr, factor, _smooth!)
    }
}


func getZoom(_ cid: Int) throws -> (Double, CGPoint, Bool) {
    let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSGetZoomParameters")
    if fnSym == nil {
        throw CmdError("Failed to find CGSGetZoomParameters function")
    }
    typealias Args = @convention(c) (
        Int,
        UnsafeMutablePointer<CGPoint>,
        UnsafeMutablePointer<Double>,
        UnsafeMutablePointer<Bool>
    ) -> Void
    let fn = unsafeBitCast(fnSym, to: Args.self)
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


func getMainScreenSize() throws -> (Double, Double) {
    guard let screen = NSScreen.main else {
        throw CmdError("Main screen unavailable")
    }
    return (screen.frame.width, screen.frame.height)
}


func getMenuBarHeight() throws -> Double {
    guard let screen = NSScreen.main else {
        throw CmdError("Main screen unavailable")
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
        throw CmdError("Failed to get main window: \(axRes.rawValue)")
    }
    guard let window = mainWindow as! AXUIElement? else {
        throw CmdError("Unexpected unwrap error")
    }
    return window
}


func getWinAttrValue(_ window: AXUIElement, _ attr: String) throws -> AnyObject {
    var _val: AnyObject?
    let res = AXUIElementCopyAttributeValue(window, attr as CFString, &_val)
    if res != .success {
        throw CmdError("Failed to get window attr [\(attr)]: \(res.rawValue)")
    }
    if let val = _val {
        return val
    } else {
        throw CmdError("Window attr [\(attr)] is NULL")
    }
}


func setWinAttrValue(_ window: AXUIElement, _ attr: String, _ value: AnyObject) throws {
    let res = AXUIElementSetAttributeValue(window, attr as CFString, value)
    if res != .success {
        throw CmdError("Failed to set window attr [\(attr)]: \(res.rawValue)")
    }
}


func getAppByName(_ name: String) throws -> NSRunningApplication {
    let runningApps = NSWorkspace.shared.runningApplications
    guard let app = runningApps.first(where: {$0.localizedName == name}) else {
        throw NotFoundError("App not found")
    }
    return app
}


func getAppSize(_ appName: String) throws -> CGRect {
    let app = try getAppByName(appName)
    let window = try getAppMainWindow(app)
    let _pos = try getWinAttrValue(window, kAXPositionAttribute)
    let _size = try getWinAttrValue(window, kAXSizeAttribute)
    var rect = CGRect.zero
    if !AXValueGetValue(_pos as! AXValue, .cgPoint, &rect.origin) ||
       !AXValueGetValue(_size as! AXValue, .cgSize, &rect.size) {
        throw CmdError("Invalid window info")
    }
    return rect
}


func resizeCmd(_ appName: String, _ width: Double, _ height: Double, x: Double? = 0, y: Double? = 0) throws {
    let app = try getAppByName(appName)
    let window = try getAppMainWindow(app)
    // X, Y get treated like floored Ints, round first...
    var pos = CGPoint(x: CGFloat(round(x!)), y: CGFloat(round(y!)))
    var size = CGSize(width: CGFloat(width), height: CGFloat(height))
    try setWinAttrValue(window, kAXPositionAttribute, AXValueCreate(.cgPoint, &pos)!)
    try setWinAttrValue(window, kAXSizeAttribute, AXValueCreate(.cgSize, &size)!)
    app.activate()
}


func zoomCmd(_ factor: Double? = nil, cx: Double? = nil, cy: Double? = nil) throws {
    let cid = try getCGSConnectionID()
    if factor == nil {
        let (factor, origin, smooth) = try getZoom(cid)
        print("Zoom:", factor)
        print("Origin:", origin)
        print("Smooth:", smooth)
        return
    } else {
        if cx == nil || cy == nil {
            try setZoom(cid, factor!, cx: 0, cy: 0)
        } else {
            try setZoom(cid, factor!, cx: cx!, cy: cy!)
        }
    }
}


func fullscreenCmd(_ appName: String) throws {
    let (sWidth, sHeight) = try getMainScreenSize()
    let menuHeight = try getMenuBarHeight()
    // HACK: I don't know of an API to get the real height.
    let estAppFrameHeight = 28.0
    let scale = (sHeight - menuHeight - estAppFrameHeight) / sHeight
    let adjWidth = sWidth * scale
    let adjHeight = sHeight - menuHeight
    print("Resizing:", adjWidth, adjHeight, 0, menuHeight)
    try resizeCmd(appName, adjWidth, adjHeight, x: 0, y: menuHeight)
    print("Zooming:", 1 / scale, 0, sHeight)
    try zoomCmd(1 / scale, cx: 0, cy: sHeight)
}


func usageAndExit() {
    let prog = CommandLine.arguments[0]
    print("Usage: \(prog) COMMAND [ARGS...]")
    print("  Command 'resize':")
    print("    Args: PROC_NAME WIDTH HEIGHT [X Y]")
    print("    Example: \(prog) resize ZwiftAppSilicon 1920 1080")
    print("")
    print("  Command 'zoom':")
    print("    Args: [FACTOR [CENTER_X CENTER_Y]]")
    print("    Example: \(prog) zoom 1.2 960 640")
    print("")
    print("  Command 'fullscreen':")
    print("    Args: APP")
    print("    Example: \(prog) ZwiftAppSilicon")
    exit(1)
}


func main() throws {
    let args = CommandLine.arguments
    if args.count < 2 {
        return usageAndExit()
    }
    let cmdName = args[1]
    if cmdName == "resize" {
        if args.count < 5 {
            return usageAndExit()
        }
        let appName = args[2]
        guard let width = Double(args[3]),
              let height = Double(args[4]) else {
            print("Invalid numbers for width and/or height")
            return usageAndExit()
        }
        if args.count > 6 {
            guard let x = Double(args[5]),
                  let y = Double(args[6]) else {
                print("Invalid numbers for x and/or y")
                return usageAndExit()
            }
            return try resizeCmd(appName, width, height, x: x, y: y)
        } else {
            return try resizeCmd(appName, width, height)
        }
    } else if cmdName == "zoom" {
        if args.count < 3 {
            return try zoomCmd()
        }
        guard let factor = Double(args[2]) else {
            print("Invalid number for factor")
            return usageAndExit()
        }
        if args.count >= 5 {
            guard let cx = Double(args[3]),
                  let cy = Double(args[4]) else {
                print("Invalid numbers for center-x, or center-y")
                return usageAndExit()
            }
            return try zoomCmd(factor, cx: cx, cy: cy)
        } else {
            return try zoomCmd(factor)
        }
    } else if cmdName == "fullscreen" {
        if args.count < 3 {
            return usageAndExit()
        }
        let appName = args[2]
        return try fullscreenCmd(appName)
    } else {
        if cmdName != "--help" {
            print("Invalid COMMAND:", cmdName)
        }
        return usageAndExit()
    }
}

do {
    try main()
} catch let e as CmdError {
    print(e.message)
    exit(e.code)
}
