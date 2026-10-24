"""
The app's type (2.0.9, the font review James asked for on 2026-10-23, and the set he chose): read from the
stylesheets, the pages and the components, each rule of the review's fixes held to what was built.

- THE FACES: Noto Sans for words, Noto Sans SemiCondensed for the large titles, Noto Sans Mono for data - every
  file self-hosted under interface/styles/font/, each folder with its OFL beside it, every file a face names on
  disk and every file on disk named (a file is served immutable for a year, so a changed one is a new name, and
  an old one nothing names is dead weight in the image). Every face of a Noto family has the same descriptors:
  Chrome and Safari take one group of a family's faces for a run of text, so a face described differently would
  leave the other scripts to the system face. SemiCondensed covers every range Noto Sans does, so a Polish or a
  Cyrillic title is as narrow as a Latin one.
  Noto Sans Mono covers them too, so a path named in Polish or Cyrillic is one face. What each file can draw is
  read from tests/fixtures/font_cmaps.json (its cmap, by fontTools, kept to the file by its sha256), not taken from
  its face's range, which can claim more.
- THE TRIMMED Latin Extended file keeps the letters names use: every European language's, the African reference
  letters, Vietnamese's (its own file), the modifier letters of romanised names and the dagger - and every such
  letter the app's own words use.
- THE FALLBACK while Noto Sans arrives is a system face sized to it, second in the stack, over the characters Noto
  Sans's files have and no others - so it never draws what Noto Sans doesn't have.
- PRELOADED: the two Latin files nearly every screen needs; the data face is fetched when text needs it.
- THE SCALE is theme.css's, one per frame: app-desktop.css draws every size from section 10, the desktop's body
  14px, meta 13, data 13, labels 12; text fields --dw-text-field's 17px on every frame (iOS zooms into a field
  under 16px), never redefined.
- PINNED LINES: body's line height is --dw-leading-row (Noto's own `normal`), player.css's line heights and sizes
  are tokens, and a track's number, title and length sit on one line (their first baselines).
- THE DATA FACE never on a sentence or a count: Info's notes, the Library's count, the tab's and a row's badges,
  an Arriving card's brief.
- LONG TITLES balanced, in the title face, a step smaller over 60 letters; --pl-text-title-2 (20px beside
  section 10's 28px --dw-text-title-2) named for what it is.
- --dw-text-3 is 4.5:1 or more on every surface it is drawn on, both frames.
- dir="auto" on every title, artist and byline, for a right-to-left name.
"""

import hashlib
import json
import re
from pathlib import Path

from fastapi.testclient import TestClient

from src.api.app import start
from tests.test_app_css import ALL_TOKENS, APP, PLAYER_CSS, THEME_CSS, declarations, rules, tokens

REPO = Path(__file__).resolve().parent.parent
INTERFACE = REPO / "interface"
FONTS = INTERFACE / "styles" / "font"
DESKTOP = (INTERFACE / "player" / "app-desktop.css").read_text()
SIGNIN = (INTERFACE / "player" / "signin.css").read_text()
LAB_CSS = (INTERFACE / "player" / "lab" / "lab.css").read_text()
PAGE = (INTERFACE / "player" / "index.html").read_text()
LAB_PAGE = (INTERFACE / "player" / "lab" / "index.html").read_text()
UI = REPO / "ui" / "src"
DESK = "@media (min-width: 1024px)"
COARSE = "@media (min-width: 1024px) and (pointer: coarse)"
NOTO_FAMILIES = ("Noto Sans", "Noto Sans SemiCondensed", "Noto Sans Mono")


def faces(css: str) -> list[dict[str, str]]:
    """Every @font-face block's descriptors (the rules() reader walks into an @-rule looking for rules, and a
    @font-face has none)."""
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    found = []
    for body in re.findall(r"@font-face\s*\{([^}]*)\}", css):
        descriptors = {}
        for part in body.split(";"):
            if ":" in part:
                name, value = part.split(":", 1)
                descriptors[name.strip()] = " ".join(value.split())
        descriptors["font-family"] = descriptors["font-family"].strip('"')
        found.append(descriptors)
    return found


FACES = faces(THEME_CSS)


def family(name: str) -> list[dict[str, str]]:
    return [face for face in FACES if face["font-family"] == name]


