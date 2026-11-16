"""
The iPhone app's Edit album, its parts after Release, as the App draws and runs them (Phase 8, slices 2-4 -
notes/ios-specs/phase8-managing.md 3.4-3.7; notes/ios.md "Edit album's Tags, Artwork, Lyrics and Delete").

Read from the Swift source, as tests/test_ios_edit.py reads slice 1's. Tags: the root's row pushes the phone's own list
(no web app row); Select is a List's selection with the bottom bar's Edit N tracks…; a track's page pushes the editor;
Edit tags is a Form whose Apply is on only as RetagFlow says, and never beside another write; its Apply holds a
background task, says an answer that never came, reads the folder again, and stops at a sign-out; its reads drop a
cancellation and only the newest lands; out of reach and back it reads again. Artwork and Lyrics: rows pushing pages of
the phone's own (Delete album… the one web app row left); the cover and CD art drawn, each full screen; each Get offered
as LibraryParts offers it, its words by its last run, on only as EditAlbumModel.canGet says - never beside another
write - held with a background task, the folder read again after anything that may have written, the other parts'
previews waiting for that read, nothing more after a sign-out. Core's rules and words are held by EditPartsVectorTests,
TagEditFlowTests and GetResultsTests, the routes by tests/test_ios_edit_parts_contract.py.
"""

from tests.test_ios_edit import EDIT, MODEL, SHEET, RELEASE, block, code, declared

TAGS_MODEL = EDIT / "TagsModel.swift"
TAGS_PAGES = EDIT / "TagsPages.swift"


def body(text: str, name: str) -> str:
    return block(text, text.index("{", text.index(name)))


# ---------------------------------------------------------------------------- Tags

def test_tags_is_a_page_of_the_phones_own():
    sheet = code(SHEET)
    assert "case tags" in sheet and "case track(String)" in sheet and "case editTags" in sheet
    view = declared(sheet, "struct", "EditPageView")
    assert "TagsListView(model: model, tags: tags, path: $path)" in view
    assert "TrackPageView(model: model, tags: tags, filename: filename, path: $path)" in view
    assert "EditTagsView(model: model, tags: tags)" in view
    root = declared(sheet, "struct", "EditAlbumRoot")
    sections = body(root, "private func albumSections(")
    row = body(sections, "NavigationLink(value: EditPage.tags)")
    assert "LabeledContent(AlbumEdit.Part.tags.label)" in row and "EditWords.tracks(album.trackCount)" in row


def test_select_is_the_lists_own_and_edits_the_tracks_chosen_or_all():
    pages = code(TAGS_PAGES)
    view = declared(pages, "struct", "TagsListView")
    assert "List(selection: selecting ? $tags.selection : nil)" in view
    assert ".environment(\\.editMode, $editMode)" in view
    # a row pushes its track's page outside Select, and only there
    assert "NavigationLink(value: EditPage.track(file.filename))" in view
    assert "ToolbarItemGroup(placement: .bottomBar)" in view and "TagEditWords.editTracks(tags.selection.count)" in view
    targets = body(view, "private var targets: [String]")
    assert "tags.selection.isEmpty ? names :" in targets
    # another set of tracks over typed work asks first, as Close does
    assert "if names != tags.editing && tags.unsaved {" in body(view, "private func open(")
    assert ".confirmationDialog(EditWords.discardTitle" in view and "Button(EditWords.keepEditing, role: .cancel) {}" in view
    # the files are read once Tags opens - again for a model held anew
    assert ".task(id: ObjectIdentifier(tags)) { tags.start() }" in view


