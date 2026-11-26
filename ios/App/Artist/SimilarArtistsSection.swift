import DeadwaxCore
import SwiftUI

/// What Similar Artists draws on an artist's page (Last.fm, slice A2 - deadwax-plans/lastfm.md 3.4; notes/ios.md
/// "Last.fm, slice A2"), as ArtistView judges it for both devices.
struct SimilarShown {
    /// Last.fm on, its answer with similar artists: the section drawn, or its room held.
    let listed: Bool
    /// The tiles drawn: the library's artists answered (or failed), or the page has waited for them
    /// (SimilarArtists.drawsTiles) - before, the row's room is held, blank.
    let drawn: Bool
    /// Core's tiles (SimilarArtists.tiles): yours and theirs, Last.fm's order, 12 at most.
    let tiles: [SimilarArtists.Tile]

    /// Nothing of it: Last.fm off, or no similar artists.
    static let none = SimilarShown(listed: false, drawn: false, tiles: [])

    /// The section on the page: listed - and, once its tiles are drawn, with one to draw.
    var shows: Bool { listed && (!drawn || !tiles.isEmpty) }

    /// See All, past four (SimilarArtists.seesAll): its grid, where a mouse reaches every tile.
    var seesAll: Bool { drawn && SimilarArtists.seesAll(tiles) }
}

extension SimilarArtists.Tile {
    /// Where a tile opens: an artist of yours their page (Navidrome's picture drawn at once), anyone else their
    /// MusicBrainz page - the person glyph its picture, Get there.
    var route: AppRoute {
        switch opens {
        case .artist(let artist): return .artist(ArtistRoute(artist))
        case .musicBrainz(let mbid, let name): return .mbArtist(MBArtistRoute(mbid: mbid, name: name))
        }
    }
}

/// The phone's tile and its row: the tile's side at the default text size (the drawings' artist tile, and See All's
/// grid's least width - "Not in your library" fits it), 14 between tiles; the section's room above it.
enum SimilarArtistsDrawn {
    static let side = CGFloat(SimilarArtists.gridMin)
    static let gap: CGFloat = 14
    static let above: CGFloat = 20
    static let edge: CGFloat = 16
}

/// Similar Artists on the phone's artist page, under the albums (lastfm.md 3.1, 3.4): the heading with See All at its
/// end past four (their grid, SimilarArtistsScreen), one row of round tiles that a finger scrolls sideways, run out to
/// the screen's edges, and "From Last.fm" under it. Flat: the tiles on the page itself, no box. Before the library's
/// artists are known the row's room is held, blank, so nothing under it moves as the tiles come. The Mac's row is
/// MacArtistPage's, the same tiles.
struct SimilarArtistsSection: View {
    let shown: SimilarShown
    let route: ArtistRoute
    let credit: String?

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The tile's side, growing with the text its words are in - never past the page (`page`, SimilarArtists.side).
    @ScaledMetric(relativeTo: .footnote) private var scaled = SimilarArtistsDrawn.side
    /// (A2's review) The page's width, measured: at AX5 a tile grown with the text (some 379) is wider than a phone's.
    @State private var page: CGFloat?

    var body: some View {
        let lines = typeSize.isAccessibilitySize ? 3 : 1
        let side = CGFloat(SimilarArtists.side(Double(scaled), page: page.map(Double.init)))
        VStack(alignment: .leading, spacing: 0) {
            ArtistSectionHead(words: LastfmWords.similarArtists) {
                if shown.seesAll {
                    Button(LastfmWords.seeAll) {
                        navigation.open(.similarArtists(route))
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: SimilarArtistsDrawn.gap) {
                    if shown.drawn {
                        ForEach(shown.tiles) { (tile: SimilarArtists.Tile) in
                            SimilarArtistTile(tile: tile, side: side, lines: lines) {
                                navigation.open(tile.route)
                            }
                        }
                    } else {
                        // the row's room, held until the tiles are drawn: one tile's height, nothing in it
                        SimilarArtistTile.room(side: side, lines: lines)
                    }
                }
                // the page's margin inside the row, so the tiles run out to the screen's edges as they scroll
                .padding(.horizontal, SimilarArtistsDrawn.edge)
            }
            .padding(.horizontal, -SimilarArtistsDrawn.edge)
            LastfmCredit(lastfmPage: credit)
        }
        .onGeometryChange(for: CGFloat.self) { (drawn: GeometryProxy) -> CGFloat in
            drawn.size.width
        } action: { (width: CGFloat) -> Void in
            page = width
        }
        .padding(.top, SimilarArtistsDrawn.above)
    }
}

/// One similar artist (lastfm.md 3.4): their round picture - Navidrome's for one of yours, the person glyph for anyone
/// else (no picture is looked up for an artist you don't have) - their name in one line, and for one you don't have
/// "Not in your library" under it (a blank line under yours, so every tile is one height). Its tap opens their page
/// (yours) or their MusicBrainz page (theirs, `tile.route`). While deadwax can't be reached a tile of theirs is dimmed
/// and does nothing - "Opens once deadwax is back" its VoiceOver value (A2's review); one of yours opens from what is
/// kept. One element to VoiceOver: "GUM, Not in your library", a button whose action opens it. No right-click: a tile
/// has no •••. The faces are the caller's (`name`, `line`): the
/// phone's and See All's the text styles, the Mac's page its own.
struct SimilarArtistTile: View {
    let tile: SimilarArtists.Tile
    let side: CGFloat
    var name = Typeface.subheadline.weight(.semibold)
    var line = Typeface.footnote
    /// The lines each of the two may take (and hold): 1, 3 at the accessibility sizes.
    var lines = 1
    let open: () -> Void

    @Environment(Reachability.self) private var reachability

    var body: some View {
        let dimmed = !tile.yours && !reachability.online
        Button(action: open) {
            SimilarArtistFace(coverArt: tile.coverArt, name: tile.name, words: tile.line, side: side,
                              nameFont: name, lineFont: line, lines: lines)
                .opacity(dimmed ? DWPalette.off : 1)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .help(tile.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.spoken)
        .accessibilityValue(dimmed ? LastfmWords.opensOnceBack : "")
        .accessibilityAddTraits(dimmed ? [] : .isButton)
        .accessibilityAction {
            if !dimmed { open() }
        }
    }

    /// A tile's room, blank: the row's height held while the library's artists are asked.
    static func room(side: CGFloat, lines: Int, name: Font = Typeface.subheadline.weight(.semibold),
                     line: Font = Typeface.footnote) -> some View {
        SimilarArtistFace(coverArt: nil, name: " ", words: " ", side: side, nameFont: name, lineFont: line, lines: lines)
            .hidden()
            .accessibilityHidden(true)
    }
}

/// A tile's face: the round picture over the name and the line under it, `side` wide.
private struct SimilarArtistFace: View {
    let coverArt: String?
    let name: String
    let words: String
    let side: CGFloat
    let nameFont: Font
    let lineFont: Font
    let lines: Int

    var body: some View {
        VStack(spacing: 6) {
            ArtistPicture(id: coverArt, side: side, pixels: CoverSize.tile)
            VStack(spacing: 1) {
                Text(name)
                    .font(nameFont)
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(lines, reservesSpace: true)
                Text(words.isEmpty ? " " : words)
                    .font(lineFont)
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(lines, reservesSpace: true)
            }
            .multilineTextAlignment(.center)
        }
        .frame(width: side)
        .contentShape(Rectangle())
    }
}