def codepoints(unicode_range: str) -> set[int]:
    points: set[int] = set()
    for part in unicode_range.split(","):
        found = re.fullmatch(r"U\+([0-9A-F]+)(?:-([0-9A-F]+))?", part.strip())
        assert found, part
        low = int(found.group(1), 16)
        points.update(range(low, int(found.group(2) or found.group(1), 16) + 1))
    return points


def covered(name: str) -> set[int]:
    return set().union(*(codepoints(face["unicode-range"]) for face in family(name)))


def source(face: dict[str, str]) -> Path:
    found = re.fullmatch(r'url\("(font/[\w./-]+\.woff2)"\) format\("woff2"\)', face["src"])
    assert found, face["src"]
    return INTERFACE / "styles" / found.group(1)


#? each file's characters as its cmap has them, read with fontTools by tests/fixtures/font_cmaps.py (the suite has neither
#? fontTools nor brotli): a face's range is what the browser may ask its file for, the cmap what the file can draw
CMAPS = json.loads((REPO / "tests" / "fixtures" / "font_cmaps.json").read_text())


def cmap(path: Path) -> set[int]:
    return codepoints(CMAPS[path.relative_to(FONTS).as_posix()]["cmap"])


def drawn(name: str) -> set[int]:
    """What a family draws in its own files: each face's range, as far as its file has the characters."""
    return set().union(*(codepoints(face["unicode-range"]) & cmap(source(face)) for face in family(name)))


# ---------------------------------------------------------------- the faces and their files

def test_three_noto_families_every_file_on_disk_and_every_file_named():
    assert {face["font-family"] for face in FACES} == {*NOTO_FAMILIES, "Noto Sans Fallback"}
    named = {source(face) for face in FACES if face["font-family"] in NOTO_FAMILIES}
    on_disk = set(FONTS.rglob("*.woff2"))
    assert named == on_disk
    assert len(family("Noto Sans")) == len(family("Noto Sans SemiCondensed")) == len(family("Noto Sans Mono")) == 7
    #? the old 164 KB latin-ext is gone, under a new name - a file is served immutable for a year
    assert not (FONTS / "noto-sans" / "noto-sans-latin-ext.woff2").exists()
    assert (FONTS / "noto-sans" / "noto-sans-latin-ext-europe.woff2").stat().st_size < 80_000


def test_the_list_of_each_files_characters_is_the_files_own():
    """A rebuilt file is a changed sha256: tests/fixtures/font_cmaps.py is run again, or the checks below would be reading
    another file's characters."""
    assert set(CMAPS) == {path.relative_to(FONTS).as_posix() for path in FONTS.rglob("*.woff2")}
    for path in sorted(FONTS.rglob("*.woff2")):
        assert CMAPS[path.relative_to(FONTS).as_posix()]["sha256"] == hashlib.sha256(path.read_bytes()).hexdigest(), path


def test_each_folder_of_faces_keeps_its_licence_beside_them():
    folders = {path.parent for path in FONTS.rglob("*.woff2")}
    assert {folder.name for folder in folders} == {"noto-sans", "noto-sans-semicondensed", "noto-sans-mono"}
    for folder in folders:
        licence = (folder / "OFL.txt").read_text()
        assert "SIL OPEN FONT LICENSE Version 1.1" in licence and "The Noto Project Authors" in licence, folder


def test_every_face_of_a_noto_family_is_described_alike():
    """Chrome and Safari group a family's faces by their descriptors and take ONE group for a run of text: a face
    described differently from the rest would leave the other scripts' characters to the system face."""
    for name in NOTO_FAMILIES:
        described = {tuple(sorted((key, value) for key, value in face.items() if key not in ("src", "unicode-range")))
                     for face in family(name)}
        assert len(described) == 1, name
        assert dict(next(iter(described)))["font-display"] == "swap"
    #? and the families alike: the title face is the text face's design, at another width
    assert {face["font-weight"] for face in FACES if face["font-family"] in NOTO_FAMILIES} == {"300 700"}


