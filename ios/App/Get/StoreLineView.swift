import DeadwaxCore
import SwiftUI

/// What the store and the downloads already have of a pressing (Phase 6, slice 2 - phase6-get-requests.md 2.9; the web's
/// app/StoreState.tsx): its box - the title (green for a pressing held), its lines, the last of several the detail under
/// them - and the notes under it (a part held, a part downloading, other pressings held). Under Get the album, and in the
/// Sources sheet where the sources would be. Every word is Core's (StoreLine): slice 2 draws `StoreLine.drawn`, neither
/// Join nor Add (slice 3's) - so neither "Join it" nor "add it" is said above no button. A path is a stranger's folder
/// name as often as not, so every line wraps rather than run off the screen. Nothing at all for nothing to say.
struct StoreLineView: View {
    let status: StoreStatus?
    let notes: [String]

    var body: some View {
        if status != nil || !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let status {
                    box(status)
                }
                ForEach(notes.indices, id: \.self) { (at: Int) in
                    Text(notes[at])
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func box(_ status: StoreStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(status.title)
                .font(Typeface.subheadline.weight(.semibold))
                .foregroundStyle(status.kind == .held ? Palette.held : Color.primary)
            ForEach(status.lines.indices, id: \.self) { (at: Int) in
                // the folders (or the peer) first; the last of several the detail under them
                Text(status.lines[at])
                    .font(Typeface.footnote)
                    .foregroundStyle(at > 0 && at == status.lines.count - 1 ? Palette.textTertiary : Palette.text2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: Corners.cardShape)
        .overlay(Corners.cardShape.strokeBorder(Palette.border))
        .accessibilityElement(children: .combine)
    }
}
