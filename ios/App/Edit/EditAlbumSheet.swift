import DeadwaxCore
import SwiftUI

/// A page pushed inside Edit album's own stack.
enum EditPage: Hashable {
    /// Release: the pressing, the fields, the cover, what Apply does, Apply.
    case release
    /// Choose a release: MusicBrainz's pressings for the album, best first.
    case chooseRelease
    /// Compare covers: the folder's beside the pressing's, and Replace cover only.
    case compareCovers
    /// Changes: each file's tag changes, old to new.
    case changes
    /// Choose the folder: any folder of the library (the album's own can't be found).
    case chooseFolder
    /// Tags: the folder's files, a section per disc, Select.
    case tags
    /// A track's page: everything its file says, by the file's name.
    case track(String)
    /// Edit tags: the fields of the tracks chosen, what would change, Apply.
    case editTags
    /// Artwork: the cover and CD art, and their Gets.
    case artwork
    /// Lyrics: how many tracks have them, and Get lyrics.
    case lyrics
    /// Delete album: what deleting the folder takes, who holds it, and Delete permanently.
    case delete
}

/// Edit album (notes/ios-specs/phase8-managing.md 3.2; the web's EditPanel, its title): a sheet over the tabs, its own
/// navigation stack, drawn as iOS Settings is - a header and sections of rows, each row pushing a page - where the web
/// has five tabs, which don't fit a phone's segmented control. Close at the leading edge; with typed work, or a write
/// under way, the sheet can't be swiped away and Close asks "Discard changes?" first (Discard destructive, Keep
/// editing the default); while an apply runs, Close is off - nothing on the sheet can close it. A delete that went closes
/// it (EditAlbumModel.deleted).
///
/// It needs deadwax: opened while deadwax can't be reached it says so and asks nothing, opening by itself once it is
/// back; gone out of reach while open, every page keeps what it drew under the amber line saying nothing can change
/// until deadwax is back, every write off - and back, everything is asked again before a write comes back on
/// (EditAlbumModel.reach). An apply that ended while the phone was locked has the folder read again as the app comes back
/// to the front.
///
/// (Phase 8, slice 6) Opened from Needs a look it is in queue mode (phase8-managing.md 3.2, 5; MetadataEditor.tsx's
/// queue nav): a bottom toolbar on its root holds ‹, "2 of 9" and Skip › - Next album › once a write was told of the
/// album (the web's Apply becoming Next) - stepping through the session (NeedsLookModel.go), each album opened afresh in
/// the same sheet with the page's scan. A step goes only through the editor's gate (EditAlbumModel.stepGate - shut out
/// of reach and until everything done to this album has settled: a write or a mark and the read after it, a read of the
/// scan, a read Release or Tags waits for, a delete waiting to be found gone), checked again as Discard steps, and asks
/// "Discard changes?" over typed work as Close does. A delete leaves the sheet up, saying so, the queue going on from
/// it. The sheet going ends the session - Close here, and its every dismissal where it is presented (MainTabs'
/// onDismiss, AppNavigation.editorDismissed) - never this content disappearing, which a full-screen cover over it
/// (Compare covers, a picture full size) brings about too (slice 6's review).
///
/// (R10 - notes/ios.md "The redesign, slice R10: Edit album, the folder list and Release") The phone's alone: on the Mac
/// every Edit album opens its page beside the library's folders (MacEditWindow, AppNavigation.editAlbum), never this
/// sheet. Its top is iEdit's - Close, "Edit album", the Matched chip - and its root the header, the strip and Release
/// (EditAlbumRoot); Discard, the swipe held over typed work and Close off while an apply runs are as they were.
struct EditAlbumSheet: View {
    let request: AlbumEditRequest

    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: EditAlbumModel?
    /// The queue's step the model is for (NeedsLookModel.steps): a step builds the next album's.
    @State private var step = 0
    @State private var path: [EditPage] = []
    @State private var askingDiscard = false
    /// A step asked over typed work: taken once Discard is pressed.
    @State private var pendingStep: Int?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model {
                    EditAlbumRoot(model: model, path: $path)
                        .toolbar {
                            if let queue = request.queue, let nav = queue.nav {
                                ToolbarItemGroup(placement: .bottomBar) {
                                    queueBar(nav, model: model)
                                }
                            }
                        }
                } else {
                    Color.clear
                }
            }
            .navigationTitle(EditWords.title)
            .navigationBarTitleDisplayMode(.inline)
            // (R10) the top's chip: the folder held matched to a release, or not
            .matchedChip(model?.album)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(EditWords.close, action: close)
                        .disabled(model?.applying == true)
                        // (the Mac app, slice 2) Escape is Close: it closes, or asks first with something typed
                        .escapeCloses()
                        .confirmationDialog(EditWords.discardTitle, isPresented: $askingDiscard, titleVisibility: .visible) {
                            Button(EditWords.discard, role: .destructive) {
                                if let delta = pendingStep {
                                    pendingStep = nil
                                    // the gate as it is now: a write may have started since the step was asked
                                    if let model { request.queue?.go(by: delta, gate: model.stepGate) }
                                } else {
                                    closeSheet()
                                }
                            }
                            Button(EditWords.keepEditing, role: .cancel) { pendingStep = nil }
                                .returnCancels()
                        }
                }
            }
            .navigationDestination(for: EditPage.self) { (page: EditPage) in
                if let model {
                    EditPageView(page: page, model: model, path: $path)
                }
            }
        }
        // typed work isn't lost by a swipe: Close asks
        .interactiveDismissDisabled(model?.holdsWork == true)
        // (the Mac app, slice 2) nor by closing the window: ⌘W and the close button are off meanwhile
        .keepsWindowOpen(model?.holdsWork == true)
        // (slice 6) in queue mode, each step opens the session's next album afresh - with the page's scan
        .task(id: request.queue?.steps ?? 0) {
            let wanted = request.queue?.steps ?? 0
            if model == nil || step != wanted {
                let made = EditAlbumModel(request: request, target: request.queue?.folder.map { .folder($0) },
                                          scan: request.queue?.scan, client: server.client,
                                          admin: server.access.seesDetail, online: reachability.online)
                made.attach(navigation, library: library)
                path.removeAll()
                model = made
                step = wanted
            }
            await model?.open()
        }
        // the folder deleted: nothing left to edit - in queue mode, the sheet stays saying so, the queue going on
        .onChange(of: model?.deleted == true) { _, gone in
            guard gone else { return }
            if request.queue != nil {
                path.removeAll()
            } else {
                dismiss()
            }
        }
        .onChange(of: reachability.online) { _, now in
            Task { await model?.reach(now) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model?.becameActive() }
        }
    }

    private func close() {
        guard let model, !model.applying else { return }
        if model.holdsWork {
            pendingStep = nil
            askingDiscard = true
        } else {
            closeSheet()
        }
    }

    /// Close (or Discard over it): Needs a look's session ended now, then the sheet dismissed - whose onDismiss says so
    /// again, to a session already over (NeedsLook.Run ends once).
    private func closeSheet() {
        request.queue?.editorClosed()
        dismiss()
    }

    /// (slice 6) Queue mode's bar: ‹ (Previous album), where it is ("2 of 9"), and Skip › - or Next album ›, once a
    /// write was told of the album and it isn't the last.
    @ViewBuilder private func queueBar(_ nav: NeedsLook.Nav, model: EditAlbumModel) -> some View {
        Button {
            take(-1, model: model)
        } label: {
            Image(systemName: "chevron.left")
        }
        .accessibilityLabel(NeedsLookWords.previous)
        .disabled(!nav.back || !model.canStep)
        Spacer()
        Text(nav.place)
            .font(Typeface.footnote)
            .foregroundStyle(Palette.quiet)
        Spacer()
        Button(nav.forward) {
            take(1, model: model)
        }
        .accessibilityLabel(nav.forwardSpoken)
        .accessibilityHint(nav.nextAlbum ? "" : NeedsLookWords.skipHint)
        .disabled(!nav.on || !model.canStep)
    }

    /// A step through the queue, through the editor's gate: typed work asks first, as Close does.
    private func take(_ delta: Int, model: EditAlbumModel) {
        guard let queue = request.queue, model.canStep else { return }
        if model.holdsWork {
            pendingStep = delta
            askingDiscard = true
            return
        }
        queue.go(by: delta, gate: model.stepGate)
    }
}