def test_the_titles_face_and_the_data_face_cover_every_script_the_text_face_does():
    """The data face too: a folder or a path named in Polish, Cyrillic or Vietnamese is one face, not Noto Sans Mono's
    slash and digits round the system monospace's letters (it was Latin only when 2.0.9 was first built)."""
    for name, prefix in (("Noto Sans SemiCondensed", "noto-sans-semicondensed-"), ("Noto Sans Mono", "noto-sans-mono-")):
        assert [face["unicode-range"] for face in family(name)] == [face["unicode-range"] for face in family("Noto Sans")], name
        for face in family(name):
            assert source(face).name.startswith(prefix)


#? the letters names are written in: every European language's, the African reference alphabet's, Vietnamese's,
#? German's capital sharp s, Greek and Cyrillic
NAME_LETTERS = (
    "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ" "čďěňřšťůžČĎĚŇŘŠŤŮŽ" "çğıöşüİĞŞ" "ășțâîȘȚ" "őűŐŰ" "þðæÞÐÆ" "āēīūļķņģėįųĀĒĪŪĻĶŅĢĖĮŲ"
    "ĉĝĥĵŝŭħċġŵŷđĐŋŊẞß" "ɓɔɖɗəɛɣɨɩɲʉʋʒƏƐƆŊ" "ạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹơưĂăĐđĨĩŨũƠơƯư"
    "ΑαΒβΓγΔδΩωάέήίόύώ" "ЖжЩщЯяЁёЇїЄєҐґЎў"
)


#? what romanised Arabic and Hebrew names, transliterations and titles are written with beside the letters: the ayin and
#? the alif ("Saʿīd"), the primes, the stress and length marks - and the dagger (Justice's "†"), which Google's Latin file
#? claims and hasn't
NAME_MARKS = "ʿʾʹʺˈː†"


def test_the_trimmed_latin_extended_file_keeps_every_letter_names_use():
    """Read from the files' own characters, not the faces' ranges: the trim first dropped † and ʿ, which the Latin
    face's range still claimed."""
    for name in NOTO_FAMILIES:
        missing = [letter for letter in NAME_LETTERS + NAME_MARKS if ord(letter) not in drawn(name)]
        assert missing == [], name


def test_every_letter_the_apps_own_words_use_that_noto_has_is_still_drawn_in_noto():
    """The trim dropped phonetic and Latin Extended-C/D letters: none of them is in the app's own words."""
    words = "".join(path.read_text() for path in sorted(UI.rglob("*.ts*")))
    letters = {ord(letter) for letter in words if 0x100 <= ord(letter) < 0x2C80 or 0xA720 <= ord(letter) < 0xA800}
    #? Google's whole latin-ext range, as it was served until 2.0.9
    old = codepoints("U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+1D00-1DBF, U+1E00-1E9F, "
                     "U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF")
    assert sorted(hex(point) for point in letters & old - drawn("Noto Sans")) == []
    #? and none was lost that Google's file had and the old range served, but the IPA, phonetic and Latin
    #? Extended-C/D letters the trim was for
    lost = old - drawn("Noto Sans")
    ipa_and_beyond = codepoints("U+0250-02AF, U+02B0-02FF, U+1D00-1DBF, U+2C60-2C7F, U+A720-A7FF")
    assert sorted(hex(point) for point in lost - ipa_and_beyond) == []


def test_the_fallback_is_a_system_face_sized_to_noto_and_only_over_notos_ranges():
    fallback = family("Noto Sans Fallback")
    assert [face["font-weight"] for face in fallback] == ["300 500", "600 700"]
    for face in fallback:
        assert face["src"].startswith('local("Arial') and "url(" not in face["src"]
        #? Noto Sans's average English letter over Arial's (Liberation Sans) is 1.0714; its ascent and descent,
        #? 1069 and 293 thousandths, divided by that, since the overrides are read after size-adjust
        assert (face["size-adjust"], face["ascent-override"], face["descent-override"], face["line-gap-override"]) == (
            "107.14%", "99.77%", "27.35%", "0%")
        assert abs(1.0714 * 99.77 - 106.9) < 0.05 and abs(1.0714 * 27.35 - 29.3) < 0.05
        #? never a character Noto Sans's files haven't (their ranges claim more: the Latin file's U+2000-206F has no U+2010
        #? hyphen), so after the swap it draws nothing - a Japanese or an Arabic name, that hyphen, go past it to the system
        #? faces; and every one they have, so nothing reflows when they arrive
        has = set().union(*(cmap(source(one)) for one in family("Noto Sans")))
        assert codepoints(face["unicode-range"]) == {point for point in has if point >= 0x20}
        assert 0x2010 not in codepoints(face["unicode-range"]) and 0x2010 in covered("Noto Sans")