def test_a_tracks_page_shows_its_pictures_and_pushes_the_editor():
    pages = code(TAGS_PAGES)
    page = declared(pages, "struct", "TrackPageView")
    assert "TrackInspector.groups(file)" in page and "TrackInspector.place(file, discs: tags.album.discCount)" in page
    assert "Button(TrackInspector.editThis)" in page and "tags.edit([filename])" in page
    assert "FullCover(source: .picture(path: tags.album.path, file: file.filename, index: picture.index))" in page
    row = declared(pages, "struct", "PictureRow")
    assert "client.trackPicture(path: path, file: file, index: picture.index)" in row
    assert ".clipShape(Corners.artShape)" in row
    release = code(RELEASE)
    assert "case picture(path: String, file: String, index: Int)" in release
    assert "EditWords.pictureFailed" in release


def test_edit_tags_applies_only_as_the_flow_says_and_never_beside_another_write():
    pages = code(TAGS_PAGES)
    view = declared(pages, "struct", "EditTagsView")
    assert ".disabled(!tags.canApply || model.writing || model.marking)" in view
    assert "Task { await model.applyTags() }" in view
    # the fields can't be typed into while the apply runs, and the keyboard has its Done
    assert ".disabled(tags.flow.applying)" in view
    assert "ToolbarItemGroup(placement: .keyboard)" in view
    # an apply that never answered is said over the page
    assert "if tags.flow.mayHaveFinished {" in view and "MayHaveFinished(" in view
    model = code(TAGS_MODEL)
    assert "var canApply: Bool { ready && flow.canApply(plan, problems: problems.count) }" in model
    # the Release's writes are off while Tags' runs, and Tags' while one of them does
    release = code(RELEASE)
    assert ".disabled(!retag.canApply || model.tagsApplying || model.getting)" in release
    edit = code(MODEL)
    assert "var applying: Bool { retag?.flow.applying == true || tagsApplying || getting }" in edit
    for name in ("func apply()", "func saveCoverOnly()"):
        assert "guard !tagsApplying," in body(edit, name), name
    tags_apply = body(edit, "func applyTags()")
    assert "!(retag?.flow.applying == true)" in tags_apply and "retag?.flow.savingCover != true" in tags_apply
    assert "!marking" in tags_apply


def test_the_tag_apply_holds_a_background_task_reads_again_and_stops_at_a_sign_out():
    edit = code(MODEL)
    apply = body(edit, "func applyTags()")
    assert 'BackgroundHold(named: "Edit album: Edit tags")' in apply and "defer { hold.end() }" in apply
    assert "client.tagsApply(body)" in apply
    assert apply.index("guard samePerson else { return }") < apply.index("await lookUp()")
    assert "AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post()" in apply
    assert apply.index("guard tags.flow.needsRead else { return }") < apply.index("await lookUp()")
    assert "if outcome != .refused { wrote(before: before) }" in apply
    # the files read again whenever the folder is: a write, a gap, Look again
    assert "tags?.albumRead(fresh)" in edit and "tags?.couldNotRead()" in edit
    assert "tags?.wentAway()" in edit and "tags?.cameBack()" in edit
    assert "tags?.flow.needsRead == true" in body(edit, "func becameActive()")
    # typed work keeps the sheet from being swiped away
    assert "tags?.unsaved == true" in edit
    # a write beside the other's preview: it waits for the read too (RetagFlow.folderChanged)
    assert "if outcome != .refused { retag?.folderChanged() }" in apply
    release_apply = body(edit, "func apply()")
    assert "if outcome != .refused { tags?.folderChanged() }" in release_apply
    model = code(TAGS_MODEL)
    changed = body(model, "func folderChanged()")
    assert "guard started else { return }" in changed and "flow.folderChanged()" in changed
    # a Tags never opened has no preview to wait for: a read lets it go
    read = body(model, "func albumRead(")
    assert read.index("guard started else {") < read.index("flow.read()") < read.index("Task { await readFiles() }")


