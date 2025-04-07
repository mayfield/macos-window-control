import Foundation
import Cocoa


func resizeCmd(_ appName: String, _ width: Double, _ height: Double,
               x: Double? = nil, y: Double? = nil) throws {
    let size = CGSize(width: width, height: height)
    let appIdent = AppIdentifier(name: appName)
    var position: CGPoint?
    if let x = x, let y = y {
        position = CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
    try setWindowSize(appIdent, size, position: position)
}


func zoomCmd(_ scale: Double? = nil, cx: Double? = nil, cy: Double? = nil) throws {
    if let scale = scale {
        var center: CGPoint?
        if let x = cx, let y = cy {
            center = CGPoint(x: x, y: y)
        }
        try setZoom(scale, center: center)
    } else {
        let (scale, center, smooth) = try getZoom()
        print("Zoom:", scale)
        print("Center:", center)
        print("Smooth:", smooth)
    }
}


func fullscreenCmd(_ appName: String) throws {
    let display = try getActiveDisplay()
    let appIdent = AppIdentifier(name: appName)
    try activateWindow(appIdent)
    let (_, window) = try getAppWindow(appIdent)
    let titleBarHeight = getTitlebarHeightEstimate(window)
    let scale = display.size.height / (display.visibleSize.height - titleBarHeight)
    let size = CGSize(width: display.size.width / scale, height: display.visibleSize.height)
    print("Resizing:", size, display.visiblePosition)
    try setWindowSize(appIdent, size, position: display.visiblePosition)
    let bottomLeft = CGPoint(x: display.position.x, y: display.position.y + display.size.height - 1)
    print("Zooming:", scale, "center", bottomLeft, "displayId", display.id)
    try setZoom(scale, center: bottomLeft, displayId: display.id)
}


func usageAndExit() {
    let prog = CommandLine.arguments[0]
    print("Usage: \(prog) COMMAND [ARGS...]")
    print("  Command 'resize':")
    print("    Args: PROC_NAME WIDTH HEIGHT [X Y]")
    print("    Example: \(prog) resize ZwiftAppSilicon 1920 1080")
    print("")
    print("  Command 'zoom':")
    print("    Args: [SCALE [CENTER_X CENTER_Y]]")
    print("    Example: \(prog) zoom 1.2 960 640")
    print("")
    print("  Command 'fullscreen':")
    print("    Args: APP")
    print("    Example: \(prog) ZwiftAppSilicon")
    print("")
    print("  Command 'permission':")
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
        guard let scale = Double(args[2]) else {
            print("Invalid number for scale")
            return usageAndExit()
        }
        if args.count >= 5 {
            guard let cx = Double(args[3]),
                  let cy = Double(args[4]) else {
                print("Invalid numbers for center-x, or center-y")
                return usageAndExit()
            }
            return try zoomCmd(scale, cx: cx, cy: cy)
        } else {
            return try zoomCmd(scale)
        }
    } else if cmdName == "fullscreen" {
        if args.count < 3 {
            return usageAndExit()
        }
        let appName = args[2]
        return try fullscreenCmd(appName)
    } else if cmdName == "permission" {
        if hasAccessibilityPermission(prompt: true) {
            print("true")
        } else {
            print("false")
        }
    } else {
        if cmdName != "--help" {
            print("Invalid COMMAND:", cmdName)
        }
        return usageAndExit()
    }
}

do {
    try main()
} catch let e as MWCError {
    print(e.message)
    exit(1)
}
