// Ported to Swift from Volta (Apache 2.0, https://github.com/irshadm/volta-android), itself a Kotlin port of
// mg-ismart-india-client by John Lazarus (MIT, https://github.com/john-lazarus/mg-ismart-india-client).
// See NOTICE.md for both licences.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Credentials: Equatable, Sendable {
    public let phone: String
    public let password: String
    public init(phone: String, password: String) {
        self.phone = phone
        self.password = password
    }
}

/// Persists the session so restarts and background work don't log in again (the app keeps it in the Keychain).
public protocol SessionStore: Sendable {
    func load() -> MGSession?
    func save(_ session: MGSession?)
}

public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: MGSession?
    public init(_ session: MGSession? = nil) { self.session = session }
    public func load() -> MGSession? { lock.lock(); defer { lock.unlock() }; return session }
    public func save(_ session: MGSession?) { lock.lock(); defer { lock.unlock() }; self.session = session }
}

/// One HTTP exchange, so tests can stand in for MG's servers.
public struct HTTPReply: Sendable {
    public let status: Int
    public let body: String
    public let headers: [String: String]
    public init(status: Int, body: String, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPReply
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> HTTPReply {
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (k, v) in http?.allHeaderFields ?? [:] { headers["\(k)"] = "\(v)" }
        return HTTPReply(status: http?.statusCode ?? 0, body: String(decoding: data, as: UTF8.self), headers: headers)
    }
}

/// Serialises MG exchanges: the TAP protocol polls one request at a time per session.
actor AsyncMutex {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func unlock() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    func withLock<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await lock()
        do {
            let v = try await body()
            unlock()
            return v
        } catch {
            unlock()
            throw error
        }
    }
}