def test_tags_reads_drop_a_cancellation_and_only_the_newest_lands():
    model = code(TAGS_MODEL)
    read = body(model, "func readFiles()")
    assert "guard ticket == reads else { return }" in read
    assert "guard !APIFailure.isCancellation(error) else { return }" in read
    assert read.index("isCancellation") < read.index("readFailure = EditWords.said(")
    assert "flow.couldNotRead()" in read and "flow.read()" in read
    preview = body(model, "private func schedulePreview()")
    assert "Retag.previewDebounceMs" in preview and "guard flow.due(edit) else { return }" in preview
    assert "guard !APIFailure.isCancellation(error) else { return }" in preview
    assert "if self.flow.answered(edit) {" in preview and "if self.flow.failed(edit) {" in preview
    # an apply's failure in the managing pages' words, its outcome RetagFlow's
    ended = body(model, "func applyEnded(")
    assert "RetagFlow.outcome(of: error)" in ended
    assert "EditWords.writeFailure(error, failed: TagEditWords.applyFailed, admin: admin)" in ended


# ---------------------------------------------------------------------------- Artwork and Lyrics (slice 3)

ART_PAGES = EDIT / "ArtworkLyricsPages.swift"


def test_artwork_and_lyrics_are_pages_of_the_phones_own():
    sheet = code(SHEET)
    assert "case artwork" in sheet and "case lyrics" in sheet
    view = declared(sheet, "struct", "EditPageView")
    assert "ArtworkPage(model: model, album: album)" in view and "LyricsPage(model: model, album: album)" in view
    sections = body(declared(sheet, "struct", "EditAlbumRoot"), "private func albumSections(")
    artwork = body(sections, "NavigationLink(value: EditPage.artwork)")
    assert "LabeledContent(AlbumEdit.Part.artwork.label)" in artwork and "EditWords.artworkValue(album)" in artwork
    lyrics = body(sections, "NavigationLink(value: EditPage.lyrics)")
    assert "LabeledContent(AlbumEdit.Part.lyrics.label)" in lyrics and "EditWords.lyricsValue(album)" in lyrics
    # Delete album… is the one row left in the web app, its line under it
    delete = body(sections, "if edit.delete, let url = webURL {")
    assert "WebAppRow(label: EditWords.deleteAlbum" in delete and "Text(EditWords.inWebAppLine)" in delete


def test_artwork_draws_the_cover_and_cd_art_and_offers_each_get_as_the_web_does():
    pages = code(ART_PAGES)
    page = declared(pages, "struct", "ArtworkPage")
    # the cover, a tap full screen; where it is said; Get cover only as LibraryParts offers it
    assert "FullCover(source: .folder(album.path, album.artMtime))" in page
    assert ".accessibilityLabel(GetResults.seeCover)" in page
    assert "Text(GetResults.coverNote(album.art))" in page
    assert "if GetResults.offersCover(album) {" in page and "GetButton(model: model, kind: .cover" in page
    # the web's pointer to the Release tab's comparison: a row pushing it - the Release page with no release
    assert "if let pointer = GetResults.coverPointer(album) {" in page
    assert "NavigationLink(value: album.releaseMbid.isEmpty ? EditPage.release : EditPage.compareCovers)" in page
    # CD art: the scan's pictures in a grid, each by name and full screen; Get CD art as the web offers it
    assert "LazyVGrid(" in page and "ForEach(album.discArt, id: \\.self)" in page
    assert "DiscArtPicture(path: album.path, file: name)" in page
    assert "FullCover(source: .discArt(path: album.path, file: name))" in page
    assert ".accessibilityLabel(GetResults.seeDiscArt(name))" in page
    assert "Text(GetResults.noDiscArt)" in page and "Text(GetResults.discArtBeside)" in page
    assert "if GetResults.offersDiscArt(album) {" in page and "GetButton(model: model, kind: .disc" in page
    assert "if let pointer = GetResults.discArtPointer(album) {" in page
    assert ".fullScreenCover(item: $full)" in page
    picture = declared(pages, "struct", "DiscArtPicture")
    assert "client.libraryDiscArt(path: path, file: file)" in picture and ".clipShape(Corners.artShape)" in picture
    release = code(RELEASE)
    assert "case discArt(path: String, file: String)" in release
    assert "client.libraryDiscArt(path: path, file: file)" in release


