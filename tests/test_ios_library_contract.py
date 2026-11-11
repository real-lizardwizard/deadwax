"""
The iPhone app's Library models against the routes that answer them (notes/ios.md, Phase 1): what
ios/DeadwaxKit/Sources/DeadwaxCore/LibraryModels.swift decodes from GET /deadwax/navidrome/album_index and
GET /deadwax/me/library, and what it sends to POST /deadwax/me/library/seen, read from the Swift source and held to
the server's own names - so a route that renames or strips a field, or a Seen model that changes, fails here, in the
Python suite, where the server is changed, instead of decoding to nil on the phone (an IndexAlbum field the route
strips is silently nil; a field pydantic doesn't declare is dropped without a word).

The models live in LibraryModels.swift, but a model is found wherever in DeadwaxCore it is declared (once), as
tests/test_ios_contract.py finds the rest - read with a reader of this file's own: each struct's stored properties
(its own, not a nested type's, never a static one), named as its CodingKeys say, and whether each is optional.
"""

import inspect
import re
import sys
import typing
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import auth  # noqa: E402
from src.routes import my_library, navidrome  # noqa: E402

CORE = Path(__file__).resolve().parent.parent / "ios" / "DeadwaxKit" / "Sources" / "DeadwaxCore"
SOURCE = CORE / "LibraryModels.swift"


def _block(code: str, opening: int) -> str:
    """What the brace at `opening` holds, up to its partner."""
    depth = 0
    for index in range(opening, len(code)):
        if code[index] == "{":
            depth += 1
        elif code[index] == "}":
            depth -= 1
            if depth == 0:
                return code[opening + 1:index]
    raise AssertionError("unbalanced braces")


def _top_level(body: str) -> str:
    """A block's own text, without what its nested blocks hold."""
    out, depth = [], 0
    for char in body:
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        elif depth == 0:
            out.append(char)
    return "".join(out)


def _body(kind: str, name: str) -> str:
    """The body of `<kind> <name>` in whichever DeadwaxCore file declares it (one only), comments out (none of these
    models' strings hold a brace)."""
    found = []
    for file in sorted(CORE.glob("*.swift")):
        code = re.sub(r"//[^\n]*", "", file.read_text(encoding="utf-8"))
        found += [_block(code, match.end() - 1) for match in re.finditer(r"\b" + kind + r"\s+" + name + r"\b[^{]*\{", code)]
    assert len(found) == 1, f"{kind} {name} is declared {len(found)} times in DeadwaxCore"
    return found[0]


def _coding_keys(body: str) -> dict[str, str] | None:
    """A struct's own CodingKeys, Swift name -> JSON name; None when it has none of its own."""
    match = next((one for one in re.finditer(r"\benum\s+CodingKeys\b[^{]*\{", body)
                  if body.count("{", 0, one.start()) == body.count("}", 0, one.start())), None)
    if not match:
        return None
    keys = {}
    for case in re.findall(r"\bcase\s+(.*?)(?=\bcase\b|\Z)", _block(body, match.end() - 1), re.S):
        for item in case.split(","):
            item = item.strip()
            if not item:
                continue
            named = re.match(r'(\w+)\s*=\s*"([^"]+)"', item)
            word = re.match(r"\w+", item).group(0)
            keys[word] = named.group(2) if named else word
    return keys


def fields(struct: str) -> dict[str, bool]:
    """A struct's stored properties by JSON name -> whether optional."""
    body = _body("struct", struct)
    keys = _coding_keys(body)
    found = {}
    for line in _top_level(body).splitlines():
        stored = re.match(r"\s*(?:public\s+)?(?:let|var)\s+(\w+)\s*:\s*([^=]+?)\s*$", line)
        if not stored:
            continue
        name, kind = stored.groups()
        if keys is not None and name not in keys:
            continue
        found[keys[name] if keys is not None else name] = kind.endswith("?")
    assert found, f"no stored properties read from {struct}"
    return found


def required(struct: str) -> set[str]:
    return {name for name, optional in fields(struct).items() if not optional}


def enum_cases(name: str) -> list[str]:
    return re.findall(r"\bcase\s+(\w+)", _top_level(_body("enum", name)))


def returned_keys(function) -> list[set[str]]:
    """The top-level keys of each dict literal a route function returns, read from its source."""
    source = inspect.getsource(function)
    return [set(re.findall(r'"(\w+)":', _top_level(_block(source, match.end() - 1))))
            for match in re.finditer(r"\breturn \{", source)]


# ---------------------------------------------------------------------------- the reader itself

def test_the_reader_reads_what_it_should():
    # a guard on the guard: CodingKeys rename, a `var` is stored, a static or computed property is not a field
    assert fields("LibraryEntry")["album_id"] is False and "albumID" not in fields("LibraryEntry")
    assert fields("SeenBody") == {"release_mbid": True, "album_ids": True}
    assert "new" in fields("MyLibrary")
    assert "fieldNames" not in fields("IndexAlbum") and len(fields("IndexAlbum")) == 14
    assert enum_cases("AlbumScope") == ["yours", "store"]
    assert returned_keys(my_library.seen) == [{"cleared"}, {"cleared"}]


# ---------------------------------------------------------------------------- /navidrome/album_index

def test_every_field_the_library_reads_is_one_the_album_index_sends():
    # a field the route doesn't keep would always be nil on the phone: no date, no cover, no year
    assert set(fields("IndexAlbum")) == set(navidrome.INDEX_FIELDS)
    assert required("IndexAlbum") == {"id"}


def test_the_album_index_answer_is_both_keys_always():
    assert required("AlbumIndexAnswer") == {"albums", "truncated"}
    assert '{"albums": albums, "truncated": truncated}' in inspect.getsource(navidrome.album_index)


def test_the_scopes_are_the_servers():
    # a scope the server doesn't know is a 422 for the whole Library
    assert tuple(enum_cases("AlbumScope")) == typing.get_args(navidrome.AlbumScope)
    assert set(enum_cases("AlbumScope")) == set(navidrome.SCOPE_LIST)


# ---------------------------------------------------------------------------- /me/library

def test_an_entry_is_what_the_route_names_it_and_never_null_where_required():
    entry = my_library._entry({"album_id": 7, "artist": None, "album": None})
    assert set(fields("LibraryEntry")) == set(entry)
    assert required("LibraryEntry") == {"album_id", "artist", "album"}
    #? a null where the Swift has a plain String would fail the whole answer's decoding
    assert entry["album_id"] == 7 and entry["artist"] == "" and entry["album"] == ""


def test_my_library_is_read_from_keys_every_answer_has():
    answers = returned_keys(my_library.my_library)
    assert len(answers) == 5, answers
    assert all("on" in keys for keys in answers), answers
    assert required("MyLibrary") == {"on"}
    sent = set().union(*answers)
    assert set(fields("MyLibrary")) <= sent, set(fields("MyLibrary")) - sent


def test_seen_sends_the_fields_the_route_declares():
    # pydantic drops an undeclared field without a word: the phone would clear nothing
    assert set(fields("SeenBody")) == set(my_library.Seen.model_fields)
    assert required("SeenBody") == set()


def test_the_break_glass_name_is_the_servers():
    found = re.search(r'public static let breakGlassUser = "([^"]+)"', SOURCE.read_text(encoding="utf-8"))
    assert found and found.group(1) == auth.BREAK_GLASS_USER
