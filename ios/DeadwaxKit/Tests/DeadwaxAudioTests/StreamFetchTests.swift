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

/// Resumes a wait once, from whichever comes first: the fetch's finish or its timeout (its lock makes it
/// safe to call from both).
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        let taken: CheckedContinuation<Bool, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        taken?.resume(returning: value)
    }
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
    ///
    /// Waits by suspending, never by blocking a thread: Swift Testing runs these in parallel on a pool as
    /// wide as the Mac has cores, and nine of them each holding a thread in a semaphore's wait stalled
    /// every fetch on an 8-core Mac until the waits ran out (5.5 s for the nine, 0.5 s one at a time or
    /// suspended - so the stub's answers seem to need a free thread of it). A CI runner has 3 or 4.
    private func fetch(_ query: String, into folder: URL, seconds: Double = 10) async -> (StreamFetch, Bool) {
        let file = folder.appendingPathComponent("s1.flac")
        let fetch = StreamFetch(request: URLRequest(url: URL(string: "http://stub.test/stream?\(query)")!), fileURL: file,
                                configuration: configuration())
        let finished = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce(continuation)
            fetch.onFinish = { _ in once.resume(true) }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { once.resume(false) }
            fetch.start()
        }
        return (fetch, finished)
    }

    /// Waits `seconds` by suspending.
    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @Test func aWholeFetchBecomesTheSongsFile() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = await fetch("declared=1000&send=1000", into: dir)
        #expect(finished)
        #expect(fetch.isComplete && fetch.failure == nil)
        #expect(!FileManager.default.fileExists(atPath: fetch.partURL.path), "the part is renamed")
        let data = try Data(contentsOf: fetch.fileURL)
        #expect(data.count == 1000 && data[999] == UInt8(999 % 251))
        #expect(fetch.bytes(at: 990, count: 100).count == 10, "a reader reads on through the rename")
        #expect(fetch.partURL.lastPathComponent == StreamCache.partName(fetch.fileURL.lastPathComponent),
                "the part is named as the launch's sweep knows it")
    }

    @Test func aFetchCutShortIsNotComplete() async {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = await fetch("declared=1000&send=600", into: dir)
        #expect(finished)
        #expect(!fetch.isComplete)
        #expect(fetch.failure?.kind == .network)
        #expect(fetch.failure?.description == "The song arrived cut short (600 of 1000 bytes).")
        #expect(!FileManager.default.fileExists(atPath: fetch.fileURL.path), "never under the song's name")
        #expect(!FileManager.default.fileExists(atPath: fetch.partURL.path), "and its part deleted")
    }

    @Test func aTranscodeWithNoLengthIsKeptWhole() async {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = await fetch("send=700", into: dir)
        #expect(finished && fetch.isComplete && fetch.expectedLength == nil)
        #expect(FileManager.default.fileExists(atPath: fetch.fileURL.path))
    }

    @Test func aFetchLongerThanSaidIsNotComplete() async {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = await fetch("declared=500&send=700", into: dir)
        #expect(finished)
        #expect(!fetch.isComplete && fetch.failure?.kind == .network)
        #expect(fetch.failure?.description == "The song arrived longer than deadwax said (700 of 500 bytes).")
        #expect(!FileManager.default.fileExists(atPath: fetch.fileURL.path), "never under the song's name")
        #expect(!FileManager.default.fileExists(atPath: fetch.partURL.path), "and its part deleted")
    }

    // A file of the song's another length (the cache's .replace, or the server's file changed) is replaced
    // by the whole fetch: the rename goes over it.
    @Test func aWholeFetchReplacesAnOldFileOfTheSong() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = dir.appendingPathComponent("s1.flac")
        try Data(repeating: 0xFF, count: 300).write(to: old)
        let (fetch, finished) = await fetch("declared=1000&send=1000", into: dir)
        #expect(finished && fetch.isComplete && fetch.failure == nil)
        let data = try Data(contentsOf: fetch.fileURL)
        #expect(data.count == 1000 && data[0] == 0 && data[999] == UInt8(999 % 251), "the new bytes")
    }

    // The app hands a fetch out under its lock and starts it after: a skip can let it go in between.
    // Started then, it makes no part and asks nothing.
    @Test func aFetchLetGoBeforeItStartsMakesNothing() async {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("s1.flac")
        let fetch = StreamFetch(request: URLRequest(url: URL(string: "http://stub.test/stream?declared=1000&send=1000")!),
                                fileURL: file, configuration: configuration())
        var finishes = 0
        fetch.onFinish = { _ in finishes += 1 }
        fetch.cancel()
        fetch.start()
        await pause(0.3)
        #expect(fetch.isCancelled && !fetch.isComplete && fetch.bytesWritten == 0)
        #expect(!FileManager.default.fileExists(atPath: fetch.partURL.path), "no part left behind")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(finishes == 0, "a fetch let go doesn't say it finished")
    }

    @Test func aRefusalIsSaidAsSignedOut() async {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = await fetch("status=401", into: dir)
        #expect(finished)
        #expect(fetch.failure?.kind == .signedOut && fetch.failure?.status == 401)
        #expect(!FileManager.default.fileExists(atPath: fetch.partURL.path))
        let (other, _) = await self.fetch("status=404", into: dir)
        #expect(other.failure?.kind == .unsupported && other.failure?.status == 404)
    }

    @Test func aSkippedFetchIsCancelledAndItsPartDeleted() async {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = await fetch("declared=100000&send=4000&hold=1", into: dir, seconds: 0.5)
        #expect(!finished, "still arriving")
        let until = Date().addingTimeInterval(5)
        while fetch.bytesWritten < 4000, Date() < until { await pause(0.01) }
        #expect(FileManager.default.fileExists(atPath: fetch.partURL.path))
        fetch.cancel()
        #expect(fetch.isCancelled && !fetch.isComplete)
        #expect(fetch.failure?.kind == .network, "a reader still holding it sees it end")
        #expect(!FileManager.default.fileExists(atPath: fetch.partURL.path), "the part deleted at once")
        #expect(!FileManager.default.fileExists(atPath: fetch.fileURL.path))
    }

    @Test func aCompleteFetchKeepsItsFileWhenLetGo() async {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (fetch, finished) = await fetch("declared=500&send=500", into: dir)
        #expect(finished)
        fetch.cancel()
        #expect(!fetch.isCancelled && fetch.isComplete)
        #expect(FileManager.default.fileExists(atPath: fetch.fileURL.path), "the cache's now")
    }
}
#endif
