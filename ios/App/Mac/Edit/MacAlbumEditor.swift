import DeadwaxCore
import SwiftUI

/// The Mac's album editor (the redesign, slice R10 - notes/ios.md "The redesign, slice R10: Edit album, the folder list
/// and Release", its "After review"): one EditAlbumModel's editor - the header (MacEditHeader), the waits, the folder
/// tabs (MacFolderTabs over EditAlbumPage.tabs), the tab's own content in its scroll, the foot (MacEditFooter) and the
/// sheet Compare covers opens in - and, in place of an album, what the editor says: deadwax out of reach, which of
/// several folders, the status with Look again.
///
/// Its hosts own the model and its opening, and draw what is round it: MacEditWindow (Settings' Edit an album, beside
/// the folder list) and R12's MacNeedsALook (beside the queue). `bar` is the host's slot - queue mode's bar, drawn (R12 -
/// notes/ios.md "The redesign, slice R12: Needs a look") under the header's chip, as NeedsALook.dc.html has it; `queue`
/// is queue mode as the foot needs it - It's fine as it is, and Apply moving on (MacEditFooter).
///
/// (R11 - notes/ios.md "The redesign, slice R11: Tags, Artwork, Lyrics and Delete") Every part a tab of its own, as
/// Main.dc.html draws them: Release's MacReleaseTab, Tags' MacTagsTab, Artwork's MacArtworkTab, Lyrics' MacLyricsTab,
/// Delete's MacDeleteTab - in place of R10's card for a part still the phone's page, and its sheet. The foot is the
/// tab's: Release's and Tags' Revert and Apply, Delete's Delete permanently.
///
/// - The tab is this view's own state, above the model: changing it never touches typed work. A new model (the host's
///   next opening) keeps the tab and puts Compare covers away.
/// - Its reads of the model are its own, and none of them a field's: a keystroke re-draws the tab and the foot, never
///   this view, nor its host (the folder list's rows).
struct MacAlbumEditor<Bar: View>: View {
    let model: EditAlbumModel
    let layout: EditAlbumPage.Layout
    /// The host's, under the header's chip: queue mode's bar (R12's), or nothing.
    let bar: Bar
    /// (R12) Queue mode, the host's: where the session is, and its step - nil from anywhere but Needs a look.
    let queue: MacEditQueue?

    @Environment(ServerModel.self) private var server
    @State private var tab: AlbumEdit.Part = .release
    @State private var sheet: MacEditSheet?
    @State private var sheetPath: [EditPage] = []

    init(model: EditAlbumModel, layout: EditAlbumPage.Layout, queue: MacEditQueue? = nil, @ViewBuilder bar: () -> Bar) {
        self.model = model
        self.layout = layout
        self.queue = queue
        self.bar = bar()
    }

