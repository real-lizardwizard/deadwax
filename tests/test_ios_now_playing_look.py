"""The redesign's slice R4b (notes/ios.md "The redesign, slice R4b: Now Playing's face (2026-11-25)"): Now Playing's
face on the phone, as iNowPlaying.dc.html draws it - the model the whole flat phone was drawn from - held to dw.css
(ios/design/dw.css, the canvas's copy) where it names a value and to the drawing's numbers where only it does.

The top is the compact top (PhoneTop, `.topbar`): Close where the chevron was (the drag down still closes), the look
button named (Turntable, Cover on the turntable) and the •••, each the accent's words or glyph with no face. The cover
is 24 either side. The title, with "Artist — Album" in the accent, and beside it the readout - "3 of 11" over "FLAC
16/44.1" in Courier Prime, Core's BarDisplay's, never counted in the view - on the title's baseline, under it at the
accessibility sizes. The scrubber is sunken (a sunken track keeps its face on the flat phone), its times in Courier
Prime under it, its drag, its VoiceOver and its seek as they were. The transport, the bottom row, Lyrics in the cover's
place (James's answer 2: the bottom row's Lyrics turns them on and off) and the turntable are as they were.

The Mac has nothing of it: its frame never opens Now Playing (tests/test_ios_mac.py holds its cover-only look).

Read from the source, as every test of the app's look is: nothing here builds or runs the app (the builds and the
device checks 550-552 do)."""

import hashlib
import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios"
APP = IOS / "App"
CORE = IOS / "DeadwaxKit" / "Sources" / "DeadwaxCore"
NOW_PLAYING = APP / "Player" / "NowPlayingView.swift"
SCRUBBER = APP / "Player" / "ScrubberView.swift"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_now_playing_look_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")
phone_look = _load("test_ios_phone_look")
fonts = _load("ios_fonts")
css = phone_look.css
px = phone_look.px


def bare(path: Path) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(path.read_text(encoding="utf-8"))[1]


def code(path: Path) -> str:
    """The source with its comments blanked, its literals kept."""
    return reader.views(path.read_text(encoding="utf-8"))[0]


def member(text: str, declaration: str) -> str:
    """The body of the one member declared as `declaration` (`func topRow`, `struct NamedLookButton: View`, ...),
    its braces with it."""
    found = list(re.finditer(r"\b" + re.escape(declaration) + r"\b[^{]*\{", text))
    assert len(found) == 1, f"{declaration} is declared {len(found)} times"
    opened = found[0].end() - 1
    return text[opened:reader.closing(text, opened) + 1]


def one(text: str, pattern: str) -> float:
    found = re.findall(pattern, text)
    assert len(found) == 1, f"{pattern}: {found}"
    return float(found[0])


