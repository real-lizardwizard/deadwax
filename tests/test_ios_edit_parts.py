"""
The iPhone app's Edit album, its parts after Release, as the App draws and runs them (Phase 8, slices 2-4 -
notes/ios-specs/phase8-managing.md 3.4-3.7; notes/ios.md "Edit album's Tags, Artwork, Lyrics and Delete").

Read from the Swift source, as tests/test_ios_edit.py reads slice 1's. Tags: the root's row pushes the phone's own list
(no web app row); Select is a List's selection with the bottom bar's Edit N tracks…; a track's page pushes the editor;
Edit tags is a Form whose Apply is on only as RetagFlow says, and never beside another write; its Apply holds a
background task, says an answer that never came, reads the folder again, and stops at a sign-out; its reads drop a
cancellation and only the newest lands; out of reach and back it reads again. Artwork and Lyrics: rows pushing pages of
the phone's own; the cover and CD art drawn, each full screen; each Get offered as LibraryParts offers it, its words by
its last run, on only as EditAlbumModel.canGet says - never beside another write - held with a background task, the
folder read again after anything that may have written, the other parts' previews waiting for that read, nothing more
after a sign-out. Delete album (slice 4, the last web app row gone): a row of Look after the library's pushing a page of
the phone's own that reads what goes live, names it and who holds it, and asks once more before Delete permanently,
Cancel the default; never beside another write; held with a background task; one that never answered settled by the
next read; once gone, the sheet closes, the album page goes back when nothing of it is left, and the Library asks
again. Core's rules and words are held by EditPartsVectorTests, TagEditFlowTests, GetResultsTests and DeleteAlbumTests,
the routes by tests/test_ios_edit_parts_contract.py.
"""

import re

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
    assert ".disabled(!retag.canApply || model.tagsApplying || model.getting || model.deleting)" in release
    edit = code(MODEL)
    assert "var applying: Bool { retag?.flow.applying == true || tagsApplying || getting || deleting }" in edit
    for name in ("func apply()", "func saveCoverOnly()"):
        assert "guard !tagsApplying," in body(edit, name), name
    tags_apply = body(edit, "func applyTags()")
    assert "!(retag?.flow.applying == true)" in tags_apply and "retag?.flow.savingCover != true" in tags_apply
    assert "!marking" in tags_apply


def test_the_tag_apply_holds_a_background_task_reads_again_and_stops_at_a_sign_out():
    edit = code(MODEL)
    apply = body(edit, "func applyTags()")
    assert 'BackgroundHold(named: "Edit album: Edit tags")' in apply and "defer { hold.end() }" in apply
    # waited for by the size of the files it edits (EditWaits.tagsApply, review 16 Nov)
    assert "client.tagsApply(body, bytes: tags.editingFiles.reduce(0) { $0 + $1.size })" in apply
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