def test_the_stacks_put_each_noto_face_first_and_the_fallback_after_the_text_face():
    stacks = tokens(THEME_CSS)
    assert stacks["--font-family"].startswith('"Noto Sans", "Noto Sans Fallback", ')
    assert stacks["--font-title"].startswith('"Noto Sans SemiCondensed", "Noto Sans", "Noto Sans Fallback", ')
    assert stacks["--font-mono"].startswith('"Noto Sans Mono", ui-monospace, ')
    assert (ALL_TOKENS["--dw-font"], ALL_TOKENS["--dw-font-title"], ALL_TOKENS["--dw-font-mono"]) == (
        "var(--font-family)", "var(--font-title)", "var(--font-mono)")


def test_the_two_latin_files_every_screen_needs_are_preloaded_and_kept_for_good():
    preloads = re.findall(r'<link rel="preload" href="(/styles/font/[^"]+)" as="font" type="font/woff2" crossorigin>', PAGE)
    assert preloads == ["/styles/font/noto-sans/noto-sans-latin.woff2",
                        "/styles/font/noto-sans-semicondensed/noto-sans-semicondensed-latin.woff2"]
    #? the bench draws no large title: the text face's file alone
    assert re.findall(r'rel="preload" href="(/styles/font/[^"]+)"', LAB_PAGE) == ["/styles/font/noto-sans/noto-sans-latin.woff2"]
    client = TestClient(start())  # no `with`: no lifespan, nothing connects
    for path in sorted(FONTS.rglob("*.woff2")):
        answer = client.get("/styles/" + path.relative_to(INTERFACE / "styles").as_posix())
        assert answer.status_code == 200 and answer.content == path.read_bytes(), path
        assert answer.headers["cache-control"] == "public, max-age=31536000, immutable", path
        assert answer.headers["content-type"] == "font/woff2" and "content-encoding" not in answer.headers, path
    for page in (PAGE, LAB_PAGE):
        for href in re.findall(r'href="(/styles/font/[^"]+)"', page):
            assert (INTERFACE / href.lstrip("/")).is_file(), href


# ---------------------------------------------------------------- the scale

def test_one_type_scale_per_frame_in_theme_css():
    phone, desk = tokens(THEME_CSS), {}
    for where, selector, values in rules(THEME_CSS):
        if where == DESK and selector == ":root":
            desk.update(values)
    assert [phone[name] for name in ("--dw-text-large-title", "--dw-text-title-2", "--dw-text-title", "--dw-text-title-long",
            "--dw-text-artist-hero", "--dw-text-body", "--dw-text-field", "--dw-text-heading", "--dw-text-data",
            "--dw-text-footnote", "--dw-text-label", "--dw-text-tab")] == [
        "34px", "28px", "22px", "20px", "20px", "17px", "17px", "15px", "15px", "13px", "12px", "10px"]
    assert [desk[name] for name in ("--dw-text-large-title", "--dw-text-title", "--dw-text-title-long", "--dw-text-artist-hero",
            "--dw-text-brand", "--dw-text-body", "--dw-text-heading", "--dw-text-data", "--dw-text-footnote", "--dw-text-label")] == [
        "28px", "30px", "24px", "18px", "20px", "14px", "13px", "13px", "13px", "12px"]
    #? a text field's size is never redefined: an iPad on its side is a desktop
    assert "--dw-text-field" not in desk


def test_the_desktop_draws_every_size_from_the_scale_and_defines_none_of_its_own():
    sizes = {values["font-size"] for _where, _selector, values in rules(DESKTOP) if "font-size" in values}
    assert sizes and all(re.fullmatch(r"var\(--dw-text-[\w-]+\)", size) for size in sizes), sizes
    #? none of the folded tokens is left: the frame's own px sizes are section 10's now
    own = {name for _where, selector, values in rules(DESKTOP) if selector == ":root" for name in values}
    assert own & {"--app-desk-text", "--app-desk-text-sm", "--app-desk-brand", "--app-desk-field-text", "--app-desk-clock",
                  "--app-desk-chip-text", "--app-desk-speed-text", "--app-viz-title", "--app-viz-artist", "--app-viz-album",
                  "--app-viz-text", "--app-viz-small", "--app-viz-hint", "--app-viz-lines"} == set()
    #? the player bar's clocks are data, at the desktop's 13px (they were 11)
    assert declarations(DESKTOP, ".app-desk .app-playbar .pl-clocks", DESK)["font-size"] == "var(--dw-text-data)"


