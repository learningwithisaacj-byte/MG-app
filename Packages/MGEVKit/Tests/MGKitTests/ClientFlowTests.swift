import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import MGKit

/// Plays MG's part: answers each request with the next queued reply and records what was sent.
final class FakeMG: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [HTTPReply] = []
    private(set) var requests: [URLRequest] = []

    func enqueue(_ reply: HTTPReply) { lock.lock(); queue.append(reply); lock.unlock() }
    func enqueue(text: String) { enqueue(HTTPReply(status: 200, body: text)) }

    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return requests.count }

    func send(_ request: URLRequest) async throws -> HTTPReply {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        guard !queue.isEmpty else { throw URLError(.timedOut) }
        return queue.removeFirst()
    }
}

final class ClientFlowTests: XCTestCase {
    var v: [String: Any] = [:]
    func s(_ k: String) -> String { v[k] as! String }
    var session: MGSession { MGSession(uid: s("uid"), token: s("token")) }

    override func setUpWithError() throws { v = try Vectors.load() }

    func vinList() -> HTTPReply {
        let g = v["gateway"] as! [String: Any]
        return HTTPReply(status: 200, body: g["cipher"] as! String, headers: [
            "APP-SEND-DATE": g["timestamp"] as! String, "ORIGINAL-CONTENT-TYPE": "application/json",
        ])
    }

    func client(_ mg: FakeMG, store: SessionStore, creds: Credentials? = Credentials(phone: "9876543210", password: "secret-pass")) -> MGIsmartClient {
        MGIsmartClient(
            transport: mg, credentials: { creds }, sessions: store,
            endpoints: .init(tapLogin: URL(string: "https://mg.test/login")!, tapStatus: URL(string: "https://mg.test/status")!, gatewayBase: "https://mg.test/gw"),
            pollDelayMs: 1, commandDelayMs: 1
        )
    }

    /// A v2.1 status-app response with `result`, an optional server message and app payload.
    func response(_ result: Int, message: String? = nil, app: [UInt8] = []) -> String {
        let d = Tap.encodeDispatcher(Tap.Dispatcher(
            applicationId: Tap.statusApp, vin: s("vin"), messageId: 1, eventCreationTime: 1_790_000_000, eventId: 1,
            appDataLength: app.count, appDataEncoding: 0, appProtocolVersion: Tap.appProtocol, result: result,
            errorMessage: message.map { Array($0.utf8) }
        ))
        let payload = [UInt8(Tap.protocolV21), UInt8(d.count + 3), 0] + [UInt8](repeating: 0, count: Tap.reserved) + d + app
        return "1" + Hex.word(payload.count + 3) + Hex.encode(payload)
    }

    func windsorChargeApp() throws -> [UInt8] { try XCTUnwrap(try Tap.decodeV21(s("chargeResponse")).app) }

    func testReadPollsUntilStatusThenFetchesCharge() async throws {
        let mg = FakeMG()
        mg.enqueue(vinList())
        mg.enqueue(text: s("pendingResponse")) // car waking up
        mg.enqueue(text: s("statusResponse"))
        mg.enqueue(text: s("chargeResponse"))
        let c = client(mg, store: InMemorySessionStore(session))
        let reading = try await c.read()
        let vin = await c.vin
        XCTAssertEqual(s("vin"), vin)
        XCTAssertEqual(59.0, try XCTUnwrap(reading.charge?.socPercent), accuracy: 1e-9)
        XCTAssertTrue(reading.snapshot.locked)
        let second = mg.requests[2]
        XCTAssertTrue(String(decoding: second.httpBody ?? Data(), as: UTF8.self).contains("0000000000"))
        XCTAssertFalse((second.value(forHTTPHeaderField: "APP-SIGNATURE") ?? "").isEmpty)
    }

    func testLockCommandVerifiesPinThenWaitsForCompletion() async throws {
        let mg = FakeMG()
        mg.enqueue(vinList())
        mg.enqueue(text: s("pinOkResponse"))
        mg.enqueue(text: s("pendingResponse"))
        mg.enqueue(text: s("controlDoneResponse"))
        try await client(mg, store: InMemorySessionStore(session)).command(.lock, pinHash: s("pinHash"))
        XCTAssertEqual(4, mg.requestCount)
    }

    func testRepeatedLoginsTripTheSignedOutGuard() async throws {
        let mg = FakeMG()
        for _ in 0..<20 { mg.enqueue(text: "0000") } // garbage: every read needs a fresh login attempt
        let c = client(mg, store: InMemorySessionStore(nil))
        for _ in 0..<MGIsmartClient.maxLoginsPerHour {
            do { _ = try await c.read(); XCTFail("expected failure") } catch let e as IsmartError { XCTAssertFalse(e.isSignedOut) }
        }
        do {
            _ = try await c.read()
            XCTFail("expected the login guard")
        } catch let e as IsmartError {
            XCTAssertTrue(e.isSignedOut, "\(e)")
        }
    }