def test_lyrics_counts_and_offers_get_lyrics_as_the_web_does():
    pages = code(ART_PAGES)
    page = declared(pages, "struct", "LyricsPage")
    assert "Text(GetResults.lyricsLine(album.lyricsCount, album.trackCount))" in page
    assert "if GetResults.offersLyrics(album, ran: model.run(.lyrics) != nil) {" in page
    assert "GetButton(model: model, kind: .lyrics" in page
    assert "GetResults.allLyricsNote(album)" in page
    # the pointer to re-timing is said: Server settings is still the web app's
    assert "Text(GetResults.retimePointer)" in page and "WebAppRow" not in pages and "openURL" not in pages


def test_a_get_says_its_words_and_is_on_only_as_the_model_says():
    pages = code(ART_PAGES)
    button = declared(pages, "struct", "GetButton")
    assert "GetResults.label(kind, run, trackCount: trackCount)" in button
    assert "Task { await model.get(kind) }" in button and ".disabled(!model.canGet)" in button
    assert "if run?.state == .working { ProgressView() }" in button
    assert "if let said = run?.said, run?.state != .working {" in button
    wait = declared(pages, "struct", "GetWait")
    assert "if model.unansweredGet != nil {" in wait and "MayHaveFinished(reading: model.scan.reading)" in wait
    assert "if model.retag?.flow.readFailed == true {" in wait and "ReadAgainFailed(model: model)" in wait
    for name in ("ArtworkPage", "LyricsPage"):
        assert "GetWait(model: model)" in declared(pages, "struct", name), name
    edit = code(MODEL)
    # a Get is a write: never beside another, nor a mark, nor before the folder's read after a write or a gap
    can = body(edit, "var canGet: Bool")
    for part in ("online", "album != nil", "!writing", "!marking", "!scan.reading", "retag?.flow.needsRead != true"):
        assert part in can, part
    assert "var applying: Bool { retag?.flow.applying == true || tagsApplying || getting }" in edit
    assert "var getting: Bool { runs.values.contains { $0.state == .working } }" in edit
    # another folder's run is never shown
    assert "guard let run = runs[kind], run.path == album?.path else { return nil }" in body(edit, "func run(")
    for name in ("func apply()", "func saveCoverOnly()"):
        assert "!getting," in body(edit, name), name
    assert "!getting," in body(edit, "func applyTags()")
    release = code(RELEASE)
    assert ".disabled(incoming == nil || !retag.flow.canSaveCover || model.tagsApplying || model.getting)" in release


def test_a_get_holds_a_background_task_reads_again_after_any_write_and_stops_at_a_sign_out():
    edit = code(MODEL)
    get = body(edit, "func get(_ kind: GetResults.Kind)")
    assert "guard canGet, let client, let before = album else { return }" in get
    assert 'BackgroundHold(named: "Edit album: ' in get and "defer { hold.end() }" in get
    for call in ("client.getCover(path: path)", "client.getDiscArt(path: path)", "client.getLyrics(path: path)"):
        assert call in get, call
    assert "run.failed(error, admin: admin)" in get
    # the other parts' previews wait for the read too - before anything is asked of the person signed in
    assert get.index("if run.wrote {") < get.index("retag?.folderChanged()") < get.index("guard samePerson else")
    assert "tags?.folderChanged()" in get
    assert "unansweredGet = kind" in get and "AccessibilityNotification.Announcement(EditWords.mayHaveFinished)" in get
    # a 404 or a refusal wrote nothing: nothing read; anything else read again, the page beneath asked again
    assert get.index("guard samePerson else { return }") < get.index("guard run.wrote else { return }")
    assert get.index("guard run.wrote else { return }") < get.index("await lookUp()") < get.index("wrote(before: before)")
    # the maybe-finished line lasts until a read lands
    look = body(edit, "func lookUp()")
    assert look.index("case .landed:") < look.index("unansweredGet = nil") < look.index("settle()")
