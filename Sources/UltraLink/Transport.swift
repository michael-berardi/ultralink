import Foundation
import Network

/// A tiny HTTP/1.1 POST client on Network.framework.
///
/// URLSession cannot choose a network interface. That matters here: a VPN or exit node (Tailscale,
/// WireGuard, a corporate client) takes over the default route and swallows traffic for the dish at
/// 192.168.100.1, which only exists on the Starlink router's own network. Binding the connection to
/// the Wi-Fi or Ethernet interface sends it straight to the router instead.
enum Transport {
    struct Reply {
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    /// The route that last reached the dish: an interface, or nil for the system's default route.
    private static let cache = Cache()
    private final class Cache: @unchecked Sendable {
        struct Route { let interface: NWInterface? }
        private let lock = NSLock()
        private var value: [String: Route] = [:]
        func get(_ k: String) -> Route? { lock.lock(); defer { lock.unlock() }; return value[k] }
        func set(_ k: String, _ v: Route?) { lock.lock(); value[k] = v; lock.unlock() }
    }

    static func post(host: String, port: Int, path: String, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> Reply {
        let key = "\(host):\(port)"
        // Fast path: the route that worked last time. No interface scan, one connection.
        if let route = cache.get(key) {
            do { return try await request(host: host, port: port, path: path, headers: headers, body: body, interface: route.interface, timeout: timeout) }
            catch { cache.set(key, nil) }
        }
        // Otherwise try the default route, then each physical interface.
        let attempts: [NWInterface?] = [nil] + (await candidateInterfaces()).map { Optional($0) }
        var firstError: Error?
        for iface in attempts {
            do {
                let reply = try await request(host: host, port: port, path: path, headers: headers, body: body, interface: iface, timeout: min(timeout, 2.5))
                cache.set(key, Cache.Route(interface: iface))
                return reply
            } catch {
                firstError = firstError ?? error
            }
        }
        throw firstError ?? DishError.unreachable("No network interface could reach \(host).")
    }

    private static func candidateInterfaces() async -> [NWInterface] {
        await withCheckedContinuation { cont in
            let monitor = NWPathMonitor()
            let gate = Once()
            monitor.pathUpdateHandler = { path in
                guard gate.fire() else { return }
                monitor.cancel()
                cont.resume(returning: path.availableInterfaces.filter { $0.type == .wifi || $0.type == .wiredEthernet })
            }
            monitor.start(queue: DispatchQueue(label: "ultralink.paths"))
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock(); private var done = false
        func fire() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }

    private static func request(host: String, port: Int, path: String, headers: [String: String], body: Data,
                                interface: NWInterface?, timeout: TimeInterval) async throws -> Reply {
        let params = NWParameters.tcp
        if let interface { params.requiredInterface = interface }
        params.prohibitExpensivePaths = false
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(clamping: port))!, using: params)
        let queue = DispatchQueue(label: "ultralink.http")

        var head = "POST \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nConnection: close\r\nContent-Length: \(body.count)\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        let payload = Data(head.utf8) + body

        return try await withCheckedThrowingContinuation { cont in
            let gate = Once()
            var buffer = Data()
            func finish(_ result: Result<Reply, Error>) {
                guard gate.fire() else { return }
                conn.cancel()
                cont.resume(with: result)
            }
            func receive() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
                    if let data { buffer.append(data) }
                    if let error { return finish(.failure(Self.map(error, host: host, port: port))) }
                    if isComplete || Self.isComplete(buffer) {
                        do { finish(.success(try Self.parse(buffer))) } catch { finish(.failure(error)) }
                    } else { receive() }
                }
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: payload, completion: .contentProcessed { error in
                        if let error { finish(.failure(Self.map(error, host: host, port: port))) } else { receive() }
                    })
                case .failed(let error): finish(.failure(Self.map(error, host: host, port: port)))
                case .waiting(let error): // no route / refused: do not sit in "waiting"
                    finish(.failure(Self.map(error, host: host, port: port)))
                default: break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(DishError.unreachable("No dish answers at \(host). Join your Starlink Wi-Fi or plug into its router, or change the address in Settings.")))
            }
        }
    }

    private static func map(_ error: NWError, host: String, port: Int) -> DishError {
        .unreachable("Could not reach \(host):\(port) (\(error.localizedDescription)). Join your Starlink Wi-Fi or plug into its router, or change the address in Settings.")
    }

    // MARK: Parsing

    private static func headerEnd(_ d: Data) -> Int? {
        let sep = Data("\r\n\r\n".utf8)
        return d.range(of: sep)?.upperBound
    }

    /// True once a complete message has arrived (Content-Length reached or the chunked terminator seen).
    private static func isComplete(_ d: Data) -> Bool {
        guard let end = headerEnd(d) else { return false }
        let head = String(decoding: d[..<end], as: UTF8.self).lowercased()
        if let r = head.range(of: "content-length:") {
            let n = Int(head[r.upperBound...].prefix { !$0.isNewline }.trimmingCharacters(in: .whitespaces)) ?? 0
            return d.count - end >= n
        }
        if head.contains("transfer-encoding: chunked") { return d.suffix(5) == Data("0\r\n\r\n".utf8) }
        return false
    }

    static func parse(_ d: Data) throws -> Reply {
        guard let end = headerEnd(d) else { throw DishError.malformed("incomplete HTTP response") }
        let lines = String(decoding: d[..<end], as: UTF8.self).components(separatedBy: "\r\n")
        guard let first = lines.first, first.hasPrefix("HTTP/"), let code = Int(first.split(separator: " ").dropFirst().first ?? "") else {
            throw DishError.malformed("bad HTTP status line")
        }
        var headers: [String: String] = [:]
        for l in lines.dropFirst() {
            guard let c = l.firstIndex(of: ":") else { continue }
            headers[l[..<c].lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
        var body = Data(d[end...])
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true { body = try dechunk(body) }
        return Reply(status: code, headers: headers, body: body)
    }

    static func dechunk(_ d: Data) throws -> Data {
        var out = Data(), i = d.startIndex
        let crlf = Data("\r\n".utf8)
        while i < d.endIndex {
            guard let r = d.range(of: crlf, in: i..<d.endIndex) else { throw DishError.malformed("bad chunk header") }
            let sizeText = String(decoding: d[i..<r.lowerBound], as: UTF8.self).split(separator: ";").first.map(String.init) ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else { throw DishError.malformed("bad chunk size") }
            i = r.upperBound
            if size == 0 { break }
            guard i + size <= d.endIndex else { throw DishError.malformed("truncated chunk") }
            out.append(d[i..<(i + size)])
            i += size + 2
        }
        return out
    }
}
