import DeadwaxCore
import SwiftUI

/// The top of an album page (screens.md 4, AlbumPage.tsx's hero): the cover (asked at 1024), the title (two lines,
/// a step smaller over 60 letters), the artist (plain text in Phase 1 - the artist page is Phase 3), the meta line,
/// the badge - its place held, unseen, until whose it is is known - and Play and Shuffle, live once the songs are in.
/// Drawn at once from what opened the page, then filled as the album answers.
struct AlbumHero: View {
    let model: AlbumModel
    let play: () -> Void
    let shuffle: () -> Void

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

            PlayButtons(enabled: !model.songs.isEmpty, play: play, shuffle: shuffle)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
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

/// Play (filled) and Shuffle (plain), side by side - one above the other at the largest text sizes.
private struct PlayButtons: View {
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
