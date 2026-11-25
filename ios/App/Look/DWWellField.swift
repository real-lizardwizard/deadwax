import DeadwaxCore
import SwiftUI

/// A field a page already has, drawn in the look's well on the phone (the redesign, slice R1c's review - notes/ios.md
/// "The redesign, slice R1c: the phone is flat (2026-11-25)"; James, 25 Nov: "actually any place you can input text
/// should be a box"): where DWField is a field of its own, this dresses one that keeps its own words, keyboard, Return
/// and focus - a playlist's Edit's name and description, the manual search's Artist and Album - as DWField's is drawn.
///
/// - On the phone: the plain field in the field's type and white (`.dw.ph .in`, 16 so iOS never zooms to it), the
///   system's focus ring off; padded 8 either side (`.in`), 36 tall at
///   least (`lines`: a field that grows a line at a time, padded 8 above and below too - this session's own room, dw.css
///   draws no field of more than a line); on DWWell, the accent's edge while it has the cursor, and a tap on the well -
///   or a finger's 44 round it - puts the cursor in it.
/// - Its focus is the page's: the field keeps its own `.focused(focus, equals: field)` (both devices'; the Mac's Tab and
///   a sheet's first cursor need it there), and this reads that binding - for the edge - and sets it from a tap, never
///   binds it again.
/// - On the Mac nothing: the field as its page already drew it (R1c: "the Mac doesn't change").
struct DWWellField<Field: Hashable>: ViewModifier {
    let focus: FocusState<Field?>.Binding
    let field: Field
    /// A field of more than a line (`axis: .vertical`).
    var lines = false

    @ViewBuilder func body(content: Content) -> some View {
        if Platform.mac {
            content
        } else {
            content
                .textFieldStyle(.plain)
                .font(Typeface.Look.text(.field))
                .foregroundStyle(DWPalette.fieldText)
                .focusEffectDisabled()
                // .in: padding 0 8px
                .padding(.horizontal, 8)
                .padding(.vertical, lines ? 8 : 0)
                .lookHeight(DWLook.here.fieldHeight)
                .background {
                    DWWell(focused: focus.wrappedValue == field)
                        .contentShape(DWTarget(face: DWCorners.buttonShape))
                        .onTapGesture {
                            focus.wrappedValue = field
                        }
                }
        }
    }
}
