// Ported to Swift from Volta (Apache 2.0, https://github.com/irshadm/volta-android), itself a Kotlin port of
// mg-ismart-india-client by John Lazarus (MIT, https://github.com/john-lazarus/mg-ismart-india-client).
// See NOTICE.md for both licences.

import Foundation

/// The MG India TAP response could not be read (bad framing, truncated data).
public struct TapFormatError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Number of bits a constrained INTEGER in `lb...ub` takes in unaligned PER.
func bitsFor(_ lb: Int64, _ ub: Int64) -> Int {
    let range = UInt64(bitPattern: ub &- lb) &+ 1
    precondition(range >= 1)
    return range == 1 ? 0 : 64 - (range - 1).leadingZeroBitCount
}

/// Minimal ASN.1 PER-unaligned (X.691) writer: just the constructs the MG India TAP schemas use.
final class BitWriter {
    private var bits: [Bool] = []

    init() { bits.reserveCapacity(512) }

    @discardableResult
    func bit(_ b: Bool) -> BitWriter { bits.append(b); return self }

    @discardableResult
    func bits(_ value: UInt64, _ count: Int) -> BitWriter {
        precondition(count == 64 || (value >> UInt64(count)) == 0, "value \(value) does not fit in \(count) bits")
        var i = count - 1
        while i >= 0 {
            bits.append((value >> UInt64(i)) & 1 == 1)
            i -= 1
        }
        return self
    }

    @discardableResult
    func int(_ value: Int64, _ lb: Int64, _ ub: Int64) -> BitWriter {
        precondition(value >= lb && value <= ub, "INTEGER \(value) outside \(lb)...\(ub)")
        return bits(UInt64(value - lb), bitsFor(lb, ub))
    }

    @discardableResult
    func ia5Fixed(_ s: String, _ size: Int) -> BitWriter {
        let chars = Array(s.utf8)
        precondition(chars.count == size, "IA5String must be \(size) chars, was \(chars.count)")
        chars.forEach { bits(UInt64($0), 7) }
        return self
    }

    @discardableResult
    func ia5(_ s: String, _ minLen: Int, _ maxLen: Int) -> BitWriter {
        let chars = Array(s.utf8)
        int(Int64(chars.count), Int64(minLen), Int64(maxLen))
        chars.forEach { bits(UInt64($0), 7) }
        return self
    }

    @discardableResult
    func numericFixed(_ s: String, _ size: Int) -> BitWriter {
        let chars = Array(s.utf8)
        precondition(chars.count == size)
        for c in chars { bits(c == UInt8(ascii: " ") ? 0 : UInt64(c - UInt8(ascii: "0") + 1), 4) }
        return self
    }

    @discardableResult
    func octetsFixed(_ b: [UInt8]) -> BitWriter {
        b.forEach { bits(UInt64($0), 8) }
        return self
    }

    @discardableResult
    func octets(_ b: [UInt8], _ minLen: Int, _ maxLen: Int) -> BitWriter {
        int(Int64(b.count), Int64(minLen), Int64(maxLen))
        return octetsFixed(b)
    }

    func bytes() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
        for (i, b) in bits.enumerated() where b { out[i / 8] |= UInt8(0x80 >> (i % 8)) }
        return out
    }
}

/// Minimal ASN.1 PER-unaligned reader, the mirror of `BitWriter`.
final class BitReader {
    private let data: [UInt8]
    private var pos: Int

    init(_ data: [UInt8], pos: Int = 0) {
        self.data = data
        self.pos = pos
    }

    func bit() throws -> Bool {
        guard pos < data.count * 8 else { throw TapFormatError("truncated PER data") }
        let b = (data[pos / 8] >> UInt8(7 - pos % 8)) & 1
        pos += 1
        return b == 1
    }

    func bits(_ count: Int) throws -> UInt64 {
        var v: UInt64 = 0
        for _ in 0..<count { v = (v << 1) | (try bit() ? 1 : 0) }
        return v
    }

    func int(_ lb: Int64, _ ub: Int64) throws -> Int64 { lb + Int64(bitPattern: try bits(bitsFor(lb, ub))) }

    func intValue(_ lb: Int64, _ ub: Int64) throws -> Int { Int(try int(lb, ub)) }

    func ia5Fixed(_ size: Int) throws -> String {
        var scalars = String.UnicodeScalarView()
        for _ in 0..<size { scalars.append(Unicode.Scalar(UInt8(try bits(7)))) }
        return String(scalars)
    }

    func ia5(_ minLen: Int, _ maxLen: Int) throws -> String { try ia5Fixed(try intValue(Int64(minLen), Int64(maxLen))) }

    func numericFixed(_ size: Int) throws -> String {
        var s = ""
        for _ in 0..<size {
            let v = try bits(4)
            s.append(v == 0 ? " " : Character(Unicode.Scalar(UInt8(ascii: "0") + UInt8(v - 1))))
        }
        return s
    }

    func octetsFixed(_ size: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(size)
        for _ in 0..<size { out.append(UInt8(try bits(8))) }
        return out
    }

    func octets(_ minLen: Int, _ maxLen: Int) throws -> [UInt8] { try octetsFixed(try intValue(Int64(minLen), Int64(maxLen))) }
}

/// Raw MSB-first bit helpers used by the fixed-layout login frame.
enum FixedBits {
    static func set(_ buf: inout [UInt8], _ offset: Int, _ count: Int, _ value: UInt64) {
        for i in 0..<count {
            let abs = offset + i
            let mask = UInt8(0x80 >> (abs % 8))
            if (value >> UInt64(count - 1 - i)) & 1 == 1 {
                buf[abs / 8] |= mask
            } else {
                buf[abs / 8] &= ~mask
            }
        }
    }

    static func read(_ buf: [UInt8], _ offset: Int, _ count: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<count {
            let abs = offset + i
            v = (v << 1) | UInt64((buf[abs / 8] >> UInt8(7 - abs % 8)) & 1)
        }
        return v
    }

    static func set7bit(_ buf: inout [UInt8], _ offset: Int, _ s: String) {
        for (i, c) in s.utf8.enumerated() { set(&buf, offset + i * 7, 7, UInt64(c)) }
    }

    static func read7bit(_ buf: [UInt8], _ offset: Int, _ count: Int) -> String {
        var scalars = String.UnicodeScalarView()
        for i in 0..<count { scalars.append(Unicode.Scalar(UInt8(read(buf, offset + i * 7, 7)))) }
        return String(scalars)
    }
}

// MARK: - Hex

enum Hex {
    private static let upper = Array("0123456789ABCDEF".utf8)
    private static let lower = Array("0123456789abcdef".utf8)

    static func encode(_ bytes: some Sequence<UInt8>, uppercase: Bool = true) -> String {
        let table = uppercase ? upper : lower
        var out: [UInt8] = []
        for b in bytes {
            out.append(table[Int(b >> 4)])
            out.append(table[Int(b & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func decode(_ s: some StringProtocol) throws -> [UInt8] {
        let chars = Array(s.utf8)
        guard chars.count % 2 == 0 else { throw TapFormatError("odd-length hex") }
        func nibble(_ c: UInt8) throws -> UInt8 {
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
            default: throw TapFormatError("invalid hex")
            }
        }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            out.append(try nibble(chars[i]) << 4 | nibble(chars[i + 1]))
            i += 2
        }
        return out
    }

    /// Four upper-case hex digits, as Kotlin's `"%04X".format(n)`.
    static func word(_ n: Int) -> String {
        let s = String(n, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 4 - s.count)) + s
    }
}
