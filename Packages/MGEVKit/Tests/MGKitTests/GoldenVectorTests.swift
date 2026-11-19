import Foundation
import XCTest
@testable import MGKit

/// Byte-exact agreement with the Python client: ismart_vectors.json holds its output for fixed, made-up inputs.
final class GoldenVectorTests: XCTestCase {
    var v: [String: Any] = [:]
    func s(_ k: String) -> String { v[k] as! String }
    var t: Int64 { (v["time"] as! NSNumber).int64Value }
    var uid: String { s("uid") }
    var token: String { s("token") }
    var vin: String { s("vin") }

    override func setUpWithError() throws {
        v = try Vectors.load()
    }

    func testStatusRequest() throws {
        XCTAssertEqual(s("statusRequest"), try Tap.statusRequest(uid: uid, token: token, vin: vin, eventId: 7, nowS: t))
    }

    func testChargeRequest() throws {
        XCTAssertEqual(s("chargeRequest"), try Tap.chargeRequest(uid: uid, token: token, vin: vin, eventId: 0, nowS: t))
    }

    func testLockRequest() throws {
        XCTAssertEqual(s("lockRequest"), try Tap.controlRequest(uid: uid, token: token, vin: vin, eventId: 0, type: 1, params: [], nowS: t))
    }

    func testUnlockRequest() throws {
        XCTAssertEqual(
            s("unlockRequest"),
            try Tap.controlRequest(uid: uid, token: token, vin: vin, eventId: 99, type: 2, params: [(4, [0]), (5, [0]), (6, [0]), (7, [3]), (255, [0])], nowS: t)
        )
    }

    func testClimateRequest() throws {
        XCTAssertEqual(
            s("climateOnRequest"),
            try Tap.controlRequest(uid: uid, token: token, vin: vin, eventId: 0, type: 6, params: [(19, [3]), (20, [3]), (255, [0])], nowS: t)
        )
    }

    func testPinHashAndRequest() throws {
        XCTAssertEqual(s("pinHash"), try MGCrypto.pinHash("1234"))
        XCTAssertEqual(s("pinRequest"), try Tap.pinRequest(uid: uid, token: token, vin: vin, pinHash: s("pinHash"), nowS: t))
        XCTAssertThrowsError(try MGCrypto.pinHash("12a4"))
    }

    func testLoginBody() throws {
        let device = s("deviceId")
        XCTAssertEqual(s("loginBody"), try LoginFrame.build(phone: "9876543210", password: "secret-pass", deviceId: device, nowS: t))
        XCTAssertEqual(device, try MGCrypto.deviceId(phone: "9876543210", prefix: "haos-mg-ismart-india-"))
    }

    func testSignatures() {
        XCTAssertEqual(s("tapSignature"), MGCrypto.tapSignature(s("statusRequest")))
        XCTAssertEqual(s("gatewaySignature"), MGCrypto.gatewaySignature(path: "/vehicle/userVinList", timestamp: "1792979136000"))
    }

    func testGatewayDecrypt() throws {
        let g = v["gateway"] as! [String: Any]
        XCTAssertEqual(
            g["plain"] as? String,
            try MGCrypto.decryptGatewayBody(g["cipher"] as! String, timestamp: g["timestamp"] as! String, contentType: "application/json")
        )
    }

