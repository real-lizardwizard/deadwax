import DeadwaxCore
import SwiftUI

/// Settings > Manage > Needs a look (Phase 8, slice 6 - notes/ios-specs/phase8-managing.md 5; the web's
/// app/NeedsALook.tsx): the review queue, pushed on the Settings tab. As the web's ladder has it: LIBRARY_PATH's problem
/// said plainly; Reading the library; a first read failed, with Try again; else the list - a status line over it (a read
/// again failed with Try again, Checking the library…, else Navidrome's note) and an album per row, its chips - New, each
/// outstanding issue, Marked fine under that facet - or, in a session, what became of it (Fixed, Marked fine, Deleted).
///
/// A row opens Edit album over the tabs on its folder in queue mode (NeedsLookModel.open); while a session's rows are
/// held after it, and while deadwax can't be reached, rows are off. Rows are known by the path they were listed at, so a
/// rename moves nothing; with Reduce Motion nothing slides. VoiceOver reads each row once (NeedsLookWords.row).
/// Without Look after the library it says so and asks nothing; opened out of reach it says it needs deadwax, and reads
/// once deadwax is back. Gone out of reach over a list, the list stays under the amber line Edit album has, its rows off
/// and a pull asking nothing; back, the library is read again (slice 6's review). A failed read is said in the page's
/// own words (NeedsLookModel.failure), never the editor's, though they share the scan. Nothing is read under the sign-in
/// over the app; once it goes, the page reads again (slice 7's review) - NeedsLookLife, the Mac's page's too.
///
/// (R12 - notes/ios.md "The redesign, slice R12: Needs a look"; iNeedsALook.dc.html) Flat, as the drawing has it: the
/// large title; Marked fine · N at the top's right, a button of its own (on while it shows, All again when pressed
/// then); the facets as a strip with their counts ("All 3", "No cover art 1" - All's is the count the badge says,
/// NeedsLook.summaryTotal); a card per album - its cover at 48, the album, its artist and edition, its folder in the
/// readout face, a chevron, and its chips under it, wrapping (each its own line at the accessibility sizes); and under
/// them what takes an album off the list. No list, no grey row: a card is its words on the page over its hairline.
/// Edit albums missing, and marks deadwax can't save, are said over it; the lead line went with the drawing.
struct NeedsLookScreen: View {
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = NeedsLookModel()

    var body: some View {
        let page = model.page
        // a ZStack, not a Group: the page's frame (its shows and hides, NeedsLookLife) is on one view that stays as the
        // branches swap - on a Group it would go to each branch, and a swap would hide and show the page (R13's rule)
        ZStack {
            if !page.allowed {
                ContentUnavailableView {
                    Label(NeedsLook.title, systemImage: "lock")
                } description: {
                    Text(EditWords.noPermission)
                }
            } else if !reachability.online && !model.scan.loaded {
                ContentUnavailableView {
                    Label(NeedsLook.title, systemImage: "wifi.slash")
                } description: {
                    Text(EditWords.needsDeadwax)
                }
            } else {
                list(page)
            }
        }
        .navigationTitle(NeedsLook.title)
        .toolbar {
            if page.allowed, model.state == .list, let fine = NeedsLookPage.markedFine(model.chips) {
                ToolbarItem(placement: .topBarTrailing) {
                    markedFine(fine)
                }
            }
        }
        .modifier(NeedsLookLife(model: model))
    }

    // MARK: the list

