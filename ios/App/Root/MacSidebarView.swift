import DeadwaxCore
import SwiftUI

/// The desktop frame's sidebar (the Mac app, slice 3 - the Mac app's plan 1.2; the web's app/Sidebar.tsx as its 2.1.35
/// drew it), redrawn (the Mac redesign, slice R1 - notes/ios.md "The Mac redesign, slice R1: the frame and the shared
/// pieces") as James approved it on the design canvas: 220 wide (MacLook.sidebarWidth) on dw.css's --side with the
/// frame's rule at its right, the wordmark at its top, and text rows with no glyphs. View > Hide Sidebar (⌃⌘S) puts it
/// away. Every row and rule is Core's MacSidebar, as before, its vectors the web's own lib/appFrame.ts
/// (MacFrameVectorTests):
///
/// - The search field in its well under the wordmark: typing there (or Return) shows Search's results in the page, as the
///   web's field does - the words are Search's own (SearchModel), so Search's page draws no field of its own on the Mac.
///   Edit > Find (⌘F) shows the sidebar and puts the cursor here.
/// - Requests, with its count - the downloads on their way (the web's top list, less Home: the Mac has none).
/// - Library, and - with a library of your own - its switch, Yours | All (DWSegmented): Yours' rows are the Library
///   switch's pages in the person's order (Playlists aside, the group below), All's the collection's three; Downloaded on
///   either. The side follows where you are, and is kept on the Mac (MacSidebar.sideKey, the web's key); turning it with
///   a view showing opens the same kind of view on the other side (MacSidebar.sideFlip).
/// - Playlists, which folds: All playlists, then yours and those shared with you, by name - at most twenty - set in.
/// - Manage, which folds, by permission (Settings > Manage's rows): Needs a look with its count - said on the heading
///   while folded.
/// - Settings at the foot, under the frame's rule, in view however far the groups scroll.
///
/// The row where you are is drawn in the selection's colours (MacSidebar.current) - a folded group's heading when its
/// page is the one showing. A row's click is MacSidebar.move: its tab's button, a Library page at the root, a section, a
/// playlist's or a Manage page put on its stack (AppNavigation.macMove). A heading that folds keeps a small chevron at
/// its right - the canvas draws none, but a fold with no mark would be a heading that hides its rows unseen.
struct MacSidebarView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(ServerModel.self) private var server
    @Environment(SearchModel.self) private var search
    @Environment(RequestsModel.self) private var requests
    @Environment(QueueCountModel.self) private var queueCount
    @Environment(PlaylistsModel.self) private var playlists
    /// The Library switch's order, as this Mac keeps it (LibraryView's own).
    @AppStorage(LibraryPages.storageKey) private var savedOrder = ""
    /// The switch's side last shown, and the folded groups (the web's keys and values).
    @AppStorage(MacSidebar.sideKey) private var savedSide = ""
    @AppStorage(MacSidebar.foldedKey) private var savedFolds = ""

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
        // .side: a column, 1 apart, padding 12px 10px 8px
        VStack(alignment: .leading, spacing: 1) {
            // .brand: padding 0 8px 10px, 19 bold
            Text(MacSidebar.Words.brand)
                .font(Typeface.Mac.text(.brand).weight(.bold))
                .kerning(-0.2)
                .foregroundStyle(DWPalette.text)
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            // .side > .find: margin-bottom 8px
            SidebarSearchField()
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    row(.requests, current: current, at: at)
                    library(side: side, personal: personal, order: order, current: current, over: over, at: at)
                    playlistsGroup(listed, folds: folds, current: current, at: at)
                    if !manage.isEmpty {
                        manageGroup(manage, folds: folds, current: current, at: at)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            // the foot: the frame's rule, 5 above Settings
            DWRule(colour: DWPalette.frame)
                .padding(.top, 7)
                .padding(.bottom, 5)
            row(.settings, current: current, at: at)
        }
        .padding(EdgeInsets(top: 12, leading: 10, bottom: 8, trailing: 10))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DWPalette.side)
        // .side: border-right 1px solid var(--frame)
        .overlay(alignment: .trailing) { DWRule(colour: DWPalette.frame, vertical: true) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MacSidebar.Words.sections)
        // (slice 3's review) asked again for each person: the sidebar stays on screen while someone else signs in over
        // the app, and their reset lets go of the last one's playlists and of every page counted as showing
        .task(id: server.person) { await playlists.ask(fresh: false) }
        .onAppear { queueCount.shows(.sidebar) }
        .onDisappear { queueCount.hides(.sidebar) }
        .onChange(of: server.person) { (_: Int, _: Int) -> Void in queueCount.shows(.sidebar) }
        .onChange(of: side) { (_: MacSidebar.Side, now: MacSidebar.Side) -> Void in
            // the side shown, remembered (the web's Sidebar keeps what sideShown says)
            if MacSidebar.side(saved: savedSide) != now { savedSide = now.rawValue }
        }
    }

    // MARK: the groups

    private func library(side: MacSidebar.Side, personal: Bool, order: [LibraryPage], current: MacSidebar.Row?,
                         over: Bool, at: MacSidebar.Where) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                heading(MacSidebar.Words.library)
                Spacer(minLength: 0)
                if personal {
                    // the switch in the heading, at its right (.navh .seg)
                    DWSegmented(options: MacSidebar.Side.allCases, words: { (one: MacSidebar.Side) -> String in one.label },
                                 chosen: Binding(get: { side }, set: { (to: MacSidebar.Side) -> Void in
                                     guard to != side else { return }
                                     savedSide = to.rawValue
                                     if let row = MacSidebar.sideFlip(current, to: to, over: over) {
                                         navigation.macMove(MacSidebar.move(row, at))
                                     }
                                 }), spoken: MacSidebar.Words.library)
                }
            }
            .padding(EdgeInsets(top: 13, leading: 8, bottom: 4, trailing: 8))
            ForEach(MacSidebar.rows(side, order: order, personal: personal), id: \.self) { (each: MacSidebar.Row) in
                row(each, current: current, at: at)
            }
        }
    }

    private func playlistsGroup(_ listed: [Playlist], folds: MacSidebar.Folds, current: MacSidebar.Row?,
                                at: MacSidebar.Where) -> some View {
        VStack(alignment: .leading, spacing: 1) {
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
        return VStack(alignment: .leading, spacing: 1) {
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

    /// A group's heading's words (.navh): 11.5 semibold in the label's colour.
    private func heading(_ words: String) -> some View {
        Text(words)
            .font(Typeface.Mac.text(.label).weight(.semibold))
            .foregroundStyle(DWPalette.label)
            .accessibilityAddTraits(.isHeader)
    }

    /// A heading that folds its group (the web's foldHead): the heading's words, a count while folded (Manage's), and a
    /// small chevron at its right pointing at the words while it is folded - drawn current when folded over the page
    /// showing.
    private func foldHead(_ fold: MacSidebar.Fold, words: String, spoken: String, count: String,
                          folds: MacSidebar.Folds, current: MacSidebar.Row?) -> some View {
        let folded = folds[fold]
        let lit = MacSidebar.foldCurrent(fold, folds, current)
        return Button {
            savedFolds = MacSidebar.saved(folds.toggled(fold))
        } label: {
            HStack(spacing: 8) {
                Text(words)
                    .font(Typeface.Mac.text(.label).weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !count.isEmpty { DWCount(count: count) }
                Image(systemName: "chevron.down")
                    .font(Typeface.symbol(size: 8, weight: .bold))
                    .rotationEffect(.degrees(folded ? -90 : 0))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(lit ? DWPalette.selt : DWPalette.label)
            // .navh: padding 13px 8px 4px - lit, it sits in the selection's colours, a row's height
            .padding(EdgeInsets(top: lit ? 0 : 13, leading: 8, bottom: lit ? 0 : 4, trailing: 8))
            .frame(minHeight: lit ? CGFloat(MacLook.navRowHeight) : nil)
            .background { if lit { SelectedFill() } }
            .padding(.top, lit ? 9 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(folded ? MacSidebar.Words.collapsed : MacSidebar.Words.expanded)
    }

    /// A row (.nav): its words, a count at its right (Requests' arriving, Needs a look's) - a playlist's set in (.nav.sub)
    /// - drawn current where you are (.nav.on); a click is its move from where the app is.
    private func row(_ each: MacSidebar.Row, words: String? = nil, current: MacSidebar.Row?,
                     at: MacSidebar.Where) -> some View {
        let lit = each == current
        let badge = self.badge(each)
        let sub: Bool
        if case .playlist = each { sub = true } else { sub = false }
        return Button {
            navigation.macMove(MacSidebar.move(each, at))
        } label: {
            HStack(spacing: 8) {
                Text(words ?? MacSidebar.label(each))
                    .font(Typeface.Mac.text(.base).weight(lit ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !badge.isEmpty { DWCount(count: badge) }
            }
            .foregroundStyle(lit ? DWPalette.selt : (sub ? DWPalette.t2 : DWPalette.head))
            // .nav: padding 0 8px (.nav.sub: 20 at its left), 26 tall
            .padding(.leading, sub ? 20 : 8)
            .padding(.trailing, 8)
            .frame(height: CGFloat(MacLook.navRowHeight))
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
}

/// Where you are (.nav.on): the selection's fill in its edge, a button's corners.
private struct SelectedFill: View {
    var body: some View {
        DWCorners.buttonShape
            .fill(DWPalette.selbg)
            .overlay(DWCorners.buttonShape.strokeBorder(DWPalette.selbd, lineWidth: 1))
    }
}

/// The sidebar's search field (the web's .app-side-search, drawn as the canvas's .well.find): Search's own words
/// (SearchModel), "Search" in it while empty and Search's name to VoiceOver - 28 tall in its well, the accent's edge
/// while it has the cursor. Typing words - or Return - shows Search's results in the page (AppNavigation.showSearch);
/// Return asks now, as the keyboard's Search does. A clear button while it has words - Escape presses it while the field
/// has the cursor, as Escape empties the web's search field. Edit > Find puts the cursor here (`findField`).
private struct SidebarSearchField: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(SearchModel.self) private var search
    /// The field has the cursor.
    @FocusState private var focused: Bool

    var body: some View {
        // .find: gap 7px, padding 0 8px, 12.5 in the third colour
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(Typeface.symbol(size: 11, weight: .medium))
                .foregroundStyle(DWPalette.t3)
                .accessibilityHidden(true)
            TextField(MacSidebar.Words.searchPlaceholder, text: Binding(get: { search.text }, set: { (typed: String) -> Void in
                search.type(typed)
                if !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { navigation.showSearch() }
            }), prompt: Text(MacSidebar.Words.searchPlaceholder).foregroundStyle(DWPalette.t3))
            .font(Typeface.Mac.text(.control))
            .foregroundStyle(DWPalette.fieldText)
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
            .focusEffectDisabled()
            // (the Mac app, slices 2 and 3) Edit > Find (⌘F) puts the cursor here
            .findField($focused)
            if !search.text.isEmpty {
                Button {
                    search.type("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Typeface.symbol(size: 11, weight: .regular))
                        .foregroundStyle(DWPalette.t3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MacSidebar.Words.clearSearch)
                // Escape empties the field while it has the cursor - a panel's Done has Escape otherwise
                .escapeCloses(focused)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: CGFloat(MacLook.findHeight))
        .background { DWWell(focused: focused) }
    }
}
