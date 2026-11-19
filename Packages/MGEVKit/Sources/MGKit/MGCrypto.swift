// Ported to Swift from Volta (Apache 2.0, https://github.com/irshadm/volta-android), itself a Kotlin port of
// mg-ismart-india-client by John Lazarus (MIT, https://github.com/john-lazarus/mg-ismart-india-client).
// See NOTICE.md for both licences.

import Crypto
import _CryptoExtras
import Foundation

/// Request signing and response decryption used by the MG India app.
public enum MGCrypto {
    public static func md5Hex(_ s: String) -> String {
        Hex.encode(Insecure.MD5.hash(data: Array(s.utf8)), uppercase: false)
    }

    static func hmacSha256Hex(key: String, message: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Array(message.utf8), using: SymmetricKey(data: Array(key.utf8)))
        return Hex.encode(mac, uppercase: false)
    }

    public static func tapSignature(_ body: String) -> String {
        let chars = Array(body.utf8)
        let middle = String(decoding: chars[1..<(chars.count / 2)], as: UTF8.self)
        return hmacSha256Hex(key: md5Hex(middle), message: body)
    }

    public static func gatewaySignature(path: String, timestamp: String, contentType: String = "application/json") -> String {
        let part1 = md5Hex(path)
        let part2 = md5Hex(part1 + timestamp + "1" + contentType)
        let key = md5Hex(part2 + timestamp)
        return hmacSha256Hex(key: key, message: path + timestamp + "1" + contentType)
    }

    public static func decryptGatewayBody(_ cipherHex: String, timestamp: String, contentType: String) throws -> String {
        let key = try Hex.decode(md5Hex(timestamp + "1" + contentType))
        let iv = try Hex.decode(md5Hex(timestamp))
        let cipher = try Hex.decode(cipherHex.trimmingCharacters(in: .whitespacesAndNewlines))
        let plain = try AES._CBC.decrypt(cipher, using: SymmetricKey(data: key), iv: AES._CBC.IV(ivBytes: iv))
        return String(decoding: plain, as: UTF8.self)
    }

    /// The control PIN is never stored; only this hash is.
    public static func pinHash(_ pin: String) throws -> String {
        guard pin.count == 4, pin.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw IsmartError.invalidInput("Control PIN must be exactly 4 digits")
        }
        return md5Hex(pin + "00").uppercased()
    }

    public static func normalizePhone(_ phone: String) throws -> String {
        let digits = String(phone.filter { $0.isASCII && $0.isNumber }.suffix(10))
        guard digits.count == 10 else { throw IsmartError.invalidInput("Use the 10 digit India mobile number") }
        return digits
    }

    /// Stable per-install device id, padded to the 103 characters the app sends.
    public static func deviceId(phone: String, prefix: String) throws -> String {
        let seed = Hex.encode(SHA256.hash(data: Array("mg-ismart-india:\(try normalizePhone(phone))".utf8)), uppercase: false)
        return String((prefix + seed + String(repeating: "0", count: 120)).prefix(103))
    }
}