    func testNoCredentialsMeansNotSignedIn() async {
        do {
            _ = try await client(FakeMG(), store: InMemorySessionStore(nil), creds: nil).read()
            XCTFail("expected failure")
        } catch let e as IsmartError {
            XCTAssertTrue(e.message.contains("Not signed in"))
        } catch {
            XCTFail("\(error)")
        }
    }

    func testALongerChargeFrameStillDecodes() throws {
        let longer = try windsorChargeApp() + [UInt8](repeating: 0x55, count: 12)
        XCTAssertEqual(try Tap.decodeChargeApp(windsorChargeApp()), Tap.decodeChargeAppOrNil(longer))
    }

    func testJunkIsNotAChargeFrame() {
        XCTAssertNil(Tap.decodeChargeAppOrNil([]))
        XCTAssertNil(Tap.decodeChargeAppOrNil([UInt8](repeating: 0, count: 8)))
        XCTAssertNil(Tap.decodeChargeAppOrNil([UInt8](repeating: 0, count: 80)))
    }

    func testUnknownResultOnTheChargeRequestKeepsTheStatus() async throws {
        let mg = FakeMG()
        mg.enqueue(vinList())
        mg.enqueue(text: s("statusResponse"))
        mg.enqueue(text: response(15016))
        let reading = try await client(mg, store: InMemorySessionStore(session)).read()
        XCTAssertNil(reading.charge)
        XCTAssertTrue(reading.snapshot.locked)
    }

    func testReadKeepsALongerChargeFrame() async throws {
        let mg = FakeMG()
        mg.enqueue(vinList())
        mg.enqueue(text: s("statusResponse"))
        mg.enqueue(text: response(0, app: try windsorChargeApp() + [0, 0, 0, 0, 0]))
        let reading = try await client(mg, store: InMemorySessionStore(session)).read()
        XCTAssertEqual(59.0, try XCTUnwrap(reading.charge?.socPercent), accuracy: 1e-9)
    }

    func testUnknownResultCarriesMgsReason() async {
        let mg = FakeMG()
        mg.enqueue(vinList())
        mg.enqueue(text: response(15016, message: "Vehicle is not online\u{0}"))
        do {
            _ = try await client(mg, store: InMemorySessionStore(session)).read()
            XCTFail("expected failure")
        } catch let e as IsmartError {
            XCTAssertEqual(.serverResult(label: "Status", result: 15016, serverMessage: "Vehicle is not online"), e)
            XCTAssertEqual("Status failed: Vehicle is not online (result 15016)", e.message)
            XCTAssertEqual("MG: Vehicle is not online (code 15016)", e.userMessage)
        } catch { XCTFail("\(error)") }
    }

    func testUnknownResultWithoutReason() async {
        let mg = FakeMG()
        mg.enqueue(vinList())
        mg.enqueue(text: response(15016))
        do {
            _ = try await client(mg, store: InMemorySessionStore(session)).read()
            XCTFail("expected failure")
        } catch let e as IsmartError {
            XCTAssertEqual("Status failed: result 15016", e.message)
            XCTAssertEqual("MG's server couldn't get the car's status (code 15016). Try again in a minute.", e.userMessage)
        } catch { XCTFail("\(error)") }
    }
}

final class CarDifferencesTests: XCTestCase {
    func testWindsorTyresCountInPsiSteps() {
        XCTAssertEqual([33.8, 35.4, 34.0, 33.0], TyreScale.psi([169, 177, 170, 165]))
    }

    func testZsEvTyresCountInBarSteps() {
        XCTAssertEqual([40.6, 40.6, 41.8, 41.8], TyreScale.psi([70, 70, 72, 72]))
    }

    func testAFlatTyreOnASaicCarStaysOnTheBarScale() {
        XCTAssertEqual([40.6, 7.0, 40.6, 40.6], TyreScale.psi([70, 12, 70, 70]))
    }

    func testASoftWindsorTyreStaysOnThePsiScale() {
        XCTAssertEqual([33.8, 20.0, 33.8, 33.8], TyreScale.psi([169, 100, 169, 169]))
    }

    func testOutOfRangeTyreReadingsAreDropped() {
        XCTAssertEqual([nil, 33.8, nil, 33.8], TyreScale.psi([0, 169, nil, 169]))
    }

    func testMultiFactorRejectionIsRecognised() {
        XCTAssertTrue(mfaRequired("Multi-factor authentication required"))
        XCTAssertTrue(mfaRequired("multifactor login is enabled"))
        XCTAssertTrue(mfaRequired("MFA required"))
        XCTAssertFalse(mfaRequired("Incorrect mobile number or password."))
    }

    func testSessionInvalidMessages() {
        XCTAssertTrue(sessionInvalid("Login is invalid, please login again."))
        XCTAssertTrue(sessionInvalid("Token expired"))
        XCTAssertFalse(sessionInvalid("Vehicle is offline"))
        XCTAssertFalse(sessionInvalid(nil))
    }
}
