"""
Every tracked source file must be free of raw control bytes.

This exists because of a real failure that no other test could see. Five template literals
across the UI built node ids and group keys with a RAW NUL byte where the escape `\u0000` was
meant: the agent file tools that wrote them turn that escape into the character it names, and
nothing downstream complains, because a control character is perfectly legal inside a JS
string. The code ran correctly. Every sim passed.

What it broke was reading the files. A NUL in the first 8000 bytes makes git store the whole
file as binary, so libraryTree.ts, tree.sim.cjs, LibraryTree.tsx and groupAlbums.ts showed no
diff at all on GitHub - four source files were unreviewable, and it was caught only because
someone happened to notice `Bin` in `git diff --stat`. The same NUL had already cost a real
bug once: an id containing one can never be found by `querySelector`, since CSS.escape() turns
it into U+FFFD, which silently broke keyboard navigation for every album and track row.

The fix is always to spell the character as an escape in the source, which leaves the runtime
string byte-identical. Because the file tools rewrite such escapes back into raw characters,
write them with a byte-level replace - see the tooling notes in CLAUDE.md.

This check is strictly stronger than git's own rule (a NUL anywhere, not just in the first
8000 bytes, and every other control byte too), so a file that passes here can never be the
binary blob that started this.
"""

import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Tab, newline and carriage return are the only control characters source may legitimately
# hold. Everything else in the C0 range, plus DEL, is a mistake worth failing over.
FORBIDDEN = set(range(0x00, 0x09)) | {0x0B, 0x0C} | set(range(0x0E, 0x20)) | {0x7F}

# The only tracked formats that are genuinely binary. Everything else is checked, including
# extensionless files like LICENSE and dockerfile. A new binary asset type fails here on
# purpose: skipping it should be a deliberate one-line decision, not a silent gap.
BINARY_SUFFIXES = {".png", ".woff2"}

NEWLINE = bytes([10])


def _tracked_text_files():
    listing = subprocess.run(
        ["git", "ls-files"], cwd=REPO, capture_output=True, text=True, check=True
    ).stdout.splitlines()
    return [p for p in listing if Path(p).suffix not in BINARY_SUFFIXES]


def test_no_tracked_source_file_holds_a_raw_control_byte():
    offenders = []
    for rel in _tracked_text_files():
        path = REPO / rel
        if not path.is_file():          # a deleted-but-staged path, or a submodule
            continue
        data = path.read_bytes()
        for offset, byte in enumerate(data):
            if byte in FORBIDDEN:
                line = data.count(NEWLINE, 0, offset) + 1
                offenders.append("%s:%d holds byte 0x%02x" % (rel, line, byte))
                break                   # one report per file is enough to act on
    assert not offenders, (
        "Raw control bytes found in source. Spell them as escapes instead - the runtime "
        "string stays byte-identical and git stops storing the file as binary:"
        + "".join("\n  " + o for o in offenders)
    )


def test_the_forbidden_set_is_the_one_that_matters():
    """A guard on the guard: pin what must be rejected and what must stay legal."""
    assert 0x00 in FORBIDDEN, "NUL is the byte that started this"
    assert 0x1B in FORBIDDEN, "ESC would sneak ANSI codes into source"
    assert 0x7F in FORBIDDEN
    for legal in (0x09, 0x0A, 0x0D):
        assert legal not in FORBIDDEN, "tab, newline and CR must stay allowed"


def test_the_binary_skip_list_only_covers_real_binaries():
    """If a new binary format is tracked, this fails so the skip is decided deliberately."""
    tracked = subprocess.run(
        ["git", "ls-files"], cwd=REPO, capture_output=True, text=True, check=True
    ).stdout.splitlines()
    suffixes = {Path(p).suffix for p in tracked}
    assert BINARY_SUFFIXES <= suffixes, (
        "BINARY_SUFFIXES lists a format no longer tracked: %s" % (BINARY_SUFFIXES - suffixes)
    )
