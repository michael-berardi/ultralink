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

// Retention bounds: the launch sweep removes leftovers older than their bound and keeps newer
// files, the live history file and unrelated files. Uses a scratch directory, never ~/Library.
let retentionRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("ultralink-retention-\(UUID().uuidString)")
let historyDir = retentionRoot.appendingPathComponent("history")
let cacheDir = retentionRoot.appendingPathComponent("cache")
let tempDir = retentionRoot.appendingPathComponent("temp")
let fm = FileManager.default
for dir in [historyDir, cacheDir, tempDir] {
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
}
func plant(_ url: URL, ageDays: Double) {
    try! Data("x".utf8).write(to: url)
    try! fm.setAttributes([.modificationDate: Date().addingTimeInterval(-ageDays * 86_400)],
                          ofItemAtPath: url.path)
}
plant(historyDir.appendingPathComponent("history.json"), ageDays: 30)          // user data: kept
plant(historyDir.appendingPathComponent("history.unreadable.json"), ageDays: 8) // stale backup
plant(historyDir.appendingPathComponent("notes.txt"), ageDays: 400)            // not ours: kept
plant(cacheDir.appendingPathComponent("UltraLink-0.2.0-mac.dmg"), ageDays: 9)  // stale download
try! fm.createDirectory(at: cacheDir.appendingPathComponent("partial"), withIntermediateDirectories: true)
try! fm.setAttributes([.modificationDate: Date().addingTimeInterval(-9 * 86_400)],
                      ofItemAtPath: cacheDir.appendingPathComponent("partial").path)
plant(cacheDir.appendingPathComponent("fresh.dmg"), ageDays: 0.5)              // recent: kept
plant(tempDir.appendingPathComponent("scratch"), ageDays: 2)                   // stale temp

// Sparkle stages downloads in nested folders whose own dates can be old. A fresh file there must
// survive; only stale files and emptied old folders may be removed.
let cacheBundle = cacheDir.appendingPathComponent("com.libertydesignstudio.ultralink", isDirectory: true)
let nestedUpdate = cacheBundle.appendingPathComponent("UltraLink 0.3.2", isDirectory: true).appendingPathComponent("Update", isDirectory: true)
try! fm.createDirectory(at: nestedUpdate, withIntermediateDirectories: true)
plant(cacheBundle.appendingPathComponent("UltraLink-0.3.0-mac.dmg"), ageDays: 9) // stale nested download
plant(nestedUpdate.appendingPathComponent("UltraLink-0.3.2-mac.dmg"), ageDays: 0.5) // fresh nested download
let emptiedFolder = cacheBundle.appendingPathComponent("OldPartial", isDirectory: true)
try! fm.createDirectory(at: emptiedFolder, withIntermediateDirectories: true)
for oldFolder in [cacheBundle, nestedUpdate, emptiedFolder] {
    try! fm.setAttributes([.modificationDate: Date().addingTimeInterval(-9 * 86_400)],
                          ofItemAtPath: oldFolder.path)
}

let removedBySweep = Set(Retention.sweep(now: Date(), historyDirectory: historyDir,
                                         cache: cacheDir, temp: tempDir))
let expectedRemovals: Set<String> = [
    "history.unreadable.json", "UltraLink-0.2.0-mac.dmg", "partial", "scratch",
    "com.libertydesignstudio.ultralink/UltraLink-0.3.0-mac.dmg",
    "com.libertydesignstudio.ultralink/OldPartial",
]
precondition(removedBySweep == expectedRemovals,
             "unexpected sweep result: \(removedBySweep.sorted())")
precondition(fm.fileExists(atPath: historyDir.appendingPathComponent("history.json").path),
             "sweep removed the history file")
precondition(fm.fileExists(atPath: historyDir.appendingPathComponent("notes.txt").path),
             "sweep removed a file UltraLink does not own")
precondition(fm.fileExists(atPath: cacheDir.appendingPathComponent("fresh.dmg").path),
             "sweep removed a recent download")
print("PASS: retention sweep bounds unreadable-history copies, update downloads and temp files")
precondition(fm.fileExists(atPath: nestedUpdate.appendingPathComponent("UltraLink-0.3.2-mac.dmg").path),
             "sweep removed a fresh nested download from an old folder")
precondition(fm.fileExists(atPath: nestedUpdate.path),
             "sweep removed the folder holding a fresh nested download")
precondition(fm.fileExists(atPath: cacheBundle.path), "sweep removed an old folder with fresh content")
precondition(!fm.fileExists(atPath: cacheBundle.appendingPathComponent("UltraLink-0.3.0-mac.dmg").path),
             "sweep kept a stale nested download")
precondition(!fm.fileExists(atPath: emptiedFolder.path), "sweep kept an emptied old folder")
print("PASS: retention sweep keeps a fresh nested download in an old cache folder")

// A missing directory (fresh install, no cache yet) is not an error and is not created.
let absent = retentionRoot.appendingPathComponent("absent/deeper")
precondition(Retention.sweep(now: Date(), historyDirectory: absent, cache: absent, temp: absent).isEmpty,
             "sweep reported removals in a directory that does not exist")
precondition(!fm.fileExists(atPath: absent.path), "sweep created a directory")
print("PASS: retention sweep is a no-op without directories and creates nothing")
try? fm.removeItem(at: retentionRoot)
