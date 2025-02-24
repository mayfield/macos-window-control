import Foundation


// Hack around swift type system...
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}


struct SuccessResp: Encodable {
    let success: Bool
    let value: AnyEncodable?
}


struct ErrorResp: Encodable {
    struct Error: Encodable {
        let type: String
        let message: String
        let stack: [String]
    }

    let success: Bool
    let error: Error
}


func objEncode(_ obj: Encodable, into: UnsafeMutablePointer<CChar>, size: CInt) throws -> CInt {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(obj)
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


func wrapError(_ e: Error) -> ErrorResp {
    return ErrorResp(
        success: false,
        error: ErrorResp.Error(
            type: String(describing: type(of: e)),
            message: (e as? MWCError)?.message ?? String(describing: e),
            stack: (e as? MWCError)?.stack ?? []
        )
    )
}


func wrapSuccess(_ _value: Encodable?) -> SuccessResp {
    var value: AnyEncodable?
    if let x = _value {
        value = AnyEncodable(x)
    }
    return SuccessResp(
        success: true,
        value: value
    )
}


func wrapCall(_ fnClosure: () throws -> Encodable?, _ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    var success: SuccessResp?
    var error: ErrorResp?
    do {
        do {
            success = wrapSuccess(try fnClosure())
        } catch let e {
            error = wrapError(e)
        }
        return try objEncode(success ?? error, into: outPtr, size: outSize)
    } catch let e {
        print("Internal Error", e)
        return -1
    }
}


@_cdecl("mwc_hasAccessibilityPermission")
public func mwc_hasAccessibilityPermission(_ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        return hasAccessibilityPermission()
    }, outPtr, outSize)
}


@_cdecl("mwc_getMainScreenSize")
public func mwc_getMainScreenSize(_ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        return try getMainScreenSize()
    }, outPtr, outSize)
}


@_cdecl("mwc_getMenuBarHeight")
public func mwc_getMenuBarHeight(_ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        return try getMenuBarHeight()
    }, outPtr, outSize)
}


@_cdecl("mwc_getWindowApps")
public func mwc_getWindowApps(_ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        return try getWindowApps()
    }, outPtr, outSize)
}


@_cdecl("mwc_getAppWindowSize")
public func mwc_getAppWindowSize(_ argsPtr: UnsafePointer<CChar>, _ argsSize: CInt,
                                 _ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        let query: AppWindowQuery = try objDecode(argsPtr, size: argsSize)
        let rect = try getAppWindowSize(query)
        return [
            "size": [rect.size.width, rect.size.height],
            "position": [rect.origin.x, rect.origin.y],
        ]
    }, outPtr, outSize)
}


@_cdecl("mwc_resizeAppWindow")
public func mwc_resizeAppWindow(_ argsPtr: UnsafePointer<CChar>, _ argsSize: CInt,
                                _ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        struct Args: Decodable {
            let query: AppWindowQuery
            let size: CGSize
            let position: CGPoint?
        }
        let args: Args = try objDecode(argsPtr, size: argsSize)
        try resizeAppWindow(args.query, args.size, position: args.position)
        return nil
    }, outPtr, outSize)
}


@_cdecl("mwc_activateAppWindow")
public func mwc_activateAppWindow(_ argsPtr: UnsafePointer<CChar>, _ argsSize: CInt,
                                  _ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        let query: AppWindowQuery = try objDecode(argsPtr, size: argsSize)
        try activateAppWindow(query)
        return nil
    }, outPtr, outSize)
}


@_cdecl("mwc_getZoom")
public func mwc_getZoom(_ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        let (factor, center, smooth) = try getZoom()
        struct Resp: Encodable {
            let factor: Double
            let smooth: Bool
            let center: [String: Double]
        }
        return Resp(factor: factor, smooth: smooth, center: ["x": center.x, "y": center.y])
    }, outPtr, outSize)
}


@_cdecl("mwc_setZoom")
public func mwc_setZoom(_ argsPtr: UnsafePointer<CChar>, _ argsSize: CInt,
                        _ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        struct Args: Decodable {
            let factor: Double
            let center: CGPoint?
            let smooth: Bool?
        }
        let args: Args = try objDecode(argsPtr, size: argsSize)
        try setZoom(args.factor, center: args.center, smooth: args.smooth)
        return nil
    }, outPtr, outSize)
}
