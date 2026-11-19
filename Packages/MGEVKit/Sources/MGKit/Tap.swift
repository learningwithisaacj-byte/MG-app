// Ported to Swift from Volta (Apache 2.0, https://github.com/irshadm/volta-android), itself a Kotlin port of
// mg-ismart-india-client by John Lazarus (MIT, https://github.com/john-lazarus/mg-ismart-india-client).
// See NOTICE.md for both licences.

import Foundation

/// MG India TAP messages. Every encoder/decoder mirrors one ASN.1 type field for field; golden vectors produced by
/// the Python client pin the exact bytes (see `ismart_vectors.json` in the tests).
public enum Tap {
    public static let protocolV21 = 33
    public static let protocolV11 = 17
    public static let appProtocol = 513
    public static let reserved = 16
    public static let statusApp = "511"
    public static let controlApp = "510"
    public static let pinApp = "313"
    public static let chargeMessageId = 8
    static let i31: Int64 = 2_147_483_647
    static let u32: Int64 = 4_294_967_295
    static let u48: Int64 = 281_474_976_710_655

    // MARK: - Dispatcher (v2.1)

    public struct Dispatcher: Equatable {
        public var uid: String?
        public var token: String?
        public var applicationId: String
        public var vin: String?
        public var messageId: Int
        public var eventCreationTime: Int64
        public var eventId: Int64?
        public var ulCounter: Int?
        public var dlCounter: Int?
        public var ackCounter: Int?
        public var ackRequired: Bool?
        public var appDataLength: Int?
        public var appDataEncoding: Int? // 0 = perUnaligned
        public var appProtocolVersion: Int?
        public var testFlag: Int?
        public var result: Int?
        public var errorMessage: [UInt8]?

        public init(
            uid: String? = nil, token: String? = nil, applicationId: String, vin: String? = nil, messageId: Int,
            eventCreationTime: Int64, eventId: Int64? = nil, ulCounter: Int? = nil, dlCounter: Int? = nil,
            ackCounter: Int? = nil, ackRequired: Bool? = nil, appDataLength: Int? = nil, appDataEncoding: Int? = nil,
            appProtocolVersion: Int? = nil, testFlag: Int? = nil, result: Int? = nil, errorMessage: [UInt8]? = nil
        ) {
            self.uid = uid; self.token = token; self.applicationId = applicationId; self.vin = vin
            self.messageId = messageId; self.eventCreationTime = eventCreationTime; self.eventId = eventId
            self.ulCounter = ulCounter; self.dlCounter = dlCounter; self.ackCounter = ackCounter
            self.ackRequired = ackRequired; self.appDataLength = appDataLength; self.appDataEncoding = appDataEncoding
            self.appProtocolVersion = appProtocolVersion; self.testFlag = testFlag; self.result = result
            self.errorMessage = errorMessage
        }

