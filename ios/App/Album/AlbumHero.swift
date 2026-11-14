import DeadwaxCore
import SwiftUI

/// The top of an album page (screens.md 4, AlbumPage.tsx's hero): the cover (asked at 1024), the title (two lines,
/// a step smaller over 60 letters), the artist (plain text in Phase 1 - the artist page is Phase 3), the meta line,
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
                Text(model.artist)
                    .font(.title3)
                    .foregroundStyle(Palette.quiet)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
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
}

/// The hero's download line (3.2): the album's line in the "In the collection" style - caption, semibold, quiet, no box
/// - its mark in front (amber, and amber words, for didn't); centred, wrapping at the largest sizes. Not a button: the
/// control in the bar is. VoiceOver reads it after the badge, the words alone.
private struct DownloadLine: View {
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

/// Play (filled) and Shuffle (plain), side by side - one above the other at the largest text sizes. An album's page's,
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
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Button(action: shuffle) {
            Label("Shuffle", systemImage: "shuffle")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