    var body: some View {
        Group {
            if !model.online && !model.scan.loaded {
                MacEditNote(words: EditWords.needsDeadwax)
            } else if let album = model.album {
                albumEditor(album)
            } else if model.choosing, let folders = model.folders {
                whichFolder(folders.paths)
            } else if let status = model.status {
                statusNote(status)
            }
        }
        .editOutOfReach(!model.online && model.scan.loaded)
        // another opening: the last one's sheet put away
        .onChange(of: ObjectIdentifier(model)) { (_: ObjectIdentifier, _: ObjectIdentifier) -> Void in
            sheet = nil
        }
        // the folder deleted: nothing left for a sheet to show
        .onChange(of: model.deleted) { (_: Bool, gone: Bool) -> Void in
            if gone { sheet = nil }
        }
        .appSheet(item: $sheet, onDismiss: { sheetPath.removeAll() }) { (shown: MacEditSheet) in
            NavigationStack(path: $sheetPath) {
                sheetRoot(shown)
                    .navigationDestination(for: EditPage.self) { (page: EditPage) in
                        EditPageView(page: page, model: model, path: $sheetPath)
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(AlbumInfoWords.done) { sheet = nil }
                                .escapeCloses()
                        }
                    }
            }
            .macSheet()
        }
    }

    // MARK: the album

    @ViewBuilder private func albumEditor(_ album: ScanAlbum) -> some View {
        let edit = Managing.albumEdit(server.access.permissions)
        let tabs = EditAlbumPage.tabs(editors: edit.editors, delete: edit.delete)
        let showing = EditAlbumPage.shown(tab, in: tabs)
        VStack(alignment: .leading, spacing: 0) {
            MacEditHeader(model: model, album: album, beside: layout.headerBeside) { bar }
            waits
            if !tabs.isEmpty {
                MacFolderTabs(tabs: tabs, words: { (part: AlbumEdit.Part) -> String in part.label },
                              chosen: Binding(get: { showing }, set: { (part: AlbumEdit.Part) -> Void in tab = part }),
                              spoken: EditAlbumPage.Words.parts)
            }
            ScrollView {
                tabContent(showing, album: album, editors: edit.editors)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DWPalette.panel)
            // (R10's review) the foot is the tab's: Release's Revert and Apply only with Edit albums, as the tab and the
            // phone's foot are gated - (R11) Tags' Revert and Apply, Delete's Delete permanently (with Look after the
            // library), Artwork's and Lyrics' line alone
            if showing != .release || edit.editors {
                MacEditFooter(model: model, album: album, part: showing, queue: queue)
            }
        }
    }

    /// (R11) The tab shown, drawn: each part's own.
    @ViewBuilder private func tabContent(_ showing: AlbumEdit.Part, album: ScanAlbum, editors: Bool) -> some View {
        switch showing {
        case .release:
            if editors, let retag = model.retag {
                MacReleaseTab(model: model, retag: retag, twoColumns: layout.twoColumns) {
                    sheet = .compareCovers
                }
            }
        case .tags:
            if let tags = model.tags {
                MacTagsTab(model: model, tags: tags, twoColumns: layout.twoColumns)
            }
        case .artwork:
            MacArtworkTab(model: model, album: album, twoColumns: layout.twoColumns,
                          compare: { sheet = .compareCovers }, showRelease: { tab = .release })
        case .lyrics:
            MacLyricsTab(model: model, album: album)
        case .delete:
            MacDeleteTab(model: model, album: album)
        }
    }

    /// The waits said over the tabs, as the sheet's root says them: an apply that never answered - (R11) or a Get, on
    /// any tab - the library that couldn't be read again, with Look again.
    @ViewBuilder private var waits: some View {
        let failed = model.scan.failure != nil || model.retag?.flow.readFailed == true
        let unanswered = model.retag?.flow.mayHaveFinished == true || model.unansweredGet != nil
        if unanswered || failed {
            VStack(alignment: .leading, spacing: 6) {
                if unanswered {
                    MayHaveFinished(reading: model.scan.reading)
                }
                if failed {
                    HStack(spacing: 8) {
                        ReadAgainFailed(model: model)
                    }
                    .buttonStyle(DWButtonStyle(size: .small))
                }
            }
            .font(Typeface.Mac.text(.base))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    /// The sheet's first page: Compare covers - Release's Compare full size…, Artwork's Compare with this pressing….
    @ViewBuilder private func sheetRoot(_ shown: MacEditSheet) -> some View {
        switch shown {
        case .compareCovers:
            EditPageView(page: .compareCovers, model: model, path: $sheetPath)
        }
    }

    // MARK: no album

    private func statusNote(_ status: AlbumEdit.Status) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if status.busy { ProgressView().controlSize(.small) }
                Text(status.text)
                    .font(Typeface.Mac.text(.base))
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
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Several folders found by name: the one this album is, chosen here (the sheet's Folder menu alone).
    private func whichFolder(_ paths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(EditWords.whichFolder)
                .font(Typeface.Mac.text(.base).weight(.semibold))
                .foregroundStyle(DWPalette.text)
                .accessibilityAddTraits(.isHeader)
            ForEach(paths, id: \.self) { (path: String) in
                Button(path) { model.choose(path, fromScan: false) }
                    .buttonStyle(DWButtonStyle(size: .small))
                    .disabled(model.writing)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension MacAlbumEditor where Bar == EmptyView {
    /// The editor with nothing over its header.
    init(model: EditAlbumModel, layout: EditAlbumPage.Layout) {
        self.init(model: model, layout: layout) { EmptyView() }
    }
}

/// What the Mac's editor says where an album would be: no folder picked yet (its host's), deadwax out of reach.
struct MacEditNote: View {
    let words: String

    var body: some View {
        Text(words)
            .font(Typeface.Mac.text(.base))
            .foregroundStyle(DWPalette.t2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// What the Mac's editor opens over itself: Compare covers. (R11) The parts R10 opened here as the phone's pages are
/// tabs now; a file's every tag is the Tags tab's own sheet.
enum MacEditSheet: Identifiable, Hashable {
    case compareCovers

    var id: String {
        switch self {
        case .compareCovers: return "compareCovers"
        }
    }
}
