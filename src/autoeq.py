"""
AutoEq's corrections, for the iPhone app's EQ (2.1.7) - the list's parsing, folding and search, one row per
headphone, each result's id and its profile's address. notes/ios-specs/eq.md (on `ios`) section 2 is the spec;
notes/ios.md "The EQ's AutoEq routes (2.1.7)" what was built.

PURE - no I/O, the reason matching.py, descriptions.py and artists.py are: asking GitHub is
src/api/autoeq_endpoint.py's, keeping and the two routes src/routes/eq.py's.

AutoEq (github.com/jaakkopasanen/AutoEq, Jaakko Pasanen, MIT - its results included; the measurements behind
them are oratory1990's, crinacle's and the other sources') publishes `results/INDEX.md`: "# Index", a paragraph,
then one line per result -

    - [Apple AirPods Pro](./crinacle/711%20in-ear/Apple%20AirPods%20Pro) by crinacle on 711

- the name; the result's folder under results/ (`<source>/<rig folder>/<name>`); who measured it, and on what
rig. The path is percent-encoded only where a URL needs it: spaces, and every byte of a letter outside ASCII
(`A%C3%BCR Audio Aure`) - parentheses, `&` and `+` are left raw (`Bruel%20&%20Kjaer%205128%20in-ear`,
`Apple%20AirPods%20Pro%202%20(51dB%20+%20ANC)`). So the path is DECODED ONCE, as the list is read, and kept
decoded; an address is made by encoding each segment whole - never the list's own encoding passed on, which
would send `&` and `+` raw and make a `%20` a `%2520`.

Every line of INDEX.md at 7ae0f56 (8,850 results) was checked against these rules when this was written: each
parses, its source is its path's first segment, its rig the rig folder less the form, its name the last segment.
"""

import hashlib
import re
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timezone
from urllib.parse import quote, unquote

REPO = "jaakkopasanen/AutoEq"
#? AutoEq's default branch - its commit is asked for, and everything after is fetched at that commit
BRANCH = "master"
#? GitHub's three kinds of address, and the only ones deadwax asks it: master's commit (a bare 40-hex answer
#? with Accept: application/vnd.github.sha), the list at that commit, and a profile at that commit
COMMIT_URL = f"https://api.github.com/repos/{REPO}/commits/{BRANCH}"
COMMIT_ACCEPT = "application/vnd.github.sha"
RAW = f"https://raw.githubusercontent.com/{REPO}"

SHA = re.compile(r"^[0-9a-f]{40}$")
#? a result's id: 16 lowercase hex digits (the route's 422 otherwise)
ID_PATTERN = r"^[0-9a-f]{16}$"

#? the forms a rig folder ends in (`711 in-ear`, `HMS II.3 over-ear`, `earbud`)
FORMS = ("in-ear", "over-ear", "earbud")

#? The order sources are offered in when one headphone was measured by several: the first is the row's own, the
#? rest its `others`, then every other source by name. The spec asks for AutoEq's own order of trust "as its README
#? states it when the slice is built" - and its README (master, read 2026-11-12, the same at 7ae0f56) states none:
#? it lists where its measurements come from (oratory1990, crinacle, Innerfidelity, Rtings and the legacy
#? headphone.com ones) without ranking them, and results/README.md says its recommended list keeps "the one with
#? the highest accuracy" without naming the order it uses. So this is the spec's fallback, as eq.md 2.1 gives it.
SOURCE_ORDER = ("oratory1990", "crinacle", "Super Review", "HypetheSonics", "Rtings", "Innerfidelity",
                "Headphone.com Legacy")

#? Sizes past which an answer is refused, as "can't reach AutoEq" (the list at 7ae0f56 is 851,757 bytes; a
#? ParametricEQ.txt is about 500)
LIST_MAX_BYTES = 8 * 1024 * 1024
PROFILE_MAX_BYTES = 64 * 1024

#? The list is fetched again when older than this - in the background, the old one answering meanwhile
REFRESH_SECONDS = 7 * 24 * 3600
#? ...and, after a refresh failed, not asked again for this long (a list is still answering): every search
#? would otherwise ask GitHub again while it is down or refusing
RETRY_SECONDS = 15 * 60
#? With no list at all, the most a search or a profile waits for the first one
FIRST_FETCH_SECONDS = 15.0
#? ...and, after that fetch failed, how long every ask is answered "can't reach AutoEq" at once without asking
#? GitHub again: a picker searching as it is typed into would otherwise spend GitHub's 60 an hour while it refuses
NO_LIST_RETRY_SECONDS = 60
#? The most a WHOLE fetch may take - httpx's 15 s is only between pieces, so an answer trickling in would hold a fetch
#? open for as long as it trickled: the list's (master's commit asked first, and counted), and a profile's
LIST_DEADLINE_SECONDS = 60.0
PROFILE_DEADLINE_SECONDS = 15.0

