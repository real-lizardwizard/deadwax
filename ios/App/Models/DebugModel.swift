import DeadwaxCore
import Foundation
import Observation

/// You's Debug (admins only, D1): Phase 0's screen as it was - the test sounds, the hi-res row, downloads, Check's
/// report and how long this install runs - its behaviour unchanged. The address and the sign-in left it for the app's
/// own screens (ServerModel); playing goes through the player (PlayerModel.playTest).
@MainActor
@Observable
final class DebugModel {
    // Check's report
    private(set) var checking = false
    private(set) var report: CheckReport?

    // the test sounds and the hi-res row
    private(set) var testSongs: [Song] = []
    private(set) var testWords: String?
    /// The test songs on this phone, and those asked for and not here yet - DownloadModel's, as the album page has them.
    var downloaded: Set<String> { Set(debugSongs.map(\.id).filter { downloads.isHere($0) }) }
    var downloading: Set<String> {
        Set(debugSongs.map(\.id).filter { id in
            switch downloads.state(id) {
            case .waiting, .fetching: return true
            default: return false
            }
        })
    }
    private(set) var hiRes: Song?
    private(set) var hiResWords: String?
    private(set) var findingHiRes = false

    /// How long this install runs (7 days on a free account).
    let installLine: String

    private let server: ServerModel
    private let player: PlayerModel
    private let downloads: DownloadModel

    init(server: ServerModel, player: PlayerModel, downloads: DownloadModel) {
        self.server = server
        self.player = player
        self.downloads = downloads
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
        if let best {
            hiResWords = HiRes.isTwentyFourOneNinetyTwo(best) ? nil
                : "No 24/192 FLAC in the library; this is the highest rate there is."
        } else {
            hiResWords = ratesSaid ? "No FLAC above 48 kHz in the library."
                : "Navidrome didn't say any song's sample rate, so a hi-res song can't be found this way."
        }
    }

    private var debugSongs: [Song] { testSongs + (hiRes.map { [$0] } ?? []) }

    /// "Download all 10" and a row's download: DownloadModel's, as the album page asks.
    func download(_ songs: [Song]) {
        downloads.download(songs: songs.filter { !downloads.isHere($0.id) })
    }

    /// "Remove the downloads": the test songs' and the hi-res row's.
    func removeDownloads() {
        downloads.remove(songs: debugSongs.map(\.id))
    }

    /// A test song's tap: the songs played from `index` - their copies on this phone first, as every song is, unless
    /// "Stream even when downloaded" is on.
    func play(_ songs: [Song], at index: Int) {
        player.playTest(songs, at: index)
    }

    /// The person changed: nothing of theirs kept.
    func reset() {
        report = nil
        testSongs = []
        testWords = nil
        hiRes = nil
        hiResWords = nil
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
