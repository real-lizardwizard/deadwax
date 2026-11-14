import DeadwaxCore
import SwiftUI
import UIKit

/// A MusicBrainz album's cover (Phase 5, slice 2 - the web's ArchiveCover.tsx): the Cover Art Archive's front through
/// deadwax's relay (`/deadwax/coverart/{kind}/{mbid}`, server 2.1.24), each of `addresses` tried in turn - a pressing's
/// front, then its album's (`ArchiveCoverID.addresses`) - at one of the relay's sizes (`ArchiveCoverSize`). Kept in
/// memory by CoverCache as Navidrome's covers are. The empty square while it loads, and for anything but a front: none,
/// the Archive away, a server before 2.1.24, deadwax out of reach. Square; the caller gives it its frame. Hidden from
/// VoiceOver - the row or the page says what it is.
struct ArchiveCover: View {
    let addresses: [ArchiveCoverID]
    let size: Int

    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    /// What a load gave this view, under the key it was asked by; let go when the view goes.
    @State private var loaded: Loaded?

    private struct Loaded {
        let key: String
        let image: UIImage
    }

    /// The server, the session (a sign-in again asks again), the addresses and the size.
    private var key: String {
        let named = addresses.map { (cover: ArchiveCoverID) -> String in "\(cover.kind.rawValue)/\(cover.mbid)" }
        return "\(server.address?.key ?? "")|\(server.client?.session?.hashValue ?? 0)|\(named.joined(separator: ","))|\(size)"
    }

    var body: some View {
        let key = self.key
        let image = loaded?.key == key ? loaded?.image : cached
        // the load's id: the key, and whether deadwax can be reached - so a front that failed while it couldn't asks once
        // more as it comes back (CoverCache.reach); what is drawn stays under the key alone, never blanked going offline
        let asking = "\(key)|\(reachability.online)"
        ZStack {
            Rectangle().fill(Palette.coverEmpty)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .accessibilityHidden(true)
        .task(id: asking) {
            guard let client = server.client, let first = addresses.first,
                  CoverCache.shared.cachedArchive(client: client, cover: first, size: size) == nil else { return }
            for address in addresses {
                let got = await CoverCache.shared.loadArchive(client: client, cover: address, size: size)
                // a load for covers this view has left (its key changed, or it went) draws nothing
                guard !Task.isCancelled else { return }
                if let got {
                    loaded = Loaded(key: key, image: got)
                    return
                }
            }
        }
        .onDisappear { loaded = nil }
    }

    /// The first of the addresses the cache holds now.
    private var cached: UIImage? {
        guard let client = server.client else { return nil }
        for address in addresses {
            if let image = CoverCache.shared.cachedArchive(client: client, cover: address, size: size) { return image }
        }
        return nil
    }
}
