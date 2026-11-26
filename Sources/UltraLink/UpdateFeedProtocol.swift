import Foundation

/// Sparkle 2.10 builds the appcast request with Foundation's default 60-second
/// timeout and does not expose an appcast timeout property. This protocol relays
/// *only the signed feed GET* through a session whose request and resource
/// timeouts are four seconds. Update downloads, release notes and every other
/// request keep using Sparkle's own downloader unchanged.
final class UpdateFeedProtocol: URLProtocol, URLSessionDataDelegate {
    static let timeout: TimeInterval = 4
    private static let handledKey = "UltraLinkFeedRelayed"
    private static let feedURL = "https://github.com/michael-berardi/ultralink/releases/latest/download/appcast.xml"

#if DEBUG
    /// Lets the standalone unit test point the relay at a local slow server.
    static var testFeedPrefixes: [String] = []
#endif

    private var session: URLSession?
    private var relayTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url?.absoluteString else { return false }
        // Sparkle may append feed parameters; update archives must not be relayed.
        let isFeed = url == feedURL || url.hasPrefix(feedURL + "?")
#if DEBUG
        let isTestFeed = testFeedPrefixes.contains(where: { url.hasPrefix($0) })
#else
        let isTestFeed = false
#endif
        guard isFeed || isTestFeed else { return false }
        return URLProtocol.property(forKey: handledKey, in: request) == nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.urlCache = nil
        // The relay session must not be intercepted by itself.
        configuration.protocolClasses = []

        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let relayTask = session.dataTask(with: mutable as URLRequest)
        self.relayTask = relayTask
        relayTask.resume()
    }

    override func stopLoading() {
        relayTask?.cancel()
        session?.finishTasksAndInvalidate()
        relayTask = nil
        session = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
        self.relayTask = nil
        self.session = nil
        session.finishTasksAndInvalidate()
    }
}
