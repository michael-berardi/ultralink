import Foundation

/// A just-enough protobuf wire reader. The dish speaks a large schema, but UltraLink only needs a
/// handful of fields, so there is no generated code and no dependency: unknown fields are skipped.
struct PBReader {
    private let bytes: [UInt8]
    private var i: Int
    private let end: Int

    init(_ data: Data) { bytes = [UInt8](data); i = 0; end = bytes.count }
    private init(bytes: [UInt8], start: Int, end: Int) { self.bytes = bytes; i = start; self.end = end }

    enum Value {
        case varint(UInt64)
        case fixed32(UInt32)
        case fixed64(UInt64)
        case bytes(PBReader)
    }

    var isAtEnd: Bool { i >= end }
    var text: String { String(decoding: bytes[i..<end], as: UTF8.self) }

    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while i < end {
            let b = bytes[i]; i += 1
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { throw DishError.malformed("varint too long") }
        }
        throw DishError.malformed("truncated varint")
    }

    /// Next field as (number, value), or nil at the end of the message.
    mutating func next() throws -> (Int, Value)? {
        if i >= end { return nil }
        let tag = try varint()
        let number = Int(tag >> 3)
        switch tag & 7 {
        case 0: return (number, .varint(try varint()))
        case 1:
            guard i + 8 <= end else { throw DishError.malformed("truncated fixed64") }
            var v: UInt64 = 0
            for k in 0..<8 { v |= UInt64(bytes[i + k]) << UInt64(8 * k) }
            i += 8
            return (number, .fixed64(v))
        case 2:
            let n = Int(try varint())
            guard n >= 0, i + n <= end else { throw DishError.malformed("truncated field \(number)") }
            let sub = PBReader(bytes: bytes, start: i, end: i + n)
            i += n
            return (number, .bytes(sub))
        case 5:
            guard i + 4 <= end else { throw DishError.malformed("truncated fixed32") }
            var v: UInt32 = 0
            for k in 0..<4 { v |= UInt32(bytes[i + k]) << UInt32(8 * k) }
            i += 4
            return (number, .fixed32(v))
        default:
            throw DishError.malformed("unsupported wire type \(tag & 7) on field \(number)")
        }
    }

    /// Decodes a repeated float field, packed or not, appending to `out`.
    static func appendFloats(_ v: Value, to out: inout [Float]) {
        switch v {
        case .fixed32(let b): out.append(Float(bitPattern: b))
        case .bytes(var r):
            while r.i + 4 <= r.end {
                var b: UInt32 = 0
                for k in 0..<4 { b |= UInt32(r.bytes[r.i + k]) << UInt32(8 * k) }
                r.i += 4
                out.append(Float(bitPattern: b))
            }
        default: break
        }
    }
}

extension PBReader.Value {
    var float: Float? { if case .fixed32(let b) = self { return Float(bitPattern: b) }; return nil }
    var double: Double? {
        switch self {
        case .fixed32(let b): return Double(Float(bitPattern: b))
        case .fixed64(let b): return Double(bitPattern: b)
        default: return nil
        }
    }
    var uint: UInt64? { if case .varint(let v) = self { return v }; return nil }
    var int: Int? { uint.map { Int(truncatingIfNeeded: Int64(bitPattern: $0)) } }
    var bool: Bool? { uint.map { $0 != 0 } }
    var message: PBReader? { if case .bytes(let r) = self { return r }; return nil }
    var string: String? { message?.text }
}

/// Encodes a message that contains one empty sub-message, which is every request UltraLink sends.
func pbEmptySubmessage(field: Int) -> Data {
    var out = Data()
    var tag = UInt64(field << 3 | 2)
    while tag >= 0x80 { out.append(UInt8(tag & 0x7F | 0x80)); tag >>= 7 }
    out.append(UInt8(tag))
    out.append(0)
    return out
}