    @ViewBuilder private func list(_ page: Managing.NeedsLookPage) -> some View {
        let side = CGFloat(PhoneLook.bigSide)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                notes(page)
                    .padding(.horizontal, side)
                switch model.state {
                case .problem(let problem):
                    Text(problem)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.amberText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, side)
                        .padding(.top, CGFloat(PhoneLook.cardPadding))
                case .reading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(NeedsLook.reading)
                            .foregroundStyle(DWPalette.t2)
                    }
                    .font(Typeface.Phone.text(.small))
                    .accessibilityElement(children: .combine)
                    .padding(.horizontal, side)
                    .padding(.top, CGFloat(PhoneLook.cardPadding))
                case .failed:
                    VStack(alignment: .leading, spacing: 8) {
                        ErrorNote(text: model.failure ?? NeedsLook.readFailed)
                        Button(NeedsLook.tryAgain) {
                            model.retry()
                        }
                        .buttonStyle(DWButtonStyle(size: .small))
                        .disabled(model.scan.reading || !reachability.online)
                    }
                    .padding(.horizontal, side)
                    .padding(.top, CGFloat(PhoneLook.cardPadding))
                case .list:
                    strip
                    status
                        .padding(.horizontal, side)
                    let rows = model.rows
                    if rows.isEmpty {
                        Text(NeedsLook.nothing)
                            .font(Typeface.Phone.text(.small))
                            .foregroundStyle(DWPalette.t2)
                            .padding(.horizontal, side)
                            .padding(.top, CGFloat(PhoneLook.cardPadding))
                    } else {
                        // iNeedsALook's `.col`: the cards 10 apart, each on its hairline
                        ForEach(Array(rows.enumerated()), id: \.element.key) { (index: Int, row: NeedsLook.DrawnRow) in
                            card(row, current: model.session?.index == index)
                                .padding(.horizontal, side)
                                .padding(.bottom, NeedsLookLook.cardGap)
                        }
                    }
                    Text(NeedsLookPage.leaves)
                        .font(Typeface.Phone.text(.extraSmall))
                        .foregroundStyle(DWPalette.t3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, side)
                        .padding(.vertical, CGFloat(PhoneLook.cardPadding))
                }
            }
        }
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
        // out of reach, the list stays as last read under the amber line, and a pull asks nothing (review, 16 Nov)
        .editOutOfReach(!reachability.online && model.scan.loaded)
        .pullToRefresh {
            await model.pulled()
        }
    }

    /// What the page says before its list: Edit albums missing (fixing needs it), and a mark that won't be kept.
    @ViewBuilder private func notes(_ page: Managing.NeedsLookPage) -> some View {
        if !page.canEdit {
            Text(NeedsLook.needsEdit)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, CGFloat(PhoneLook.cardPadding))
        }
        if model.ignoresUnsaved {
            Text(NeedsLook.ignoresUnsavedWords)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.amberText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, CGFloat(PhoneLook.cardPadding))
        }
    }

    /// The facets but Marked fine (its button's), with their counts - All's the badge's own count. Choosing one while
    /// a session lasts ends it (the sheet is over the page then, so only the sheet's going can).
    private var strip: some View {
        let chips = NeedsLookPage.strip(model.chips)
        return PhoneStrip(options: chips.map(\.id), words: { (id: String?) -> String in
            NeedsLook.chip(chips, pressed: id).map(NeedsLookWords.facet) ?? NeedsLook.show
        }, shown: Binding(get: { model.pressed }, set: { (id: String?) -> Void in model.choose(facet: id) }),
           spoken: NeedsLook.show, said: { (id: String?) -> String in
            NeedsLook.chip(chips, pressed: id).map(NeedsLookWords.facetSpoken) ?? NeedsLook.show
        })
    }

    /// The status line over the cards - always there, one line at least, so its coming and going moves no card.
    private var status: some View {
        Group {
            switch model.status {
            case .failed?:
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.failure ?? NeedsLook.checkFailed)
                        .foregroundStyle(DWPalette.redChipText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(NeedsLook.tryAgain) {
                        model.retry()
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                    .disabled(model.scan.reading || !reachability.online)
                }
            case .checking?:
                Text(NeedsLook.checking)
                    .foregroundStyle(DWPalette.t2)
            case .navidrome(let note)?:
                Text(note)
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
            case nil:
                Text(" ")
                    .accessibilityHidden(true)
            }
        }
        .font(Typeface.Phone.text(.extraSmall))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A card: the album's cover, its lines and chips - opening Edit album in queue mode. One element to VoiceOver.
    private func card(_ row: NeedsLook.DrawnRow, current: Bool) -> some View {
        let chips = NeedsLookPage.chips(row, pressed: model.pressed, issueTypes: model.issueTypes)
        return Button {
            model.open(row)
        } label: {
            NeedsLookCard(row: row, chips: chips)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NeedsLookWords.row(row, chips: chips.map(\.words), current: current))
                .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(.plain)
        .disabled(!reachability.online || model.ending != nil)
    }

    // MARK: Marked fine

    /// Marked fine · N in the top's right: Marked fine shown - on while it is, pressed again All - its count the facet's.
    private func markedFine(_ fine: NeedsLook.Facet) -> some View {
        let on = NeedsLookPage.isMarkedFine(model.pressed)
        return Button {
            model.choose(facet: NeedsLookPage.markedFineTapped(model.pressed))
        } label: {
            Text(NeedsLookPage.markedFineWords(fine.count))
                .fontWeight(on ? .semibold : .regular)
        }
        .accessibilityLabel(NeedsLookWords.facetSpoken(fine))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// (R12) What Needs a look does as it shows and goes - the phone's page's and the Mac's alike (MacNeedsALook): attached
/// to deadwax, the navigation and the count as it shows; read the first time and again underneath (`shows`); let go as
/// it hides; read again as deadwax comes back, as the app comes back to the front, as Look after the library is given
/// while it is up, and as the sign-in over the app goes; and any read of the scan ending - the page's or the editor's -
/// lets an ending go, or gives up an emptied facet. Slice 6's and slice 7's rules, as the page had them.
struct NeedsLookLife: ViewModifier {
    let model: NeedsLookModel

    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(QueueCountModel.self) private var count
    @Environment(\.scenePhase) private var scenePhase
    /// The page is on screen (between onAppear and onDisappear).
    @State private var visible = false

    func body(content: Content) -> some View {
        let page = model.page
        content
            .onAppear {
                model.attach(server: server, navigation: navigation, count: count)
                visible = true
                count.shows(.needsLook)
            }
            .task {
                model.attach(server: server, navigation: navigation, count: count)
                await model.shows(online: reachability.online)
            }
            .onDisappear {
                visible = false
                model.hidden()
                count.hides(.needsLook)
            }
            .onChange(of: reachability.online) { _, now in
                Task { await model.reach(now) }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    guard visible else { return }
                    Task { await model.shows(online: reachability.online) }
                case .background:
                    model.hidden()
                default:
                    break
                }
            }
            // any read of the scan ending - the page's or the editor's - lets an ending go, or gives up an emptied facet
            .onChange(of: model.scan.reading) { _, _ in
                model.settle()
            }
            // Look after the library given while the page is up: read now
            .onChange(of: page.allowed) { _, allowed in
                guard allowed, visible else { return }
                Task { await model.shows(online: reachability.online) }
            }
            // signed in again over the app: what failed or was skipped under it is read again
            .onChange(of: server.signInOver == nil) { _, clear in
                guard clear, visible else { return }
                Task { await model.signedInAgain() }
            }
    }
}

/// (R12) A chip's colour by what it says, both devices': an issue amber, New the accent's, Fixed green, the rest plain.
extension NeedsLookPage.ChipKind {
    var tone: DWChip.Tone {
        switch self {
        case .issue: return .caution
        case .new: return .marked
        case .fixed: return .good
        case .markedFine, .deleted: return .plain
        }
    }

    /// The tone's words' colour, for a chip drawn as a line of words (the phone's accessibility sizes).
    var colour: Color {
        switch self {
        case .issue: return DWPalette.amberText
        case .new: return DWPalette.acct
        case .fixed: return DWPalette.greenText
        case .markedFine, .deleted: return DWPalette.t2
        }
    }
}

/// (R12) One album of Needs a look on the phone (iNeedsALook's `.card`): its cover at 48, the album, its artist and
/// edition, its folder in the readout face, a chevron; under them its chips, wrapping - at the accessibility sizes each a
/// line of its own words in its colour, so no chip is ever wider than the card. Faded once a session has marked it.
struct NeedsLookCard: View {
    let row: NeedsLook.DrawnRow
    let chips: [(words: String, kind: NeedsLookPage.ChipKind)]

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let album = row.album
        // `.ell`, one line each - at the accessibility sizes the album and its artist wrap, so nothing is lost
        let lines = typeSize.isAccessibilitySize ? nil : 1
        PhoneCard {
            VStack(alignment: .leading, spacing: NeedsLookLook.cardGap) {
                HStack(alignment: .center, spacing: NeedsLookLook.coverGap) {
                    FolderCover(path: album.path, mtime: album.artMtime, hasArt: !album.art.isEmpty, pixels: 144)
                        .frame(width: NeedsLookLook.cover, height: NeedsLookLook.cover)
                        .clipShape(Corners.artShape)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(NeedsLook.title(album))
                            .font(Typeface.Phone.text(.row).weight(.semibold))
                            .foregroundStyle(DWPalette.text)
                            .lineLimit(lines)
                        let byline = NeedsLook.byline(album)
                        if !byline.isEmpty {
                            Text(byline)
                                .font(Typeface.Phone.text(.small))
                                .foregroundStyle(DWPalette.t2)
                                .lineLimit(lines)
                        }
                        Text(album.path)
                            .font(Typeface.Phone.mono(.extraSmall))
                            .foregroundStyle(DWPalette.t3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    PhoneChevron()
                }
                if !chips.isEmpty {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: NeedsLookLook.chipGap) {
                            ForEach(Array(chips.enumerated()), id: \.offset) {
                                (_: Int, chip: (words: String, kind: NeedsLookPage.ChipKind)) in
                                Text(chip.words)
                                    .font(Typeface.Look.text(.chip).weight(.medium))
                                    .foregroundStyle(chip.kind.colour)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        NeedsLookChipRows(spacing: NeedsLookLook.chipGap) {
                            ForEach(Array(chips.enumerated()), id: \.offset) {
                                (_: Int, chip: (words: String, kind: NeedsLookPage.ChipKind)) in
                                DWChip(words: chip.words, tone: chip.kind.tone)
                            }
                        }
                    }
                }
            }
        }
        .opacity(row.mark == nil ? 1 : DWPalette.off)
        .contentShape(Rectangle())
    }
}

/// (R12) The phone's card's sizes, from iNeedsALook.dc.html: its cover (48), between the cover and the words (12),
/// between the card's lines and its chips and between cards (10), and between chips each way (5).
enum NeedsLookLook {
    static let cover: CGFloat = 48
    static let coverGap: CGFloat = 12
    static let cardGap: CGFloat = 10
    static let chipGap: CGFloat = 5
}

/// (R12) A card's chips laid in rows, wrapping at the card's width (iNeedsALook's `flex-wrap: wrap`), 5 apart each way.
private struct NeedsLookChipRows: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