LINE_START = "- ["
NAME_END = "](./"
SOURCE_START = ") by "
RIG_START = " on "

_RUNS = re.compile(r"[^\W_]+")

#? Latin letters NFKD leaves whole - each is one letter, not a base and a mark, so dropping marks keeps it as it is -
#? folded to the plain letters a person types for them, so "rode" finds the RØDE NTH-100 as "røde" does. Applied
#? after casefold, so each is listed once, in lower case (`Ø` is `ø` by then); `ß` needs no entry, casefold makes it
#? `ss`. Letters with no one plain spelling (`ŋ`, `ĸ`) are left as they are.
LETTERS = str.maketrans({"æ": "ae", "ð": "d", "đ": "d", "ħ": "h", "ı": "i", "ł": "l", "ø": "o", "œ": "oe", "ŧ": "t",
                         "þ": "th"})


@dataclass(frozen=True)
class Result:
    """One line of INDEX.md: one measurement of one headphone, corrected by AutoEq."""
    id: str
    name: str
    source: str
    rig: str | None
    form: str | None
    #? decoded, without the list's `./`: `HypetheSonics/Bruel & Kjaer 5128 in-ear/Apple AirPods Pro`
    path: str
    folded: str


@dataclass(frozen=True)
class Row:
    """One headphone: every result whose name folds the same, the best source first."""
    folded: str
    #? the folded name with its spaces taken out, and where each of its words starts in it
    compact: str
    starts: tuple[int, ...]
    results: tuple[Result, ...]


def fold(text: str) -> str:
    """A name or a query as searching compares them: NFKD, marks dropped, lowercased (casefold, so a `ß` is `ss`),
    the letters NFKD keeps whole made plain (LETTERS: `ø` is `o`, `æ` is `ae`), every run of anything not a letter or
    digit one space."""
    decomposed = unicodedata.normalize("NFKD", text or "")
    unmarked = "".join(c for c in decomposed if not unicodedata.combining(c))
    return " ".join(_RUNS.findall(unmarked.casefold().translate(LETTERS)))


def result_id(path: str) -> str:
    """A result's id: the first 16 hex digits of SHA-1 of "autoeq:" and its decoded path - stable while AutoEq keeps
    the path, and nothing a person types."""
    return hashlib.sha1(f"autoeq:{path}".encode("utf-8")).hexdigest()[:16]


def rig_and_form(folder: str) -> tuple[str | None, str | None]:
    """The rig folder as shown: (`711`, `in-ear`) from `711 in-ear`, (None, `over-ear`) from `over-ear`, and the
    folder itself with no form when it names none."""
    for form in FORMS:
        if folder == form:
            return None, form
        if folder.endswith(" " + form):
            return folder[:-len(form)].strip() or None, form
    return folder or None, None


def parse_line(line: str) -> Result | None:
    """
    One result line, or None when it doesn't parse. The name is between `- [` and the first `](./`; the path from
    there to the LAST `) by ` (names and paths hold parentheses); the source and rig from ` by <source>[ on <rig>]`.
    The path must be `<source>/<rig folder>/<name>`, three segments none empty, `.` or `..`.
    """
    line = line.rstrip("\r\n")
    if not line.startswith(LINE_START):
        return None
    name_end = line.find(NAME_END)
    if name_end < 0:
        return None
    name = line[len(LINE_START):name_end].strip()
    rest = line[name_end + len(NAME_END):]
    path_end = rest.rfind(SOURCE_START)
    if not name or path_end < 0:
        return None
    path = unquote(rest[:path_end])
    said = rest[path_end + len(SOURCE_START):].strip()
    segments = path.split("/")
    if len(segments) != 3 or any(segment in ("", ".", "..") or segment != segment.strip() for segment in segments):
        return None
    #? the source as the line says it - read as the path's own first segment when the line starts with it, so a
    #? source whose name held " on " would still be whole
    if said == segments[0] or said.startswith(segments[0] + RIG_START):
        source = segments[0]
    else:
        source = said.split(RIG_START, 1)[0].strip()
    if not source:
        return None
    rig, form = rig_and_form(segments[1])
    folded = fold(name)
    if not folded:
        return None
    return Result(id=result_id(path), name=name, source=source, rig=rig, form=form, path=path, folded=folded)


def parse_index(text: str) -> tuple[list[Result], int]:
    """INDEX.md's results, in its order, and how many lines that look like results (`- `) didn't parse. The heading,
    its paragraph and blank lines are not results. A path listed twice is one result."""
    results: list[Result] = []
    seen: set[str] = set()
    skipped = 0
    for line in (text or "").splitlines():
        if not line.startswith("- "):
            continue
        result = parse_line(line)
        if result is None:
            skipped += 1
        elif result.id not in seen:
            seen.add(result.id)
            results.append(result)
    return results, skipped