FIELD = re.compile(r"(?<![\w-])(input|select|textarea)(?![\w-])|-input\b|-select\b|-field\b")


def field_sizes(css: str, context: str) -> dict[str, str]:
    return {" ".join(selector.split()): values["font-size"] for where, selector, values in rules(css)
            if where == context and "font-size" in values and FIELD.search(selector) and "label" not in selector
            and "note" not in selector and ":" not in selector.split()[-1]}


def resolve(value: str) -> str:
    """A var() chain followed to the --dw-text-* token it ends at."""
    while (found := re.fullmatch(r"var\((--[\w-]+)\)", value)) and not found.group(1).startswith("--dw-text-"):
        value = ALL_TOKENS.get(found.group(1)) or tokens(SIGNIN)[found.group(1)]
    return value


def test_every_text_field_is_the_field_size_on_every_frame():
    """--dw-text-body is 14px on a desktop since 2.0.9, so a field reading it would be small enough for iOS to zoom
    into on an iPad on its side: every field reads --dw-text-field - and where a desktop's pointer is fine, its
    13px is put back to 17 where the pointer is coarse."""
    phone = {**field_sizes(APP, ""), **field_sizes(SIGNIN, ""), **field_sizes(LAB_CSS, "")}
    assert len(phone) >= 12
    assert {selector: resolve(size) for selector, size in phone.items() if resolve(size) != "var(--dw-text-field)"} == {
        ".lab-file, .lab-field": "var(--dw-text-heading)"}  # the bench's label around its field, not the field
    coarse = field_sizes(DESKTOP, COARSE)
    assert len(coarse) >= 5 and set(coarse.values()) == {"var(--dw-text-field)"}
    #? each field the desktop draws smaller for a pointer you aim is put back where the pointer is coarse
    aimed = {selector for selector, size in field_sizes(DESKTOP, DESK).items() if size != "var(--dw-text-field)"}
    assert aimed and aimed <= set(coarse), aimed - set(coarse)
    #? the sign-in card is the phone's on a desktop too: its button's word as big as its fields, not the desktop's 14px body
    assert resolve(declarations(SIGNIN, ".app-signin-submit")["font-size"]) == "var(--dw-text-field)"


# ---------------------------------------------------------------- pinned lines, and the track row

def test_no_line_takes_a_faces_normal_and_player_css_types_only_tokens():
    assert declarations(PLAYER_CSS, "body")["line-height"] == "var(--pl-leading-row)"
    assert ALL_TOKENS["--pl-leading-row"] == "var(--dw-leading-row)" and ALL_TOKENS["--dw-leading-row"] == "1.36"
    raw = [(selector, name, value) for _where, selector, values in rules(PLAYER_CSS) if selector != ":root"
           for name, value in values.items()
           if name in ("line-height", "font-size", "font-weight", "letter-spacing", "font-family") and not value.startswith("var(")
           and value != "inherit"]
    assert raw == []
    #? the name clash: player.css's 20px artist line was --pl-text-title-2, beside section 10's 28px --dw-text-title-2
    assert "--pl-text-title-2" not in re.sub(r"/\*.*?\*/", "", PLAYER_CSS + APP + DESKTOP, flags=re.S)
    assert declarations(PLAYER_CSS, ".pl-hero-artist")["font-size"] == "var(--pl-text-artist-hero)"
    assert ALL_TOKENS["--pl-text-artist-hero"] == "var(--dw-text-artist-hero)"


