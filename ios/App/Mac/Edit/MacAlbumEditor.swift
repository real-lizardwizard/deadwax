import DeadwaxCore
import SwiftUI

/// The Mac's album editor (the redesign, slice R10 - notes/ios.md "The redesign, slice R10: Edit album, the folder list
/// and Release", its "After review"): one EditAlbumModel's editor - the header (MacEditHeader), the waits, the folder
/// tabs (MacFolderTabs over EditAlbumPage.tabs), the tab's own content in its scroll (Release's MacReleaseTab), the foot
/// (MacEditFooter) and the sheet a part still today's page opens in - and, in place of an album, what the editor says:
/// deadwax out of reach, which of several folders, the status with Look again.
///
/// Its hosts own the model and its opening, and draw what is round it: MacEditWindow (Settings' Edit an album, beside
/// the folder list) and R12's MacNeedsALook. `bar` is the host's slot over the header - queue mode's bar. R11 adds Tags,
/// Artwork, Lyrics and Delete here as tabs, in place of `partCard` and the part's sheet.
///
/// - The tab is this view's own state, above the model: changing it never touches typed work. A new model (the host's
///   next opening) keeps the tab and puts a part's sheet away.
/// - Its reads of the model are its own, and none of them a field's: a keystroke re-draws the tab and the foot, never
///   this view, nor its host (the folder list's rows).
struct MacAlbumEditor<Bar: View>: View {
    let model: EditAlbumModel
    let layout: EditAlbumPage.Layout
    /// The host's, over the header: queue mode's bar (R12's), or nothing.
    let bar: Bar

    @Environment(ServerModel.self) private var server
    @State private var tab: AlbumEdit.Part = .release
    @State private var sheet: MacEditSheet?
    @State private var sheetPath: [EditPage] = []

    init(model: EditAlbumModel, layout: EditAlbumPage.Layout, @ViewBuilder bar: () -> Bar) {
        self.model = model
        self.layout = layout
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
        // another opening: the last one's part sheet put away
        .onChange(of: ObjectIdentifier(model)) { (_: ObjectIdentifier, _: ObjectIdentifier) -> Void in
            sheet = nil
        }
        // the folder deleted: nothing left for a part's page to show
        .onChange(of: model.deleted) { (_: Bool, gone: Bool) -> Void in
            if gone { sheet = nil }
        }
        .appSheet(item: $sheet, onDismiss: { sheetPath.removeAll() }) { (shown: MacEditSheet) in
            NavigationStack(path: partPath) {
                sheetRoot(shown)
                    .navigationDestination(for: EditPage.self) { (page: EditPage) in
                        EditPageView(page: page, model: model, path: partPath)
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
            bar
            MacEditHeader(model: model, album: album, beside: layout.headerBeside)
            waits
            if !tabs.isEmpty {
                MacFolderTabs(tabs: tabs, words: { (part: AlbumEdit.Part) -> String in part.label },
                              chosen: Binding(get: { showing }, set: { (part: AlbumEdit.Part) -> Void in tab = part }),
                              spoken: EditAlbumPage.Words.parts)
            }
            ScrollView {
                if showing == .release, edit.editors, let retag = model.retag {
                    MacReleaseTab(model: model, retag: retag, twoColumns: layout.twoColumns) {
                        sheet = .compareCovers
                    }
                } else if showing != .release {
                    partCard(showing, album: album)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DWPalette.panel)
            // (R10's review) the foot is the tab's: Release's Revert and Apply only with Edit albums, as the tab and the
            // phone's foot are gated - a part still today's page its Open… (Delete's, with Look after the library)
            if showing != .release || edit.editors {
                MacEditFooter(model: model, part: showing) { (part: AlbumEdit.Part) -> Void in
                    sheet = .part(part)
                }
            }
        }
    }

    /// The waits said over the tabs, as the sheet's root says them: an apply that never answered, the library that
    /// couldn't be read again - with Look again.
    @ViewBuilder private var waits: some View {
        let failed = model.scan.failure != nil || model.retag?.flow.readFailed == true
        if model.retag?.flow.mayHaveFinished == true || failed {
            VStack(alignment: .leading, spacing: 6) {
                if model.retag?.flow.mayHaveFinished == true {
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

    /// (R10) A part still today's page: what it holds, and its foot's Open… - R11 draws each as its tab instead.
    private func partCard(_ part: AlbumEdit.Part, album: ScanAlbum) -> some View {
        MacGroupBox(legend: part.label) {
            VStack(alignment: .leading, spacing: 6) {
                Text(partSummary(part, album: album))
                    .font(Typeface.Mac.text(.base))
                    .foregroundStyle(part == .delete ? DWPalette.redText : DWPalette.text)
                Text(EditAlbumPage.Words.partFoot)
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t2)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 22, leading: 16, bottom: 16, trailing: 16))
    }

    private func partSummary(_ part: AlbumEdit.Part, album: ScanAlbum) -> String {
        switch part {
        case .release: return EditWords.releaseValue(album, pressing: nil)
        case .tags: return EditWords.tracks(album.trackCount)
        case .artwork: return EditWords.artworkValue(album)
        case .lyrics: return EditWords.lyricsValue(album)
        case .delete: return EditWords.deleteAlbum
        }
    }

    /// The sheet's first page: the part's own (as the phone pushes it), or Compare covers.
    @ViewBuilder private func sheetRoot(_ shown: MacEditSheet) -> some View {
        switch shown {
        case .part(let part):
            if let page = MacEditSheet.page(part) { EditPageView(page: page, model: model, path: partPath) }
        case .compareCovers:
            EditPageView(page: .compareCovers, model: model, path: partPath)
        }
    }

    /// The sheet's stack - where Artwork's pointer to the Release tab pushes Release, the tab is shown instead.
    private var partPath: Binding<[EditPage]> {
        Binding(get: { sheetPath }, set: { (now: [EditPage]) -> Void in
            if now.last == .release {
                sheet = nil
                tab = .release
            } else {
                sheetPath = now
            }
        })
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

/// What the Mac's editor opens over itself: a part still today's page (R11 draws each as its tab), or Compare covers.
enum MacEditSheet: Identifiable, Hashable {
    case part(AlbumEdit.Part)
    case compareCovers

    var id: String {
        switch self {
        case .part(let part): return part.rawValue
        case .compareCovers: return "compareCovers"
        }
    }

    /// A part's page, as the phone pushes it.
    static func page(_ part: AlbumEdit.Part) -> EditPage? {
        switch part {
        case .release: return nil
        case .tags: return .tags
        case .artwork: return .artwork
        case .lyrics: return .lyrics
        case .delete: return .delete
        }
    }
}
