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
        let description: String
        let message: String
    }

    let success: Bool
    let error: Error
}


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


func wrapError(_ e: Error) -> ErrorResp {
    var message = "generic error"
    if let mwcError = e as? MWCError {
        message = mwcError.message
    }
    return ErrorResp(
        success: false,
        error: ErrorResp.Error(
            type: String(describing: type(of: e)),
            description: String(describing: e),
            message: message
        )
    )
}


func wrapSuccess(_ value: Encodable?) -> SuccessResp {
    return SuccessResp(
        success: true,
        value: value != nil ? AnyEncodable(value!) : nil
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


@_cdecl("mwc_getMainScreenSize")
public func mwc_getMainScreenSize(_ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        let (x, y) = try getMainScreenSize()
        return ["x": x, "y": y]
    }, outPtr, outSize)
}


@_cdecl("mwc_getMenuBarHeight")
public func mwc_getMenuBarHeight(_ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        return try getMenuBarHeight()
    }, outPtr, outSize)
}


@_cdecl("mwc_resizeAppWindow")
public func mwc_resizeAppWindow(_ argsPtr: UnsafePointer<CChar>, _ argsSize: CInt,
                                _ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
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
