"""
Edit album's Tags, Artwork, Lyrics and Delete in the redesign's look (slice R11 - notes/ios.md "The redesign, slice
R11: Tags, Artwork, Lyrics and Delete"; the drawings Main.dc.html, iEditTags, iEditArtwork, iEditLyrics and
iEditDelete): every part a tab on both devices. On the phone the root's strip shows each under it, flat, its action in
the foot (Tags' Select all and Edit N tracks…, Delete's Delete permanently; Artwork's and Lyrics' Gets inline, as their
drawings have them); on the Mac each tab a view of its own in the editor, MacEditFooter taking Tags' Revert and Apply
and Delete's Delete permanently.

The app's Swift read as text, as the other look tests read it:

- Only the ticked rows count: Edit N tracks…, the Mac's legend and Apply to N tracks are each EditAlbumPage.ticked's of
  the folder's tracks, and what is edited is EditAlbumPage.tagTargets' (Core's rules - EditAlbumPageTests).
- The library's writers as they were: each Apply and each Get the model's own call in the tap, no plan sent; getting a
  cover chooses nothing; Delete permanently asks first on both devices, in DeleteButton's one question - nothing deletes
  but the question's Delete.
- The lyrics line is the album's as the editor holds it - read again after Get lyrics wrote - and no track's lyrics
  state is drawn: which track has lyrics is no fact the app can have.
- The phone is flat (R1c): only what the drawings give a face or a line - a picture's face, the disc's; Edit tags'
  fields on the look's wells (R1c's typing rule, test_ios_phone_look's TEXT_INPUTS).
- DWCheckbox, the look's (R1's MacCheckbox made for both): dw.css's 13 on the Mac, 20 on the phone.
- Tokens only in what this slice drew; "Queue", never "Up Next".
"""

import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_parts_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")
phone_look = _load("test_ios_phone_look")
mac_look = _load("test_ios_mac_look")


def bare(text: str) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(text)[1]


def kept(text: str) -> str:
    """The source with its comments blanked, its literals kept."""
    return reader.views(text)[0]


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def body(code: str, start: str) -> str:
    """The text from `start` to the end of the declaration it opens, by its braces."""
    at = code.index(start)
    opened = code.index("{", at)
    return code[at:reader.closing(code, opened) + 1]


