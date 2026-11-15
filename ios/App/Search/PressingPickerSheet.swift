import DeadwaxCore
import SwiftUI

/// The pressing picker (the web's PressingPicker.tsx, as a sheet on the phone - question 17): every pressing of the
/// album as Core's Pressings.view lists them - the usual one first, a pressing of each other format, the ones that
/// differ, the ones with no tracklist - each its label, its facts, how it compares with the usual tracklist and
/// whether you hold it; those with the usual tracklist folded under "N more pressings with the usual tracklist". The
/// chosen one ticked. An album of more than `Pressings.filterMin` pressings has a filter ("JP, CD, a label or
/// catalogue no."), what it leaves said as it narrows. A tap picks the pressing and closes the sheet.
struct PressingPickerSheet: View {
    let view: PressingsView
    let pick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var expanded = false

    private var all: [PressingChoice] { view.shown + view.more }
    private var filterable: Bool { all.count > Pressings.filterMin }
    private var filtering: Bool { filterable && !JSText.trim(typed).isEmpty }

    /// Filtering: every pressing that matches, the fold stepped aside; otherwise the list as it folds.
    private var rows: [PressingChoice] {
        if filtering { return Pressings.filter(all, typed) }
        return expanded ? all : view.shown
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { (row: PressingChoice) in
                        Button {
                            pick(row.id)
                            dismiss()
                        } label: {
                            PressingChoiceRow(row: row, selected: row.id == view.chosenId)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(row.id == view.chosenId ? .isSelected : [])
                    }
                    if filtering && rows.isEmpty {
                        Text(Pressings.filterWords(0, typed))
                            .foregroundStyle(Palette.quiet)
                    }
                    if !view.more.isEmpty && !expanded && !filtering {
                        Button(Pressings.moreWords(view.more.count)) { expanded = true }
                    }
                }
            }
            .listStyle(.plain)
            .accessibilityLabel(Pressings.pressingsLabel)
            .navigationTitle(Pressings.picker)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Pressings.done) { dismiss() }
                }
            }
            .modifier(PressingFilter(on: filterable, typed: $typed))
            .onChange(of: typed) { _, now in
                // what the filter left, said as the list narrows
                let said = Pressings.filterWords(filtering ? rows.count : 0, now)
                if !said.isEmpty { Notice.announce(said) }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The filter's field, only for an album of many pressings.
private struct PressingFilter: ViewModifier {
    let on: Bool
    @Binding var typed: String

    func body(content: Content) -> some View {
        if on {
            content
                .searchable(text: $typed, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: Text(Pressings.filterPrompt))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityHint(Pressings.filterLabel)
        } else {
            content
        }
    }
}

/// One pressing: the tick, its label ("CD · 2008 · GB · Island"), its facts, how it compares ("Adds 2 tracks", in amber
/// when it differs), and "In your library" / "In the collection" for one held. Read as one.
private struct PressingChoiceRow: View {
    let row: PressingChoice
    let selected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark")
                .font(Typeface.symbol(.footnote).weight(.bold))
                .foregroundStyle(Palette.accent)
                .opacity(selected ? 1 : 0)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .foregroundStyle(.primary)
                if !row.facts.isEmpty {
                    Text(row.facts)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                }
                Text(row.note)
                    .font(Typeface.footnote)
                    .foregroundStyle(row.kind == .differs ? Palette.amber : Palette.quiet)
                if row.held {
                    Text(row.heldLabel)
                        .font(Typeface.caption.weight(.semibold))
                        .foregroundStyle(Palette.held)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