        /// The server's reason for a non-zero `result`, as readable text, or nil when it sent none.
        public func errorText() -> String? {
            guard let errorMessage else { return nil }
            let s = String(decoding: errorMessage, as: UTF8.self)
            let kept = String(String.UnicodeScalarView(s.unicodeScalars.filter { $0 == " " || !isISOControl($0) }))
            let trimmed = String(kept.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    static func isISOControl(_ c: Unicode.Scalar) -> Bool {
        (0x00...0x1F).contains(c.value) || (0x7F...0x9F).contains(c.value)
    }

    public static func encodeDispatcher(_ d: Dispatcher) -> [UInt8] {
        let w = BitWriter()
        let present: [Bool] = [
            d.uid != nil, d.token != nil, d.vin != nil, d.eventId != nil, d.ulCounter != nil, d.dlCounter != nil,
            d.ackCounter != nil, d.ackRequired != nil, d.appDataLength != nil, d.appDataEncoding != nil,
            d.appProtocolVersion != nil, d.testFlag != nil, d.result != nil, d.errorMessage != nil,
        ]
        present.forEach { w.bit($0) }
        if let v = d.uid { w.ia5Fixed(v, 50) }
        if let v = d.token { w.ia5Fixed(v, 40) }
        w.ia5Fixed(d.applicationId, 3)
        if let v = d.vin { w.ia5Fixed(v, 17) }
        w.int(Int64(d.messageId), 0, 255)
        w.int(d.eventCreationTime, 0, i31)
        if let v = d.eventId { w.int(v, 0, i31) }
        if let v = d.ulCounter { w.int(Int64(v), 0, 65535) }
        if let v = d.dlCounter { w.int(Int64(v), 0, 65535) }
        if let v = d.ackCounter { w.int(Int64(v), 0, 65535) }
        if let v = d.ackRequired { w.bit(v) }
        if let v = d.appDataLength { w.int(Int64(v), 0, 65535) }
        if let v = d.appDataEncoding { w.int(Int64(v), 0, 2) }
        if let v = d.appProtocolVersion { w.int(Int64(v), 0, 65535) }
        if let v = d.testFlag { w.int(Int64(v), 1, 3) }
        if let v = d.result { w.int(Int64(v), 0, 65535) }
        if let v = d.errorMessage { w.octets(v, 1, 1024) }
        return w.bytes()
    }

    public static func decodeDispatcher(_ bytes: [UInt8]) throws -> Dispatcher {
        let r = BitReader(bytes)
        var p: [Bool] = []
        for _ in 0..<14 { p.append(try r.bit()) }
        let uid = try p[0] ? r.ia5Fixed(50) : nil
        let token = try p[1] ? r.ia5Fixed(40) : nil
        let app = try r.ia5Fixed(3)
        let vin = try p[2] ? r.ia5Fixed(17) : nil
        let msg = try r.intValue(0, 255)
        let created = try r.int(0, i31)
        return Dispatcher(
            uid: uid, token: token, applicationId: app, vin: vin, messageId: msg, eventCreationTime: created,
            eventId: try p[3] ? r.int(0, i31) : nil,
            ulCounter: try p[4] ? r.intValue(0, 65535) : nil,
            dlCounter: try p[5] ? r.intValue(0, 65535) : nil,
            ackCounter: try p[6] ? r.intValue(0, 65535) : nil,
            ackRequired: try p[7] ? r.bit() : nil,
            appDataLength: try p[8] ? r.intValue(0, 65535) : nil,
            appDataEncoding: try p[9] ? r.intValue(0, 2) : nil,
            appProtocolVersion: try p[10] ? r.intValue(0, 65535) : nil,
            testFlag: try p[11] ? r.intValue(1, 3) : nil,
            result: try p[12] ? r.intValue(0, 65535) : nil,
            errorMessage: try p[13] ? r.octets(1, 1024) : nil
        )
    }

    // MARK: - Requests

    private static func requestDispatcher(
        uid: String, token: String, vin: String, appId: String, app: [UInt8], eventId: Int64, nowS: Int64, messageId: Int = 1
    ) -> [UInt8] {
        encodeDispatcher(Dispatcher(
            uid: uid, token: token, applicationId: appId, vin: vin, messageId: messageId, eventCreationTime: nowS,
            eventId: eventId, ulCounter: 0, dlCounter: 0, ackCounter: 0, ackRequired: false, appDataLength: app.count,
            appDataEncoding: 0, appProtocolVersion: appProtocol, testFlag: 2, result: 0
        ))
    }

    private static func frameV21(_ dispatcher: [UInt8], _ app: [UInt8]) throws -> String {
        let dLen = dispatcher.count + 3
        guard dLen <= 255 else { throw TapFormatError("TAP dispatcher too large") }
        let payload = [UInt8(protocolV21), UInt8(dLen), 0] + [UInt8](repeating: 0, count: reserved) + dispatcher + app
        return "1" + Hex.word(payload.count + 3) + Hex.encode(payload)
    }

    public static func statusRequest(uid: String, token: String, vin: String, eventId: Int64, nowS: Int64) throws -> String {
        let app = BitWriter().int(2, 0, 255).bytes() // OTARVMVehicleStatusReq { vehStatusReqType 2 }
        return try frameV21(requestDispatcher(uid: uid, token: token, vin: vin, appId: statusApp, app: app, eventId: eventId, nowS: nowS), app)
    }

    public static func chargeRequest(uid: String, token: String, vin: String, eventId: Int64, nowS: Int64) throws -> String {
        try frameV21(
            requestDispatcher(uid: uid, token: token, vin: vin, appId: statusApp, app: [], eventId: eventId, nowS: nowS, messageId: chargeMessageId),
            []
        )
    }

    /// OTARVCReq: remote command `type` with (paramId, value) pairs.
    public static func controlRequest(
        uid: String, token: String, vin: String, eventId: Int64, type: Int, params: [(Int, [UInt8])], nowS: Int64
    ) throws -> String {
        let w = BitWriter().bit(!params.isEmpty).octetsFixed([UInt8(type)])
        if !params.isEmpty {
            w.int(Int64(params.count), 1, 10)
            for (id, value) in params { w.int(Int64(id), 0, 65535).octets(value, 1, 255) }
        }
        let app = w.bytes()
        return try frameV21(requestDispatcher(uid: uid, token: token, vin: vin, appId: controlApp, app: app, eventId: eventId, nowS: nowS), app)
    }

    public static func pinRequest(uid: String, token: String, vin: String, pinHash: String, nowS: Int64) throws -> String {
        let app = BitWriter().ia5Fixed(pinHash, 32).bytes()
        let body = encodeDispatcherV11(DispatcherV11(
            uid: uid, token: token, applicationId: pinApp, vin: vin, eventCreationTime: nowS, messageId: 1,
            messageCounter: (1, 0), simInfo: "1234567890987654321", iccId: "12345678901234567890",
            appDataLength: Int64(app.count), appDataEncoding: 0, appProtocolVersion: appProtocol, testFlag: 2
        ))
        let dLen = body.count + 4
        guard dLen <= 255 else { throw TapFormatError("TAP PIN dispatcher too large") }
        let payload = [UInt8(protocolV11), 0, UInt8(dLen), 0] + body + app
        return Hex.word(payload.count * 2 + 5) + "1" + Hex.encode(payload)
    }

    // MARK: - Dispatcher (v1.1, login and PIN)

    public struct DispatcherV11 {
        public var uid: String?
        public var token: String?
        public var applicationId: String
        public var vin: String?
        public var eventCreationTime: Int64
        public var eventId: Int64?
        public var messageId: Int
        public var messageCounter: (Int, Int)?
        public var simInfo: String?
        public var iccId: String
        public var appDataLength: Int64
        public var appDataEncoding: Int?
        public var appProtocolVersion: Int
        public var testFlag: Int?
        public var result: Int?
        public var errorMessage: [UInt8]?

        public init(
            uid: String? = nil, token: String? = nil, applicationId: String, vin: String? = nil, eventCreationTime: Int64,
            eventId: Int64? = nil, messageId: Int, messageCounter: (Int, Int)? = nil, simInfo: String? = nil,
            iccId: String, appDataLength: Int64, appDataEncoding: Int? = nil, appProtocolVersion: Int,
            testFlag: Int? = nil, result: Int? = nil, errorMessage: [UInt8]? = nil
        ) {
            self.uid = uid; self.token = token; self.applicationId = applicationId; self.vin = vin
            self.eventCreationTime = eventCreationTime; self.eventId = eventId; self.messageId = messageId
            self.messageCounter = messageCounter; self.simInfo = simInfo; self.iccId = iccId
            self.appDataLength = appDataLength; self.appDataEncoding = appDataEncoding
            self.appProtocolVersion = appProtocolVersion; self.testFlag = testFlag; self.result = result
            self.errorMessage = errorMessage
        }
    }

    public static func encodeDispatcherV11(_ d: DispatcherV11) -> [UInt8] {
        let w = BitWriter()
        // OPTIONAL bitmap: uid token vin eventID messageCounter ackRequired stateless crqm basicPosition
        // networkInfo simInfo hmiLanguage applicationDataEncoding testFlag result errorMessage
        let present: [Bool] = [
            d.uid != nil, d.token != nil, d.vin != nil, d.eventId != nil, d.messageCounter != nil, false, false, false,
            false, false, d.simInfo != nil, false, d.appDataEncoding != nil, d.testFlag != nil, d.result != nil,
            d.errorMessage != nil,
        ]
        present.forEach { w.bit($0) }
        if let v = d.uid { w.ia5Fixed(v, 50) }
        if let v = d.token { w.ia5Fixed(v, 40) }
        w.ia5Fixed(d.applicationId, 3)
        if let v = d.vin { w.ia5Fixed(v, 17) }
        w.int(d.eventCreationTime, 0, u32)
        if let v = d.eventId { w.int(v, 0, u48) }
        w.int(Int64(d.messageId), 0, 255)
        if let (up, down) = d.messageCounter { w.int(Int64(up), 0, 255).int(Int64(down), 0, 255) }
        if let v = d.simInfo { w.numericFixed(v, 19) }
        w.numericFixed(d.iccId, 20)
        w.int(d.appDataLength, 0, u32)
        if let v = d.appDataEncoding { w.int(Int64(v), 0, 2) }
        w.int(Int64(d.appProtocolVersion), 0, 65535)
        if let v = d.testFlag { w.int(Int64(v), 1, 3) }
        if let v = d.result { w.int(Int64(v), 0, 65535) }
        if let v = d.errorMessage { w.octets(v, 1, 1024) }
        return w.bytes()
    }

    public static func decodeDispatcherV11(_ bytes: [UInt8]) throws -> DispatcherV11 {
        let r = BitReader(bytes)
        var p: [Bool] = []
        for _ in 0..<16 { p.append(try r.bit()) }
        let uid = try p[0] ? r.ia5Fixed(50) : nil
        let token = try p[1] ? r.ia5Fixed(40) : nil
        let app = try r.ia5Fixed(3)
        let vin = try p[2] ? r.ia5Fixed(17) : nil
        let created = try r.int(0, u32)
        let eventId = try p[3] ? r.int(0, u48) : nil
        let msg = try r.intValue(0, 255)
        let counter: (Int, Int)? = try p[4] ? (r.intValue(0, 255), r.intValue(0, 255)) : nil
        if p[5] { _ = try r.bit() }
        if p[6] { _ = try r.bit() }
        if p[7] { _ = try r.bit() }
        if p[8] {
            _ = try r.int(-90_000_000, 90_000_000)
            _ = try r.int(-180_000_000, 180_000_000)
        }
        if p[9] {
            for _ in 0..<4 { _ = try r.numericFixed(3) }
            _ = try r.int(0, 99)
        }
        let sim = try p[10] ? r.numericFixed(19) : nil
        if p[11] { _ = try r.int(0, 4) }
        let icc = try r.numericFixed(20)
        let len = try r.int(0, u32)
        let enc = try p[12] ? r.intValue(0, 2) : nil
        let proto = try r.intValue(0, 65535)
        let test = try p[13] ? r.intValue(1, 3) : nil
        let result = try p[14] ? r.intValue(0, 65535) : nil
        let err = try p[15] ? r.octets(1, 1024) : nil
        return DispatcherV11(
            uid: uid, token: token, applicationId: app, vin: vin, eventCreationTime: created, eventId: eventId,
            messageId: msg, messageCounter: counter, simInfo: sim, iccId: icc, appDataLength: len, appDataEncoding: enc,
            appProtocolVersion: proto, testFlag: test, result: result, errorMessage: err
        )
    }

    // MARK: - Responses

    public struct V21Response {
        public let dispatcher: Dispatcher
        public let app: [UInt8]?
    }

    public static func decodeV21(_ raw: String) throws -> V21Response {
        let chars = Array(raw.utf8)
        guard chars.count >= 5, chars[0] == UInt8(ascii: "1") else { throw TapFormatError("unexpected TAP v2.1 response framing") }
        let data = try Hex.decode(raw.dropFirst(5))
        guard data.count >= 19 else { throw TapFormatError("short TAP v2.1 response") }
        guard Int(data[0]) == protocolV21 else { throw TapFormatError("unsupported TAP response protocol") }
        let dLen = Int(data[1])
        let dEnd = reserved + dLen
        guard dLen >= 3, dEnd <= data.count else { throw TapFormatError("invalid TAP dispatcher length") }
        let d = try decodeDispatcher(Array(data[19..<dEnd]))
        if let enc = d.appDataEncoding, enc != 0 { throw TapFormatError("unsupported TAP app encoding") }
        if let proto = d.appProtocolVersion, proto != appProtocol { throw TapFormatError("unsupported TAP app protocol") }
        guard [0, 4, 6].contains(d.result ?? 0) else { return V21Response(dispatcher: d, app: nil) }
        let appLen = d.appDataLength ?? 0
        if appLen == 0 { return V21Response(dispatcher: d, app: nil) }
        guard dEnd + appLen <= data.count else { throw TapFormatError("truncated TAP app data") }
        return V21Response(dispatcher: d, app: Array(data[dEnd..<(dEnd + appLen)]))
    }

    public static func decodePinResponse(_ raw: String) throws -> DispatcherV11 {
        let chars = Array(raw.utf8)
        let hex = (chars.count >= 5 && chars[4] == UInt8(ascii: "1")) ? raw.dropFirst(5) : Substring(raw)
        let payload = try Hex.decode(hex)
        guard payload.count >= 4 else { throw TapFormatError("short TAP PIN header") }
        let dLen = Int(payload[2]) + (Int(payload[3]) << 8)
        guard Int(payload[0]) == protocolV11, dLen >= 5, dLen <= payload.count else {
            throw TapFormatError("invalid TAP PIN dispatcher header")
        }
        let d = try decodeDispatcherV11(Array(payload[4..<dLen]))
        guard d.applicationId == pinApp else { throw TapFormatError("unexpected PIN application identity") }
        return d
    }

    // MARK: - Vehicle status payloads

    public struct Position: Equatable {
        public let latitudeMicro: Int64
        public let longitudeMicro: Int64
        public let altitudeM: Int
        public let heading: Int
        public let speedTenths: Int
        public let hdop: Int
        public let satellites: Int
        public let timeSeconds: Int64
        public let gpsStatus: Int
    }

    private static func readPosition(_ r: BitReader) throws -> Position {
        Position(
            latitudeMicro: try r.int(-90_000_000, 90_000_000),
            longitudeMicro: try r.int(-180_000_000, 180_000_000),
            altitudeM: try r.intValue(-100, 8900),
            heading: try r.intValue(0, 359),
            speedTenths: try r.intValue(-1000, 4500),
            hdop: try r.intValue(0, 1000),
            satellites: try r.intValue(0, 16),
            timeSeconds: try r.int(0, i31),
            gpsStatus: try r.intValue(0, 3)
        )
    }

    /// RvsBasicStatus513, in raw protocol units.
    public struct BasicStatus: Equatable {
        public var driverDoor, passengerDoor, rearLeftDoor, rearRightDoor, boot, bonnet, locked: Bool
        public var driverWindow, passengerWindow, rearLeftWindow, rearRightWindow, sunroof: Bool?
        public var tyreFrontRight, tyreFrontLeft, tyreRearRight, tyreRearLeft, tyreMonitor: Int?
        public var sideLights, dippedBeam, mainBeam: Bool
        public var alarm: Int?
        public var engineStatus, powerMode, lastKeySeen, journeyDistance: Int
        public var journeyId: Int64
        public var interiorTemp, exteriorTemp, fuelLevelPrc, fuelRange, remoteClimate: Int
        public var seatHeatLeft, seatHeatRight: Int?
        public var canBusActive: Bool
        public var lastCanActivity: Int64
        public var clusterFuelSegment: Int
        public var mileage: Int64
        public var batteryVoltage: Int
        public var ext1, ext2: Int64?
        public var handBrake: Bool
    }

    private static func readBasic(_ r: BitReader) throws -> BasicStatus {
        var p: [Bool] = []
        for _ in 0..<15 { p.append(try r.bit()) }
        func ob(_ i: Int) throws -> Bool? { try p[i] ? r.bit() : nil }
        func oi(_ i: Int) throws -> Int? { try p[i] ? r.intValue(0, 255) : nil }
        let dd = try r.bit(), pd = try r.bit(), rl = try r.bit(), rr = try r.bit()
        let bt = try r.bit(), bn = try r.bit(), lk = try r.bit()
        let dw = try ob(0), pw = try ob(1), rlw = try ob(2), rrw = try ob(3), sr = try ob(4)
        let tfr = try oi(5), tfl = try oi(6), trr = try oi(7), trl = try oi(8), tm = try oi(9)
        let side = try r.bit(), dip = try r.bit(), main = try r.bit()
        let alarm = try oi(10)
        let engine = try r.intValue(0, 255)
        let power = try r.intValue(0, 255)
        let key = try r.intValue(0, 65535)
        let jd = try r.intValue(0, 65535)
        let jid = try r.int(0, i31)
        let it = try r.intValue(-128, 127)
        let et = try r.intValue(-128, 127)
        let fuel = try r.intValue(0, 255)
        let range = try r.intValue(0, 65535)
        let climate = try r.intValue(0, 255)
        let shl = try oi(11), shr = try oi(12)
        let can = try r.bit()
        let canT = try r.int(0, i31)
        let seg = try r.intValue(0, 255)
        let mileage = try r.int(0, i31)
        let volt = try r.intValue(0, 65535)
        let e1 = try p[13] ? r.int(0, i31) : nil
        let e2 = try p[14] ? r.int(0, i31) : nil
        let hb = try r.bit()
        return BasicStatus(
            driverDoor: dd, passengerDoor: pd, rearLeftDoor: rl, rearRightDoor: rr, boot: bt, bonnet: bn, locked: lk,
            driverWindow: dw, passengerWindow: pw, rearLeftWindow: rlw, rearRightWindow: rrw, sunroof: sr,
            tyreFrontRight: tfr, tyreFrontLeft: tfl, tyreRearRight: trr, tyreRearLeft: trl, tyreMonitor: tm,
            sideLights: side, dippedBeam: dip, mainBeam: main, alarm: alarm, engineStatus: engine, powerMode: power,
            lastKeySeen: key, journeyDistance: jd, journeyId: jid, interiorTemp: it, exteriorTemp: et,
            fuelLevelPrc: fuel, fuelRange: range, remoteClimate: climate, seatHeatLeft: shl, seatHeatRight: shr,
            canBusActive: can, lastCanActivity: canT, clusterFuelSegment: seg, mileage: mileage, batteryVoltage: volt,
            ext1: e1, ext2: e2, handBrake: hb
        )
    }

    public struct StatusFrame: Equatable {
        public let statusTime: Int64
        public let position: Position
        public let basic: BasicStatus
        public let alerts: [AlertPair]
    }

    public struct AlertPair: Equatable {
        public let id: Int
        public let value: Int
    }

    public static func decodeStatusApp(_ app: [UInt8]) throws -> StatusFrame {
        let r = BitReader(app)
        let hasExt = try r.bit()
        let time = try r.int(0, i31)
        let pos = try readPosition(r)
        let basic = try readBasic(r)
        var alerts: [AlertPair] = []
        if hasExt {
            let n = try r.intValue(0, 64)
            for _ in 0..<n { alerts.append(AlertPair(id: try r.intValue(0, 255), value: try r.intValue(0, 255))) }
        }
        return StatusFrame(statusTime: time, position: pos, basic: basic, alerts: alerts)
    }

    public struct ControlFrame: Equatable {
        public let reqType: Int
        public let reqStatus: Int
        public let failureType: Int?
    }

    public static func decodeControlApp(_ app: [UInt8]) throws -> ControlFrame {
        let r = BitReader(app)
        let hasFailure = try r.bit()
        let type = Int(try r.octetsFixed(1)[0])
        let sts = Int(try r.octetsFixed(1)[0])
        let failure = try hasFailure ? r.intValue(0, 255) : nil
        return ControlFrame(reqType: type, reqStatus: sts, failureType: failure)
    }

    /// RvsChargingStatus, in raw protocol units (see `ChargeStatus` for scaled values).
    public struct ChargeFrame: Equatable {
        public let statusTime: Int64
        public let realtimePower: Int
        public let powerLevelPrc: Int?
        public let charging: Bool
        public let gunConnected: Bool
        public let fuelRange: Int
        public let chargingType: Int
        public let timeLevelPrc: Int?
        public let startTime: Int64?
        public let endTime: Int64?
        public let current: Int
        public let voltage: Int
        public let pileId: String?
        public let pileSupplier: String?
        public let workingCurrent: Int?
        public let workingVoltage: Int?
        public let mileageSinceCharge: Int?
        public let powerUsageSinceCharge: Int?
        public let mileageOfDay: Int?
        public let powerUsageOfDay: Int?
        public let staticConsumption: Int?
        public let phase: Int?
        public let duration: Int64?
        public let lastChargeEndingPower: Int?
        public let totalCapacity: Int?
        public let fotaLowestVoltage: Int?
        public let mileage: Int64
    }

    /// 2020-01-01: a charging frame stamped earlier than this was not decoded right.
    static let minPlausibleTimeS: Int64 = 1_577_836_800

    /// The charging frame from any model, or nil when `app` isn't one. Its length varies by model, so it is checked
    /// by decoding: it must decode without running out of data and carry a believable time and battery level.
    public static func decodeChargeAppOrNil(_ app: [UInt8]) -> ChargeFrame? {
        guard !app.isEmpty, let f = try? decodeChargeApp(app) else { return nil }
        guard f.statusTime >= minPlausibleTimeS, (f.powerLevelPrc ?? 0) <= 1000 else { return nil }
        return f
    }

    public static func decodeChargeApp(_ app: [UInt8]) throws -> ChargeFrame {
        let r = BitReader(app)
        let time = try r.int(0, i31)
        _ = try readPosition(r)
        var p: [Bool] = []
        for _ in 0..<22 { p.append(try r.bit()) }
        func o16(_ i: Int) throws -> Int? { try p[i] ? r.intValue(0, 65535) : nil }
        func o31(_ i: Int) throws -> Int64? { try p[i] ? r.int(0, i31) : nil }
        let rp = try r.intValue(0, 65535)
        let level = try o16(0)
        let st = try r.bit()
        let gun = try r.bit()
        let range = try r.intValue(0, 65535)
        let type = try r.intValue(0, 255)
        let tl = try o16(1)
        let start = try o31(2)
        let end = try o31(3)
        let cur = try r.intValue(0, 65535)
        let volt = try r.intValue(0, 65535)
        let pile = try p[4] ? r.ia5(0, 64) : nil
        let sup = try p[5] ? r.ia5(0, 64) : nil
        let wc = try o16(6), wv = try o16(7), ms = try o16(8), pu = try o16(9)
        let md = try o16(10), pdy = try o16(11), sec = try o16(12)
        let phase = try p[13] ? r.intValue(0, 255) : nil
        let dur = try o31(14)
        let lce = try o16(15)
        let cap = try o16(16)
        let fota = try p[17] ? r.intValue(0, 255) : nil
        let mileage = try r.int(0, i31)
        // extendedData1...4 follow; not used.
        return ChargeFrame(
            statusTime: time, realtimePower: rp, powerLevelPrc: level, charging: st, gunConnected: gun,
            fuelRange: range, chargingType: type, timeLevelPrc: tl, startTime: start, endTime: end, current: cur,
            voltage: volt, pileId: pile, pileSupplier: sup, workingCurrent: wc, workingVoltage: wv,
            mileageSinceCharge: ms, powerUsageSinceCharge: pu, mileageOfDay: md, powerUsageOfDay: pdy,
            staticConsumption: sec, phase: phase, duration: dur, lastChargeEndingPower: lce, totalCapacity: cap,
            fotaLowestVoltage: fota, mileage: mileage
        )
    }
}
