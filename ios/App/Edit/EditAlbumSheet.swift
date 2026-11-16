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
}

/// Edit album (notes/ios-specs/phase8-managing.md 3.2; the web's EditPanel, its title): a sheet over the tabs, its own
/// navigation stack, drawn as iOS Settings is - a header and sections of rows, each row pushing a page - where the web
/// has five tabs, which don't fit a phone's segmented control. Close at the leading edge; with typed work, or a write
/// under way, the sheet can't be swiped away and Close asks "Discard changes?" first (Discard destructive, Keep
/// editing the default); while an apply runs, Close is off - nothing on the sheet can close it.
///
/// It needs deadwax: opened while deadwax can't be reached it says so and asks nothing, opening by itself once it is
/// back; gone out of reach while open, every page keeps what it drew under the amber line saying nothing can change
/// until deadwax is back, every write off - and back, everything is asked again before a write comes back on
/// (EditAlbumModel.reach). An apply that ended while the phone was locked has the folder read again as the app comes back
/// to the front.
struct EditAlbumSheet: View {
    let request: AlbumEditRequest

    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: EditAlbumModel?
    @State private var path: [EditPage] = []
    @State private var askingDiscard = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model {
                    EditAlbumRoot(model: model)
                } else {
                    Color.clear
                }
            }
            .navigationTitle(EditWords.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(EditWords.close, action: close)
                        .disabled(model?.applying == true)
                        .confirmationDialog(EditWords.discardTitle, isPresented: $askingDiscard, titleVisibility: .visible) {
                            Button(EditWords.discard, role: .destructive) { dismiss() }
                            Button(EditWords.keepEditing, role: .cancel) {}
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
        .task {
            if model == nil {
                let made = EditAlbumModel(request: request, client: server.client, admin: server.access.seesDetail,
                                          online: reachability.online)
                made.navigation = navigation
                model = made
            }
            await model?.open()
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
            askingDiscard = true
        } else {
            dismiss()
        }
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
            }
        }
        .editOutOfReach(!model.online)
    }
}

/// Edit album's root: the album's header, then its sections - the Folder menu with several folders, Needs a look, Edit
/// (Release, and the editors still in the web app), Delete album… - each by the person's permissions (Core's
/// Managing.albumEdit and AlbumEdit.marksFine). Without an album, what AlbumEdit.status says, with Look again and
/// Choose the folder; several folders by name alone, the Folder menu alone, "Which folder is this album?" over it.
struct EditAlbumRoot: View {
    let model: EditAlbumModel

    @Environment(ServerModel.self) private var server

    var body: some View {
        Group {
            if !model.online && !model.scan.loaded {
                // opened out of reach: nothing asked, nothing drawn as if live
                ContentUnavailableView {
                    Label(EditWords.title, systemImage: "wifi.slash")
                } description: {
                    Text(EditWords.needsDeadwax)
                }
            } else {
                List {
                    if let album = model.album {
                        albumSections(album)
                    } else if model.choosing, let folders = model.folders {
                        Section {
                            folderMenu(folders.paths, chosen: nil)
                        } header: {
                            Text(EditWords.whichFolder)
                                .font(Typeface.footnote)
                        }
                    } else if let status = model.status {
                        statusSection(status)
                    }
                }
            }
        }
        .editOutOfReach(!model.online && model.scan.loaded)
    }

    // MARK: no album