def flat(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


#? Dynamic Type at each size, Apple's tables (the HIG's "Specifications"): footnote (the small button's 13.5 scales
#? with it), caption (the readout's 12, `.dw.ph .xs`) and title2 (the title's 22). PhoneTop is capped at xxxLarge;
#? the readout and the title grow on, so their table runs on to the first accessibility size.
FOOTNOTE = {"xSmall": 12, "small": 12, "medium": 12, "large": 13, "xLarge": 15, "xxLarge": 17, "xxxLarge": 19}
CAPTION = {"xSmall": 11, "small": 11, "medium": 11, "large": 12, "xLarge": 13, "xxLarge": 15, "xxxLarge": 17,
           "accessibility1": 20}
TITLE2 = {"xSmall": 19, "small": 20, "medium": 21, "large": 22, "xLarge": 24, "xxLarge": 26, "xxxLarge": 28,
          "accessibility1": 34}
#? subheadline, the notice's 15 (Notice.swift's Typeface.subheadline) - capped at xxxLarge, as the top is
SUBHEADLINE = {"xSmall": 12, "small": 13, "medium": 14, "large": 15, "xLarge": 17, "xxLarge": 19, "xxxLarge": 21}
STANDARD = list(FOOTNOTE)
#? the narrower phone the app runs on (an iPhone SE, a 13 mini), the drawing's (an iPhone 14), and a 15's or 16's
NARROW, DRAWN, WIDER = 375, 390, 393

#? a face, an edge or a fill: what the flat phone draws only for the primary button, the red, a sunken track, a picture
#? and a field (R1c) - with iOS's own faces (a bordered or a material button) and a shadow
FACES = re.compile(r"\.(fill|background|strokeBorder|stroke|shadow|glassEffect)\b|\bDW(Raised|Well|Rule)\b"
                   r"|\bMaterial\b|\.bordered(Prominent)?\b|\bRoundedRectangle\b|\bCapsule\b|\bCircle\(\)"
                   r"|\bPalette\.(toggledFill|toggledEdge|pressed)\b|\bkind: \.")

#? the members of Now Playing that draw words, glyphs and buttons on the phone, each with no face
FLAT_MEMBERS = ("func topRow", "var closeButton: some View", "struct NamedLookButton: View", "func titles",
                "func coverTitles", "func coverNames", "func byline", "func coverByline",
                "struct NowPlayingReadout: View", "struct NoticeWord: View", "var transport: some View",
                "struct ModeButton: View", "func menu", "var bottomRow: some View", "func sheetItem",
                "var lyricsItem: some View", "struct EQRowItem: View", "func lyricsFace")


# ----------------------------------------------------------------------------- the top

def test_the_top_is_close_the_look_button_named_and_the_more():
    now = bare(NOW_PLAYING)
    top = member(now, "func topRow")
    # the compact top (PhoneTop, `.topbar`): Close leads it; the look button and the ••• trail it, the look button none
    # on the Mac (which has no turntable)
    parts = ("PhoneTop {", "closeButton", "} trailing: {", "HStack(spacing: gap) {", "if !Platform.mac {",
             "NamedLookButton(showingTurntable: look == .turntable, action: lookTapped)", "menu(track)")
    order = [top.index(part) for part in parts]
    assert order == sorted(order), order
    # Close: a flat small button in the accent's words, where the chevron was - Escape's on the Mac, as the chevron's
    close = flat(member(now, "var closeButton: some View"))
    assert close == ("{ Button(NowPlayingWords.close, action: close) .buttonStyle(DWButtonStyle(size: .small)) "
                     ".accessibilityShowsLargeContentViewer { Text(NowPlayingWords.close) } .escapeCloses() }"), close
    assert re.search(r'public static let close = "Close"', code(CORE / "Info.swift"))
    # the look button, named: the look a tap shows - Turntable while the cover shows, Cover on the turntable - and to
    # VoiceOver what a tap does, as before
    look = flat(member(now, "struct NamedLookButton: View"))
    assert look == ("{ let showingTurntable: Bool let action: () -> Void var body: some View { let words = "
                    "showingTurntable ? TurntableWords.lookCover : TurntableWords.lookTurntable Button(words, action: "
                    "action) .buttonStyle(DWButtonStyle(size: .small)) .accessibilityLabel(TurntableWords.lookButton("
                    "showingTurntable: showingTurntable)) .accessibilityShowsLargeContentViewer { Text(words) } } }"), look
    words = code(CORE / "TurntableWords.swift")
    assert 'lookCover = "Cover"' in words and 'lookTurntable = "Turntable"' in words
    assert 'showingTurntable ? "Show the cover" : "Show as a turntable"' in words
    # the •••: its glyph in the accent (it was the primary colour), large under a long press past the top's cap
    menu = flat(member(now, "func menu"))
    assert ".foregroundStyle(DWPalette.acc) .accessibilityShowsLargeContentViewer { Image(systemName: " in menu
    assert ".foregroundStyle(.primary)" not in menu
    # no chevron, and LookButton's glyphs are drawn nowhere in Now Playing (the turntable's files keep no diff)
    assert "chevron.down" not in code(NOW_PLAYING)
    assert not re.search(r"(?<!Named)\bLookButton\(", now)
    # the top's own room: 12 from the screen's edges, 8 between, 44 tall, capped at xxxLarge (`.dw.ph .topbar`)
    look_code = code(CORE / "DWLook.swift")
    assert one(look_code, r"public static let topSide: Double = (\d+)") == px(css(".topbar", "padding-left")) == 12
    assert one(look_code, r"public static let topGap: Double = (\d+)") == px(css(".topbar", "gap")) == 8
    assert one(look_code, r"public static let top: Double = (\d+)") == px(css(".topbar", "height")) == 44
    assert ".dynamicTypeSize(...DynamicTypeSize.xxxLarge)" in bare(APP / "Phone" / "PhoneTop.swift")


def test_the_top_row_is_the_grip_the_whole_width_and_the_drag_down_still_closes():
    now = bare(NOW_PLAYING)
    content = member(now, "func content")
    # the top row out past the column's 24 either side, to the top's own 12 from the screen's edges - its grip the
    # whole width (the contentShape and the gesture before the negative padding, so they take the widened frame)
    inset = one(content, r"\.padding\(\.horizontal, (\d+)\)\s*\.padding\(\.bottom, \d+\)\s*\}$")
    assert inset == 24
    head = flat(content[:content.index("ZStack {")])
    # (R4b's review) and drawn over what follows it, so a notice laid just under the top shows over the cover
    assert head.endswith("topRow(track) .contentShape(Rectangle()) .gesture(grip) .padding(.horizontal, -24) "
                         ".zIndex(1)"), head
    # the drag down closes Now Playing past dismissDistance, as before
    grip = flat(member(now, "var grip: some Gesture"))
    assert "DragGesture(minimumDistance: PlayerWords.dragStartDistance, coordinateSpace: .global)" in grip
    assert "if max(0, value.translation.height) > PlayerWords.dismissDistance { close() }" in grip
    assert flat(member(now, "func close")) == "{ navigation.nowPlayingShown = false }"


def top_ends(phone: float, size: str) -> tuple[float, float, float]:
    """Close's width and the look button's with the •••, at the top's own size (PhoneTop stops growing at xxxLarge),
    and the room the middle leaves the notice's words inside its padding - each from the source and the fonts."""
    typeface = (APP / "Shared" / "Typeface.swift").read_text(encoding="utf-8")
    found = re.search(r"case \.smallButton: return \(([\d.]+), \.footnote\)\s*// dw\.ph: \.btn\.sm font-size", typeface)
    assert found and float(found.group(1)) == px(css(".btn.sm", "font-size")) == 13.5
    look = code(CORE / "DWLook.swift")
    on_phone = look[look.index("static let onPhone = DWLook("):]
    on_phone = on_phone[:on_phone.index("grows: true)")]
    pad, target = one(on_phone, r"smallButtonPadding: (\d+),"), one(on_phone, r"\btarget: (\d+),")
    assert (pad, target) == (6, 44)
    side, gap = 12, 8
    points = float(found.group(1)) * FOOTNOTE[size] / FOOTNOTE["large"]
    close = max(target, fonts.words("Close", points, "medium") + 2 * pad)
    named = max(target, max(fonts.words(w, points, "medium") for w in ("Turntable", "Cover")) + 2 * pad)
    trailing = named + gap + target  # the look button, the gap, NowPlayingMenu's 44 x 44 label
    middle = phone - 2 * side - close - trailing - 2 * gap - 2 * notice_pad()
    return close, trailing, middle


def notice_pad() -> float:
    return one(bare(APP / "Shared" / "Notice.swift"), r"\.padding\(\.horizontal, (\d+)\)")


def notices() -> list[str]:
    """What the notice says over Now Playing, from Core's own words: the •••'s downloads, Play Next and Play Last, a
    download removed - and the review's "Downloading"."""
    downloads = code(CORE / "DownloadWords.swift")
    assert 'func downloadingSong(_ title: String) -> String { "Downloading: \\(title)" }' in downloads
    assert '{ "Downloading \\(songs(count)) from the \\(UpNextWords.title)" }' in downloads
    assert '"Removed from this \\(device.noun): \\(name)"' in downloads
    queue = code(CORE / "UpNextView.swift")
    assert 'how == .next ? "Playing next: \\(label)" : "Added to \\(UpNextWords.title): \\(label)"' in queue
    return ["Downloading", "Downloading: Roads", "Downloading 23 songs from the Queue", "Playing next: Roads",
            "Added to Queue: Glory Box", "Removed from this iPhone: Dummy"]


def test_the_top_fits_and_the_notice_never_breaks_a_word():
    """Worked out on a 375 and a 393 pt phone at each standard size (the top and the notice stop growing at xxxLarge;
    past it a long press shows each of the top's buttons large): the top fits, and the notice is in its middle only
    while its longest word fits there - else the whole width under the top - so no word is ever wider than its room.
    R3's place holds at the default size and at xLarge; from xxLarge both phones lay "Downloading: Roads" under the
    top ("Downloading:" 120 against the middle's 99 on 375 and 117 on 393), where the room is 319 and 337."""
    side = 12
    under = {}
    for phone in (NARROW, WIDER):
        for size in STANDARD:
            close, trailing, middle = top_ends(phone, size)
            assert 2 * side + close + trailing + 16 < phone, (phone, size)
            points = SUBHEADLINE[size]
            for notice in notices():
                word = max(fonts.words(w, points) for w in notice.split())
                in_middle = 0 < word <= middle
                room = middle if in_middle else phone - 2 * side - 2 * notice_pad()
                assert word <= room, (phone, size, notice, word, room)
                if not in_middle:
                    under.setdefault(phone, set()).add(size)
    #? the middle at the default size on both, as R3 drew it (129 for its words on 375, at least the 120 R3's review
    #? asked); under the top for the •••'s download notices from xxLarge on both
    assert top_ends(NARROW, "large")[2] >= 120
    assert under == {NARROW: {"xxLarge", "xxxLarge"}, WIDER: {"xxLarge", "xxxLarge"}}, under


def test_the_notice_is_measured_as_it_is_drawn_and_laid_where_its_words_fit():
    now = bare(NOW_PLAYING)
    top = flat(member(now, "func topRow"))
    # the two ends, the whole top and the notice's longest word measured, each as laid out
    for measured in ("topEnds.leading = width", "topEnds.trailing = width", "topEnds.whole = width",
                     "topEnds.word = width"):
        assert top.count(measured) == 1, measured
    assert top.count(".onGeometryChange(for: CGFloat.self)") == 4
    assert "let middle = Self.noticeInMiddle(topEnds, side: side, gap: gap)" in top
    rule = flat(member(now, "func noticeInMiddle"))
    assert rule == ("{ let room = ends.whole - 2 * side - ends.leading - ends.trailing - 2 * gap - 2 * noticePad "
                    "return ends.word > 0 && ends.word <= room }"), rule
    assert one(code(NOW_PLAYING), r"private static let noticePad: CGFloat = (\d+)") == notice_pad()
    # the word measured in the notice's own face and cap, every word whole on one line, unseen and unheard
    word = flat(member(now, "struct NoticeWord: View"))
    assert word == ("{ let text: String var body: some View { let words = text.split(whereSeparator: \\.isWhitespace)"
                    ".map(String.init) ZStack { ForEach(words.indices, id: \\.self) { (index: Int) in Text(words[index]) "
                    "} } .font(Typeface.subheadline) .fixedSize() .dynamicTypeSize(...DynamicTypeSize.xxxLarge) "
                    ".hidden() .accessibilityHidden(true) } }"), word
    # (R18) the notice draws the phone's own strip face, which is that very font - Libre Franklin at 15, scaled as the
    # subheadline (tests/test_ios_sheets_look.py holds the two the same)
    assert ("Text(text) .font(Platform.mac ? Typeface.Look.text(.field) : Typeface.Phone.text(.strip))"
            in flat(bare(APP / "Shared" / "Notice.swift")))
    typeface = (APP / "Shared" / "Typeface.swift").read_text(encoding="utf-8")
    assert "case .strip: return (15, .subheadline)" in typeface
    assert "static let subheadline = text(15, .subheadline)" in typeface
    assert "if let notice = player.notice { NoticeWord(text: notice) .onGeometryChange" in top


# ----------------------------------------------------------------------------- flat

def test_now_playings_words_glyphs_and_buttons_have_no_face():
    now = phone_look.phone_path(bare(NOW_PLAYING))
    # the top's one background is the notice's longest word, measured unseen (NoticeWord: `.hidden()`) - no face
    measuring = flat(member(now, "func topRow"))
    measured = measuring[measuring.index(".background {"):measuring.index(".overlay(alignment:")]
    assert measured == (".background { if let notice = player.notice { NoticeWord(text: notice) .onGeometryChange(for: "
                        "CGFloat.self) { (word: GeometryProxy) -> CGFloat in word.size.width } action: { (width: "
                        "CGFloat) -> Void in topEnds.word = width } } } "), measured
    faced = {}
    for declaration in FLAT_MEMBERS:
        body = flat(member(now, declaration)).replace(measured, "")
        found = [m.group(0) for m in FACES.finditer(body)]
        if found:
            faced[declaration] = found
    assert not faced, faced
    # what keeps a face here, each as it was: the cover's shadow (a picture), the speed chip's toggled face, the
    # output's AirPlay button laid under its column (no face of its own: AirPlayButton draws none - its glyph hidden)
    assert ".shadow(color: .black.opacity(0.4), radius: 24, y: 12)" in now
    assert ".buttonStyle(SpeedChipFace())" in now
    assert "AirPlayButton(glyph: false, playsTo: name)" in member(now, "struct OutputItem: View")
    # the top's buttons are DWButtonStyle's flat small one - no kind, so never the purple or the red
    for declaration in ("var closeButton: some View", "struct NamedLookButton: View"):
        assert ".buttonStyle(DWButtonStyle(size: .small))" in member(now, declaration), declaration
    # and the matcher finds a face planted on a flat button
    assert FACES.search(".background(DWPalette.buttonFace)") and FACES.search(".buttonStyle(.bordered)")
    assert FACES.search("DWButtonStyle(kind: .pri, size: .small)")


#? the transport as it is (binding 6): Shuffle, Previous, Play/Pause, Next, Repeat - their glyphs, frames, actions and
#? names exactly as R4b found them (31cab12d). A change to them is a change of its own, never this slice's. One since:
#? (Last.fm, A3) Shuffle dimmed with a station as for a library's shuffle, while it is off (A3's review) - `paged`
#? reads `|| player.stationHoldsShuffle` - deadwax-plans/lastfm.md 3.5 and check 497 ("During a radio, Shuffle is
#? greyed out")
TRANSPORT_DIGEST = "c724df8126f7c5680dd5a93ae62758b4f06a3323584ce92aef74a73ce1eb38e7"


def transport_digest() -> str:
    now = bare(NOW_PLAYING)
    text = flat(member(now, "var transport: some View")) + "\n" + flat(member(now, "struct ModeButton: View"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def test_the_transport_is_as_it_was():
    assert transport_digest() == TRANSPORT_DIGEST
    transport = flat(member(bare(NOW_PLAYING), "var transport: some View"))
    # sharp glyphs, no face, each play PlayerModel's (or the deck's) straight from the tap, nothing awaited first
    for part in ("SharpSymbol(.previous).font(Typeface.symbol(.title)) .frame(minWidth: 56, minHeight: 56)",
                 "PlayPauseGlyph(playing: player.isPlaying) .font(Typeface.symbol(size: 44))",
                 ".frame(minWidth: 72, minHeight: 72)",
                 "SharpSymbol(.next).font(Typeface.symbol(.title)) .frame(minWidth: 56, minHeight: 56)",
                 "if turntable { deck.toggle() } else { player.toggle() }", "player.previous()", "player.next()",
                 "if !paged { player.toggleShuffle() }", "player.setRepeat(nextRepeat(mode))", ".buttonStyle(.plain)"):
        assert part in transport, part
    assert not re.search(r"\bawait\b|\bTask\b", transport)


# ----------------------------------------------------------------------------- the cover

def test_the_cover_is_24_either_side_and_still_the_grip():
    now = bare(NOW_PLAYING)
    content = member(now, "func content")
    cover = content[content.index("} else {\n                    VStack(spacing: 0) {"):]
    cover = cover[:cover.index(".highPriorityGesture(grip)") + len(".highPriorityGesture(grip)")]
    # the column's own 24 either side, every phone: no cap and no room of its own (it was 32 and at most 360)
    image = cover[cover.index("CoverImage("):cover.index("Spacer(minLength: 12)", cover.index("CoverImage("))]
    assert ".frame(" not in image and ".padding(" not in image, image
    assert flat(image).startswith("CoverImage(id: track.coverArt, size: 360) .clipShape(Corners.artShape) "
                                  ".opensCoverFullScreen(track, into: $viewing)"), image
    # still the grip: a drag on the cover is the sheet's from its first dragStartDistance (a tap opens it full screen)
    assert flat(cover).endswith(".frame(maxWidth: .infinity, maxHeight: .infinity) .contentShape(Rectangle()) "
                                ".highPriorityGesture(grip)"), cover
    #? worked out: the drawing's cover is 342 on its 390 phone - the column there; 327 on the narrower one
    inset = one(content, r"\.padding\(\.horizontal, (\d+)\)\s*\.padding\(\.bottom, \d+\)\s*\}$")
    assert DRAWN - 2 * inset == 342 and NARROW - 2 * inset == 327


def test_lyrics_take_the_covers_place_and_the_bottom_rows_lyrics_turns_them_on_and_off():
    """James's answer 2 (3.8, binding): lyrics take the cover's place, and the bottom row's Lyrics turns them on and
    off - never the sheet (tests/test_ios_panels_look.py holds that)."""
    now = bare(NOW_PLAYING)
    content = member(now, "func content")
    place = content[content.index("ZStack {"):]
    place = place[:reader.closing(place, place.index("{")) + 1]
    assert place.index("if lyricsShown {") < place.index("lyricsFace(track)") < place.index("} else if turntable {")
    assert place.index("} else if turntable {") < place.index("CoverImage(id: track.coverArt")
    assert "topRow" not in place and "titles(" not in place
    assert "tapped(.lyrics)" in member(now, "var lyricsItem: some View")
    assert "withAnimation(.easeInOut(duration: 0.25)) { lyrics.showing = tapped.lyricsOn }" in member(now, "func lyricsTapped")


# ----------------------------------------------------------------------------- the title and the readout

def test_the_covers_title_and_artist_album_in_the_accent():
    now = bare(NOW_PLAYING)
    names = flat(member(now, "func coverNames"))
    assert names == ("{ VStack(alignment: .leading, spacing: 0) { Text(track.title) .font(Typeface.title2.bold()) "
                     ".tracking(Self.titleTracking) .foregroundStyle(DWPalette.text) .lineLimit(1) coverByline(track) } "
                     ".frame(maxWidth: .infinity, alignment: .leading) }"), names
    assert one(code(NOW_PLAYING), r"private static let titleTracking: CGFloat = (-[\d.]+)") == -0.3
    assert re.search(r"static let title2 = text\(22, \.title2\)", code(APP / "Shared" / "Typeface.swift"))
    # "Artist — Album": the link to the album in the accent (the drawing's `.acc`); a song naming no album, plain
    # words in the second colour - the accent would say a tap goes somewhere
    byline = member(now, "func coverByline")
    link, words = byline.split("} else {")
    assert ".foregroundStyle(DWPalette.acc)" in link and "navigation.openAlbum(route)" in link
    assert ".accessibilityLabel(PlayerWords.goToAlbum(byline))" in link
    assert ".foregroundStyle(DWPalette.t2)" in words and "Button" not in words
    assert "Palette.quiet" not in byline


#? the turntable keeps no diff (mac-redesign-build.md 3.6): its titles - `titles`, called centred, and the `byline` it
#? draws - exactly as at 31cab12d, centred, quiet and with no tracking
TURNTABLE_TITLES_DIGEST = "9e0874e1a7748f07a31880fb921264859a7003de79b7aa631a3322f708ff1c6a"


def turntable_titles_digest() -> str:
    now = bare(NOW_PLAYING)
    text = flat(member(now, "func titles")) + "\n" + flat(member(now, "func byline"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def test_the_turntables_titles_are_as_they_were():
    assert turntable_titles_digest() == TURNTABLE_TITLES_DIGEST
    now = bare(NOW_PLAYING)
    content = flat(member(now, "func content"))
    # the turntable's branch draws `titles` centred, the cover's coverTitles - each the only call of it
    assert ("ZStack { if turntable { titles(track, centred: true) .transition(.opacity) } else { coverTitles(track) "
            ".transition(.opacity) } }") in content
    assert len(re.findall(r"\btitles\(track", now)) == 1 and len(re.findall(r"\bcoverTitles\(track", now)) == 1
    assert len(re.findall(r"\bbyline\(track", now)) == 1 and "byline(track, centred: centred)" in member(now, "func titles")
    titles = flat(member(now, "func titles"))
    assert "Text(track.title) .font(Typeface.title2.bold()) .lineLimit(1) byline(track, centred: centred)" in titles
    for added in (".tracking(", "DWPalette", "NowPlayingReadout"):
        assert added not in titles and added not in member(now, "func byline"), added


def test_the_readout_is_bar_displays_and_nothing_is_counted_in_the_view():
    now = bare(NOW_PLAYING)
    readout = flat(member(now, "struct NowPlayingReadout: View"))
    # the whole view, exactly: BarDisplay's place and format, each line drawn as BarDisplay says it (`Text(place)`,
    # `Text(format)`), one element saying BarDisplay's spoken readout - nothing else to count with
    assert readout == ("{ let under: Bool @Environment(PlayerModel.self) private var player var body: some View { "
                       "let queue = player.queue let place = BarDisplay.place(queue).map(BarDisplay.Words.place) "
                       "let format = queue.current.flatMap(BarDisplay.format) if place != nil || format != nil { "
                       "VStack(alignment: under ? .leading : .trailing, spacing: 4) { if let place { Text(place) } "
                       "if let format { Text(format) } } .font(Typeface.Phone.mono(.extraSmall)) "
                       ".foregroundStyle(DWPalette.t3) .lineLimit(under ? nil : 1) .fixedSize(horizontal: !under, "
                       "vertical: true) .accessibilityElement(children: .ignore) "
                       '.accessibilityLabel(BarDisplay.readoutSpoken(queue) ?? "") } } }'), readout
    # nothing counted, numbered or formatted anywhere in Now Playing: no index, no count, no grouping, no " of "
    source = code(NOW_PLAYING)
    for counted in (r"\.count\b", r"\+ 1\b", r"\bqueue\.(index|tracks|upNext)\b", r"\bUpNextWords\.grouped\b",
                    r'" of "', r"\bplayer\.(index|tracks)\b", r"\bbitDepth\b", r"\bsampleRate\b", r"\bsuffix\b"):
        assert not re.search(counted, source), counted
    # the place and the format are worked out in the readout's own view alone (Now Playing's body reads
    # `player.current` as it always has, so it is drawn again as the song changes either way)
    assert len(re.findall(r"\bplayer\.queue\b", now)) == 1 and "player.queue" in readout
    # Core's words: "3 of 11", "FLAC 16/44.1"
    words = code(CORE / "BarDisplay.swift")
    assert '"\\(UpNextWords.grouped(place.number)) of \\(UpNextWords.grouped(place.of))"' in words
    assert 'return "\\(format) \\(bits)/\\(rate)"' in words


def test_the_readout_is_drawn_mono_xs_q3_beside_the_title_on_its_baseline():
    now = bare(NOW_PLAYING)
    readout = flat(member(now, "struct NowPlayingReadout: View"))
    # `.col.mono.xs.q3`, `align-items: flex-end; gap: 4px`: Courier Prime at the phone's xs, the third colour
    assert "VStack(alignment: under ? .leading : .trailing, spacing: 4)" in readout
    assert ".font(Typeface.Phone.mono(.extraSmall)) .foregroundStyle(DWPalette.t3)" in readout
    typeface = (APP / "Shared" / "Typeface.swift").read_text(encoding="utf-8")
    assert re.search(r"case \.extraSmall: return \((\d+), \.caption\)\s*// dw\.ph: \.xs font-size", typeface)
    assert px(css(".xs", "font-size")) == 12
    # on the title's first baseline (a readout beside words), 10 from it (`.f` gap 10); under it at the accessibility
    # sizes; never on the turntable, whose titles are centred over the record with nothing beside them
    titles = flat(member(now, "func coverTitles"))
    assert titles == ("{ VStack(alignment: .leading, spacing: 4) { if let error = player.errorLine, !error.isEmpty { "
                      "Text(error) .font(Typeface.footnote) .foregroundStyle(DWPalette.t2) .fixedSize(horizontal: false, "
                      "vertical: true) } let under = dynamicTypeSize.isAccessibilitySize let layout = under ? "
                      "AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: "
                      ".firstTextBaseline, spacing: Self.readoutGap)) layout { coverNames(track) "
                      "NowPlayingReadout(under: under) } } .frame(maxWidth: .infinity, alignment: .leading) }"), titles
    assert "NowPlayingReadout" not in member(now, "func titles")
    assert one(code(NOW_PLAYING), r"private static let readoutGap: CGFloat = (\d+)") == 10
    # beside the title each line is whole (fixed), the title giving way with its ellipsis; under it, as many lines
    assert ".lineLimit(under ? nil : 1) .fixedSize(horizontal: !under, vertical: true)" in readout
    assert ".frame(maxWidth: .infinity, alignment: .leading)" in member(now, "func coverNames")
    assert ".monospacedDigit()" not in code(NOW_PLAYING) and ".monospacedDigit()" not in code(SCRUBBER)


def test_beside_the_title_the_readout_leaves_it_room_through_xxxlarge_and_goes_under_past_it():
    """Worked out on a 375 pt phone, whose column is 327: the widest readout a library's shuffle says ("1,612 of 2,100"
    - wider than any format, "FLAC 24/176.4") leaves the title at least half the column, and the drawing's title ("One
    Wing", 22 and bold, its letters drawn closer) whole, at every standard size - and at the first accessibility size
    neither, so the readout goes under the title there (`dynamicTypeSize.isAccessibilitySize`)."""
    column = NARROW - 48
    gap = 10
    widest = ("1,612 of 2,100", "FLAC 24/176.4", "FLAC 16/44.1", "3 of 11")

    def room(size: str) -> float:
        return column - gap - max(fonts.readout(words, CAPTION[size]) for words in widest)

    def title(size: str) -> float:
        return fonts.words("One Wing", TITLE2[size], "bold") - 0.3 * (len("One Wing") - 1)

    for size in STANDARD:
        assert room(size) >= column / 2, (size, room(size))
        assert title(size) <= room(size), (size, title(size), room(size))
    assert room("accessibility1") < column / 2 and title("accessibility1") > room("accessibility1")
    assert not fonts.lacks("".join(widest), "CourierPrime-Regular")


# ----------------------------------------------------------------------------- the scrubber

def test_the_scrubber_is_sunken_as_the_meter_is():
    scrubber = bare(SCRUBBER)
    body = flat(member(member(scrubber, "struct ScrubberView: View"), "var body: some View"))
    # DWMeter's track: the well, the shade along its top, its 1 pt line, square on the phone - the fill the meter's
    # grey, inside the line (`.meter`, `.meter > i`)
    assert ("ZStack(alignment: .leading) { DWCorners.meterShape .fill(DWPalette.well.shadow(.inner(color: "
            "DWPalette.meterShade, radius: 1, x: 0, y: 1))) .overlay { DWCorners.meterShape.strokeBorder(DWPalette.line, "
            "lineWidth: Self.edge) } TimelineView(") in body, body
    assert ("DWCorners.meterFillShape.fill(DWPalette.meterFill) .frame(width: max(0, width - 2 * Self.edge) * "
            "Self.part(drawn(held, length: length), length: length)) } .padding(Self.edge) }") in body
    meter = flat(bare(APP / "Look" / "DWMeter.swift"))
    assert (".fill(DWPalette.well.shadow(.inner(color: DWPalette.meterShade, radius: 1, x: 0, y: 1))) "
            ".overlay { DWCorners.meterShape.strokeBorder(DWPalette.line, lineWidth: 1) }") in meter
    assert one(code(SCRUBBER), r"private static let edge: CGFloat = (\d+)") == 1
    assert ".dw.ph .meter" in (IOS / "design" / "dw.css").read_text(encoding="utf-8")
    # its sizes as James chose them (14 Nov, "a squared off thicker bar"): 12, 16 while held, in a 44 pt target
    source = code(SCRUBBER)
    assert one(source, r"private static let barHeight: CGFloat = (\d+)") == 12
    assert one(source, r"private static let heldHeight: CGFloat = (\d+)") == 16
    assert one(source, r"private static let target: CGFloat = (\d+)") == 44
    assert ".frame(height: drag == nil ? Self.barHeight : Self.heldHeight)" in body
    # tokens alone: no colour of its own, no corner of its own
    for raw in (r"\bColor\.", r"\.opacity\(", r"cornerRadius:", r"\bPalette\.quiet\b", r"\bRectangle\(\)\.fill"):
        assert not re.search(raw, scrubber), raw


#? (R4b's review) the sunken track's two shapes, the only face the scrubber draws: the well in its line, and the fill
SCRUBBER_TRACK = (".fill(DWPalette.well.shadow(.inner(color: DWPalette.meterShade, radius: 1, x: 0, y: 1))) "
                  ".overlay { DWCorners.meterShape.strokeBorder(DWPalette.line, lineWidth: Self.edge) }",
                  "DWCorners.meterFillShape.fill(DWPalette.meterFill)")


def test_the_scrubber_draws_no_face_but_its_track():
    """The flat rule past the track: nothing behind the bar's 44 pt target or round the column, and no face on the
    clocks - a face anywhere in the scrubber but the sunken track's two shapes fails."""
    scrubber = bare(SCRUBBER)
    body = flat(member(member(scrubber, "struct ScrubberView: View"), "var body: some View"))
    for shape in SCRUBBER_TRACK:
        assert body.count(shape) == 1, shape
        body = body.replace(shape, "")
    assert not [m.group(0) for m in FACES.finditer(body)], body
    clocks = member(scrubber, "struct ScrubberClocks: View, Equatable")
    assert not [m.group(0) for m in FACES.finditer(clocks)], clocks


def test_now_playing_reads_no_position():
    """The busy position is read only by the views that exist to show it - the scrubber, the turntable's time line,
    the mini player's seek line, each in its own file: Now Playing's own views read none (at 31cab12d they read none
    either), so the position's ticks and frames never draw it again. Its one "position" is SpeedChipBand's layout."""
    now = bare(NOW_PLAYING)
    layout = ".position(x: band.size.width * CGFloat(NowPlayingTabs.chipAt), y: band.size.height / 2)"
    assert now.count(layout) == 1 and layout in member(now, "struct SpeedChipBand: View")
    rest = now.replace(layout, "")
    assert not re.search(r"(?i)position|\bbarsRun\b|\bPlayClock\b|\bTimelineView\b", rest), \
        re.findall(r"(?i)\w*position\w*", rest)


def test_the_scrubbers_times_are_courier_prime_under_it():
    scrubber = bare(SCRUBBER)
    clocks = flat(member(scrubber, "struct ScrubberClocks: View, Equatable"))
    assert clocks == ("{ let elapsed: String let remaining: String var body: some View { HStack { Text(elapsed) "
                      "Spacer() Text(remaining) } .font(Typeface.readout(.caption)) .foregroundStyle(DWPalette.t2) "
                      ".accessibilityHidden(true) } }"), clocks
    # under the bar (`.f.mono.xs.q`): the bar's target, then the clocks, in one column
    body = member(member(scrubber, "struct ScrubberView: View"), "var body: some View")
    assert body.index("VStack(spacing: 6) {") < body.index("GeometryReader {") < body.index("ScrubberClocks(elapsed:")
    assert px(css(".xs", "font-size")) == 12
    assert re.search(r"case \.caption: size = 12", code(APP / "Shared" / "Typeface.swift"))


def test_the_scrubbers_drag_voiceover_and_seek_are_as_they_were():
    scrubber = bare(SCRUBBER)
    body = flat(member(member(scrubber, "struct ScrubberView: View"), "var body: some View"))
    for part in (".accessibilityElement(children: .ignore) .accessibilityLabel(PlayerWords.scrubberName) "
                 ".accessibilityValue(PlayerWords.scrubberValue(shown: shown, length: length))",
                 "if let target = Scrub.adjusted(increment: increment, from: shown, length: length) { "
                 "player.seek(to: target) }",
                 ".gesture(press(track: track, width: width, length: length))",
                 "drag = Scrub.dragEnd(drag, pointer: 0, how: .cancel).drag"):
        assert part in body, part
    press = flat(member(scrubber, "func press"))
    assert "DragGesture(minimumDistance: 0, coordinateSpace: .local)" in press
    assert ("let (next, seek) = Scrub.dragEnd(drag, pointer: 0, how: .up) drag = next "
            "if let seek { player.seek(to: seek) }") in press
    # a seek is never awaited before the bar moves: no task, no await anywhere in the scrubber
    assert not re.search(r"\bawait\b|\bTask\b|\basync\b", scrubber)


# ----------------------------------------------------------------------------- the Mac

def test_the_mac_has_none_of_it():
    """The Mac's frame never opens Now Playing: no Mac file names the new pieces, and Now Playing's look stays the
    cover there (tests/test_ios_mac.py)."""
    for path in sorted((APP / "Mac").rglob("*.swift")):
        text = bare(path)
        for piece in ("NamedLookButton", "NowPlayingReadout", "ScrubberView", "NowPlayingView"):
            assert piece not in text, (path.name, piece)
    now = bare(NOW_PLAYING)
    assert "private var look: TurntableSettings.Look { Platform.mac ? .cover : switched ?? deck.opensAs }" in now
