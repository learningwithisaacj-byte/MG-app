// Ported to Swift from Volta (Apache 2.0, https://github.com/irshadm/volta-android), itself a Kotlin port of
// mg-ismart-india-client by John Lazarus (MIT, https://github.com/john-lazarus/mg-ismart-india-client).
// See NOTICE.md for both licences.

import Foundation

/// A signed-in MG session.
public struct MGSession: Codable, Equatable, Sendable {
    public let uid: String
    public let token: String
    public init(uid: String, token: String) {
        self.uid = uid
        self.token = token
    }
}

/// Fixed-layout login frame (from the Python client's `_build_login_body` / `decode_login_response`).
public enum LoginFrame {
    private static let dispatcherTemplate =
        "11005600882c60c183060c183060c183060c183060c183060c183060c183060c183060c183" +
        "060c183060c183060c183060c1ab06200000000020200468acf134468acf1342468acf134" +
        "2468acf1342000000000100a0"

    /// The MG app trims passwords to 16 characters; sending more fails as "incorrect password".
    public static let passwordMaxLength = 16

    public static func build(phone: String, password: String, deviceId: String, nowS: Int64) throws -> String {
        var dispatcher = try Hex.decode(dispatcherTemplate)
        let app = BitWriter().bits(1, 1).ia5(String(password.prefix(passwordMaxLength)), 6, 30).ia5(deviceId, 1, 200).bytes()
        let phoneDigits = try MGCrypto.normalizePhone(phone)
        FixedBits.set7bit(&dispatcher, 48, String(repeating: "0", count: 50 - phoneDigits.count) + phoneDigits)
        FixedBits.set(&dispatcher, 419, 32, UInt64(nowS))
        let n = dispatcher.count
        let len = UInt64(app.count * 2)
        for i in 0..<4 { dispatcher[n - 7 + i] = UInt8(truncatingIfNeeded: len >> UInt64(8 * (3 - i))) }
        dispatcher[n - 3] = 1
        dispatcher[n - 2] = 0
        dispatcher[n - 1] = 160
        let raw = "1" + Hex.encode(dispatcher + app)
        return Hex.word(raw.utf8.count + 4) + raw
    }

    public enum Result: Equatable {
        case ok(MGSession)
        /// Definitive server verdict (bad password, unregistered, daily limit). Never retry automatically.
        case rejected(String)
    }

    public static func decode(_ raw: String) throws -> Result {
        let chars = Array(raw.utf8)
        guard chars.count >= 5, chars[4] == UInt8(ascii: "1") else { throw TapFormatError("Unexpected TAP login response framing") }
        let payload = try Hex.decode(raw.dropFirst(5))
        guard payload.count >= 4 else { throw TapFormatError("TAP login response is too short") }
        let dLen = Int(payload[2]) + (Int(payload[3]) << 8)
        guard dLen >= 4, dLen <= payload.count else { throw TapFormatError("Invalid TAP login dispatcher length") }
        if let d = try? Tap.decodeDispatcherV11(Array(payload[4..<dLen])) {
            let result = d.result ?? 0
            if result != 0 {
                let text = d.errorMessage.map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
                return .rejected((text?.isEmpty == false ? text! : "result \(result)"))
            }
        }
        let dispatcher = Array(payload[0..<dLen])
        let app = Array(payload[dLen...])
        if dispatcher.count < 50 || app.count * 8 < 6 + 40 * 7 * 2 {
            return .rejected("Login rejected (check phone/password, or the account may not be allowed to use this app)")
        }
        let uidRaw = FixedBits.read7bit(dispatcher, 300, 14)
        let uid = String(repeating: "0", count: max(0, 50 - uidRaw.count)) + uidRaw
        let r = BitReader(app)
        _ = try r.bits(6)
        let token = try r.ia5Fixed(40)
        let refresh = try r.ia5Fixed(40)
        guard token == refresh else { throw TapFormatError("Login token and refresh token differ") }
        return .ok(MGSession(uid: uid, token: token))
    }
}