/// One of Edit album's pushed pages, by its value - each under the out-of-reach line while deadwax can't be reached.
struct EditPageView: View {
    let page: EditPage
    let model: EditAlbumModel
    @Binding var path: [EditPage]

    var body: some View {
        Group {
            switch page {
            case .release:
                if let retag = model.retag { ReleasePage(model: model, retag: retag) }
            case .chooseRelease:
                if let retag = model.retag { ChooseReleaseView(retag: retag, path: $path) }
            case .compareCovers:
                if let retag = model.retag, let album = model.album {
                    CompareCoversView(model: model, retag: retag, album: album)
                }
            case .changes:
                if let plan = model.retag?.currentPlan { ChangesView(plan: plan) }
            case .chooseFolder:
                ChooseFolderView(scan: model.scan, online: model.online) { (path: String) in
                    model.choose(path, fromScan: true)
                    self.path.removeAll()
                }
            case .tags:
                if let tags = model.tags { TagsListView(model: model, tags: tags, path: $path) }
            case .track(let filename):
                if let tags = model.tags { TrackPageView(model: model, tags: tags, filename: filename, path: $path) }
            case .editTags:
                if let tags = model.tags { EditTagsView(model: model, tags: tags) }
            case .artwork:
                if let album = model.album { ArtworkPage(model: model, album: album) }
            case .lyrics:
                if let album = model.album { LyricsPage(model: model, album: album) }
            case .delete:
                if let album = model.album { DeletePage(model: model, album: album) }
            }
        }
        .editOutOfReach(!model.online)
    }
}

