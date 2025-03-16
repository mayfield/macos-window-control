import Foundation


typealias DeferredCallback = @convention(c) (UnsafeRawPointer, UnsafeRawPointer, CInt) -> Void


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


struct AppWindowIdentifier: Codable {
    var app: AppIdentifier
    var window: WindowIdentifier? = nil
}


func objEncode(_ obj: Encodable, into: UnsafeMutablePointer<CChar>, size: CInt) throws -> CInt {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(obj)
    if data.count > size {
        throw MWCError("JSON input buffer too small")
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


func wrapCallAsync(_ fnClosure: @escaping () async throws -> Encodable?,
                   _ rawDeferredCtx: UnsafeRawPointer, _ rawDeferredCallback: UnsafeRawPointer) {
    print("  outside task", getpid())
    let deferredCallback = unsafeBitCast(rawDeferredCallback, to: DeferredCallback.self)
    // Swift 6 requires this evil hack..
    struct CtxWrap: @unchecked Sendable {
        let raw: UnsafeRawPointer
    }
    let deferredCtxWrap = CtxWrap(raw: rawDeferredCtx)
    //DispatchQueue.global().async {
     //   print("    inside dispatch queue ", getpid())
        Task {
            print("       inside task")
            do {
                print("starttit  XXX")
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                var data: Data
                do {
                    data = try encoder.encode(wrapSuccess(try await fnClosure()))
                } catch let e {
                    data = try encoder.encode(wrapError(e))
                }
                print("back from async, ready to call back to node deferred callbavck XXX", data)
                data.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
                    deferredCallback(deferredCtxWrap.raw, p.baseAddress!, CInt(data.count))
                    print("did it work???????...", data)
                }
                print("DIDI I DIE??????")
            } catch let e {
                print("Internal Error", e)
            }
        }
       // print("after Task.detached")
    //}
    print("after dispatch queue.detached")
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


@_cdecl("mwc_getApps")
public func mwc_getApps(_ argsPtr: UnsafePointer<CChar>, _ argsSize: CInt,
                        _ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        return try getAppDescs()
    }, outPtr, outSize)
}


@_cdecl("mwc_getWindows")
public func mwc_getWindows(_ argsPtr: UnsafePointer<CChar>, _ argsSize: CInt,
                           _ deferredCtx: UnsafeRawPointer, _ deferredCallbackRaw: UnsafeRawPointer) {
    let argsData = Data(bytes: argsPtr, count: Int(argsSize)) // Must copy before yield!
    wrapCallAsync({
        struct Args: Decodable {
            let app: AppIdentifier
        }
        let args = try JSONDecoder().decode(Args.self, from: argsData)
        return try await getWindowDescs(args.app)
    }, deferredCtx, deferredCallbackRaw)
}



@_cdecl("mwc_getWindowSize")
public func mwc_getWindowSize(_ argsPtr: UnsafePointer<CChar>, _ argsSize: CInt,
                              _ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        let ident: AppWindowIdentifier = try objDecode(argsPtr, size: argsSize)
        let rect = try getWindowSize(ident.app, ident.window)
        return [
            "size": [rect.size.width, rect.size.height],
            "position": [rect.origin.x, rect.origin.y],
        ]
    }, outPtr, outSize)
}


@_cdecl("mwc_setWindowSize")
public func mwc_setWindowSize(_ argsPtr: UnsafePointer<CChar>, _ argsSize: CInt,
                              _ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        struct Args: Decodable {
            let app: AppIdentifier
            let window: WindowIdentifier?
            let size: CGSize
            let position: CGPoint?
        }
        let args: Args = try objDecode(argsPtr, size: argsSize)
        try setWindowSize(args.app, args.window, args.size, position: args.position)
        return nil
    }, outPtr, outSize)
}


@_cdecl("mwc_activateWindow")
public func mwc_activateWindow(_ argsPtr: UnsafePointer<CChar>, _ argsSize: CInt,
                               _ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        let ident: AppWindowIdentifier = try objDecode(argsPtr, size: argsSize)
        try activateWindow(ident.app, ident.window)
        return nil
    }, outPtr, outSize)
}


@_cdecl("mwc_getZoom")
public func mwc_getZoom(_ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        let (scale, center, smooth) = try getZoom()
        struct Resp: Encodable {
            let scale: Double
            let smooth: Bool
            let center: [String: Double]
        }
        return Resp(scale: scale, smooth: smooth, center: ["x": center.x, "y": center.y])
    }, outPtr, outSize)
}


@_cdecl("mwc_setZoom")
public func mwc_setZoom(_ argsPtr: UnsafePointer<CChar>, _ argsSize: CInt,
                        _ outPtr: UnsafeMutablePointer<CChar>, _ outSize: CInt) -> CInt {
    return wrapCall({
        struct Args: Decodable {
            let scale: Double
            let center: CGPoint?
            let smooth: Bool?
        }
        let args: Args = try objDecode(argsPtr, size: argsSize)
        try setZoom(args.scale, center: args.center, smooth: args.smooth)
        return nil
    }, outPtr, outSize)
}
