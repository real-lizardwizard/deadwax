import DeadwaxAudio
import DeadwaxCore
import Foundation

/// What Info asks for while it is open (ui/src/app/useInfoDetails.ts, Phase 1's part of it), for the song playing:
///
///  - the song as Navidrome has it NOW (GET .../songs/{id}): its play count and writers, which the album answer it
///    was played from holds only as they were at the tap;
///  - the store's folders of its album (the id bridge, GET /store/album by Navidrome's id) - "This pressing: …"
///    and the folder - asked only with a library of one's own (D12, Access.hasLibrary).
///
/// The two are held back for each other until both have answered or InfoWords.settleSeconds has gone, so a card
/// doesn't grow under a finger reaching for the one below it; after that each lands as it comes. A failure leaves
/// its lines out, as everything Navidrome doesn't send is. The web's artist answers (getArtist, MusicBrainz's facts)
/// are the artist page's, Phase 3's: the artist card is the name alone (D8).
///
/// Each call is made in a task the view starts for one song (`.task(id:)`), so a song changing under an open Info
/// cancels the last one's asking, and nothing of it lands (the newest answer alone draws).
enum InfoAsk {
    /// What a call has said, for which song - drawn only while it is the song playing.
    struct Said: Equatable {
        let songID: String
        var details: AboutDetails
    }

    private enum Landed: Sendable {
        case song(SongDetails?)
        case store([PressingRow]?)
        case settled
    }

    /// Asks for the song `songID`'s details and, with `bridge`, its album's folders - `put` called with what is
    /// known so far, once both are in or the wait is over, then again as the rest lands.
    @MainActor
    static func details(songID: String, albumID: String?, bridge: Bool, client: DeadwaxClient,
                        put: @escaping @MainActor (AboutDetails) -> Void) async {
        let albumID = albumID.flatMap { $0.isEmpty ? nil : $0 }
        let store = bridge ? albumID : nil
        var held = AboutDetails()
        var holding = true
        var out = store == nil ? 1 : 2
        await withTaskGroup(of: Landed.self) { group in
            group.addTask {
                .song(try? await client.call(Routes.song, as: SongDetails.self, path: ["song_id": songID]))
            }
            if let store {
                group.addTask {
                    .store(try? await client.storeAlbum(navidromeID: store).present.map(PressingRow.init(row:)))
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(InfoWords.settleSeconds))
                return .settled
            }
            for await landed in group {
                if Task.isCancelled { return }
                switch landed {
                case .song(let song):
                    out -= 1
                    held.song = song
                case .store(let present):
                    out -= 1
                    held.present = present
                case .settled:
                    if !holding { continue }
                    holding = false
                    put(held)
                    continue
                }
                if !holding {
                    put(held)
                } else if out == 0 {
                    holding = false
                    put(held)
                    //? both in: the wait has nothing left to hold back
                    group.cancelAll()
                }
            }
        }
    }

    /// The album answer as Navidrome sends it, every field as it came, for Debug's "Fields from Navidrome" - nil when
    /// it can't be had.
    static func rawAlbum(id: String, client: DeadwaxClient) async -> RawJSON? {
        try? await client.call(Routes.album, as: RawJSON.self, path: ["album_id": id])
    }
}

extension InfoDebug.Engine {
    /// What the phone's engine says of the song heard, as Debug's rows read it: the output (its rate and latency,
    /// the route's name), Phase 0's readout of the file against the output, and the lane the song heard is on -
    /// else the first - with what it has scheduled ahead; and what the EQ's unit does with the sound (eq.md 3.1).
    init(_ debug: EngineDebug?, outputName: String?, readout: String?, eq: String? = nil) {
        let lane = debug?.lanes.first(where: \.heard) ?? debug?.lanes.first
        self.init(outputRate: debug?.outputRate,
                  outputName: outputName,
                  latency: debug?.outputRate == nil ? nil : debug?.latency,
                  conversion: readout,
                  laneRate: lane?.rate,
                  laneChannels: lane?.channels,
                  nodeRate: lane?.nodeRate,
                  converting: lane?.converting,
                  aheadSeconds: lane?.aheadSeconds,
                  lastStartSeconds: debug?.lastStartSeconds,
                  eq: eq)
    }
}