/// Edit album's root: the album's header, then its parts - the Folder menu with several folders, Needs a look, Edit
/// (Release, Tags, Artwork, Lyrics), Delete album… (slice 4: its page) - each by the person's permissions (Core's
/// Managing.albumEdit and AlbumEdit.marksFine). Without an album, what AlbumEdit.status says, with Look again and
/// Choose the folder; several folders by name alone, the Folder menu alone, "Which folder is this album?" over it.
///
/// (R10 - notes/ios.md "The redesign, slice R10: Edit album, the folder list and Release") Drawn as iEdit.dc.html draws
/// it, flat: the header (the cover, the album, its byline and facts, its path in the readout face), the strip of five
/// in place of the root's rows - Release its one tab, drawn under it; Tags, Artwork, Lyrics and Delete pushing their
/// pages as the rows did (EditAlbumPage.strip, by the same permissions), until R11 draws each as a tab - Release's cards,
/// and its foot: Revert and Apply, laid over the page's foot and never riding up on the keyboard (`.phoneFoot`).
struct EditAlbumRoot: View {
    let model: EditAlbumModel
    @Binding var path: [EditPage]

    @Environment(ServerModel.self) private var server
    @Environment(\.dynamicTypeSize) private var typeSize

    private let side = CGFloat(PhoneLook.bigSide)

