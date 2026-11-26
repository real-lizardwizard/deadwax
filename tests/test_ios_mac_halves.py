"""
The Mac's half of the shared look, pinned (the redesign, slice R1c - notes/ios.md "The redesign, slice R1c: the phone is
flat (2026-11-25)"). R1c restyled the phone through the pieces both devices draw - App/Look's buttons, chips and
switches - and "the Mac doesn't change": so what the Mac runs of each is pinned here, as R1c left it, which no other
test held (a Mac button's drop taken away passed every Mac look test).

What the Mac runs is read from the source: each `if Platform.mac { A } else { B }` as A, `Platform.mac ? a : b` as a, a
half the Mac never runs (`if !Platform.mac`, `x && !Platform.mac ? a : b`'s a) dropped, and the phone's own parts
(PHONE_ONLY - each named from a phone half alone, held below) taken out; then its code alone - comments, literals'
contents and spacing aside - digested. A deliberate change to a Mac half changes its digest here, in the same commit,
with the reason in that commit; the digest's line names the file and the part.
"""

import hashlib
import importlib.util
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(f"_mac_halves_{name}", Path(__file__).resolve().parent / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load("test_ios_no_web_app")


def bare(text: str) -> str:
    """The source as code alone: its comments and its literals' contents blanked."""
    return reader.views(text)[1]


def block(code: str, at: int) -> tuple[int, int]:
    """The braces opened at or after `at`: (the `{`, its `}`)."""
    opened = code.index("{", at)
    return opened, reader.closing(code, opened)


def mac_path(code: str) -> str:
    """The code as the Mac runs it."""
    while True:
        found = re.search(r"\bif (!?)((?:\w+, )?)Platform\.mac( \|\| [^{]+)? \{", code)
        if not found:
            break
        negated, before, _ = found.groups()
        opened, closed = block(code, found.start())
        first, otherwise, end = code[opened + 1:closed], "", closed
        if re.match(r"\s*else \{", code[closed + 1:]):
            other_open, end = block(code, closed + 1)
            otherwise = code[other_open + 1:end]
        if negated:
            kept = otherwise                    # the Mac never runs `if !Platform.mac`'s half
        elif before:
            kept = f"if {before[:-2]} {{{first}}}"  # `if on, Platform.mac` is `if on` on the Mac
        else:
            kept = first                        # `Platform.mac` (or `Platform.mac || x`) is true on the Mac
        code = code[:found.start()] + kept + code[end + 1:]
    code = re.sub(r"(?:\w+ == )?[\w.]+ && !Platform\.mac \? [\w.]+ : ([\w.]+)", r"\1", code)
    code = re.sub(r"Platform\.mac \? ([\w.]+) : [\w.]+", r"\1", code)
    assert "Platform.mac" not in code, code[code.index("Platform.mac") - 80:code.index("Platform.mac") + 80]
    return code


#? the phone's own parts of the shared pieces: what the phone's halves name and the Mac's never do - R1c's flat button,
#? chip and switch, and (R2b) the switch's measure, the phone's Library row's alone (LibraryTop)
PHONE_ONLY = {
    "Look/DWButtonStyle.swift": [r"private struct DWFlatButtonBody: View \{"],
    "Look/DWChip.swift": [r"private var flat: some View \{"],
    "Look/DWSegmented.swift": [r"private var phoneSegments: some View \{",
                               r"private func phoneSegment\(_ option: Value\) -> some View \{",
                               r"struct DWSegmentedNeed: View \{"],
}
#? and the phone's lines of their own, one line each - (R1c's review) the chip's `keepsFace` among them: the Mac's chip
#? is faced whatever it says
PHONE_LINES = {
    "Look/DWChip.swift": ["@ScaledMetric(relativeTo: .footnote) private var dot = CGFloat(DWFlat.dot)",
                          "var keepsFace = false"],
}


def without_phone(name: str, code: str) -> str:
    for start in PHONE_ONLY.get(name, []):
        found = re.search(start, code)
        assert found, (name, start)
        code = code[:found.start()] + code[block(code, found.start())[1] + 1:]
    for line in PHONE_LINES.get(name, []):
        assert code.count(line) == 1, (name, line)
        code = code.replace(line, "")
    return code


def digest(code: str) -> str:
    flat = re.sub(r"\s+", " ", code.replace("@ViewBuilder", "")).strip()
    return hashlib.sha256(flat.encode("utf-8")).hexdigest()[:16]


def part(code: str, start: str) -> str:
    """One declaration: from `start` to its brace's close."""
    found = re.search(start, code)
    assert found, start
    return code[found.start():block(code, found.start())[1] + 1]


def read_statics(code: str, text: str) -> str:
    """The declarations of the statics `text` reads (`Self.pictureSide`), one line each, in their file's order - a size
    moved is a change to what the Mac draws."""
    names = set(re.findall(r"\bSelf\.(\w+)", text))
    lines = [line.strip() for line in code.splitlines()
             if (found := re.search(r"\bstatic (?:let|var) (\w+)\b", line)) and found.group(1) in names]
    assert len(lines) == len(names), (sorted(names), lines)
    return "\n".join(lines)


#? R1c's one-off screens with a Mac half: RefreshProblemNote (the Mac's Downloaded and Songs pages borrow it) and the
#? artist page's top - (R1c's review) its dispatcher with it, `hero()`, so the Mac sent to the phone's top is a change,
#? and the statics it reads (its 200 pt picture); and the review's two, the Downloaded page's first ask (the Mac's
#? Downloaded borrows it) and the empty library's See All music. (R6) The artist's top on the Mac is MacArtistPage's
#? band now - macHero and its dispatcher gone, the whole page the Mac's desk - so the band is pinned in its place, with
#? the drawing's numbers it reads, for the slices after R6 (A2, A4) that touch the artist's page. (R6's review) And the
#? band's shared reads, each drawn by both devices: the artist's picture (ArtistHeroPicture), Last.fm's credit under Top
#? Songs (LastfmCredit) and the foot under their discography (ArtistTheirFoot) - a phone-side change to one is a change
#? to the Mac's page too
PARTS = {
    "RefreshProblemNote": ("Library/AlbumsScreen.swift", [r"struct RefreshProblemNote: View \{"]),
    "MacArtistPage.band": ("Mac/Artist/MacArtistPage.swift", [r"    enum Drawn \{", r"private func band\("]),
    "ArtistHeroPicture": ("Artist/ArtistView.swift", [r"struct ArtistHeroPicture: View \{"]),
    "LastfmCredit": ("Artist/TopSongsSection.swift", [r"struct LastfmCredit: View \{"]),
    "ArtistTheirFoot": ("Artist/ArtistView.swift", [r"struct ArtistTheirFoot: View \{"]),
    "FirstAskCard": ("Library/AlbumsScreen.swift", [r"struct FirstAskCard: View \{"]),
    "EmptyLibraryNote": ("Library/AlbumsScreen.swift", [r"struct EmptyLibraryNote: View \{"]),
}


def mac_halves() -> dict[str, str]:
    found = {}
    for path in sorted((APP / "Look").glob("*.swift")):
        name = path.relative_to(APP).as_posix()
        if name == "Look/DWPalette.swift":
            continue  # its colours: each `dw:` line held to dw.css's Mac root by test_ios_mac_look.py
        found[name] = digest(mac_path(without_phone(name, bare(path.read_text(encoding="utf-8")))))
    for label, (name, starts) in PARTS.items():
        code = bare((APP / name).read_text(encoding="utf-8"))
        mac = mac_path("\n".join(part(code, start) for start in starts))
        found[label] = digest(mac + "\n" + read_statics(code, mac))
    return found


#? as R1c left them - read the same way, each is R2b's code (75ea812e; the fonts, c3c461cd, changed none of them) as the
#? Mac ran it, but for R1c's moves: the chip's face into `faced`, RefreshProblemNote's words into `words`, the artist's
#? top renamed macHero. And for R1c's review's: RefreshProblemNote's face renamed `macCardFace` (the same #1c1b22, the
#? Mac's own now - its digest with the old name is the old pin, 2586cd6415e417ec); the artist's top pinned with its
#? dispatcher and its 200 (macHero alone is still a3c6345e7963ca6a); DWChip's unchanged by `keepsFace` and `.facedChip`
#? (the ternaries read as the Mac's halves); and three new, each R2b's code where the Mac draws it: DWWellField (its Mac
#? half the field as its page drew it), the Downloaded page's first ask (its words moved into `ask`) and the empty
#? library's See All music (inside its `if Platform.mac`). A change to one is a change to what the Mac draws. (R6)
#? ArtistView.macHero's pin (3acb28f11dad5501) retired with it: MacArtistPage's band is R6's own, pinned as R6 left it.
#? (R6's review) The band re-pinned (it was d2227dd82a6d4bf1): its chips take who may get albums, so "10 more to get" is
#? drawn only for them. And its three shared reads pinned as R6 left them.
PINNED = {
    "Look/DWButtonStyle.swift": "05ac2b1f28675581",
    "Look/DWChip.swift": "cf86e3708a29bfc1",
    "Look/DWCorners.swift": "d27587b71394da17",
    "Look/DWField.swift": "b35a4a6a9fa784b8",
    "Look/DWMeter.swift": "12f478f7c6fea571",
    "Look/DWPopUp.swift": "cbc9e3a3694aa415",
    "Look/DWRaised.swift": "77fc96aaa37dfee4",
    "Look/DWSegmented.swift": "8d680fda0b85a713",
    "Look/DWToggleStyle.swift": "1d0c62c233c1c4c6",
    "Look/DWWellField.swift": "24c48997e0b50edb",
    "RefreshProblemNote": "b1701810fad9be68",
    "MacArtistPage.band": "7c6c1f9fac106e83",
    "ArtistHeroPicture": "62b50dcf0400dac1",
    "LastfmCredit": "af492e61b5a3bda3",
    "ArtistTheirFoot": "f19dafdb6bb6738c",
    "FirstAskCard": "f7d6bf161c90975f",
    "EmptyLibraryNote": "72f1e022695aeff8",
}


def test_the_macs_half_of_each_shared_piece_is_pinned():
    found = mac_halves()
    assert found == PINNED, {name: value for name, value in found.items() if PINNED.get(name) != value}


def test_the_phones_own_parts_are_named_from_the_phone_alone():
    # what PHONE_ONLY takes out, the Mac never reaches: each part named only in a phone half
    for name, starts in PHONE_ONLY.items():
        code = bare((APP / name).read_text(encoding="utf-8"))
        mac = mac_path(without_phone(name, code))
        for start in starts:
            word = re.match(r"(?:private )?(?:struct|var|func) (\w+)", start.replace("\\", "")).group(1)
            assert not re.search(rf"\b{word}\b", mac), f"{name}: the Mac reaches {word}"
    # the switch's measure is the phone's Library row's: no Mac page names it
    mac_pages = [path.name for path in sorted((APP / "Mac").rglob("*.swift"))
                 if "DWSegmentedNeed" in path.read_text(encoding="utf-8")]
    library_top = (APP / "Library" / "LibraryTop.swift").read_text(encoding="utf-8")
    assert not mac_pages and "DWSegmentedNeed(words: pages)" in library_top
    chip = mac_path(without_phone("Look/DWChip.swift", bare((APP / "Look" / "DWChip.swift").read_text(encoding="utf-8"))))
    assert "dot" not in re.findall(r"\b\w+\b", chip)
    # (R1c's review) and the New mark's kept face is the phone's alone: the Mac's chip names none of it
    assert not re.search(r"\bkeepsFace\b|\.facedChip\b|\bDWFlat\.", chip), chip
    # (R6) the artist's page on the Mac is its desk, MacArtistPage, top to foot: the phone's top and the phone's rows
    # unreached - the band pinned above, with its picture 88
    artist = bare((APP / "Artist" / "ArtistView.swift").read_text(encoding="utf-8"))
    body = part(artist, r"    var body: some View \{")
    branch = re.search(r"if let desk, Platform\.mac \{", body)
    assert branch, "the desk's branch"
    opened, closed = block(body, branch.start())
    assert re.sub(r"\s+", " ", body[opened + 1:closed]).strip().startswith("desk(artistDesk(rows: rows,")
    assert re.match(r"\s*else \{", body[closed + 1:]), "the phone's page its else"
    assert "macHero" not in artist and "private func hero(" not in artist
    for phone in ("phoneHero(", "albumsList(", "strip(", "topSongs("):
        assert phone not in body[opened:closed], phone
    mac_page = bare((APP / "Mac" / "Artist" / "MacArtistPage.swift").read_text(encoding="utf-8"))
    assert "static let picture: CGFloat = 88" in part(mac_page, r"    enum Drawn \{")


def test_the_mac_path_is_read_as_the_mac_runs_it():
    code = bare("if Platform.mac { a } else { b } if !Platform.mac { c } if on, Platform.mac { d } "
                "if Platform.mac || kind == .pri { e } else { f } x(Platform.mac ? g : h) y(size == .large && "
                "!Platform.mac ? i : j)")
    assert re.sub(r"\s+", " ", mac_path(code)).strip() == "a if on { d } e x(g) y(j)"