def source(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


SHEET = "Edit/EditAlbumSheet.swift"
TAGS = "Edit/TagsPages.swift"
ART = "Edit/ArtworkLyricsPages.swift"
DELETE = "Edit/DeletePage.swift"
CHECKBOX = "Look/DWCheckbox.swift"
EDITOR = "Mac/Edit/MacAlbumEditor.swift"
FOOTER = "Mac/Edit/MacEditFooter.swift"
MAC_TAGS = "Mac/Edit/MacTagsTab.swift"
MAC_ART = "Mac/Edit/MacArtworkTab.swift"
MAC_LYRICS = "Mac/Edit/MacLyricsTab.swift"
MAC_DELETE = "Mac/Edit/MacDeleteTab.swift"
PHONE_FILES = (TAGS, ART, DELETE)
MAC_FILES = (FOOTER, MAC_TAGS, MAC_ART, MAC_LYRICS, MAC_DELETE)


# ----------------------------------------------------------------------------- every part a tab

def test_every_part_is_a_tab_on_both_devices():
    root = flat(body(bare(source(SHEET)), "struct EditAlbumRoot: View {"))
    # the phone: the strip's tab shown under it, each part's own view, no page of a part pushed
    for case, view in (("release", "ReleaseCards(model: model, retag: retag)"),
                       ("tags", "TagsListView(model: model, tags: tags, path: $path)"),
                       ("artwork", "ArtworkPage(model: model, album: album) { tab = .release }"),
                       ("lyrics", "LyricsPage(model: model, album: album)"),
                       ("delete", "DeletePage(model: model, album: album)")):
        assert view in root, case
    page = flat(body(bare(source(SHEET)), "enum EditPage: Hashable {"))
    assert re.findall(r"\bcase (\w+)", page) == ["chooseRelease", "compareCovers", "changes", "chooseFolder", "track",
                                                 "editTags"]
    # the Mac: each tab its own view, R10's card and its sheet gone
    editor = flat(bare(source(EDITOR)))
    for view in ("MacReleaseTab(model: model, retag: retag, twoColumns: layout.twoColumns)",
                 "MacTagsTab(model: model, tags: tags, twoColumns: layout.twoColumns)",
                 "MacArtworkTab(model: model, album: album, twoColumns: layout.twoColumns, "
                 "compare: { sheet = .compareCovers }, showRelease: { tab = .release })",
                 "MacLyricsTab(model: model, album: album)", "MacDeleteTab(model: model, album: album)"):
        assert view in editor, view
    for gone in ("partCard", "partSummary", "partPath", "case part(", "MacEditSheet.page("):
        assert gone not in editor, gone
    assert re.findall(r"\bcase (\w+)", body(bare(source(EDITOR)), "enum MacEditSheet")) == ["compareCovers"]


def test_each_tabs_action_is_in_its_foot():
    root = flat(body(bare(source(SHEET)), "struct EditAlbumRoot: View {"))
    # the phone: Release's, Tags' and Delete's feet - Delete's the red one; Artwork's and Lyrics' Gets inline
    assert ".phoneFoot { TagsFoot(model: model, tags: tags, path: $path) }" in root
    assert (".phoneFoot { DeleteButton(model: model, album: album) "
            ".buttonStyle(DWButtonStyle(kind: .danger, size: .large, fills: true)) }") in root
    assert "case .artwork, .lyrics: page" in root
    foot = flat(body(bare(source(TAGS)), "struct TagsFoot: View {"))
    assert ".buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))" in foot
    # the Mac: the foot's actions by the tab shown - Tags' Revert and Apply, Delete's Delete permanently
    footer = flat(bare(source(FOOTER)))
    assert ("switch part { case .release: if let retag = model.retag { release(retag) } "
            "case .tags: if let tags = model.tags { self.tags(tags) } "
            "case .delete: DeleteButton(model: model, album: album) .buttonStyle(DWButtonStyle(kind: .danger)) "
            "case .artwork, .lyrics: EmptyView() }") in footer
    # its line the tab's (Main.dc.html's `foots`) - Delete's who holds the album, short (R11's review: the whole
    # sentence is the tab's own row, test_the_macs_delete_says_what_goes_and_who_holds_it_whole)
    assert ("part == .delete ? EditAlbumPage.deleteFoot(model.deletion.summary) : EditAlbumPage.Words.foot(part)"
            in flat(kept(source(FOOTER))))
    assert ".lineLimit(2) .fixedSize(horizontal: false, vertical: true) .help(note)" in footer
    drawing = (Path.home() / "Desktop/Code/deadwax-plans/mac-redesign/Main.dc.html")
    if drawing.exists():
        words = drawing.read_text(encoding="utf-8")
        page = (CORE / "EditAlbumPage.swift").read_text(encoding="utf-8")
        for name in ("release", "tags", "artwork", "lyrics"):
            said = re.search(rf"{name}: '([^']+)'", words[words.index("const foots"):]).group(1)
            assert f'"{said}"' in page, (name, said)


# ----------------------------------------------------------------------------- only the ticked rows count

def test_only_the_ticked_rows_are_counted_and_edited():
    # the phone's foot: Edit N tracks… of the rows ticked, the tracks edited the ticked ones (every track with none)
    foot = flat(body(bare(source(TAGS)), "struct TagsFoot: View {"))
    assert "Text(TagEditWords.editTracks(EditAlbumPage.ticked(names, tags.selection)))" in foot
    assert "open(EditAlbumPage.tagTargets(names, ticked: tags.selection))" in foot
    assert "let all = EditAlbumPage.allTicked(names, tags.selection)" in foot
    # the Mac's legend and Apply to N tracks the same count; a tick sets the editor to the ticked tracks
    tab = flat(bare(source(MAC_TAGS)))
    assert "let ticked = EditAlbumPage.ticked(names, tags.selection)" in tab
    assert "MacGroupBox(legend: EditAlbumPage.Words.editLegend(ticked))" in tab
    choose = flat(body(bare(source(MAC_TAGS)), "private func choose("))
    assert choose.startswith("private func choose(_ next: Set<String>, names: [String], discard: Bool = false) "
                             "{ let targets = EditAlbumPage.tagTargets(names, ticked: next)")
    assert "tags.selection = next tags.edit(targets)" in choose
    footer = flat(body(bare(source(FOOTER)), "@ViewBuilder private func tags(_ tags: TagsModel) -> some View {"))
    assert ("EditAlbumPage.Words.applyTo(ticked: EditAlbumPage.ticked(names, tags.selection), of: names.count)"
            in footer)
    # nothing else counts the tracks for a button's words
    for name in (TAGS, MAC_TAGS, FOOTER):
        code = bare(source(name))
        assert not re.search(r"editTracks\((?!EditAlbumPage\.ticked)|applyTo\(ticked: (?!EditAlbumPage\.ticked)|"
                             r"editLegend\((?!ticked\))", code), name
        assert "selection.count" not in code, name


def test_a_tick_over_typed_work_asks_first_and_a_read_never_puts_it_away():
    tab = flat(bare(source(MAC_TAGS)))
    choose = flat(body(bare(source(MAC_TAGS)), "private func choose("))
    # (R11's review) Core's rule (EditAlbumPage.asksFirst, EditAlbumPageTests) - and with a sheet up, the pick waits
    # for the sheet to have gone
    assert ("if !discard && EditAlbumPage.asksFirst(names, ticked: next, editing: tags.editing, typed: tags.unsaved) "
            "{ if everyTag != nil { picked = next } else { discarding = next } return }") in choose
    assert ("Button(EditWords.discard, role: .destructive) { if let next = discarding "
            "{ choose(next, names: fileNames, discard: true) } }") in tab
    assert "Button(EditWords.keepEditing, role: .cancel) {} .returnCancels()" in tab
    # the editor follows a read by Core's rule (EditAlbumPage.afterRead): as the files are read, and as typed work
    # is put back - typed work never put away by a read
    assert ".onChange(of: names, initial: true) { (_: [String], now: [String]) -> Void in follow(now) }" in tab
    assert ".onChange(of: tags.unsaved) { (_: Bool, _: Bool) -> Void in follow(fileNames) }" in tab
    follow = flat(body(bare(source(MAC_TAGS)), "private func follow("))
    assert ("switch EditAlbumPage.afterRead(now, ticked: tags.selection, editing: tags.editing, typed: tags.unsaved) "
            "{ case .keep, .stranded: break case .edit(let targets): tags.edit(targets) "
            "case .tick(let held): tags.selection = held }") in follow
    # the ticks off while a write runs - (M3) VoiceOver's Select too, never ticking while busy
    assert "let busy = tags.flow.applying || model.writing" in tab and ".disabled(busy)" in tab
    voice = flat(body(bare(source(MAC_TAGS)), "private func voice("))
    assert ("let toggle = MacRowAction(words: ticked ? EditAlbumPage.Words.deselect : TagEditWords.select) "
            "{ if !busy { tick(file.filename, names: names) } }") in voice
    assert voice.count("tick(") == 1


def test_the_macs_editor_says_typed_work_a_rename_stranded_and_never_drops_it():
    # (R11's review) a release applied renaming every track the typed work was for: the editor says so with Discard -
    # never an empty box; Discard (or Revert) the one way the typed work goes
    editor = flat(body(bare(source(MAC_TAGS)), "@ViewBuilder private func editorBox("))
    stranded = editor[editor.index("} else if EditAlbumPage.afterRead(names, ticked: tags.selection, editing: "
                                   "tags.editing, typed: tags.unsaved) == .stranded {"):]
    assert "Text(EditAlbumPage.Words.editedGone) .foregroundStyle(DWPalette.amberText)" in stranded
    assert ("Button(EditWords.discard) { tags.edit(EditAlbumPage.tagTargets(names, ticked: tags.selection)) } "
            ".buttonStyle(DWButtonStyle(size: .small)) .disabled(tags.flow.applying || model.writing)") in stranded
    assert editor.index("} else if tags.ready {") < editor.index("== .stranded {")
    # TagsModel unchanged: its read keeps of the ticks and the tracks edited only the names the folder holds
    model = flat(body(bare(source("Edit/TagsModel.swift")), "func readFiles() async {"))
    assert "selection = selection.filter(held) editing = editing.filter(held)" in model
    # the tracks the editor edits are set in three places only: a pick (choose), a read (follow), the stranded Discard
    # - none of them inside the sheet
    assert flat(bare(source(MAC_TAGS))).count("tags.edit(") == 3


def test_edit_this_track_is_chosen_once_the_sheet_has_gone():
    # (R11's review) Edit this track… sets the pick and puts the sheet away; the pick is chosen in the sheet's onDismiss,
    # so "Discard changes?" is raised once the sheet has gone - SwiftUI drops one raised over a sheet on its way down
    tab = flat(bare(source(MAC_TAGS)))
    sheet = tab[tab.index(".appSheet(item: $everyTag, onDismiss: {"):]
    assert sheet.startswith(".appSheet(item: $everyTag, onDismiss: { guard let next = picked else { return } "
                            "picked = nil choose(next, names: fileNames) }) { (shown: EveryTag) in")
    content = sheet[:sheet.index(".macSheet()")]
    # (M1) never the editor set from inside the sheet: tags.edit there would put typed work away unasked
    assert ("MacTrackTags(model: model, tags: tags, filename: shown.filename) { picked = [shown.filename] "
            "everyTag = nil }") in content
    assert "tags.edit(" not in content and "choose(" not in content.replace("choose(next, names: fileNames)", "")
    # (M8) Edit this track… off while a write runs
    head = flat(body(bare(source(MAC_TAGS)), "private func head("))
    assert ("Button(TrackInspector.editThis, action: editThis) .buttonStyle(DWButtonStyle(size: .small)) "
            ".disabled(model.writing || tags.flow.applying)") in head
    # (M12) See a file's every tag… only with a row selected
    assert ("Button(EditAlbumPage.Words.seeEveryTag) { if let selected { everyTag = EveryTag(filename: selected) } } "
            ".buttonStyle(DWButtonStyle(size: .small)) .disabled(selected == nil)") in tab


def test_discard_changes_is_held_only_while_it_can_show():
    tab = flat(bare(source(MAC_TAGS)))
    # put away by the dialog itself, by a sheet coming up, and (M9) by the tab's model held anew - with the pick
    assert ("isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } })") in tab
    assert ".onChange(of: everyTag?.id) { (_: String?, now: String?) -> Void in if now != nil { discarding = nil } }" in tab
    assert (".onChange(of: ObjectIdentifier(tags)) { (_: ObjectIdentifier, _: ObjectIdentifier) -> Void in "
            "everyTag = nil discarding = nil picked = nil }") in tab
    # set in one place, choose's - only with no sheet up
    assert tab.count("discarding = next") == 1
    assert tab.count("picked = next") == 1 and tab.count("picked = [shown.filename]") == 1
    # the names a question is answered with read when it is answered, never the body's from before
    names = flat(body(bare(source(MAC_TAGS)), "private var fileNames: [String] {"))
    assert "(tags.files ?? []).map" in names


# ----------------------------------------------------------------------------- the writers, as they were

def test_each_write_is_the_models_own_and_sends_no_plan():
    footer = flat(bare(source(FOOTER)))
    phone = flat(body(bare(source(TAGS)), "struct EditTagsView: View {"))
    # Tags' Apply: the model's applyTags in the tap, nothing awaited before it, on as the phone's is
    gate = ".disabled(!tags.canApply || model.writing || model.marking)"
    assert "Button { Task { await model.applyTags() } } label:" in footer and gate in footer
    assert "Task { await model.applyTags() }" in phone and gate in phone
    # Revert: every field typed over put back as the files say, by Revert's button alone
    assert ("Button(EditAlbumPage.Words.revert) { for key in tags.draft.keys.sorted() { tags.revert(key) } } "
            ".buttonStyle(DWButtonStyle()) .disabled(!tags.unsaved || tags.flow.applying)") in footer
    for name in PHONE_FILES + MAC_FILES + (SHEET, EDITOR):
        code = bare(source(name))
        for word in ("beginApply", "TagEditBody(", "RetagRequestBody", "CoverFetchBody", "DeleteAlbumBody"):
            assert word not in code, (name, word)
        assert not re.search(r"\bclient\??\.(tagsApply|tagsPreview|fetchCover|getCover|getLyrics|getDiscArt|"
                             r"deleteAlbum|retagApply)\(", code), name
        assert not re.search(r"\b(model|client|tags)\??(\.\w+)*\([^)]*\bplan\b", code), name
    # each Get the model's, one button for every device (GetButton): getting a cover chooses nothing
    get = flat(body(bare(source(ART)), "struct GetButton: View {"))
    assert "Button { Task { await model.get(kind) } } label:" in get and ".disabled(!model.canGet)" in get
    for name in (ART, MAC_ART, MAC_LYRICS):
        code = bare(source(name))
        assert "model.get(" not in code.replace("Task { await model.get(kind) }", ""), name
        assert "setFetchArt" not in code and "retag?.choose" not in code and ".select(" not in code, name


def test_delete_asks_first_on_both_devices_with_every_guard():
    # one Delete permanently, DeleteButton's: both feet draw it, nothing else deletes
    button = flat(body(bare(source(DELETE)), "struct DeleteButton: View {"))
    assert "Button(role: .destructive) { if let summary = delete.summary { asking = (album.path, summary) } }" in button
    assert ".disabled(!model.canDelete)" in button
    assert "Task { await model.delete(path: asked.path, summary: asked.summary) }" in button
    assert button.count("model.delete(") == 1
    root = flat(bare(source(SHEET)))
    footer = flat(bare(source(FOOTER)))
    assert root.count("DeleteButton(model: model, album: album)") == 1
    assert footer.count("DeleteButton(model: model, album: album)") == 1
    for name in (SHEET, FOOTER, MAC_DELETE, EDITOR, TAGS, ART):
        assert "model.delete(" not in bare(source(name)), name
    assert "func delete(path:" not in bare(source(DELETE))
    # the guards the model holds, as they were: on only for this folder's summary, never beside another write
    model = flat(body(bare(source("Edit/EditAlbumModel.swift")), "var canDelete: Bool {"))
    for part in ("online", "!writing", "!marking", "!scan.reading", "deletion.canDelete(album.path)"):
        assert part in model, part
    # each device's tab reads what goes live, for the folder shown
    for name in (DELETE, MAC_DELETE):
        code = flat(kept(source(name)))
        assert '.task(id: "\\(album.path)|\\(model.online)") { await model.readDeletion() }' in code, name
        assert "Text(DeleteWords.warning) .foregroundStyle(DWPalette.redChipText)" in code, name
    # the red words are dw.css's `.dw .red`
    red = mac_look.colours(mac_look.rule(".red")["color"])
    palette = (APP / "Look" / "DWPalette.swift").read_text(encoding="utf-8")
    token = re.search(r"static let redChipText = hex\(0x([0-9a-f]{6})\)", palette).group(1)
    assert red == [(int(token[0:2], 16), int(token[2:4], 16), int(token[4:6], 16), 1.0)]
    # after a delete on the Mac, the album's pages leave every stack (R10's leaveAlbum, held by test_ios_edit_look)
    assert "if all { navigation?.leaveAlbum(id) }" in flat(bare(source("Edit/EditAlbumModel.swift")))


def test_the_macs_delete_says_what_goes_and_who_holds_it_whole():
    tab = flat(bare(source(MAC_DELETE)))
    # (R11's review) the well: the counts, then deadwax's "and 40 other files:" in the caution's colour over the names
    well = tab[tab.index("if let summary = delete.summary {"):]
    assert ("VStack(alignment: .leading, spacing: 3) { Text(DeleteWords.counts(summary)) "
            ".foregroundStyle(DWPalette.text) if let others = DeleteWords.others(summary) { Text(others.lead) "
            ".foregroundStyle(DWPalette.amberText) Text(others.names) .foregroundStyle(DWPalette.t2) } }") in well
    assert ".background { DWWell(focused: false) }" in well
    # who holds it, the whole sentence, a row of the tab's own - the foot's is short
    assert ("if let holders = DeleteWords.holders(summary) { Text(holders) .foregroundStyle(DWPalette.amberText) "
            ".fixedSize(horizontal: false, vertical: true) }") in well
    assert well.index("DWWell(focused: false)") < well.index("DeleteWords.holders(summary)") < well.index(
        "Text(DeleteWords.warning)")
    assert "deleteFacts" not in tab and "lineLimit" not in tab
    footer = flat(bare(source(FOOTER)))
    assert "DeleteWords.holders" not in footer


def test_a_folder_openings_delete_closes_the_albums_pages_by_what_the_folder_holds():
    # (R11's review, from R10) opened by its folder - Choose the folder, the Mac's folder list, Needs a look - the
    # album's pages are found by the folder (EditAlbumPage.folderPages, EditAlbumPageTests): decided as the delete
    # starts, from the scan as it was and the id bridge's answer for the folder's release
    model = flat(bare(source("Edit/EditAlbumModel.swift")))
    delete = flat(body(bare(source("Edit/EditAlbumModel.swift")), "func delete(path: String, summary: DeletionSummary)"))
    assert ("folderPages = subject != nil ? nil : EditAlbumPage.folderPages( before.path, tracks: before.trackCount, "
            "bridge: folderBridge?.path == before.path ? folderBridge?.answer : nil, scan: scan.albums, "
            "pages: openAlbums)") in delete
    assert delete.index("EditAlbumPage.folderPages(") < delete.index("client.deleteAlbum(path: before.path)")
    # the bridge asked by the folder's release as Delete's summary is read - only for a folder opening, kept with
    # the folder it was for (no new route: the release's id bridge, as Done's rows ask it)
    read = flat(body(bare(source("Edit/EditAlbumModel.swift")), "func readDeletion() async {"))
    assert "deletion.read(ticket, summary) await askFolderBridge(album)" in read
    ask = flat(body(bare(source("Edit/EditAlbumModel.swift")), "private func askFolderBridge("))
    assert ask.startswith("private func askFolderBridge(_ album: ScanAlbum) async { guard subject == nil, let client")
    assert "guard let release = EditAlbumPage.bridgeRelease(album) else { folderBridge = nil return }" in ask
    assert "try? await client.storeAlbum(releaseMbid: release)" in ask
    assert "guard self.album?.path == album.path else { return } folderBridge = (album.path, found)" in ask
    # every stack's album pages, as each was opened
    pages = flat(body(bare(source("Edit/EditAlbumModel.swift")), "private var openAlbums: [AlbumEdit.Subject] {"))
    assert "(navigation.library + navigation.search + navigation.requests + navigation.you)" in pages
    assert ("AlbumEdit.Subject(id: shown.id, name: shown.name ?? \"\", artist: shown.artist, "
            "musicBrainzId: shown.musicBrainzId)") in flat(kept(source("Edit/EditAlbumModel.swift")))
    # once gone: an album opening's page as before; a folder opening's pages left or asked again
    gone = flat(body(bare(source("Edit/EditAlbumModel.swift")), "private func gone("))
    assert "guard let id = pageId else { leaveFolderPages() return }" in gone
    leave = flat(body(bare(source("Edit/EditAlbumModel.swift")), "private func leaveFolderPages() {"))
    assert "guard let pages = folderPages else { return } folderPages = nil" in leave
    assert "for id in pages.leave { navigation?.leaveAlbum(id) }" in leave
    assert "for id in pages.ask { navigation?.albumWritten(id) }" in leave
    assert "AlbumEdit.settleMs" in leave and "guard self.samePerson else { return }" in leave
    assert model.count("leaveFolderPages()") == 2


def test_the_phones_tags_row_is_one_element_and_its_foot_fits():
    row = flat(body(bare(source(TAGS)), "struct TagTrackRow: View {"))
    # (R11's review) the whole row one element, a toggle: a double-tap ticks it, See a file's every tag… its named
    # action - the › no element of its own
    outer = row[row.index(".overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }"):]
    assert outer.startswith(".overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) } "
                            ".accessibilityElement(children: .ignore) "
                            ".accessibilityLabel(TagEditWords.trackRow(label: label, title: title, artist: artist)) "
                            ".accessibilityValue(TrackInspector.trackTime(file.length)) "
                            ".accessibilityAddTraits(ticked ? [.isToggle, .isSelected] : .isToggle) "
                            ".accessibilityAction { toggle() } "
                            ".accessibilityAction(named: EditAlbumPage.Words.seeEveryTag) "
                            "{ path.append(.track(file.filename)) } }")
    assert row.count(".accessibility") == 6, "nothing inside the row says anything of its own"
    assert "Button { toggle() } label:" in row
    # the foot: side by side while both fit, one over the other at the largest size PhoneFoot gives (xxxLarge)
    foot = flat(body(bare(source(TAGS)), "struct TagsFoot: View {"))
    assert ("ViewThatFits(in: .horizontal) { HStack(spacing: CGFloat(PhoneLook.footGap)) { selectButton(names) "
            "editButton(names) } VStack(spacing: CGFloat(PhoneLook.footGap)) { selectButton(names) editButton(names) } "
            ".padding(.vertical, CGFloat(PhoneLook.footGap)) }") in foot
    # (M5) Select all ticks every track, Deselect all none (EditAlbumPage.selectAll, EditAlbumPageTests)
    assert "tags.selection = EditAlbumPage.selectAll(names, tags.selection)" in foot
    assert foot.count("tags.selection =") == 1
    # (M2) Edit N tracks… off while a write runs
    assert ("Text(TagEditWords.editTracks(EditAlbumPage.ticked(names, tags.selection))) } "
            ".buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true)) "
            ".disabled(names.isEmpty || model.writing)") in foot
    # an accessibility size never reaches a foot's words (PhoneFoot stops at xxxLarge): no line limit claims one
    assert ".dynamicTypeSize(...DynamicTypeSize.xxxLarge)" in flat(bare(source("Phone/PhoneFoot.swift")))
    for name, start in ((TAGS, "struct TagsFoot: View {"), (DELETE, "struct DeleteButton: View {"),
                        (TAGS, "private var applyButton: some View {")):
        part = flat(body(bare(source(name)), start))
        assert "isAccessibilitySize" not in part and "lineLimit" not in part, (name, start)


def test_the_cover_pointer_names_compare_only_while_release_shows_it():
    # (R11's review) the pointer shows only where Artwork offers no Compare - Release's own condition - so it names
    # Release's button only while Release shows it (EditAlbumPage.coverPointer, EditAlbumPageTests)
    mac = flat(bare(source(MAC_ART)))
    assert ("if !compares, let pointer = EditAlbumPage.coverPointer(album, compare: ArtworkLooks.releaseCompares(model) "
            "? EditAlbumPage.Words.compareFullSize : nil) {") in mac
    assert "GetResults.webCoverPointer(" not in mac and "phoneCoverPointer" not in mac
    phone = flat(bare(source(ART)))
    assert "phoneCoverPointer" not in phone and "GetResults.webCoverPointer(" not in phone
    # Release's Compare, on each device, shown by that very condition
    for name in ("Edit/ReleasePage.swift", "Mac/Edit/MacReleaseTab.swift"):
        assert "if retag.coverRelease != nil {" in bare(source(name)), name
    # (R11's review) the phone's CD art 112 across, as the notes and the drawing say - each disc framed, its cell no
    # wider; the Mac's 150
    assert ("LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.side, maximum: Self.side), spacing: 14, "
            "alignment: .top)],") in phone
    assert "DiscArtPicture(path: album.path, file: name) .frame(width: Self.side, height: Self.side)" in phone
    assert "private static let side: CGFloat = 112" in phone
    assert "DiscArtPicture(path: album.path, file: name) .frame(width: Self.side, height: Self.side)" in mac


# ----------------------------------------------------------------------------- Lyrics

def test_the_lyrics_line_is_the_albums_as_the_editor_holds_it_and_no_track_is_drawn():
    for name, start in ((ART, "struct LyricsPage: View {"), (MAC_LYRICS, "struct MacLyricsTab: View {")):
        view = flat(body(bare(source(name)), start))
        # the count the album's, handed down from the model each draw - never a copy kept by the view
        assert "let album: ScanAlbum" in view and "@State" not in view, name
        assert "Text(GetResults.lyricsLine(album.lyricsCount, album.trackCount))" in view, name
        # no Each track list: no track's lyrics state is a fact the app has
        assert "ForEach" not in view and "tags" not in view and "files" not in view, name
        assert "GetButton(model: model, kind: .lyrics, trackCount: album.trackCount," in view, name
    # each device's tab handed the album the model holds, which Get lyrics reads again once it has written
    assert "case .lyrics: LyricsPage(model: model, album: album)" in flat(bare(source(SHEET)))
    assert "case .lyrics: MacLyricsTab(model: model, album: album)" in flat(bare(source(EDITOR)))
    get = flat(body(bare(source("Edit/EditAlbumModel.swift")), "func get(_ kind: GetResults.Kind) async {"))
    assert get.index("guard run.wrote else { return }") < get.index("await lookUp()")


# ----------------------------------------------------------------------------- the phone is flat

FLAT = {
    # the list's hairline over its first row (iEditTags' `.list`) and each row's; the track page's black, its fields'
    # and its tags' hairlines, a picture's empty square on the card's face (a picture's, R1c) and its hairline; Edit
    # tags' black and its fields' rows' hairline
    TAGS: ["DWRule: DWPalette.rowRule", "DWRule: DWPalette.rowRule", "background: DWPalette.page",
           "DWRule: DWPalette.groupRule", "DWRule: DWPalette.groupRule", "ZStack: DWPalette.card",
           "DWRule: DWPalette.groupRule", "background: DWPalette.page", "DWRule: DWPalette.groupRule"],
    # the cover's empty square (a picture's face); a wait's hairline; the empty disc and its hole, a picture's face
    ART: ["fill: DWPalette.card", "DWRule: DWPalette.groupRule", "fill: DWPalette.card", "strokeBorder: DWPalette.line",
          "fill: DWPalette.panel", "strokeBorder: DWPalette.line"],
    # the reading row's hairline; (R11's review) what else goes, its row's
    DELETE: ["DWRule: DWPalette.groupRule", "DWRule: DWPalette.groupRule"],
}


def test_the_phone_is_flat_in_the_parts():
    found = {name: phone_look.drawn(phone_look.phone_path(bare(source(name)))) for name in PHONE_FILES}
    assert found == FLAT, {name: draws for name, draws in found.items() if draws != FLAT[name]}
    # what this slice drew: PhoneGroup's legends and PhoneCard's lines alone - no List, no Form
    for name in PHONE_FILES:
        code = bare(source(name))
        assert not re.search(r"\b(List|Form|Section)\s*[({]", code), name
        assert ".listRowBackground" not in code and "insetGrouped" not in code, name
    art = flat(bare(source(ART)))
    for legend in ("GetResults.cover", "GetResults.discArt", "GetResults.lyrics"):
        assert f"PhoneGroup(legend: {legend})" in art, legend
    assert "PhoneGroup(legend: DeleteWords.title)" in bare(source(DELETE))
    # the phone square, the disc round: the cover on the art's (square) shape, each CD art picture a circle
    assert ".clipShape(Corners.artShape)" in art and ".clipShape(Circle())" in art
    # Edit tags' fields on the look's well, Release's way (the typing rule's WELL)
    edit = flat(body(bare(source(TAGS)), "struct EditTagsView: View {"))
    assert edit.count("TextField(") == 1 and ".modifier(DWWellField(focus: $focused, field: field.key))" in edit


def test_the_checkbox_is_dw_css_on_each_device():
    code = bare(source(CHECKBOX))
    mark = flat(body(code, "struct DWCheckMark: View {"))
    mac = mac_look.rule("input[type=checkbox]")
    assert f"private static let macBox: CGFloat = {round(mac_look.px(mac['width']))}" in mark
    assert mac["width"] == mac["height"]
    css = (IOS / "design" / "dw.css").read_text(encoding="utf-8")
    phone = re.search(r"\.dw\.ph input\[type=checkbox\] \{ width: (\d+)px; height: (\d+)px; \}", css)
    assert phone and phone.group(1) == phone.group(2)
    assert f"@ScaledMetric(relativeTo: .body) private var phoneBox: CGFloat = {phone.group(1)}" in mark
    assert mac_look.colours(mac["accent-color"]) == [(0xa8, 0x55, 0xf7, 1.0)]
    assert "DWCorners.chipShape.fill(DWPalette.checkFill)" in mark
    # one element, a toggle, saying its words even where they aren't drawn
    box = flat(body(code, "struct DWCheckbox: View {"))
    assert (".accessibilityElement(children: .ignore) .accessibilityLabel(words) "
            ".accessibilityAddTraits(on ? [.isToggle, .isSelected] : .isToggle)") in box
    assert "if showsWords {" in box
    # the Mac's Release cover switch is the look's checkbox now; MacCheckbox kept for its users, none of them R11's
    # (Settings', and R14's People)
    assert "DWCheckbox(words: RetagWords.coverToggle(existing: existing)," in flat(bare(source("Mac/Edit/MacReleaseTab.swift")))
    users = [path.relative_to(APP).as_posix() for path in sorted(APP.rglob("*.swift"))
             if "MacCheckbox(" in bare(path.read_text(encoding="utf-8"))]
    assert users == ["Mac/Manage/MacPeoplePage.swift", "Mac/Settings/MacSettingsRoot.swift"], users


# ----------------------------------------------------------------------------- tokens only, the Mac's type, Queue

PHONE_FONT = re.compile(r"Typeface\.(?:Phone\.(?:text|mono)|symbol|Look\.(?:text|mono))\(")

#? what this slice drew of each phone file (the rest - Edit tags' preview words, the track page, as they were - read
#? whole too, since R11 redrew them flat)
def drawn_code(name: str) -> str:
    return bare(source(name))


def faces(fonts: list[str]) -> list[str]:
    """Each font argument, a ternary's both choices."""
    found = []
    for font in fonts:
        choice = re.fullmatch(r"[^?()]+ \? (\S+) : (\S+)", font)
        found += list(choice.groups()) if choice else [font]
    return found


def test_the_parts_draw_no_value_of_their_own():
    left = []
    for name in PHONE_FILES + MAC_FILES + (CHECKBOX,):
        code = drawn_code(name)
        for what, pattern in (("a colour made", r"\bColor\s*\(|\bUIColor\b|\bCGColor\b"),
                              ("a colour by number", r"0x[0-9a-fA-F]{6}\b"),
                              ("an opacity of its own", r"\.opacity\(\s*0?\.[0-9]"),
                              ("a radius", r"cornerRadius|RoundedRectangle\(|\bCapsule\b"),
                              ("a font of its own", r"\.system\(|\bFont\.(system|custom)\b|\.custom\(|\.monospaced")):
            if re.search(pattern, code):
                left.append(f"{name}: {what}")
        named = mac_look.NAMED_COLOUR.search(re.sub(r"\bcase \.\w+:", "", code))
        if named:
            left.append(f"{name}: a named colour ({named.group(0)})")
        old = re.search(r"(?<![\w.])Palette\.\w+", code)
        if old:
            left.append(f"{name}: the old palette ({old.group(0)})")
    assert not left, left
    for name in PHONE_FILES:
        code = drawn_code(name)
        if name == TAGS:
            # TagFileChanges draws in the faces its caller hands it (the phone's own, by its init(file:))
            changes = body(code, "struct TagFileChanges: View {")
            assert re.findall(r"\.font\((\w+)", changes) == ["mono", "words", "mono", "mono"]
            code = code.replace(changes, "")
            assert ("init(file: TagEditFile) { self.init(file: file, mono: Typeface.Phone.mono(.extraSmall), "
                    "words: Typeface.Phone.text(.small)) }") in flat(code)
        if name == ART:
            # GetButton, both devices': its line in the face its caller hands it, each device's own small type
            button = body(code, "struct GetButton: View {")
            assert re.findall(r"\.font\((\w+)", button) == ["saidFont"]
            code = code.replace(button, "")
        fonts = faces(mac_look.font_arguments(code))
        assert fonts and not [f for f in fonts if not PHONE_FONT.match(f)], (name, fonts)
    for name in MAC_FILES:
        fonts = faces(mac_look.font_arguments(drawn_code(name)))
        assert not [f for f in fonts if not mac_look.MAC_FONT.match(f)], (name, fonts)
    # every GetButton handed its device's own small type
    for name, wanted in ((ART, "Typeface.Phone.text(.extraSmall)"), (MAC_ART, "Typeface.Mac.text(.small)"),
                         (MAC_LYRICS, "Typeface.Mac.text(.small)")):
        handed = re.findall(r"saidFont: (Typeface[^)]*\))", flat(drawn_code(name)))
        assert len(re.findall(r"GetButton\(model:", flat(drawn_code(name)))) == len(handed), name
        assert handed and set(handed) == {wanted}, (name, handed)


def test_the_queue_is_the_queue():
    for name in PHONE_FILES + MAC_FILES + (CHECKBOX, SHEET, EDITOR):
        assert "Up Next" not in kept(source(name)), name
    # the app's verb is Select (TagEditWords.select): the drawings' "Tick" in no word of the page's
    page = re.sub(r"//.*", "", (CORE / "EditAlbumPage.swift").read_text(encoding="utf-8"))
    words = [re.sub(r"\\\(\w+", "", word) for word in re.findall(r'"[^"\n]*"', page)]
    assert words and not [w for w in words if re.search(r"\btick|Up Next", w, re.I)]