def test_after_review_tags_types_only_what_differs_and_never_shows_stale_fields():
    # review, 16 Nov: a field's "" handed back without a key pressed is no typing (TagEdit.typed - Core's, tested there)
    model = code(TAGS_MODEL)
    typed = body(model, "func set(_ key: String, _ value: String)")
    assert "guard let next = TagEdit.typed(value, key: key, draft: draft, shared: shared(key)) else { return }" in typed
    assert "draft[key] != value" not in typed and "draft = next" in typed
    # saved: the fields wait for the files' read (refreshing), set as the draft goes and cleared only as a read lands
    ended = body(model, "func applyEnded(")
    assert ended.index("draft = [:]") < ended.index("refreshing = true") < ended.index("case .failure(let error):")
    read = body(model, "func readFiles()")
    assert read.index("files = found") < read.index("refreshing = false") < read.index("} catch {")
    assert "refreshing" not in read[read.index("} catch {"):], "a read that failed leaves the fields away"
    pages = code(TAGS_PAGES)
    view = declared(pages, "struct", "EditTagsView")
    assert view.index("if tags.refreshing {") < view.index("} else if tags.ready {") < view.index("editingSection")
    shown = view[view.index("if tags.refreshing {"):view.index("} else if tags.ready {")]
    assert "TextField" not in shown and "Text(applied)" in shown and "TagEditWords.readingFiles" in shown
    assert "if tags.readFailure == nil, !tags.flow.readFailed {" in shown
    # a read that failed is said with Look again - the files' own, or the scan's the flow waited for
    state = declared(pages, "struct", "TagsReadState")
    assert ("if let failure = tags.readFailure ?? (tags.flow.readFailed ? model.scan.failure ?? EditWords.readFailed"
            " : nil) {") in state
    # a refused apply's preview is out of date until asked again (changed: planning, then a new preview)
    assert "if outcome == .refused { changed() }" in ended
    assert ended.count("plan = nil") == 2, "the plan in hand goes whatever came of the apply"
    # a file gone since (a release applied renames them) leaves the editor's files as it leaves the selection
    assert read.index("let held = { (name: String) in found.contains { $0.filename == name } }") < read.index(
        "editing = editing.filter(held)") < read.index("flow.read()")
    assert "selection = selection.filter(held)" in read
    # a track's pictures by place: an index read loosely as 0 twice is still two rows
    page = declared(pages, "struct", "TrackPageView")
    assert "ForEach(Array(file.pictures.enumerated()), id: \\.offset)" in page
    assert "ForEach(file.pictures, id: \\.index)" not in page


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
    # Delete album…, the last row that was the web app's, is a page of the phone's own since slice 4
    delete = body(sections, "if edit.delete {")
    assert "NavigationLink(value: EditPage.delete)" in delete and "WebAppRow" not in sheet


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
    assert ".appCover(item: $full)" in page
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
    # the read that holds the Gets off, said in the phone's words with Look again (review, 16 Nov)
    failed = declared(code(SHEET), "struct", "ReadAgainFailed")
    assert "failure = model.readBlocking ?? model.scan.failure" in failed
    for name in ("ArtworkPage", "LyricsPage"):
        assert "GetWait(model: model)" in declared(pages, "struct", name), name
    edit = code(MODEL)
    # a Get is a write: never beside another, nor a mark, nor before the folder's read after a write or a gap
    can = body(edit, "var canGet: Bool")
    for part in ("online", "album != nil", "!writing", "!marking", "!scan.reading", "retag?.flow.needsRead != true"):
        assert part in can, part
    assert "var applying: Bool { retag?.flow.applying == true || tagsApplying || getting || deleting }" in edit
    assert "var getting: Bool { runs.values.contains { $0.state == .working } }" in edit
    # another folder's run is never shown
    assert "guard let run = runs[kind], run.path == album?.path else { return nil }" in body(edit, "func run(")
    for name in ("func apply()", "func saveCoverOnly()"):
        assert "!getting," in body(edit, name), name
    assert "!getting," in body(edit, "func applyTags()")
    release = code(RELEASE)
    assert re.search(r"\.disabled\(incoming == nil \|\| !retag\.flow\.canSaveCover \|\| model\.tagsApplying \|\| "
                     r"model\.getting\s*\|\| model\.deleting\)", release)


def test_a_get_holds_a_background_task_reads_again_after_any_write_and_stops_at_a_sign_out():
    edit = code(MODEL)
    get = body(edit, "func get(_ kind: GetResults.Kind)")
    assert "guard canGet, let client, let before = album else { return }" in get
    assert 'BackgroundHold(named: "Edit album: ' in get and "defer { hold.end() }" in get
    # the long two waited for by the album in hand (EditWaits, review 16 Nov): handed the album, not its path
    for call in ("client.getCover(path: path)", "client.getDiscArt(before)", "client.getLyrics(before)"):
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


# ---------------------------------------------------------------------------- Delete album (slice 4)

DELETE_PAGE = EDIT / "DeletePage.swift"
LIBRARY_MODEL = EDIT.parent / "Models" / "LibraryModel.swift"
ROUTES = EDIT.parent / "Shared" / "Routes.swift"