def test_a_tracks_number_title_and_length_sit_on_one_line():
    """Centred one by one, a 15px number sat about 3px above a 17px title (the review measured it), and with an
    artist's line under the title, level with neither. Their first baselines are aligned - the title's when an
    artist's line is under it - and the one line of them centred in the row."""
    row = declarations(PLAYER_CSS, ".pl-track")
    assert (row["display"], row["align-items"], row["align-content"]) == ("grid", "baseline", "center")
    numbers = declarations(PLAYER_CSS, ".pl-track-time")
    assert (numbers["font-family"], numbers["font-size"]) == ("var(--pl-font-data)", "var(--pl-text-data)")
    assert ALL_TOKENS["--pl-text-data"] == "var(--dw-text-data)"
    assert "align-self" not in numbers and "align-self" not in declarations(PLAYER_CSS, ".pl-track-text")
    #? a playlist's row is aligned the same way (centred whole, it drew the length between the title's line and the
    #? artist's, 8px below the title) - and only its cover, which a baseline would sit on the line, is centred
    assert "align-items" not in declarations(APP, ".app-playlist-track")
    assert declarations(APP, ".app-playlist-track-art")["align-self"] == "center"
    assert not [selector for _where, selector, values in rules(APP) + rules(DESKTOP)
                if "align-items" in values and re.search(r"\.(pl-track|app-playlist-track)(?![\w-])", selector)]


# ---------------------------------------------------------------- the data face

def test_the_data_face_is_never_on_a_sentence_or_a_count():
    every = [(where, selector, values) for css in (THEME_CSS, PLAYER_CSS, APP, DESKTOP, SIGNIN) for where, selector, values in rules(css)]
    mono = {selector for _where, selector, values in every if values.get("font-family") in ("var(--dw-font-mono)", "var(--pl-font-data)")}
    for prose in (".app-kv-note", ".app-library-count", ".app-tab-badge", ".app-job-brief", ".app-queue-badge", ".app-queue-count",
                  ".app-side-badge", ".app-kv-label", ".pl-sheet-title", ".pl-track-title", ".app-info-line"):
        assert not [selector for selector in mono if re.search(re.escape(prose) + r"(?![\w-])", selector)], prose
    #? ...and the data it is for keeps it: times, numbers, the turntable's readouts, paths
    for data in (".pl-track-time", ".pl-clocks", ".app-tt-time", ".app-tt-readout-face", ".app-job-data", ".app-rg-length",
                 ".app-artist-folder", ".app-mono"):
        assert any(re.search(re.escape(data) + r"(?![\w-])", selector) for selector in mono), data
    #? the components don't put the class back on a count
    markup = "\n".join(path.read_text() for path in sorted(UI.rglob("*.tsx")))
    for count in ("app-library-count", "app-queue-badge", "app-queue-count", "app-side-badge"):
        for found in re.finditer(r'class=(?:"[^"]*|\{`[^`]*)\b' + count + r"\b[^\"`]*", markup):
            assert "app-mono" not in found.group(0), found.group(0)
    #? a source card's facts: Quality and Size are data; Tracks ("10 of 12") and Starts ("after 3 others") are a count
    #? and a phrase
    card = (UI / "app" / "SourceCard.tsx").read_text()
    facts = dict(re.findall(r'<dt class="app-source-label">(\w+)</dt>\s*<dd class=(\{`[^`]*`\}|"[^"]*")', card))
    assert {label: "app-mono" in value for label, value in facts.items()} == {
        "Tracks": False, "Quality": True, "Size": True, "Starts": False}


def test_the_data_size_is_only_on_data():
    """--dw-text-data grew to 15px on a phone in 2.0.9 for track numbers and times: a word sized by it grew with
    them (a source card's Get did, 14px to 15). Every rule sized by it is in the data face, or is one of these."""
    sized = {(where, " ".join(selector.split())) for css in (PLAYER_CSS, APP, DESKTOP, SIGNIN, LAB_CSS) for where, selector, values in rules(css)
             if values.get("font-size") in ("var(--dw-text-data)", "var(--pl-text-data)")
             and values.get("font-family") not in ("var(--dw-font-mono)", "var(--pl-font-data)")}
    assert sized == {
        #? the desktop's clocks and track numbers, their face set by their own rules on every frame
        (DESK, ".app-desk .app-playbar .pl-clocks"), (DESK, ".app-desk .pl-track-number, .app-desk .pl-track-time"),
        #? the desktop log's table: a line's time and its words at one size, the footnote's 13px there
        (DESK, ".app-desk .app-log-row"),
        #? a source card's values on a desktop, where the data size is the footnote's 13px: Quality and Size are data,
        #? Tracks and Starts in the text face
        (DESK, ".app-desk .app-layer.is-panel .app-source-value"), (DESK, ".app-desk .app-layer.is-panel .app-source-missing"),
    }, sized
    #? Get on a source card is a word, as big as Search's Get
    assert declarations(APP, ".app-source-get")["font-size"] == declarations(APP, ".app-result-get")["font-size"] == "var(--dw-text-heading)"


