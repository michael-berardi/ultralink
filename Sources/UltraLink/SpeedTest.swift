import Foundation

/// Apple's own `networkQuality` tool (macOS 12+) measures what the whole connection can do:
/// no extra download, no third-party server.
@MainActor
final class SpeedTest: ObservableObject {
    enum Phase: Equatable { case idle, running, done(Result), failed(String) }
    struct Result: Equatable {
        let down: Double, up: Double, rtt: Double?, responsiveness: Double?
        let date = Date()
    }

    @Published private(set) var phase: Phase = .idle
    private var process: Process?

    var isRunning: Bool { phase == .running }

    func run() {
        guard !isRunning else { return }
        phase = .running
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        p.arguments = ["-c", "-M", "25"]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        process = p
        p.terminationHandler = { [weak self] proc in
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let status = proc.terminationStatus
            Task { @MainActor in self?.finish(status: status, data: data, stderr: errText) }
        }
        do { try p.run() }
        catch { phase = .failed("Could not start networkQuality: \(error.localizedDescription)") }
    }

    func cancel() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        phase = .idle
    }

    private func finish(status: Int32, data: Data, stderr: String) {
        process = nil
        guard status == 0, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            phase = .failed(msg.isEmpty ? "The speed test did not finish (exit code \(status))." : msg)
            return
        }
        func num(_ k: String) -> Double? { (json[k] as? NSNumber)?.doubleValue }
        guard let d = num("dl_throughput"), let u = num("ul_throughput") else {
            phase = .failed("The speed test returned no throughput numbers."); return
        }
        phase = .done(Result(down: d, up: u, rtt: num("base_rtt"), responsiveness: num("responsiveness")))
    }
}
