import DeadwaxCore
import SwiftUI

/// Settings > Manage > Needs a look (Phase 8, slice 6 - notes/ios-specs/phase8-managing.md 5; the web's
/// app/NeedsALook.tsx): the review queue, pushed on the Settings tab. At its top what it is for (by Edit albums - without
/// it, that fixing needs it) and, when deadwax can't save marks, that "It's fine as it is" will come back. Then, as the
/// web's ladder has it: LIBRARY_PATH's problem said plainly; Reading the library; a first read failed, with Try again;
/// else the list - its header the facet shown and how many ("All · 12"), the status line under it (a read again failed
/// with Try again, Checking the library…, else Navidrome's note), and a row per album: its cover, album, artist and
/// edition, and its chips - New, each outstanding issue, Marked fine under that facet - or, in a session, what became of
/// it (Fixed, Marked fine, Deleted). The facets are a Show menu in the bar where the web has chips.
///
/// A row opens Edit album over the tabs on its folder in queue mode (NeedsLookModel.open); while a session's rows are
/// held after it, and while deadwax can't be reached, rows are off. Rows are known by the path they were listed at, so a
/// rename moves nothing; with Reduce Motion nothing slides. VoiceOver reads each row once (NeedsLookWords.row).
/// Without Look after the library it says so and asks nothing; opened out of reach it says it needs deadwax, and reads
/// once deadwax is back.
struct NeedsLookScreen: View {
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(QueueCountModel.self) private var count
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = NeedsLookModel()
    /// The page is on screen (between onAppear and onDisappear).
    @State private var visible = false

    var body: some View {
        let page = model.page
        Group {
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if page.allowed, model.state == .list {
                ToolbarItem(placement: .topBarTrailing) {
                    showMenu
                }
            }
        }
        .onAppear {
            model.attach(server: server, navigation: navigation, count: count)
            visible = true
        }
        .task {
            model.attach(server: server, navigation: navigation, count: count)
            await model.shows(online: reachability.online)
        }
        .onDisappear {
            visible = false
            model.hidden()
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
    }

    // MARK: the list

    @ViewBuilder private func list(_ page: Managing.NeedsLookPage) -> some View {
        let rows = model.rows
        List {
            Section {
                Text(NeedsLook.lead(canEdit: page.canEdit))
                    .fixedSize(horizontal: false, vertical: true)
                if !page.canEdit {
                    Text(NeedsLook.needsEdit)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.ignoresUnsaved {
                    Text(NeedsLook.ignoresUnsavedWords)
                        .foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(Typeface.footnote)
            switch model.state {
            case .problem(let problem):
                Section {
                    Text(problem)
                        .foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .reading:
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(NeedsLook.reading).foregroundStyle(Palette.quiet)
                    }
                    .accessibilityElement(children: .combine)
                }
            case .failed:
                Section {
                    ErrorNote(text: model.scan.failure ?? NeedsLook.readFailed)
                    Button(NeedsLook.tryAgain) {
                        model.retry()
                    }
                    .disabled(model.scan.reading || !reachability.online)
                }
            case .list:
                Section {
                    if rows.isEmpty {
                        Text(NeedsLook.nothing)
                            .foregroundStyle(Palette.quiet)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.key) { (index: Int, row: NeedsLook.DrawnRow) in
                            rowButton(row, current: model.session?.index == index)
                        }
                    }
                } header: {
                    header
                }
            }
        }
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
        .refreshable {
            await model.read()
        }
    }

    /// The facet shown and its count, then the status line - always there, one line at least, so its coming and going
    /// moves no row.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NeedsLookWords.header(model.pressedChip))
                .font(Typeface.footnote.weight(.semibold))
            Group {
                switch model.status {
                case .failed?:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model.scan.failure ?? NeedsLook.checkFailed)
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(NeedsLook.tryAgain) {
                            model.retry()
                        }
                        .font(Typeface.footnote.weight(.semibold))
                        .disabled(model.scan.reading || !reachability.online)
                    }
                case .checking?:
                    Text(NeedsLook.checking)
                case .navidrome(let note)?:
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                case nil:
                    Text(" ")
                        .accessibilityHidden(true)
                }
            }
            .font(Typeface.footnote)
        }
        .textCase(nil)
    }

    /// A row: the album's cover, its lines and chips - opening Edit album in queue mode.
    private func rowButton(_ row: NeedsLook.DrawnRow, current: Bool) -> some View {
        let chips = model.chipWords(row)
        return Button {
            model.open(row)
        } label: {
            NeedsLookRow(row: row, chips: chips)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NeedsLookWords.row(row, chips: chips, current: current))
                .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(.plain)
        .disabled(!reachability.online || model.ending != nil)
        .listRowBackground(current ? Palette.accent.opacity(0.14) : nil)
    }

    // MARK: Show

    /// The facets, as a menu in the bar: each with its count, the one shown ticked - its symbol filled while a facet
    /// other than All narrows the list.
    private var showMenu: some View {
        let chosen = model.pressed
        return Menu {
            Picker(NeedsLook.show, selection: Binding<String?>(
                get: { chosen },
                set: { (picked: String?) -> Void in model.choose(facet: picked) }
            )) {
                ForEach(model.chips, id: \.id) { (chip: NeedsLook.Facet) in
                    Text(NeedsLookWords.facet(chip))
                        .accessibilityLabel(NeedsLookWords.facetSpoken(chip))
                        .tag(chip.id)
                }
            }
        } label: {
            Image(systemName: NeedsLookWords.showSymbol(narrowed: chosen != nil))
        }
        .accessibilityLabel(NeedsLookWords.showSpoken(model.pressedChip))
    }
}

/// One album of Needs a look: its cover, album, artist and edition, and its chips or its mark.
struct NeedsLookRow: View {
    let row: NeedsLook.DrawnRow
    let chips: [String]

    var body: some View {
        let album = row.album
        HStack(alignment: .top, spacing: 12) {
            FolderCover(path: album.path, mtime: album.artMtime, hasArt: !album.art.isEmpty, pixels: 120)
                .frame(width: 44, height: 44)
                .clipShape(Corners.artShape)
            VStack(alignment: .leading, spacing: 2) {
                Text(NeedsLook.title(album))
                    .font(Typeface.body.weight(.semibold))
                let byline = NeedsLook.byline(album)
                if !byline.isEmpty {
                    Text(byline)
                        .font(Typeface.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
                if !chips.isEmpty {
                    Text(chips.joined(separator: " \u{00B7} "))
                        .font(Typeface.footnote.weight(.semibold))
                        .foregroundStyle(row.mark == nil ? Palette.amber : Palette.held)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(row.mark == nil ? 1 : 0.7)
        .contentShape(Rectangle())
    }
}