# ---------------------------------------------------------------- the large titles

TITLES = (".pl-large-title", ".pl-hero-title", ".pl-sheet-title")


def test_the_large_titles_are_semicondensed_and_balanced():
    for selector in TITLES:
        assert declarations(PLAYER_CSS, selector)["font-family"] == "var(--pl-font-display)", selector
    assert ALL_TOKENS["--pl-font-display"] == "var(--dw-font-title)"
    for css, selector, context in ((APP, ".app-artist-name", ""), (APP, ".app-identity-name", ""), (SIGNIN, ".app-signin-title", ""),
                                   (DESKTOP, ".app-desk .app-side-brand", DESK)):
        assert declarations(css, selector, context)["font-family"] == "var(--dw-font-title)", selector
    #? never on a row, a heading or a panel's title
    assert "font-family" not in declarations(APP, ".app-shelf-title") and "font-family" not in declarations(APP, ".app-artist-panel-title")
    #? balanced where a title wraps (the sheet's song is one line, with an ellipsis)
    for css, selector in ((PLAYER_CSS, ".pl-large-title"), (PLAYER_CSS, ".pl-hero-title"), (APP, ".app-artist-name"), (APP, ".app-info-name")):
        assert declarations(css, selector)["text-wrap"] == "balance", selector
    assert declarations(PLAYER_CSS, ".pl-sheet-title")["white-space"] == "nowrap"
    #? a long one a step smaller: 20px on a phone, 24 on a desktop
    assert declarations(PLAYER_CSS, ".pl-hero-title.is-long")["font-size"] == "var(--pl-text-title-long)"
    assert ALL_TOKENS["--pl-text-title-long"] == "var(--dw-text-title-long)"
    #? set by the three pages that draw a hero title, from lib/titles.ts
    for page in ("player/AlbumPage.tsx", "app/ReleaseGroupPage.tsx", "app/PlaylistPage.tsx"):
        text = (UI / page).read_text()
        assert 'class="pl-hero-title"' not in text and "class={heroTitleClass(" in text, page


# ---------------------------------------------------------------- contrast

def luminance(colour: str) -> float:
    colour = colour.lstrip("#")
    if len(colour) == 3:
        colour = "".join(part * 2 for part in colour)
    def channel(value: int) -> float:
        value /= 255
        return value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4
    red, green, blue = (int(colour[at:at + 2], 16) for at in (0, 2, 4))
    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)