def kept_results(rows: list[dict]) -> list[Result]:
    """A list kept in the database (store.py autoeq_list_get's rows) as results, every name FOLDED AGAIN as fold() is
    now: the `folded` kept beside it is the fold of the deadwax that kept it, and an unchanged commit keeps a list for
    months, so a change to fold() reaches it at the next start, not at AutoEq's next commit. A name that folds to
    nothing is no result, as parse_line() has it."""
    results = []
    for row in rows:
        folded = fold(row["name"])
        if folded:
            results.append(Result(**{**row, "folded": folded}))
    return results


def source_rank(result: Result) -> tuple:
    """Where a result's source stands: SOURCE_ORDER's first, then every other source by name; one source's own
    results by rig, then path, so the order never depends on the list's."""
    known = SOURCE_ORDER.index(result.source) if result.source in SOURCE_ORDER else len(SOURCE_ORDER)
    return known, result.source.casefold(), result.source, (result.rig or "").casefold(), result.path


def rows_of(results: list[Result]) -> list[Row]:
    """One row per headphone - results with the same folded name together, the best source first - in folded
    order."""
    grouped: dict[str, list[Result]] = {}
    for result in results:
        grouped.setdefault(result.folded, []).append(result)
    rows = []
    for folded in sorted(grouped):
        words = folded.split(" ")
        starts, at = [], 0
        for word in words:
            starts.append(at)
            at += len(word)
        rows.append(Row(folded=folded, compact="".join(words), starts=tuple(starts),
                        results=tuple(sorted(grouped[folded], key=source_rank))))
    return rows


def query_words(query: str) -> list[str]:
    return fold(query).split()


def matches(row: Row, words: list[str]) -> bool:
    """Every word of the query is in the folded name with its spaces taken out: "hd650" and "hd 650" both find
    "Sennheiser HD 650"."""
    return all(word in row.compact for word in words)


def starts_words(row: Row, words: list[str]) -> bool:
    """Every query word starts a word of the name - found in the compact name where one of the name's words begins,
    so "hd650" starts "hd" in "Sennheiser HD 650" as "hd" does."""
    return all(any(row.compact.startswith(word, start) for start in row.starts) for word in words)


def search(rows: list[Row], query: str) -> list[Row]:
    """The rows a query finds, ranked: names where every query word starts a word first, then shorter names, then by
    name. A query with no letter or digit in it finds nothing."""
    words = query_words(query)
    if not words:
        return []
    found = [row for row in rows if matches(row, words)]
    return sorted(found, key=lambda row: (not starts_words(row, words), len(row.folded), row.folded,
                                          row.results[0].name))


def _place(result: Result) -> dict:
    return {"id": result.id, "source": result.source, "rig": result.rig, "form": result.form}


def row_answer(row: Row) -> dict:
    """A search result as the route answers it: the best source's result, and the others under it."""
    best = row.results[0]
    return {"id": best.id, "name": best.name, "source": best.source, "rig": best.rig, "form": best.form,
            "others": [_place(result) for result in row.results[1:]]}


def profile_answer(result: Result, text: str) -> dict:
    return {"id": result.id, "name": result.name, "source": result.source, "rig": result.rig, "form": result.form,
            "text": text}


def when(seconds: float) -> str:
    """A time as the answers say it: UTC, to the second (`2026-11-10T04:12:00Z`)."""
    return datetime.fromtimestamp(seconds, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def is_stale(fetched_at: float | None, now: float) -> bool:
    return fetched_at is None or now - fetched_at >= REFRESH_SECONDS


def _commit(sha: str) -> str:
    if not SHA.match(sha or ""):
        raise ValueError(f"not a commit: {sha!r}")
    return sha


def _encoded(segment: str) -> str:
    #? every character a path segment could hold that isn't unreserved, `&`, `+`, `(`, `)` and `/` included
    return quote(segment, safe="")


def index_url(sha: str) -> str:
    """The list's address at one commit."""
    return f"{RAW}/{_commit(sha)}/results/INDEX.md"


def profile_url(sha: str, path: str) -> str:
    """A result's ParametricEQ.txt at one commit: `results/<path>/<name> ParametricEQ.txt`, `<name>` the path's last
    segment, each segment encoded whole exactly once. `path` is always one from deadwax's own list."""
    segments = path.split("/")
    folder = "/".join(_encoded(segment) for segment in segments)
    return f"{RAW}/{_commit(sha)}/results/{folder}/{_encoded(segments[-1] + ' ParametricEQ.txt')}"
