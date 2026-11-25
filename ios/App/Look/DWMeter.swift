import DeadwaxCore
import SwiftUI

/// A download's bar, dw.css's `.meter`, on both devices (the redesign, slice R8 - notes/ios.md "The redesign, slice R8:
/// Requests"): the sunken track - the well, its 1 pt line, the inset shade along its top - and the fill inside its line,
/// in its tone's gradient (.meter's grey, .pur's purple, .grn's green). Its height is DWLook's: .meter's 6 on the Mac,
/// exactly, and .dw.ph's 8 on the phone, grown there with the text as everything is. Rounded on the Mac (.meter's 2, its
/// fill's 1), square on the phone (dw.css's last block, DWCorners' phone half). A fill never passes its track: how much
/// of it the fill takes is Core's DWLook.meterShare - 104% is full, -3% and NaN are empty.
///
/// Drawn beside its words ("3 of 11 files"), which say what it shows: VoiceOver hears those, and not the bar again.
struct DWMeter: View {
    enum Tone {
        /// .meter's grey.
        case plain
        /// .meter.pur: a download coming in.
        case marked
        /// .meter.grn: done.
        case good
    }

    /// How far along: 0 to 1 (anything outside is the nearest end).
    let fraction: Double
    var tone: Tone = .marked

    @ScaledMetric(relativeTo: .footnote) private var grown: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let share = CGFloat(DWLook.meterShare(fraction))
        DWCorners.meterShape
            .fill(DWPalette.well.shadow(.inner(color: DWPalette.meterShade, radius: 1, x: 0, y: 1)))
            .overlay { DWCorners.meterShape.strokeBorder(DWPalette.line, lineWidth: 1) }
            .overlay {
                //? inside the track's 1 pt line, as `.meter > i` sits inside .meter's border
                GeometryReader { (track: GeometryProxy) in
                    DWCorners.meterFillShape
                        .fill(fill)
                        .frame(width: track.size.width * share)
                }
                .padding(1)
            }
            .frame(height: height)
            .animation(reduceMotion ? nil : .linear(duration: 0.25), value: share)
            .accessibilityHidden(true)
    }

    /// DWLook's height: the Mac's exactly, the phone's grown with the text.
    private var height: CGFloat {
        CGFloat(DWLook.here.meterHeight) * (DWLook.here.grows ? grown : 1)
    }

    private var fill: LinearGradient {
        switch tone {
        case .plain: return DWPalette.meterFill
        case .marked: return DWPalette.meterMarked
        case .good: return DWPalette.meterGood
        }
    }
}
