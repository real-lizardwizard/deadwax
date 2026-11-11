import DeadwaxCore
import Foundation
import Observation

/// You's Debug (admins only, D1): Phase 0's screen as it was - the test sounds, the hi-res row, downloads, Check's
/// report and how long this install runs - its behaviour unchanged. The address and the sign-in left it for the app's
/// own screens (ServerModel); playing goes through the player (PlayerModel.playTest).
@MainActor
@Observable
final class DebugModel {
    enum Source: String, CaseIterable, Identifiable {
        case stream = "Streamed"
        case downloaded = "Downloaded"
        var id: String { rawValue }
    }

    // Check's report
    private(set) var checking = false
    private(set) var report: CheckReport?

    // the test sounds and the hi-res row
    private(set) var testSongs: [Song] = []
    private(set) var testWords: String?
    var source: Source = .stream
    private(set) var downloaded: Set<String> = []
    private(set) var downloading: Set<String> = []
    private(set) var downloadWords: String?
    private(set) var hiRes: Song?
    private(set) var hiResWords: String?
    private(set) var findingHiRes = false

    /// How long this install runs (7 days on a free account).
    let installLine: String

    private let server: ServerModel
    private let player: PlayerModel
    private let files: SongFiles

    init(server: ServerModel, player: PlayerModel, files: SongFiles) {
        self.server = server
        self.player = player
        self.files = files
        installLine = InstallExpiry.line(expiration: Self.profile()?.expiration, now: Date())
    }

    /// The app's own provisioning profile: how long this install runs.
    static func profile() -> ProvisioningProfile? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ProvisioningProfile.parse(data)
    }

    // MARK: Check

    /// Phase 0's Check against the address in use: /health, then /me, said as CheckReport's lines - and the test
    /// sounds looked for when it's all well.
    func check() async {
        guard let client = server.client else { return }
        checking = true
        defer { checking = false }
        let health = await outcome { try await client.health() }
        var who: Result<Me, DeadwaxError>?
        if case .success = health { who = await outcome { try await client.me() } }
        let report = CheckReport.from(health: health, me: who)
        self.report = report
        if report.ok { await loadTestSongs() }
    }

    // MARK: the test sounds and the hi-res row

    func loadTestSongs() async {
        guard let client = server.client else { return }
        do {
            let found = try await client.search(TestSounds.query, songs: TestSounds.pageSize)
            testSongs = TestSounds.pick(found.songs)
            testWords = testSongs.isEmpty
                ? "The beep album isn't in the library: copy \"Start test (2026)\" by \"deadwax test\" into it, let Navidrome scan, and Check again."
                : nil
            refreshDownloaded()
        } catch {
            testWords = words(error)
        }
    }

    func findHiRes() async {
        guard let client = server.client else { return }
        findingHiRes = true
        defer { findingHiRes = false }
        var best: Song?
        var ratesSaid = false
        do {
            for page in 0..<HiRes.maxPages {
                let found = try await client.search("", songs: HiRes.pageSize, songOffset: page * HiRes.pageSize)
                ratesSaid = ratesSaid || found.songs.contains { $0.samplingRate != nil }
                if let candidate = HiRes.best(found.songs + (best.map { [$0] } ?? [])) { best = candidate }
                if let best, HiRes.isTwentyFourOneNinetyTwo(best) { break }
                if found.songs.count < HiRes.pageSize { break }
            }
        } catch {
            hiResWords = words(error)
            return
        }
        hiRes = best
        refreshDownloaded()
        if let best {
            hiResWords = HiRes.isTwentyFourOneNinetyTwo(best) ? nil
                : "No 24/192 FLAC in the library; this is the highest rate there is."
        } else {
            hiResWords = ratesSaid ? "No FLAC above 48 kHz in the library."
                : "Navidrome didn't say any song's sample rate, so a hi-res song can't be found this way."
        }
    }

    func refreshDownloaded() {
        downloaded = Set((testSongs + (hiRes.map { [$0] } ?? [])).filter { files.downloadedURL(for: $0) != nil }.map(\.id))
    }

    func download(_ songs: [Song]) async {
        guard let client = server.client else { return }
        downloadWords = nil
        for song in songs where !downloaded.contains(song.id) {
            downloading.insert(song.id)
            do {
                try await files.download(song, client: client)
                downloaded.insert(song.id)
            } catch {
                downloadWords = "\(song.name): \(words(error))"
            }
            downloading.remove(song.id)
        }
    }

    func removeDownloads() {
        files.removeDownloads()
        refreshDownloaded()
    }

    /// A test song's tap: the songs played from `index`, their downloaded copies with Downloaded chosen.
    func play(_ songs: [Song], at index: Int) {
        player.playTest(songs, at: index, copies: source == .downloaded)
    }

    /// The person changed: nothing of theirs kept.
    func reset() {
        report = nil
        testSongs = []
        testWords = nil
        hiRes = nil
        hiResWords = nil
        downloadWords = nil
        refreshDownloaded()
    }

    // MARK: words

    private func words(_ error: Error) -> String {
        (error as? DeadwaxError)?.words ?? String(describing: error)
    }

    private func outcome<T>(_ body: () async throws -> T) async -> Result<T, DeadwaxError> {
        do {
            return .success(try await body())
        } catch let error as DeadwaxError {
            return .failure(error)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }
}
