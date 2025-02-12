import Foundation


func objEncode(_ obj: Encodable, into: UnsafeMutablePointer<CChar>, size: CInt) throws -> CInt {
    let data = try JSONEncoder().encode(obj)
    if data.count > size {
        throw MWCError("JSON input buffer overlow")
    }
    data.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
        _ = memcpy(into, p.baseAddress, data.count)
    }
    return CInt(data.count)
}


func objDecode<T: Decodable>(_ dataPtr: UnsafePointer<CChar>, size: CInt, type: T.Type = T.self) throws -> T {
    let data = Data(bytes: dataPtr, count: Int(size))
    return try JSONDecoder().decode(type, from: data)
}


@_cdecl("mwc_getMainScreenSize")
public func mwc_getMainScreenSize(_ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    do {
        let (x, y) = try getMainScreenSize();
        return try objEncode(["x": x, "y": y], into: outPtr, size: outSize)
    } catch let e {
        print("Unexpected error", e)
        return -1
    }
}


@_cdecl("mwc_getMenuBarHeight")
public func mwc_getMenuBarHeight(_ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    do {
        let height = try getMenuBarHeight()
        return try objEncode(height, into: outPtr, size: outSize)
    } catch let e {
        print("Unexpected error", e)
        return -1
    }
}


@_cdecl("mwc_resizeAppWindow")
public func mwc_resizeAppWindow(_ argsPtr: UnsafePointer<CChar>, _ argsSize: CInt) -> CInt {
    do {
        struct Args: Decodable {
            let appName: String
            let width: Double
            let height: Double
            let x: Double?
            let y: Double?
            let activate: Bool?
        }
        let args: Args = try objDecode(argsPtr, size: argsSize)
        try resizeAppWindow(args.appName, args.width, args.height, x: args.x, y: args.y, activate: args.activate)
        return 0
    } catch let e {
        print("Unexpected error", e)
        return -1
    }
}