def contrast(one: str, other: str) -> float:
    lighter, darker = sorted((luminance(one), luminance(other)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


def test_tertiary_text_is_legible_on_every_surface_it_is_drawn_on():
    """--dw-text-3 is the Edit panel's, the inspector's and the log's words at 12-13px, on cards, side panels and
    popovers: it was #7d7d92, 3.6:1 on a popover and 3.9 on a card."""
    phone = tokens(THEME_CSS)
    desk = {name: value for where, selector, values in rules(THEME_CSS) if where == DESK and selector == ":root" for name, value in values.items()}
    surfaces = ("--dw-bg", "--dw-bg-now-playing", "--dw-bg-sheet", "--dw-card", "--dw-tab-bar", "--dw-popover", "--dw-field",
                "--dw-sidebar", "--dw-side-panel", "--dw-player-bar", "--dw-empty-cover")
    for frame in (phone, {**phone, **desk}):
        for surface in surfaces:
            colour = frame[surface]
            while colour.startswith("var("):
                colour = frame[colour[4:-1]]
            assert contrast(frame["--dw-text-3"], colour) >= 4.5, (surface, colour, round(contrast(frame["--dw-text-3"], colour), 2))
    assert phone["--dw-text-3"] == "#8e8ea3"
    #? still the quietest of the three greys
    assert luminance(phone["--dw-text-3"]) < luminance(phone["--dw-text-label-color"]) < luminance(phone["--dw-text-2"])


# ---------------------------------------------------------------- right-to-left names

NAMES = ("pl-hero-title", "pl-hero-artist", "pl-track-title", "pl-track-artist", "pl-sheet-title", "pl-sheet-byline", "pl-mini-title",
         "pl-mini-artist", "app-playbar-title", "app-playbar-byline", "app-viz-title", "app-viz-artist", "app-viz-album", "app-tile-title",
         "app-tile-artist", "pl-album-title", "pl-album-artist", "app-info-name", "app-artist-name", "app-result-title", "app-pin-title",
         "app-job-title",
         #? and every other line that can carry a title, an artist or a name: the album you don't have's tracks, an Arriving
         #? card's artist and Requests' lines, the sources' "for ...", Held by nobody's, Info's artist line, a playlist's
         #? and a pin's artist line, the sidebar's playlists, a band's members, Which artist is this?'s names, the picker's
         #? playlists
         "app-rg-title", "app-job-line", "app-sources-subtitle", "app-care-held-name", "app-info-line", "app-pin-line",
         "app-side-item-label", "app-artist-member-name", "app-artist-match-name", "app-playlist-pick-name")


def class_attributes(text: str):
    """Each JSX class attribute: (its value, what follows it)."""
    for found in re.finditer(r"\bclass=", text):
        at = found.end()
        if text[at] == '"':
            end = text.index('"', at + 1) + 1
        else:
            depth, end = 1, at + 1
            while depth:
                depth += {"{": 1, "}": -1}.get(text[end], 0)
                end += 1
        yield text[at:end], text[end:end + 11]


def test_every_title_artist_and_byline_takes_its_direction_from_its_words():
    """An Arabic or a Hebrew name in an English page: its own direction, so a mixed byline doesn't reorder round
    its dash. dir="auto" straight after the class attribute of every element that draws one."""
    seen = set()
    for path in sorted(UI.rglob("*.tsx")):
        for value, after in class_attributes(path.read_text()):
            names = [name for name in NAMES if re.search(r"(?<![\w-])" + name + r"(?![\w-])", value)]
            if "heroTitleClass(" in value:
                names.append("pl-hero-title")
            if names:
                assert after == ' dir="auto"', (path.name, value)
                seen.update(names)
    assert seen == set(NAMES)
    #? the desktop panel's "for <album>": the line's direction is its English word's, so the name is isolated in its own
    assert "for <bdi>{request.subtitle}</bdi>" in (UI / "app" / "Sources.tsx").read_text()


def test_a_names_direction_never_moves_it_to_the_other_side():
    """dir="auto" sets an Arabic name's direction, and with it `start` - the right edge: an Arabic artist's name sat
    flush right over a page whose Play, albums and facts start at the left, and Now Playing's song right over its
    left-aligned byline (the recheck measured both, 2.0.9). Every dir="auto" line takes the alignment its parent has in
    the page's own direction, at zero specificity so a rule of its own still wins - and no rule of the app's sets a
    side that depends on the words' direction."""
    css = re.sub(r"/\*.*?\*/", "", PLAYER_CSS, flags=re.S)
    found = re.search(r'(?m)^:where\(\[dir="auto"\]:not\(button\)\) \{([^}]*)\}', css)
    assert found, "the dir=auto alignment rule is missing from player.css"
    #? Chromium (154) and WebKit read only the prefixed spelling, Firefox only the plain one; each drops the other
    assert re.findall(r"text-align:\s*([^;]+);", found.group(1)) == ["-webkit-match-parent", "match-parent"]
    #? player.css is linked before every stylesheet that sizes or places a name, on the app's page and the bench's
    for page in (PAGE, LAB_PAGE):
        links = re.findall(r'href="/(?:player|styles)/([\w/.-]+\.css)', page)
        assert links.index("player.css") == 0 or links[:links.index("player.css")] == ["theme.css"]
    sheets = {"player.css": PLAYER_CSS, "app.css": APP, "app-desktop.css": DESKTOP, "signin.css": SIGNIN, "lab.css": LAB_CSS}
    for name, sheet in sheets.items():
        for _where, selector, values in rules(sheet):
            align = values.get("text-align", "left")
            assert align not in ("start", "end"), (name, selector, align)
            if re.search(r"\.(" + "|".join(NAMES) + r")(?![\w-])", selector):
                assert align in ("left", "center", "right"), (name, selector, align)
