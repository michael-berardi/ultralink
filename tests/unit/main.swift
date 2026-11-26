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

// The relay caps a stalled GET at UpdateFeedProtocol.timeout in a session that uses it.
// Sparkle's private feed session does not use this relay; see docs/updates.md.
precondition(UpdateFeedProtocol.timeout <= 4, "feed relay timeout exceeds four seconds")
print("PASS: feed relay timeout constant <= 4s")

func feedRequest(_ string: String) -> URLRequest {
    URLRequest(url: URL(string: string)!)
}
let appcast = "https://github.com/michael-berardi/ultralink/releases/latest/download/appcast.xml"
precondition(UpdateFeedProtocol.canInit(with: feedRequest(appcast)), "signed feed is not relayed")
precondition(UpdateFeedProtocol.canInit(with: feedRequest(appcast + "?q=1")), "feed with parameters is not relayed")
precondition(!UpdateFeedProtocol.canInit(with: feedRequest("https://github.com/michael-berardi/ultralink/releases/download/v0.2.3/UltraLink-0.2.3-mac.dmg")), "update download must not be relayed")
precondition(!UpdateFeedProtocol.canInit(with: feedRequest("https://example.com/appcast.xml")), "unrelated URL must not be relayed")
print("PASS: timeout relay is scoped to the signed feed only (Sparkle session not proven)")

if let feed = ProcessInfo.processInfo.environment["ULTRALINK_TEST_FEED_URL"], let url = URL(string: feed) {
    URLProtocol.registerClass(UpdateFeedProtocol.self)
    UpdateFeedProtocol.testFeedPrefixes = [feed]
    let done = DispatchSemaphore(value: 0)
    var failure: Error?
    let started = Date()
    let task = URLSession.shared.dataTask(with: URLRequest(url: url)) { _, _, error in
        failure = error
        done.signal()
    }
    task.resume()
    precondition(done.wait(timeout: .now() + 8) == .success, "feed request did not finish")
    let elapsed = Date().timeIntervalSince(started)
    guard let urlError = failure as? URLError else {
        print("FAIL: slow feed did not report a URL error: \(String(describing: failure))")
        exit(1)
    }
    precondition(urlError.code == .timedOut, "expected a timeout, got \(urlError.code.rawValue)")
    precondition(elapsed >= 3 && elapsed <= 5.5, "unexpected timeout duration: \(elapsed)s")
    print("PASS: stalled feed GET through URLSession.shared relay timed out in \(String(format: "%.1f", elapsed))s")
}