/// Client for MG India's i-SMART servers: one session, logins only when the server says the session is invalid, a
/// guard against a login tug-of-war with the MG app, polled status and charge frames, PIN-verified commands.
public actor MGIsmartClient {
    public static let userAgent = "CER_IKE_01/2.3.0 (iPad; iOS 26.3; Scale/2.00)"
    public static let statusAttempts = 10
    public static let commandAttempts = 15
    public static let maxLoginsPerHour = 3

    public struct Endpoints: Sendable {
        public var tapLogin: URL
        public var tapStatus: URL
        public var gatewayBase: String

        public static let production = Endpoints(
            tapLogin: URL(string: "https://iov-tap.mgindia.co.in/TAP.Web/ota.mp")!,
            tapStatus: URL(string: "https://iov-tap.mgindia.co.in/TAP.Web/ota.mpv21")!,
            gatewayBase: "https://iov-gateway.mgindia.co.in/api.app/v1"
        )

        public init(tapLogin: URL, tapStatus: URL, gatewayBase: String) {
            self.tapLogin = tapLogin
            self.tapStatus = tapStatus
            self.gatewayBase = gatewayBase
        }
    }

    public struct Reading: Sendable {
        public let snapshot: VehicleSnapshot
        public let charge: ChargeStatus?
    }

    private let transport: HTTPTransport
    private let credentials: @Sendable () -> Credentials?
    private let sessions: SessionStore
    private let prefix: String
    private let clock: @Sendable () -> Int64
    private let endpoints: Endpoints
    private let pollDelayMs: UInt64
    private let commandDelayMs: UInt64
    private let mutex = AsyncMutex()
    private var recentLogins: [Int64] = []
    public private(set) var vin: String?

    public init(
        transport: HTTPTransport = URLSessionTransport(),
        credentials: @escaping @Sendable () -> Credentials?,
        sessions: SessionStore,
        deviceIdPrefix: String = "mg-ev-ios-",
        clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        endpoints: Endpoints = .production,
        pollDelayMs: UInt64 = 1_500,
        commandDelayMs: UInt64 = 2_000
    ) {
        self.transport = transport
        self.credentials = credentials
        self.sessions = sessions
        self.prefix = deviceIdPrefix
        self.clock = clock
        self.endpoints = endpoints
        self.pollDelayMs = pollDelayMs
        self.commandDelayMs = commandDelayMs
    }

    private func nowS() -> Int64 { clock() / 1000 }

    private func sleep(_ ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }

    // MARK: - Transport

    private func postTap(_ url: URL, _ body: String) async throws -> String {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data(body.utf8)
        req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("en-US;q=1", forHTTPHeaderField: "Accept-Language")
        req.setValue(MGCrypto.tapSignature(body), forHTTPHeaderField: "APP-SIGNATURE")
        req.setValue("1", forHTTPHeaderField: "SIGNATURE")
        let res = try await transport.send(req)
        guard (200..<300).contains(res.status) else { throw IsmartError.failed("MG server error: HTTP \(res.status)") }
        return res.body
    }

    // MARK: - Session

    /// Logs in explicitly (first sign-in or "Reconnect"). Resets the tug-of-war guard.
    @discardableResult
    public func signIn() async throws -> MGSession {
        try await mutex.withLock {
            await self.resetLoginGuard()
            return try await self.loginLocked()
        }
    }

    private func resetLoginGuard() { recentLogins.removeAll() }

    public func signOut() {
        sessions.save(nil)
        vin = nil
    }

    private func loginLocked() async throws -> MGSession {
        guard let creds = credentials() else { throw IsmartError.failed("Not signed in to MG i-SMART") }
        let now = clock()
        recentLogins.removeAll { now - $0 > 3_600_000 }
        if recentLogins.count >= Self.maxLoginsPerHour {
            throw IsmartError.loginThrottled(retryAt: Date(timeIntervalSince1970: Double(recentLogins[0] + 3_600_000) / 1000))
        }
        recentLogins.append(now)
        var last: Error?
        for attempt in 0..<3 {
            do {
                let body = try LoginFrame.build(
                    phone: creds.phone, password: creds.password,
                    deviceId: try MGCrypto.deviceId(phone: creds.phone, prefix: prefix), nowS: nowS()
                )
                switch try LoginFrame.decode(try await postTap(endpoints.tapLogin, body)) {
                case let .ok(session):
                    sessions.save(session)
                    return session
                case let .rejected(message):
                    throw mfaRequired(message) ? IsmartError.mfaRequired(message) : IsmartError.loginRejected(message)
                }
            } catch let e as IsmartError where e.isLoginRejected {
                throw e // each POST counts against MG's daily quota
            } catch let e as IsmartError where e == .invalidInput(e.message) {
                throw e
            } catch {
                last = error
                if attempt < 2 { await sleep(1_500) }
            }
        }
        throw IsmartError.failed("Login failed: \(describe(last))")
    }

    private func session() async throws -> MGSession {
        if let s = sessions.load() { return s }
        return try await loginLocked()
    }

    /// When the login guard lets the next login through, or nil if one is allowed now.
    public func nextLoginAllowedAt() -> Date? {
        let now = clock()
        let recent = recentLogins.filter { now - $0 <= 3_600_000 }
        return recent.count >= Self.maxLoginsPerHour ? Date(timeIntervalSince1970: Double(recent[0] + 3_600_000) / 1000) : nil
    }

    // MARK: - Gateway (REST)

    private func gatewayGet(_ path: String, params: [String: String] = [:], retry: Bool = true) async throws -> [String: Any] {
        let s = try await session()
        guard var comps = URLComponents(string: endpoints.gatewayBase + path) else { throw IsmartError.failed("Bad gateway URL") }
        if !params.isEmpty { comps.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps.url else { throw IsmartError.failed("Bad gateway URL") }
        let signingPath = path + (comps.percentEncodedQuery.map { "?\($0)" } ?? "")
        let ts = String(clock())
        let ct = "application/json"
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(ct, forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "APP-CONTENT-ENCRYPTED")
        req.setValue("en-us", forHTTPHeaderField: "APP-LANGUAGE-TYPE")
        req.setValue(s.token, forHTTPHeaderField: "APP-LOGIN-TOKEN")
        req.setValue(s.uid, forHTTPHeaderField: "APP-USER-ID")
        req.setValue(ts, forHTTPHeaderField: "APP-SEND-DATE")
        req.setValue(MGCrypto.gatewaySignature(path: signingPath, timestamp: ts, contentType: ct), forHTTPHeaderField: "APP-VERIFICATION-STRING")
        req.setValue(ct, forHTTPHeaderField: "ORIGINAL-CONTENT-TYPE")
        let res = try await transport.send(req)
        guard (200..<300).contains(res.status) else { throw IsmartError.failed("MG gateway error: HTTP \(res.status)") }
        let plain = try MGCrypto.decryptGatewayBody(res.body, timestamp: res.header("APP-SEND-DATE") ?? "", contentType: res.header("ORIGINAL-CONTENT-TYPE") ?? ct)
        guard let parsed = try JSONSerialization.jsonObject(with: Data(plain.utf8)) as? [String: Any] else {
            throw IsmartError.failed("MG gateway sent an unreadable reply")
        }
        let code = (parsed["code"] as? NSNumber)?.intValue
        let message = parsed["message"] as? String
        if code == 7 || (code != nil && code != 0 && sessionInvalid(message)) {
            guard retry else { throw IsmartError.failed("MG session stays invalid after login") }
            sessions.save(nil)
            _ = try await loginLocked()
            return try await gatewayGet(path, params: params, retry: false)
        }
        if let code, code != 0 { throw IsmartError.failed(message ?? "MG gateway error \(code)") }
        return parsed
    }

    public func vehicles() async throws -> [Vehicle] {
        try await mutex.withLock { try await self.vehiclesLocked() }
    }

    private func vehiclesLocked() async throws -> [Vehicle] {
        let data = try await gatewayGet("/vehicle/userVinList")
        func list(_ e: Any?) -> [[String: Any]] {
            if let a = e as? [Any] { return a.compactMap { $0 as? [String: Any] } }
            if let o = e as? [String: Any] {
                for key in ["list", "vehicleList", "vehicles", "vinList", "result"] {
                    if let a = o[key] as? [Any] { return a.compactMap { $0 as? [String: Any] } }
                }
                return list(o["data"])
            }
            return []
        }
        let found: [Vehicle] = list(data).compactMap { o in
            guard let vin = ["vin", "VIN", "vinNo", "vehicleVin"].lazy.compactMap({ o[$0] as? String }).first else { return nil }
            return Vehicle(
                vin: vin, series: o["series"] as? String, model: o["modelName"] as? String,
                colorName: o["colorName"] as? String, isSubAccount: (o["isSubaccount"] as? Bool) ?? false
            )
        }
        if vin == nil || !found.contains(where: { $0.vin == vin }) { vin = found.first?.vin }
        return found
    }

    // MARK: - Status

    /// Full status, then (optionally) the charging frame, each polled to completion as the MG app does.
    public func read(includeCharge: Bool = true) async throws -> Reading {
        if vin == nil { _ = try await vehicles() }
        return try await mutex.withLock { try await self.readLocked(includeCharge: includeCharge) }
    }

    private func readLocked(includeCharge: Bool) async throws -> Reading {
        guard let v = vin else { throw IsmartError.failed("No vehicle on this MG account") }
        let polled = try await poll(label: "Status", vin: v, unavailable: []) { vin, s, ev, now in
            try Tap.statusRequest(uid: s.uid, token: s.token, vin: vin, eventId: ev, nowS: now)
        }
        guard let statusApp = polled else {
            throw IsmartError.failed("The car did not answer (it may be in a weak signal area)")
        }
        let status = try Tap.decodeStatusApp(statusApp)
        var charge: ChargeStatus?
        if includeCharge {
            // Decoded by shape: another model's frame may be longer. An unknown result on this request costs only
            // the charging figures; the status has already arrived.
            do {
                let app = try await poll(label: "Charge", vin: v, unavailable: [5], tolerateFraming: true) { vin, s, ev, now in
                    try Tap.chargeRequest(uid: s.uid, token: s.token, vin: vin, eventId: ev, nowS: now)
                }
                charge = app.flatMap(Tap.decodeChargeAppOrNil).map(ChargeStatus.from)
            } catch let e as IsmartError {
                if case .serverResult = e { charge = nil } else { throw e }
            }
        }
        return Reading(snapshot: .from(status), charge: charge)
    }

    /// Polls one request until its app payload arrives; nil means not available. Re-logs in at most once.
    private func poll(
        label: String, vin: String, unavailable: Set<Int>, tolerateFraming: Bool = false,
        frame: (String, MGSession, Int64, Int64) throws -> String
    ) async throws -> [UInt8]? {
        loginLoop: for loginAttempt in 0..<2 {
            var eventId: Int64 = 0
            for attempt in 0..<Self.statusAttempts {
                let s = try await session()
                let res: Tap.V21Response
                do {
                    res = try Tap.decodeV21(try await postTap(endpoints.tapStatus, try frame(vin, s, eventId, nowS())))
                } catch is TapFormatError {
                    guard tolerateFraming else { throw IsmartError.failed("\(label) response could not be read") }
                    await sleep(pollDelayMs)
                    continue
                }
                let d = res.dispatcher
                if let dv = d.vin, dv != vin { throw IsmartError.failed("\(label) response is for a different vehicle") }
                let result = d.result ?? 0
                switch result {
                case 2:
                    guard loginAttempt == 0 else { throw IsmartError.failed("\(label): session invalid") }
                    sessions.save(nil)
                    _ = try await loginLocked()
                    continue loginLoop
                case _ where unavailable.contains(result):
                    return nil
                case 0, 4, 6:
                    break
                default:
                    throw IsmartError.serverResult(label: label, result: result, serverMessage: d.errorText())
                }
                if let app = res.app { return app }
                eventId = d.eventId ?? eventId
                if attempt < Self.statusAttempts - 1 { await sleep(pollDelayMs) }
            }
            return nil
        }
        return nil
    }

    // MARK: - Commands

    /// Checks `pinHash` with MG, the same check every command starts with, without sending anything to the car.
    public func checkPin(_ pinHash: String) async throws {
        if vin == nil { _ = try await vehicles() }
        guard let v = vin else { throw IsmartError.failed("No vehicle on this MG account") }
        try await mutex.withLock { try await self.verifyPin(vin: v, pinHash: pinHash) }
    }

    /// Sends `cmd` after PIN verification. Lock, unlock and windows that never report completion are checked from a
    /// fresh status before reporting failure.
    public func command(_ cmd: RemoteCommand, pinHash: String) async throws {
        if vin == nil { _ = try await vehicles() }
        guard let v = vin else { throw IsmartError.failed("No vehicle on this MG account") }
        let startedAt = nowS()
        do {
            try await mutex.withLock {
                try await self.verifyPin(vin: v, pinHash: pinHash)
                try await self.sendCommand(vin: v, cmd: cmd)
            }
        } catch let IsmartError.commandIndeterminate(message) where message.contains("did not complete") {
            let check: ((VehicleSnapshot) -> Bool)?
            switch cmd {
            case .lock, .unlock:
                check = { $0.locked == (cmd == .lock) }
            case .windowsOpen, .windowsClose:
                let open = cmd == .windowsOpen
                check = { ($0.driverWindowOpen ?? !open) == open && ($0.passengerWindowOpen ?? !open) == open }
            default:
                check = nil
            }
            if let check, let snap = try? await read(includeCharge: false).snapshot, snap.statusTime > startedAt, check(snap) {
                return
            }
            throw IsmartError.commandIndeterminate(message)
        }
    }

    private func verifyPin(vin: String, pinHash: String) async throws {
        for loginAttempt in 0..<2 {
            let s = try await session()
            let d: Tap.DispatcherV11
            do {
                d = try Tap.decodePinResponse(try await postTap(endpoints.tapLogin, try Tap.pinRequest(uid: s.uid, token: s.token, vin: vin, pinHash: pinHash, nowS: nowS())))
            } catch is TapFormatError {
                throw IsmartError.failed("PIN response could not be read")
            }
            if let dv = d.vin, dv != vin { throw IsmartError.failed("PIN response is for a different vehicle") }
            switch d.result ?? 0 {
            case 0:
                return
            case 2:
                guard loginAttempt == 0 else { throw IsmartError.failed("PIN check: session invalid") }
                sessions.save(nil)
                _ = try await loginLocked()
            default:
                throw IsmartError.wrongPin("Wrong control PIN (result \(d.result ?? 0))")
            }
        }
    }

    private func sendCommand(vin: String, cmd: RemoteCommand) async throws {
        let s = try await session()
        let params = cmd.params.map { ($0.0, [UInt8(truncatingIfNeeded: $0.1)]) }
        var eventId: Int64 = 0
        for attempt in 0..<Self.commandAttempts {
            let raw: String
            do {
                raw = try await postTap(endpoints.tapStatus, try Tap.controlRequest(uid: s.uid, token: s.token, vin: vin, eventId: eventId, type: cmd.type, params: params, nowS: nowS()))
            } catch {
                throw IsmartError.commandIndeterminate("\(cmd.label): completion is unknown (\(describe(error)))")
            }
            let res: Tap.V21Response
            do {
                res = try Tap.decodeV21(raw)
            } catch {
                throw IsmartError.commandIndeterminate("\(cmd.label): response could not be read")
            }
            let result = res.dispatcher.result ?? 0
            guard [0, 4, 6].contains(result) else { throw IsmartError.commandIndeterminate("\(cmd.label): completion unknown (result \(result))") }
            if let dv = res.dispatcher.vin, dv != vin { throw IsmartError.commandIndeterminate("\(cmd.label): response for a different vehicle") }
            if let app = res.app {
                let c = try Tap.decodeControlApp(app)
                guard c.reqType == cmd.type else { throw IsmartError.commandIndeterminate("\(cmd.label): response type mismatch") }
                switch c.reqStatus {
                case 2: return
                case 1: break
                default:
                    throw IsmartError.failed("\(cmd.label) failed (status \(c.reqStatus)\(c.failureType.map { ", reason \($0)" } ?? ""))")
                }
            }
            guard let next = res.dispatcher.eventId else {
                throw IsmartError.commandIndeterminate("\(cmd.label): completion unknown (no polling cursor)")
            }
            eventId = next
            if attempt < Self.commandAttempts - 1 { await sleep(commandDelayMs) }
        }
        throw IsmartError.commandIndeterminate("\(cmd.label) did not complete")
    }
}

private func describe(_ error: Error?) -> String {
    switch error {
    case let e as IsmartError: return e.message
    case let e as TapFormatError: return e.message
    case let e?: return String(describing: e)
    case nil: return "unknown error"
    }
}
