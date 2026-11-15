import Foundation

func rejects(_ name: String, _ body: () throws -> Void) {
    do { try body(); print("FAIL: \(name) accepted malformed input"); exit(1) }
    catch DishError.malformed { print("PASS: \(name)") }
    catch { print("FAIL: \(name): \(error)"); exit(1) }
}
rejects("overflowing varint") {
    var r = PBReader(Data(Array(repeating: UInt8(0xff), count: 9) + [0x02]))
    _ = try r.varint()
}
rejects("unrepresentable length") {
    var r = PBReader(Data([0x0a] + Array(repeating: UInt8(0xff), count: 9) + [0x01]))
    _ = try r.next()
}
rejects("overflowing end offset") {
    var r = PBReader(Data([0x0a] + Array(repeating: UInt8(0xff), count: 8) + [0x7f]))
    _ = try r.next()
}
rejects("truncated field") {
    var r = PBReader(Data([0x0a, 0x02, 0x61])); _ = try r.next()
}
var maximum = PBReader(Data(Array(repeating: UInt8(0xff), count: 9) + [0x01]))
let maxValue = try maximum.varint(); precondition(maxValue == UInt64.max)
print("PASS: maximum varint")
var message = PBReader(Data([0x0a, 0x02, 0x6f, 0x6b, 0x10, 0x01]))
let text = try message.next()?.1.string; precondition(text == "ok")
let number = try message.next()?.1.uint; precondition(number == 1)
precondition(message.isAtEnd)
print("PASS: valid fields")
