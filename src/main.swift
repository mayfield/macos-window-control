import Foundation
import Cocoa
import ApplicationServices


struct E: Error {
    var m: String
}


func getCGSConnectionID() throws -> Int {
    let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSMainConnectionID")
    if fnSym == nil {
        throw E(m: "Failed to find CGSMainConnectionID function")
    }
    typealias Args = @convention(c) (UnsafeRawPointer?) -> Int
    let fn = unsafeBitCast(fnSym, to: Args.self)
    return fn(nil)
}


func setZoom(_ cid: Int, _ factor: Double, cx: Double, cy: Double) throws {
    let fnSym = dlsym(dlopen(nil, RTLD_LAZY), "CGSSetZoomParameters")
    if fnSym == nil {
        throw E(m: "Failed to find CGSSetZoomParameters function")
    }
    typealias Args = @convention(c) (Int, UnsafePointer<CGPoint>, Double, Int8) -> Void
    let fn = unsafeBitCast(fnSym, to: Args.self)
    // X, Y get floored, round first...
    var origin = CGPoint(x: round(cx), y: round(cy))
    withUnsafePointer(to: &origin) { originPtr in
        fn(cid, originPtr, factor, 1)
    }
}


func getMainScreenSize() throws -> (Double, Double) {
    guard let screen = NSScreen.main else {
        throw E(m: "Main screen unavailable")
    }
    return (screen.frame.width, screen.frame.height)
}


func getMenuBarHeight() throws -> Double {
    guard let screen = NSScreen.main else {
        throw E(m: "Main screen unavailable")
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
            print("Go to System -> Privacy and Security -> Accessibility, then enable this tool")
        }
        throw E(m: "Failed to get main window: \(axRes.rawValue)")
    }
    guard let window = mainWindow as! AXUIElement? else {
        throw E(m: "Unexpected unwrap error")
    }
    return window
}


func getWinAttrValue(_ window: AXUIElement, _ attr: String) throws -> AnyObject {
    var _val: AnyObject?
    let res = AXUIElementCopyAttributeValue(window, attr as CFString, &_val)
    if res != .success {
        throw E(m: "Failed to get window attr [\(attr)]: \(res.rawValue)")
    }
    if let val = _val {
        return val
    } else {
        throw E(m: "Window attr [\(attr)] is NULL")
    }
}


func setWinAttrValue(_ window: AXUIElement, _ attr: String, _ value: AnyObject) throws {
    let res = AXUIElementSetAttributeValue(window, attr as CFString, value)
    if res != .success {
        throw E(m: "Failed to set window attr [\(attr)]: \(res.rawValue)")
    }
}
   

func getAppByName(_ name: String) throws -> NSRunningApplication {
    let runningApps = NSWorkspace.shared.runningApplications
    guard let app = runningApps.first(where: {$0.localizedName == name}) else {
        throw E(m: "App not found")
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
        throw E(m: "Invalid window info")
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


func zoomCmd(_ factor: Double, cx: Double? = nil, cy: Double? = nil) throws {
    let cid = try getCGSConnectionID()
    if cx == nil || cy == nil {
        try setZoom(cid, factor, cx: 0, cy: 0)
    } else {
        try setZoom(cid, factor, cx: cx!, cy: cy!)
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
    print("    Args: FACTOR [CENTER_X CENTER_Y]")
    print("    Example: \(prog) zoom 1.2 960 640")
    print("")
    print("  Command 'fullscreen':")
    print("    Args: APP")
    print("    Example: \(prog) ZwiftAppSilicon")
    exit(1)
}


func main() {
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
            try! resizeCmd(appName, width, height, x: x, y: y)
        } else {
            try! resizeCmd(appName, width, height)
        }
    } else if cmdName == "zoom" {
        if args.count < 3 {
            return usageAndExit()
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
            try! zoomCmd(factor, cx: cx, cy: cy)
        } else {
            try! zoomCmd(factor)
        }
    } else if cmdName == "fullscreen" {
        if args.count < 3 {
            return usageAndExit()
        }
        let appName = args[2]
        try! fullscreenCmd(appName)
    } else {
        if cmdName != "--help" {
            print("Invalid COMMAND:", cmdName)
        }
        return usageAndExit()
    }
}

main()