    @ViewBuilder private func statusSection(_ status: AlbumEdit.Status) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if status.busy {
                    ProgressView()
                }
                Text(status.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if status.retry {
                Button(EditWords.lookAgain) {
                    Task { await model.lookUp() }
                }
                .disabled(!model.online || model.scan.reading)
            }
            if status.choose {
                NavigationLink(value: EditPage.chooseFolder) {
                    Text(EditWords.chooseFolder)
                }
                .disabled(!model.online)
            }
        }
    }

    // MARK: the album

    @ViewBuilder private func albumSections(_ album: ScanAlbum) -> some View {
        let edit = Managing.albumEdit(server.access.permissions)
        Section {
            header(album)
        }
        if model.retag?.flow.mayHaveFinished == true {
            Section {
                MayHaveFinished(reading: model.scan.reading)
            }
        }
        if let folders = model.folders, folders.paths.count > 1 {
            Section {
                folderMenu(folders.paths, chosen: album.path)
            }
        }
        // the web's issues and marks are on its Release tab, Edit albums': Look after the library alone has Delete only
        if edit.editors {
            needsALook(album)
        }
        if edit.editors, let retag = model.retag {
            Section {
                NavigationLink(value: EditPage.release) {
                    LabeledContent(EditWords.release) {
                        Text(EditWords.releaseValue(album, pressing: retag.selected?.release))
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let url = webURL {
                    WebAppRow(label: AlbumEdit.Part.tags.label, line: EditWords.tracks(album.trackCount), url: url,
                              live: model.online)
                    WebAppRow(label: AlbumEdit.Part.artwork.label, line: EditWords.artworkValue(album), url: url,
                              live: model.online)
                    WebAppRow(label: AlbumEdit.Part.lyrics.label, line: EditWords.lyricsValue(album), url: url,
                              live: model.online)
                }
            } header: {
                Text(EditWords.edit)
                    .font(Typeface.footnote)
            } footer: {
                Text(EditWords.inWebAppLine)
                    .font(Typeface.footnote)
            }
        }
        if edit.delete, let url = webURL {
            Section {
                WebAppRow(label: EditWords.deleteAlbum, url: url, live: model.online)
            } footer: {
                if !edit.editors {
                    Text(EditWords.inWebAppLine)
                        .font(Typeface.footnote)
                }
            }
        }
    }

    /// The editors not yet on the phone open the album in the web app: its page there, else (a folder opened from
    /// Choose the folder, no album page behind it) the web app's Library.
    private var webURL: URL? {
        if let subject = model.subject { return Managing.albumURL(id: subject.id, at: server.address) }
        return Managing.url(.edit, at: server.address)
    }

    private func header(_ album: ScanAlbum) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                FolderCover(path: album.path, mtime: album.artMtime, hasArt: !album.art.isEmpty, pixels: 240)
                    .frame(width: 72, height: 72)
                    .clipShape(Corners.artShape)
                VStack(alignment: .leading, spacing: 3) {
                    Text(album.album.isEmpty ? album.path : album.album)
                        .font(Typeface.headline)
                    let byline = EditWords.byline(album)
                    if !byline.isEmpty {
                        Text(byline)
                            .font(Typeface.subheadline)
                            .foregroundStyle(Palette.quiet)
                    }
                    Text(EditWords.facts(album))
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(album.path)
                .font(Typeface.mono(.caption))
                .foregroundStyle(Palette.quiet)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    /// The Folder menu (a menu Picker of the paths): another of the album's folders - or, several by name, the one
    /// this album is.
    private func folderMenu(_ paths: [String], chosen: String?) -> some View {
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
        .disabled(model.applying)
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
            Section {
                ForEach(outstanding, id: \.self) { (code: String) in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MetadataQueue.label(code, types))
                            .font(Typeface.body.weight(.semibold))
                        let hint = MetadataQueue.hint(code, types)
                        if !hint.isEmpty {
                            Text(hint)
                                .font(Typeface.footnote)
                                .foregroundStyle(Palette.quiet)
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
                    .disabled(!model.online || model.marking)
                }
                if !fine.isEmpty {
                    Text(RetagWords.markedFine(fine.map { MetadataQueue.label($0, types) }))
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                    if marks {
                        Button(RetagWords.askAgain) {
                            Task { await model.askAgain() }
                        }
                        .disabled(!model.online || model.marking)
                    }
                }
                if let failure = model.markFailure {
                    ErrorNote(text: failure)
                }
            } header: {
                Text(EditWords.needsALook)
                    .font(Typeface.footnote)
            }
        }
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

extension View {
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
