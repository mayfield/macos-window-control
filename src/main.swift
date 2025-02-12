import Foundation


func resizeCmd(_ appName: String, _ width: Double, _ height: Double, x: Double? = 0, y: Double? = 0) throws {
    try resizeAppWindow(appName, width, height, x: x, y: y)
}


func zoomCmd(_ factor: Double? = nil, cx: Double? = nil, cy: Double? = nil) throws {
    if factor == nil {
        let (factor, origin, smooth) = try getZoom()
        print("Zoom:", factor)
        print("Origin:", origin)
        print("Smooth:", smooth)
        return
    } else {
        if cx == nil || cy == nil {
            try setZoom(factor!, cx: 0, cy: 0)
        } else {
            try setZoom(factor!, cx: cx!, cy: cy!)
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
} catch let e as MWCError {
    print(e.message)
    exit(1)
}
