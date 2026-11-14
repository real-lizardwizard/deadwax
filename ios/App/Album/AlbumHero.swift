import DeadwaxCore
import SwiftUI

/// The top of an album page (screens.md 4, AlbumPage.tsx's hero): the cover (asked at 1024), the title (two lines,
/// a step smaller over 60 letters), the artist (plain text until Phase 4's slice 4, the link to their page since), the meta line,
/// the badge - its place held, unseen, until whose it is is known - the album's download line under it (Phase 2), and
/// Play and Shuffle, live once the songs are in (offline: once a song of it is on this phone). Drawn at once from what
/// opened the page, then filled as the album answers.
struct AlbumHero: View {
    let model: AlbumModel
    /// The album's download (phase2-downloads.md 3.2): its line under the badge, nothing at all for none.
    let download: AlbumDownload
    /// Play and Shuffle have something to play: the songs, or offline the songs on this phone.
    let playable: Bool
    let play: () -> Void
    let shuffle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppNavigation.self) private var navigation

    /// The cover's side, in points (CoverImage asks the nearest step for the screen's scale: 1024 on an iPhone).
    static let coverSide: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            CoverImage(id: model.coverArt, size: Self.coverSide)
                .frame(maxWidth: Self.coverSide)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.top, 8)

            Text(model.name)
                .font(model.longTitle ? .title3.bold() : .title2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)

            if !model.artist.isEmpty {
                artistLine
                    .padding(.top, 2)
            }

            // the meta line holds its line while it is empty, so nothing below moves as it fills
            Text(model.meta.isEmpty ? " " : model.meta)
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .accessibilityHidden(model.meta.isEmpty)

            HeldBadge(mine: model.mine)
                .opacity(model.badgeShown ? 1 : 0)
                .accessibilityHidden(!model.badgeShown)
                .padding(.top, 10)

            // its own line, so the badge never slides as the count moves; none at all for an album never downloaded
            if let line = DownloadWords.albumLine(download) {
                DownloadLine(download: download, line: line)
                    .padding(.top, 6)
                    .transition(.opacity)
            }

            PlayButtons(enabled: playable, play: play, shuffle: shuffle)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .default, value: DownloadWords.albumLine(download) != nil)
    }

    /// (Phase 4, slice 4) The artist (ArtistLink, AlbumPage.tsx's): a link to their page in the accent when the album
    /// names an artist and their name; drawn the same, but not tappable, while the album hasn't answered and it might
    /// still become one - so it never flashes from grey to the accent; quiet once the album has answered naming no
    /// artist to go to.
    @ViewBuilder private var artistLine: some View {
        let words = Text(model.artist)
            .font(.title3)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        switch model.artistLink {
        case .link(let id):
            // a button, not a NavigationLink: in the page's List a link would take the whole hero's row
            Button {
                navigation.open(.artist(ArtistRoute(id: id, preview: Artist(id: id, name: model.artist))))
            } label: {
                words
                    .foregroundStyle(Palette.accent)
                    // 44 pt to a finger, as the web's link reaches past its line
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -8)
        case .pending:
            words.foregroundStyle(Palette.accent)
        case .plain:
            words.foregroundStyle(Palette.quiet)
        }
    }
}

/// The hero's download line (3.2): the album's line in the "In the collection" style - caption, semibold, quiet, no box
/// - its mark in front (amber, and amber words, for didn't); centred, wrapping at the largest sizes. Not a button: the
/// control in the bar is. VoiceOver reads it after the badge, the words alone.
struct DownloadLine: View {
    let download: AlbumDownload
    let line: String

    var body: some View {
        let failed: Bool = {
            if case .failed = download { return true }
            return false
        }()
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let mark = DownloadWords.mark(download) {
                // a symbol's own baseline (the ring keeps the hidden symbol's) sits it on the words' line
                DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(download), font: .caption)
            }
            Text(line)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(failed ? Palette.amber : Palette.quiet)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line)
    }
}

/// "In your library" (with its tick, in the green badge) or "In the collection" (grey, no box) - Whose's badge.
struct HeldBadge: View {
    let mine: AlbumMine

    var body: some View {
        let yours = mine.yours == true
        HStack(spacing: 5) {
            if yours {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(mine.badge)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(yours ? Palette.held : Palette.quiet)
        .padding(.horizontal, yours ? 8 : 0)
        .padding(.vertical, 3)
        .background {
            if yours {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.heldFill)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.heldEdge, lineWidth: 0.5))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Play (the primary pill) and Shuffle (the secondary), side by side - one above the other at the largest text sizes. An album's page's,
/// and a playlist's (Phase 4).
struct PlayButtons: View {
    let enabled: Bool
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { buttons }
                .frame(maxWidth: 420)
            VStack(spacing: 10) { buttons }
        }
        .disabled(!enabled)
    }

    @ViewBuilder private var buttons: some View {
        Button(action: play) {
            Label("Play", systemImage: "play.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryFace(large: true))

        Button(action: shuffle) {
            Label("Shuffle", systemImage: "shuffle")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryPill(large: true))
    }
}