    var body: some View {
        Group {
            if !model.online && !model.scan.loaded {
                // opened out of reach: nothing asked, nothing drawn as if live
                ContentUnavailableView {
                    Label(EditWords.title, systemImage: "wifi.slash")
                } description: {
                    Text(EditWords.needsDeadwax)
                }
            } else if let album = model.album {
                albumPage(album)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.choosing, let folders = model.folders {
                            PhoneGroup(legend: EditWords.whichFolder) {
                                folderMenu(folders.paths, chosen: nil)
                            }
                        } else if let status = model.status {
                            statusSection(status)
                        }
                    }
                    .padding(.horizontal, side)
                }
                .background(DWPalette.page)
            }
        }
        .editOutOfReach(!model.online && model.scan.loaded)
    }

    // MARK: no album

    @ViewBuilder private func statusSection(_ status: AlbumEdit.Status) -> some View {
        PhoneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if status.busy {
                        ProgressView()
                    }
                    Text(status.text)
                        .font(Typeface.Phone.text(.row))
                        .foregroundStyle(DWPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                if status.retry {
                    Button(EditWords.lookAgain) {
                        Task { await model.lookUp() }
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                    .disabled(!model.online || model.scan.reading)
                }
                if status.choose {
                    NavigationLink(value: EditPage.chooseFolder) {
                        Text(EditWords.chooseFolder)
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                    .disabled(!model.online)
                }
            }
        }
    }

    // MARK: the album

    /// The album's page: what scrolls, and Release's foot over it - Release's wherever its cards are drawn.
    @ViewBuilder private func albumPage(_ album: ScanAlbum) -> some View {
        let edit = Managing.albumEdit(server.access.permissions)
        let page = ScrollView {
            albumSections(album)
                .padding(.horizontal, side)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DWPalette.page)
        if edit.editors, let retag = model.retag {
            page.phoneFoot { ReleaseFoot(model: model, retag: retag) }
        } else {
            page
        }
    }

    @ViewBuilder private func albumSections(_ album: ScanAlbum) -> some View {
        let edit = Managing.albumEdit(server.access.permissions)
        let strip = EditAlbumPage.strip(editors: edit.editors, delete: edit.delete)
        VStack(alignment: .leading, spacing: 0) {
            header(album)
            if let folders = model.folders, folders.paths.count > 1 {
                folderMenu(folders.paths, chosen: album.path)
            }
            if !strip.tabs.isEmpty || !strip.pushes.isEmpty {
                PhoneStrip(options: strip.tabs, words: { (part: AlbumEdit.Part) -> String in part.label },
                           shown: Binding(get: { AlbumEdit.Part.release },
                                          set: { (part: AlbumEdit.Part) -> Void in open(part) }),
                           spoken: EditAlbumPage.Words.parts, pushes: strip.pushes)
                    // the strip's own sides and hairline run to the screen's edges
                    .padding(.horizontal, -side)
            }
            if model.retag?.flow.mayHaveFinished == true {
                PhoneCard {
                    MayHaveFinished(reading: model.scan.reading)
                }
            }
            // the library couldn't be read again: what is drawn is the last read's, said, with Look again
            if model.scan.failure != nil {
                PhoneCard {
                    VStack(alignment: .leading, spacing: 8) {
                        ReadAgainFailed(model: model)
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                }
            }
            // the web's issues and marks are on its Release tab, Edit albums': Look after the library alone has Delete
            // only - the strip's one push
            if edit.editors {
                needsALook(album)
            }
            if edit.editors, let retag = model.retag {
                ReleaseCards(model: model, retag: retag)
            }
        }
    }

    /// A push of the strip's (R10: Tags, Artwork, Lyrics, Delete - each its page, as the root's rows pushed them; R11
    /// draws each as a tab instead): Release is the root's own, never pushed.
    private func open(_ part: AlbumEdit.Part) {
        switch part {
        case .release: break
        case .tags: path.append(.tags)
        case .artwork: path.append(.artwork)
        case .lyrics: path.append(.lyrics)
        case .delete: path.append(.delete)
        }
    }

    /// iEdit's header: the cover at 60, the album semibold, its byline and facts in the second colour, its path in the
    /// readout face - which can be selected, so it stays apart from the rest, read as one.
    private func header(_ album: ScanAlbum) -> some View {
        HStack(alignment: .top, spacing: 12) {
            FolderCover(path: album.path, mtime: album.artMtime, hasArt: !album.art.isEmpty, pixels: 180)
                .frame(width: 60, height: 60)
                .clipShape(Corners.artShape)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.album.isEmpty ? album.path : album.album)
                        .font(Typeface.Phone.text(.row).weight(.semibold))
                        .foregroundStyle(DWPalette.text)
                    // (R10's review) one line each, as iEdit draws them (`.ell`) - their whole words to VoiceOver
                    let byline = [EditWords.byline(album), EditWords.facts(album)].filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    Text(byline)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .accessibilityLabel(byline)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                // the path cut in its middle, as the Mac's header cuts it: its artist's folder and its own name stay
                Text(album.path)
                    .font(Typeface.Phone.mono(.extraSmall))
                    .foregroundStyle(DWPalette.t3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel(album.path)
                    .textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    /// The Folder menu (a menu Picker of the paths): another of the album's folders - or, several by name, the one
    /// this album is.
    private func folderMenu(_ paths: [String], chosen: String?) -> some View {
        HStack(spacing: 8) {
            Text(EditWords.folder)
                .font(Typeface.Look.text(.fieldLabel))
                .foregroundStyle(DWPalette.rowText)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Picker(EditWords.folder, selection: Binding<String?>(
                get: { chosen },
                set: { (picked: String?) in
                    if let picked { model.choose(picked, fromScan: false) }
                })) {
                if chosen == nil {
                    Text(EditWords.pickOne).tag(String?.none)
                }
                ForEach(paths, id: \.self) { (path: String) in
                    Text(path).tag(Optional(path))
                }
            }
            .pickerStyle(.menu)
            .tint(DWPalette.acc)
            .disabled(model.writing)
        }
        .frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
    }

    /// Needs a look (metadataQueue.ts): each issue the album still has, its label and hint, and what was marked fine -
    /// with Edit albums, as the web's Release tab shows them; It's fine as it is and Ask about it again only with Look
    /// after the library too, their routes' permission (AlbumEdit.marksFine) - both, as on the web since 2.1.31.
    @ViewBuilder private func needsALook(_ album: ScanAlbum) -> some View {
        let outstanding = MetadataQueue.outstanding(album)
        let fine = MetadataQueue.markedFine(album)
        let types = model.scan.answer?.issueTypes ?? [:]
        let marks = AlbumEdit.marksFine(server.access.permissions)
        if !outstanding.isEmpty || !fine.isEmpty {
            PhoneGroup(legend: EditWords.needsALook) {
                PhoneCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(outstanding, id: \.self) { (code: String) in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(MetadataQueue.label(code, types))
                                    .font(Typeface.Phone.text(.row).weight(.semibold))
                                    .foregroundStyle(DWPalette.amberText)
                                let hint = MetadataQueue.hint(code, types)
                                if !hint.isEmpty {
                                    Text(hint)
                                        .font(Typeface.Phone.text(.small))
                                        .foregroundStyle(DWPalette.t2)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                        }
                        if marks, !outstanding.isEmpty {
                            Button {
                                Task { await model.markFine() }
                            } label: {
                                if model.marking {
                                    Label(RetagWords.markingFine, systemImage: "hourglass")
                                } else {
                                    Text(RetagWords.fine)
                                }
                            }
                            .buttonStyle(DWButtonStyle(size: .small))
                            .disabled(!model.online || model.marking || model.writing)
                        }
                        if !fine.isEmpty {
                            Text(RetagWords.markedFine(fine.map { MetadataQueue.label($0, types) }))
                                .font(Typeface.Phone.text(.small))
                                .foregroundStyle(DWPalette.t2)
                                .fixedSize(horizontal: false, vertical: true)
                            if marks {
                                Button(RetagWords.askAgain) {
                                    Task { await model.askAgain() }
                                }
                                .buttonStyle(DWButtonStyle(size: .small))
                                .disabled(!model.online || model.marking || model.writing)
                            }
                        }
                        if let failure = model.markFailure {
                            ErrorNote(text: failure)
                        }
                    }
                }
            }
        }
    }
}

/// The library couldn't be read again while an album is held - after a write, a gap, a mark, Look again: deadwax's
/// failure in the phone's words (LibraryScanModel's, EditWords.said), and Look again, which reads it again. Until one
/// lands nothing is planned or applied (RetagFlow.couldNotRead), and the page drawn is the last read's.
///
/// (Phase 8, slice 5) The artist tools' too: a look for pictures or a preview of the moves that failed - its words, and
/// Look again asking it again (`init(failure:disabled:lookAgain:)`).
struct ReadAgainFailed: View {
    let failure: String?
    let disabled: Bool
    let lookAgain: () -> Void

    init(model: EditAlbumModel) {
        // the read a write or a gap waits for, whichever part's (EditAlbumModel.readBlocking), else the scan's
        failure = model.readBlocking ?? model.scan.failure
        disabled = !model.online || model.scan.reading || model.tags?.reading == true
        // the scan read again - and with it, once it lands, Tags' files (TagsModel.albumRead)
        lookAgain = { Task { await model.lookUp() } }
    }

    init(failure: String?, disabled: Bool, lookAgain: @escaping () -> Void) {
        self.failure = failure
        self.disabled = disabled
        self.lookAgain = lookAgain
    }

    var body: some View {
        if let failure {
            ErrorNote(text: failure)
        }
        Button(EditWords.lookAgain) { lookAgain() }
            .disabled(disabled)
    }
}

/// An apply's answer never came: said, with the folder being read again (EditWords.mayHaveFinished).
struct MayHaveFinished: View {
    let reading: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if reading { ProgressView() }
            Text(EditWords.mayHaveFinished)
                .foregroundStyle(Palette.amber)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// (R10) The top's trailing chip (iEdit's `.chip.green`): the folder held tagged with a MusicBrainz release, Matched -
/// else Not matched, plain; nothing until a folder is held.
private struct MatchedChip: ToolbarContent {
    let album: ScanAlbum?

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let album {
                let matched = EditAlbumPage.matched(album)
                DWChip(words: matched ? EditAlbumPage.Words.matched : EditAlbumPage.Words.notMatched,
                       tone: matched ? .good : .plain)
                    .accessibilityLabel(matched ? EditAlbumPage.Words.matchedMusicBrainz : EditWords.notMatched)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
    }
}

extension View {
    /// The chip in the sheet's top - on iOS 26 and later with no glass behind it, as the drawings' top has none (Now
    /// Playing's sheetTopItems).
    @ViewBuilder
    fileprivate func matchedChip(_ album: ScanAlbum?) -> some View {
        if #available(iOS 26.0, *) {
            toolbar { MatchedChip(album: album).sharedBackgroundVisibility(.hidden) }
        } else {
            toolbar { MatchedChip(album: album) }
        }
    }

    /// Edit album's line while deadwax can't be reached (phase8-managing.md 2): at the top of each of its pages, under
    /// the bar, amber as the offline banner - what is drawn is how it was, and nothing can change until it's back.
    func editOutOfReach(_ shown: Bool) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if shown {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .accessibilityHidden(true)
                    Text(EditWords.outOfReach)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Typeface.footnote.weight(.semibold))
                .foregroundStyle(Palette.amber)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background {
                    Rectangle().fill(.bar)
                        .overlay(Rectangle().fill(Palette.amberFill))
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