def test_delete_album_is_a_page_of_the_phones_own():
    sheet = code(SHEET)
    assert "case delete" in sheet
    view = declared(sheet, "struct", "EditPageView")
    assert "DeletePage(model: model, album: album)" in view
    sections = body(declared(sheet, "struct", "EditAlbumRoot"), "private func albumSections(")
    row = body(sections, "if edit.delete {")
    assert "NavigationLink(value: EditPage.delete)" in row and "Text(EditWords.deleteAlbum)" in row
    assert ".foregroundStyle(Palette.danger)" in row
    # under Look after the library's gate alone: Edit albums alone has no Delete album… (check 338), Look after the
    # library alone only it (342)
    assert sections.index("if edit.editors, let retag = model.retag {") < sections.index("if edit.delete {")
    assert "webURL" not in sheet and "inWebAppLine" not in sheet


def test_the_page_says_what_goes_and_who_holds_it_as_the_dialog_does():
    page = declared(code(DELETE_PAGE), "struct", "DeletePage")
    # read live as the page opens - and for the folder followed to, and back in reach - never kept
    assert '.task(id: "\\(album.path)|\\(model.online)") { await model.readDeletion() }' in page
    assert "if delete.reading {" in page and "Text(DeleteWords.checking)" in page
    assert "Text(DeleteWords.counts(summary))" in page
    assert "if let others = DeleteWords.others(summary) {" in page and "Text(others.lead)" in page
    assert "Text(others.names)" in page
    assert "if let holders = DeleteWords.holders(summary) {" in page
    assert "if let failure = delete.readFailure {" in page and "Task { await model.readDeletion() }" in page
    assert "Text(DeleteWords.warning)" in page and "Text(DeleteWords.title)" in page
    assert ".navigationTitle(DeleteWords.page)" in page


def test_delete_permanently_asks_first_with_cancel_the_default():
    page = declared(code(DELETE_PAGE), "struct", "DeletePage")
    button = body(page, "Button(role: .destructive) {")
    # the question keeps the folder and the summary it was raised over (review, 16 Nov) - nothing deleted from here
    assert "if let summary = delete.summary { asking = (album.path, summary) }" in button
    assert "model.delete(" not in button
    assert "@State private var asking: (path: String, summary: DeletionSummary)?" in page
    assert "delete.deleting ? DeleteWords.deleting : DeleteWords.confirm" in page
    assert ".disabled(!model.canDelete)" in page
    dialog = page[page.index(".confirmationDialog(DeleteWords.question(album.album),"):]
    assert "isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })" in dialog
    assert "titleVisibility: .visible, presenting: asking) { asked in" in dialog
    assert "Button(DeleteWords.delete, role: .destructive) {" in dialog
    assert "Task { await model.delete(path: asked.path, summary: asked.summary) }" in dialog
    assert "Button(DeleteWords.cancel, role: .cancel) {}" in dialog
    assert "Text(DeleteWords.noUndo)" in dialog
    # followed to another folder while it is up: put away
    assert ".onChange(of: album.path) { asking = nil }" in page
    # a delete that never answered is said over the page, and a read that failed after it with Look again - as is
    # any read Delete waits for that couldn't be made, the Release's or Tags' (review, 16 Nov)
    assert "if delete.mayHaveFinished {" in page and "MayHaveFinished(reading: model.scan.reading)" in page
    assert "if model.readBlocking != nil || (delete.mayHaveFinished && model.scan.failure != nil) {" in page
    assert "ReadAgainFailed(model: model)" in page
    assert "if let failure = delete.failure {" in page


