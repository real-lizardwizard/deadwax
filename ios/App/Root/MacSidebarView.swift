import DeadwaxCore
import SwiftUI

/// The desktop frame's sidebar (the Mac app, slice 3 - the Mac app's plan 1.2; the web's app/Sidebar.tsx as its 2.1.35
/// drew it), MacFrame.sidebarWidth (232) wide, on --dw-sidebar with a rule at its right; View > Hide Sidebar (⌃⌘S) puts
/// it away. Every row and rule is Core's MacSidebar, its vectors the web's own lib/appFrame.ts (MacFrameVectorTests):
///
/// - The search field at its top: typing there (or Return) shows Search's results in the page, as the web's field does
///   - the words are Search's own (SearchModel), so Search's page draws no field of its own on the Mac. Edit > Find
///   (⌘F) shows the sidebar and puts the cursor here.
/// - Requests, with its badge - the count of downloads on their way (the web's top list, less Home: the Mac has none).
/// - Library, and - with a library of your own - its switch, Yours | All: Yours' rows are the Library switch's pages in
///   the person's order (Playlists aside, the group below), All's the collection's three; Downloaded on either. The side
///   follows where you are, and is kept on the Mac (MacSidebar.sideKey, the web's key); turning it with a view showing
///   opens the same kind of view on the other side (MacSidebar.sideFlip).
/// - Playlists, which folds: All playlists, then yours and those shared with you, by name - at most twenty.
/// - Manage, which folds, by permission (Settings > Manage's rows): Needs a look with its count - said on the heading
///   while folded.
/// - Settings at the foot, under a rule, in view however far the groups scroll.
///
/// The row where you are is drawn in the selection's colours (MacSidebar.current) - a folded group's heading when its
/// page is the one showing. A row's click is MacSidebar.move: its tab's button, a Library page at the root, a section, a
/// playlist's or a Manage page put on its stack (AppNavigation.macMove). Every row carries its glyph, as the web's.
struct MacSidebarView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(ServerModel.self) private var server
    @Environment(SearchModel.self) private var search
    @Environment(RequestsModel.self) private var requests
    @Environment(QueueCountModel.self) private var queueCount
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(\.displayScale) private var displayScale
    /// The Library switch's order, as this Mac keeps it (LibraryView's own).
    @AppStorage(LibraryPages.storageKey) private var savedOrder = ""
    /// The switch's side last shown, and the folded groups (the web's keys and values).
    @AppStorage(MacSidebar.sideKey) private var savedSide = ""
    @AppStorage(MacSidebar.foldedKey) private var savedFolds = ""

    /// --app-desk-side-pad-x and -y, --app-desk-side-gap, --app-desk-item-gap, --app-desk-label-pad.
    private static let padX: CGFloat = 12
    private static let padY: CGFloat = 20
    private static let groupGap: CGFloat = 18
    private static let itemGap: CGFloat = 2
    private static let labelPad: CGFloat = 6
    /// --app-desk-you: Settings' row at the foot.
    private static let foot: CGFloat = 44

    var body: some View {
        let personal = server.access.hasLibrary
        let order = LibraryPages.shown(LibraryPages.read(savedOrder), personal: personal)
        let at = navigation.macWhere(page: navigation.macLibraryPage ?? LibraryPages.first(order))
        let listed = MacSidebar.playlists(playlists.list)
        let current = MacSidebar.current(at, listed: listed.map(\.id))
        let over = MacSidebar.overLibraryView(at)
        let side = MacSidebar.sideShown(current, remembered: MacSidebar.side(saved: savedSide), over: over)
        let folds = MacSidebar.folds(saved: savedFolds)
        let manage = MacSidebar.manageRows(server.access)
        VStack(spacing: 0) {
            SidebarSearchField()
                .padding(.horizontal, Self.padX)
                .padding(.top, Self.padY)
                .padding(.bottom, Self.groupGap)
            ScrollView {
                VStack(alignment: .leading, spacing: Self.groupGap) {
                    VStack(spacing: Self.itemGap) {
                        row(.requests, current: current, at: at)
                    }
                    library(side: side, personal: personal, order: order, current: current, over: over, at: at)
                    playlistsGroup(listed, folds: folds, current: current, at: at)
                    if !manage.isEmpty {
                        manageGroup(manage, folds: folds, current: current, at: at)
                    }
                }
                .padding(.horizontal, Self.padX)
                .padding(.bottom, Self.padY)
            }
            VStack(spacing: 0) {
                rule
                row(.settings, current: current, at: at)
                    .frame(height: Self.foot)
            }
            .padding(.horizontal, Self.padX)
            .padding(.bottom, Self.padY / 2)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.sidebar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MacSidebar.Words.sections)
        .task { await playlists.ask(fresh: false) }
        .onAppear { queueCount.shows(.sidebar) }
        .onDisappear { queueCount.hides(.sidebar) }
        .onChange(of: side) { (_: MacSidebar.Side, now: MacSidebar.Side) -> Void in
            // the side shown, remembered (the web's Sidebar keeps what sideShown says)
            if MacSidebar.side(saved: savedSide) != now { savedSide = now.rawValue }
        }
    }

    // MARK: the groups

    private func library(side: MacSidebar.Side, personal: Bool, order: [LibraryPage], current: MacSidebar.Row?,
                         over: Bool, at: MacSidebar.Where) -> some View {
        VStack(alignment: .leading, spacing: Self.itemGap) {
            HStack(spacing: 8) {
                label(MacSidebar.Words.library)
                Spacer(minLength: 0)
                if personal {
                    SideSwitch(side: side) { (to: MacSidebar.Side) -> Void in
                        savedSide = to.rawValue
                        if let row = MacSidebar.sideFlip(current, to: to, over: over) {
                            navigation.macMove(MacSidebar.move(row, at))
                        }
                    }
                }
            }
            .padding(.bottom, Self.labelPad)
            ForEach(MacSidebar.rows(side, order: order, personal: personal), id: \.self) { (each: MacSidebar.Row) in
                row(each, current: current, at: at)
            }
        }
    }

    private func playlistsGroup(_ listed: [Playlist], folds: MacSidebar.Folds, current: MacSidebar.Row?,
                                at: MacSidebar.Where) -> some View {
        VStack(alignment: .leading, spacing: Self.itemGap) {
            foldHead(.playlists, words: MacSidebar.Words.playlists, spoken: MacSidebar.Words.playlists, count: "",
                     folds: folds, current: current)
            if !folds.playlists {
                row(.playlists, current: current, at: at)
                ForEach(listed, id: \.id) { (playlist: Playlist) in
                    row(.playlist(playlist.id), words: playlist.name, current: current, at: at)
                }
            }
        }
    }

    private func manageGroup(_ rows: [MacSidebar.Row], folds: MacSidebar.Folds, current: MacSidebar.Row?,
                             at: MacSidebar.Where) -> some View {
        let queue = rows.contains(.manage(.queue))
        let count = folds.manage && queue ? queueCount.count.value : ""
        let spoken = MacSidebar.manageHeadLabel(folded: folds.manage, needsLook: queue ? queueCount.count.server : nil)
        return VStack(alignment: .leading, spacing: Self.itemGap) {
            foldHead(.manage, words: MacSidebar.Words.manage, spoken: spoken, count: count, folds: folds,
                     current: current)
            if !folds.manage {
                ForEach(rows, id: \.self) { (each: MacSidebar.Row) in
                    row(each, current: current, at: at)
                }
            }
        }
    }

    // MARK: the parts

    /// A group's label (Library's): the web's .app-side-label.
    private func label(_ words: String) -> some View {
        Text(words)
            .font(Typeface.footnote.weight(.semibold))
            .foregroundStyle(Palette.quiet)
            .accessibilityAddTraits(.isHeader)
    }

    /// A heading that folds its group (the web's foldHead): the label's words, a count while folded (Manage's), and a
    /// chevron pointing at the words while it is folded - drawn current when folded over the page showing.
    private func foldHead(_ fold: MacSidebar.Fold, words: String, spoken: String, count: String,
                          folds: MacSidebar.Folds, current: MacSidebar.Row?) -> some View {
        let folded = folds[fold]
        let lit = MacSidebar.foldCurrent(fold, folds, current)
        return Button {
            savedFolds = MacSidebar.saved(folds.toggled(fold))
        } label: {
            HStack(spacing: 10) {
                Text(words)
                    .font(Typeface.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !count.isEmpty { SidebarBadge(count: count) }
                Image(systemName: "chevron.down")
                    .font(Typeface.symbol(.caption2).weight(.semibold))
                    .rotationEffect(.degrees(folded ? -90 : 0))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(lit ? Palette.selectedText : Palette.quiet)
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
            .background { if lit { SelectedFill() } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, Self.labelPad)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(folded ? MacSidebar.Words.collapsed : MacSidebar.Words.expanded)
    }

    /// A row: its glyph and words, a badge at its right (Requests' arriving, Needs a look's count) - drawn current where
    /// you are; a click is its move from where the app is.
    private func row(_ each: MacSidebar.Row, words: String? = nil, current: MacSidebar.Row?,
                     at: MacSidebar.Where) -> some View {
        let lit = each == current
        let badge = self.badge(each)
        return Button {
            navigation.macMove(MacSidebar.move(each, at))
        } label: {
            HStack(spacing: 10) {
                if let symbol = MacSidebar.symbol(each) {
                    Image(systemName: symbol)
                        .font(Typeface.symbol(.body))
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                } else {
                    // a playlist's name, set in under All playlists' words (the web's .app-side-playlist)
                    Color.clear
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                }
                Text(words ?? MacSidebar.label(each))
                    .font(Typeface.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !badge.isEmpty { SidebarBadge(count: badge) }
            }
            .foregroundStyle(lit ? Palette.selectedText : Color.primary)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background { if lit { SelectedFill() } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenRow(each, words: words ?? MacSidebar.label(each)))
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    /// The count at a row's right: Requests' downloads on their way, Needs a look's albums - none at 0.
    private func badge(_ row: MacSidebar.Row) -> String {
        switch row {
        case .requests: return RequestWords.badgeText(requests.badgeCount)
        case .manage(.queue): return queueCount.count.value
        default: return ""
        }
    }

    /// What VoiceOver reads for a row: its words, with Requests' and Needs a look's counts.
    private func spokenRow(_ row: MacSidebar.Row, words: String) -> String {
        switch row {
        case .requests: return RequestWords.badgeLabel(words, requests.badgeCount)
        case .manage(.queue): return queueCount.count.spoken
        default: return words
        }
    }

    /// --dw-frame-border, a hairline.
    private var rule: some View {
        Palette.frameBorder
            .frame(height: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }
}

/// Where you are: Explorer's selection, as the web draws it (--dw-selection-bg, a hairline of --dw-selection-border).
private struct SelectedFill: View {
    var body: some View {
        Corners.controlShape
            .fill(Palette.selectionFill)
            .overlay(Corners.controlShape.strokeBorder(Palette.selectionEdge, lineWidth: 1))
    }
}

/// A count at a row's right (the web's .app-side-badge): STYLE.md's purple badge, the tab bar's on the iPhone.
private struct SidebarBadge: View {
    let count: String

    var body: some View {
        Text(count)
            .font(Typeface.caption2.weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Palette.accentText)
            .padding(.horizontal, 4)
            .frame(minWidth: 20, minHeight: 20)
            .background(Palette.badgeFill, in: Corners.controlShape)
            .overlay(Corners.controlShape.strokeBorder(Palette.badgeEdge, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Library's switch, Yours | All (the web's .app-side-switch): the side shown checked; a click turns it.
private struct SideSwitch: View {
    let side: MacSidebar.Side
    let turn: (MacSidebar.Side) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MacSidebar.Side.allCases, id: \.self) { (one: MacSidebar.Side) in
                let on = one == side
                Button {
                    if !on { turn(one) }
                } label: {
                    Text(one.label)
                        .font(Typeface.caption.weight(.semibold))
                        .foregroundStyle(on ? Palette.accentText : Palette.quiet)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 22)
                        .background {
                            if on {
                                Corners.controlShape
                                    .fill(Palette.badgeFill)
                                    .overlay(Corners.controlShape.strokeBorder(Palette.badgeEdge, lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MacSidebar.Words.library)
    }
}

/// The sidebar's search field (the web's .app-side-search): Search's own words (SearchModel), "Search" in it while
/// empty and Search's name to VoiceOver. Typing words - or Return - shows Search's results in the page
/// (AppNavigation.showSearch); Return asks now, as the keyboard's Search does. A clear button while it has words -
/// Escape presses it while the field has the cursor, as Escape empties the web's search field. Edit > Find puts the
/// cursor here (`findField`).
private struct SidebarSearchField: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(SearchModel.self) private var search
    /// The field has the cursor.
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Typeface.symbol(.footnote))
                .foregroundStyle(Palette.quiet)
                .accessibilityHidden(true)
            TextField(MacSidebar.Words.searchPlaceholder, text: Binding(get: { search.text }, set: { (typed: String) -> Void in
                search.type(typed)
                if !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { navigation.showSearch() }
            }))
            .font(Typeface.subheadline)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .onSubmit {
                guard !search.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                navigation.showSearch()
                search.submitted()
            }
            .accessibilityLabel(MacSidebar.Words.searchLabel)
            // (the Mac app, slices 2 and 3) Edit > Find (⌘F) puts the cursor here
            .findField($focused)
            if !search.text.isEmpty {
                Button {
                    search.type("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Typeface.symbol(.footnote))
                        .foregroundStyle(Palette.quiet)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MacSidebar.Words.clearSearch)
                // Escape empties the field while it has the cursor - a panel's Done has Escape otherwise
                .escapeCloses(focused)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(Palette.well, in: Corners.controlShape)
        .overlay(Corners.controlShape.strokeBorder(Palette.frameBorder, lineWidth: 1))
    }
}