    func testStatusResponseDecodes() throws {
        let res = try Tap.decodeV21(s("statusResponse"))
        XCTAssertEqual(4242, res.dispatcher.eventId)
        XCTAssertEqual(vin, res.dispatcher.vin)
        let f = try Tap.decodeStatusApp(try XCTUnwrap(res.app))
        let e = v["statusExpect"] as! [String: Any]
        func n(_ k: String) -> NSNumber { e[k] as! NSNumber }
        XCTAssertEqual(n("statusTime").int64Value, f.statusTime)
        XCTAssertEqual(n("soc").intValue, f.basic.fuelLevelPrc)
        XCTAssertEqual(n("mileage").int64Value, f.basic.mileage)
        XCTAssertEqual(e["locked"] as? Bool, f.basic.locked)
        XCTAssertEqual(n("tyreFL").intValue, f.basic.tyreFrontLeft)
        XCTAssertEqual(n("battery").intValue, f.basic.batteryVoltage)
        XCTAssertEqual(n("journeyId").int64Value, f.basic.journeyId)
        XCTAssertEqual(n("alerts").intValue, f.alerts.count)
        XCTAssertEqual(-2, f.position.altitudeM)

        let st = VehicleSnapshot.from(f)
        XCTAssertEqual(n("soc").intValue, st.socPercent)
        XCTAssertEqual(n("mileage").doubleValue / 10, try XCTUnwrap(st.odometerKm), accuracy: 1e-6)
        XCTAssertEqual((n("tyreFL").doubleValue * 0.2 * 10).rounded() / 10, try XCTUnwrap(st.tyres).frontLeft, accuracy: 1e-9)
        XCTAssertEqual(n("battery").doubleValue / 10, try XCTUnwrap(st.auxVolts), accuracy: 1e-9)
    }

    func testChargeResponseDecodes() throws {
        let res = try Tap.decodeV21(s("chargeResponse"))
        let app = try XCTUnwrap(res.app)
        XCTAssertEqual((v["chargeAppLen"] as! NSNumber).intValue, app.count)
        let c = ChargeStatus.from(try Tap.decodeChargeApp(app))
        XCTAssertEqual(59.0, try XCTUnwrap(c.socPercent), accuracy: 1e-9)
        XCTAssertEqual(21.9, c.batteryEnergyKwh, accuracy: 1e-9)
        XCTAssertEqual(187.0, c.rangeKm, accuracy: 1e-9)
        XCTAssertEqual(36.6, try XCTUnwrap(c.distanceSinceChargeKm), accuracy: 1e-9)
        XCTAssertEqual(6.1, try XCTUnwrap(c.energySinceChargeKwh), accuracy: 1e-9)
        XCTAssertEqual(0.0, c.currentA, accuracy: 1e-9)
        XCTAssertEqual(375.5, c.voltageV, accuracy: 1e-9)
        XCTAssertFalse(c.charging)
        XCTAssertFalse(c.pluggedIn)
        XCTAssertNil(c.minutesRemaining)
    }

    func testPendingAndSessionResults() throws {
        let pending = try Tap.decodeV21(s("pendingResponse"))
        XCTAssertEqual(4, pending.dispatcher.result)
        XCTAssertEqual(777, pending.dispatcher.eventId)
        XCTAssertNil(pending.app)
        XCTAssertEqual(2, try Tap.decodeV21(s("sessionInvalidResponse")).dispatcher.result)
    }

    func testControlAndPinResponses() throws {
        let c = try Tap.decodeControlApp(try XCTUnwrap(try Tap.decodeV21(s("controlDoneResponse")).app))
        XCTAssertEqual(1, c.reqType)
        XCTAssertEqual(2, c.reqStatus)
        XCTAssertEqual(0, try Tap.decodePinResponse(s("pinOkResponse")).result)
    }

    func testLoginRejectionIsReported() throws {
        let d = Tap.encodeDispatcherV11(Tap.DispatcherV11(
            applicationId: "001", eventCreationTime: t, messageId: 2, iccId: "12345678901234567890",
            appDataLength: 0, appProtocolVersion: 513, result: 3, errorMessage: Array("Incorrect password".utf8)
        ))
        let payload: [UInt8] = [17, 0, UInt8(d.count + 4), 0] + d
        let raw = Hex.word(payload.count * 2 + 5) + "1" + Hex.encode(payload)
        XCTAssertEqual(.rejected("Incorrect password"), try LoginFrame.decode(raw))
    }
}

enum Vectors {
    static func load() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ismart_vectors", withExtension: "json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