def test_a_delete_is_a_write_never_beside_another():
    edit = code(MODEL)
    can = body(edit, "var canDelete: Bool")
    for part in ("online", "let album", "!writing", "!marking", "!scan.reading", "retag?.flow.needsRead != true",
                 "tags?.flow.needsRead != true", "deletion.canDelete(album.path)"):
        assert part in can, part
    assert "var deleting: Bool { deletion.deleting }" in edit
    for name in ("func apply()", "func saveCoverOnly()", "func applyTags()"):
        assert "!deleting," in body(edit, name), name
    assert "!deleting" in body(edit, "private func mark(")
    release = code(RELEASE)
    assert ".disabled(!retag.canApply || model.tagsApplying || model.getting || model.deleting)" in release


def test_a_delete_holds_a_background_task_and_settles_one_that_never_answered():
    edit = code(MODEL)
    delete = body(edit, "func delete(path: String, summary: DeletionSummary)")
    assert "guard canDelete, let client, let before = album," in delete
    assert "deletion.beginDelete(path, over: summary, holding: before.path) else { return }" in delete
    # decided before the folder goes, as the web's dialog is given it
    assert delete.index("AlbumEdit.deletesAll(folders, tracks: before.trackCount, subject)") < delete.index(
        "client.deleteAlbum(path: before.path)")
    assert "BackgroundHold(named:" in delete and "defer { hold.end() }" in delete
    assert "outcome = RetagFlow.outcome(of: error)" in delete
    assert "said = EditWords.writeFailure(error, failed: DeleteWords.failed, admin: admin)" in delete
    assert delete.index("guard samePerson else { return }") < delete.index("gone(before, all: all)")
    unanswered = delete[delete.index("case .unanswered:"):]
    for part in ("EditWords.mayHaveFinished", "retag?.folderChanged()", "tags?.folderChanged()",
                 "unansweredDelete = (before, all)", "await lookUp()"):
        assert part in unanswered, part
    # the next read that lands says whether it went: gone from a scan that read the library - else read it again
    look = body(edit, "func lookUp()")
    assert "DeleteFlow.went(answer, path: pending.before.path)" in look
    assert "deletion.settled(gone: went)" in look and "gone(pending.before, all: pending.all)" in look
    assert look.index("deletion.settled(gone: went)") < look.index("await readDeletion()")
    read = body(edit, "func readDeletion()")
    assert "APIFailure.isCancellation(error)" in read and "deletion.readCancelled(ticket)" in read
    assert "EditWords.said(error, failed: DeleteWords.readFailed, admin: admin)" in read


def test_once_gone_the_sheet_closes_the_page_goes_back_and_the_library_asks_again():
    edit = code(MODEL)
    gone = body(edit, "private func gone(")
    assert "deleted = true" in gone and "DeleteWords.deleted(before.path)" in gone
    assert gone.count("library?.albumDeleted()") == 2 and "AlbumEdit.settleMs" in gone
    assert "guard self.samePerson else { return }" in gone
    assert "navigation?.leaveAlbum(id)" in body(gone, "if all {") and "wrote(before: before)" in gone
    sheet = code(SHEET)
    view = declared(sheet, "struct", "EditAlbumSheet")
    assert ".onChange(of: model?.deleted == true) { _, gone in" in view
    # (Phase 8, slice 6) anywhere but Needs a look's queue the sheet closes; there it stays, saying so, the queue going on
    gone_view = block(view, view.index("{", view.index(".onChange(of: model?.deleted == true)")))
    assert "guard gone else { return }" in gone_view and "if request.queue != nil {" in gone_view
    assert gone_view.index("path.removeAll()") < gone_view.index("dismiss()")
    assert "@Environment(LibraryModel.self) private var library" in view
    # the page beneath goes back only while it is what shows (App.tsx's `else if (showing) router.back()`)
    navigation = declared(code(ROUTES), "class", "AppNavigation")
    leave = body(navigation, "func leaveAlbum(")
    assert "if case .album(let shown)? = stack.last, shown.id == id { stack.removeLast() }" in leave
    assert "switch tab {" in leave
    library = body(code(LIBRARY_MODEL), "func albumDeleted()")
    assert "index.forget(.store)" in library and "index.forget(.yours)" in library
    assert "guard server.access.hasLibrary else { return }" in library and "await askMine()" in library
