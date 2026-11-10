#if canImport(AVFAudio)
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

/// A server that answers from the URL's own query: `status` (200), `declared` (the Content-Length said,
/// or none), `send` (the bytes sent) and `hold` (send them, then never finish - a slow stream).
final class StubServer: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "stub.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> Int? { query.first { $0.name == name }?.value.flatMap { Int($0) } }
        let status = value("status") ?? 200
        var headers = ["Content-Type": "audio/flac"]
        if let declared = value("declared") { headers["Content-Length"] = String(declared) }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let send = value("send") ?? 0
        if send > 0 { client.urlProtocol(self, didLoad: Data((0..<send).map { UInt8($0 % 251) })) }
        if value("hold") == nil { client.urlProtocolDidFinishLoading(self) }
    }

    override func stopLoading() {}
}

/// The streaming cache's fetch: a part while the bytes arrive, renamed to the song's file only when they
/// are all there, deleted when the fetch fails or is let go; a 401 said as signed out.
@Suite struct StreamFetchTests {
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-fetch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        return configuration
    }

    /// Starts a fetch of `query` into `<folder>/s1.flac` and waits for it to finish (or `seconds`).
    private func fetch(_ query: String, into folder: URL, seconds: Double = 10) -> (StreamFetch, Bool) {
        let file = folder.appendingPathComponent("s1.flac")
        let fetch = StreamFetch(request: URLRequest(url: URL(string: "http://stub.test/stream?\(query)")!), fileURL: file,
                                configuration: configuration())
        let done = DispatchSemaphore(value: 0)
        fetch.onFinish = { _ in done.signal() }
        fetch.start()
        return (fetch, done.wait(timeout: .now() + seconds) == .success)
    }

    @Test func aWholeFetchBecomesTheSongsFile() throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = fetch("declared=1000&send=1000", into: dir)
        #expect(finished)
        #expect(fetch.isComplete && fetch.failure == nil)
        #expect(!FileManager.default.fileExists(atPath: fetch.partURL.path), "the part is renamed")
        let data = try Data(contentsOf: fetch.fileURL)
        #expect(data.count == 1000 && data[999] == UInt8(999 % 251))
        #expect(fetch.bytes(at: 990, count: 100).count == 10, "a reader reads on through the rename")
        #expect(fetch.partURL.lastPathComponent == StreamCache.partName(fetch.fileURL.lastPathComponent),
                "the part is named as the launch's sweep knows it")
    }

    @Test func aFetchCutShortIsNotComplete() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = fetch("declared=1000&send=600", into: dir)
        #expect(finished)
        #expect(!fetch.isComplete)
        #expect(fetch.failure?.kind == .network)
        #expect(fetch.failure?.description == "The song arrived cut short (600 of 1000 bytes).")
        #expect(!FileManager.default.fileExists(atPath: fetch.fileURL.path), "never under the song's name")
        #expect(!FileManager.default.fileExists(atPath: fetch.partURL.path), "and its part deleted")
    }

    @Test func aTranscodeWithNoLengthIsKeptWhole() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = fetch("send=700", into: dir)
        #expect(finished && fetch.isComplete && fetch.expectedLength == nil)
        #expect(FileManager.default.fileExists(atPath: fetch.fileURL.path))
    }

    @Test func aRefusalIsSaidAsSignedOut() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = fetch("status=401", into: dir)
        #expect(finished)
        #expect(fetch.failure?.kind == .signedOut && fetch.failure?.status == 401)
        #expect(!FileManager.default.fileExists(atPath: fetch.partURL.path))
        let (other, _) = self.fetch("status=404", into: dir)
        #expect(other.failure?.kind == .unsupported && other.failure?.status == 404)
    }

    @Test func aSkippedFetchIsCancelledAndItsPartDeleted() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = fetch("declared=100000&send=4000&hold=1", into: dir, seconds: 0.5)
        #expect(!finished, "still arriving")
        let until = Date().addingTimeInterval(5)
        while fetch.bytesWritten < 4000, Date() < until { Thread.sleep(forTimeInterval: 0.01) }
        #expect(FileManager.default.fileExists(atPath: fetch.partURL.path))
        fetch.cancel()
        #expect(fetch.isCancelled && !fetch.isComplete)
        #expect(fetch.failure?.kind == .network, "a reader still holding it sees it end")
        #expect(!FileManager.default.fileExists(atPath: fetch.partURL.path), "the part deleted at once")
        #expect(!FileManager.default.fileExists(atPath: fetch.fileURL.path))
    }

    @Test func aCompleteFetchKeepsItsFileWhenLetGo() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = fetch("declared=500&send=500", into: dir)
        #expect(finished)
        fetch.cancel()
        #expect(!fetch.isCancelled && fetch.isComplete)
        #expect(FileManager.default.fileExists(atPath: fetch.fileURL.path), "the cache's now")
    }
}
#endif
