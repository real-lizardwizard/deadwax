"""
AutoEq through deadwax, for the iPhone app's EQ (2.1.7) - src/autoeq.py (pure), src/api/autoeq_endpoint.py and the
routes `GET /deadwax/eq/autoeq` and `GET /deadwax/eq/autoeq/{id}` (src/routes/eq.py), through the whole app,
start(), with a real SQLite store and an httpx MockTransport for GitHub. notes/ios-specs/eq.md (on `ios`) 2.5 lists
what these hold; the suite never calls out.

The fixtures (tests/fixtures/autoeq/, its README says where each came from): 46 lines of AutoEq's results/INDEX.md
at 7ae0f56 - its heading, the AirPods Pro from four sources and the AirPods Pro 2's, the HD 650 from seven, names
with parentheses, `&` and `+` raw in paths, a path with a letter outside ASCII percent-encoded, every form - and
ONE line written for these tests that doesn't parse; and two ParametricEQ.txt files, unchanged.

The fake GitHub answers as the real one was seen to on 2026-11-12 (by hand, with curl): master's commit with
`Accept: application/vnd.github.sha` is the bare 40 hex digits; raw.githubusercontent.com decodes a path ONCE, so
`Bruel%20%26%20Kjaer` is the folder `Bruel & Kjaer` and `711%2520in-ear` is a 404.
"""

import asyncio
import hashlib
import logging
import re
import sqlite3
import sys
import time
from contextlib import asynccontextmanager, contextmanager
from pathlib import Path
from urllib.parse import unquote

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import __version__  # noqa: E402
from src import autoeq as A  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.autoeq_endpoint import Unreachable, autoeq_client  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import eq as eq_route  # noqa: E402
from src.store import JobStore  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "autoeq"
INDEX = (FIXTURES / "INDEX.md").read_text(encoding="utf-8")

#? the commit the fixtures were taken at, and a later one
OLD = "7ae0f56d53074872b028649617a22bbb4232feb7"
NEW = "0123456789abcdef0123456789abcdef01234567"

AIRPODS_PRO = "crinacle/711 in-ear/Apple AirPods Pro"
HD650 = "oratory1990/over-ear/Sennheiser HD 650"
BK_AIRPODS = "HypetheSonics/Bruel & Kjaer 5128 in-ear/Apple AirPods Pro"
PRO2_51 = "crinacle/711 in-ear/Apple AirPods Pro 2 (51dB + ANC)"
AUR = "Kazi/in-ear/AüR Audio Aure"
INNERFIDELITY_HD650 = "- [Sennheiser HD 650](./Innerfidelity/over-ear/Sennheiser%20HD%20650) by Innerfidelity\n"


def profile_file(path: str) -> str:
    name = path.rsplit("/", 1)[-1]
    return (FIXTURES / "results" / path / f"{name} ParametricEQ.txt").read_text(encoding="utf-8")


AIRPODS_PRO_TEXT = profile_file(AIRPODS_PRO)
HD650_TEXT = profile_file(HD650)


def rid(path: str) -> str:
    return hashlib.sha1(f"autoeq:{path}".encode("utf-8")).hexdigest()[:16]


# ----------------------------------------------------------------- the fake GitHub

class GitHub:
    """api.github.com's commit and raw.githubusercontent.com's files, as AutoEq's repository has them: `lists` by
    commit, `files` by (commit, decoded path under results/). Every request kept."""

    def __init__(self):
        self.master = OLD
        self.lists = {OLD: INDEX}
        self.files = {(OLD, f"{AIRPODS_PRO}/Apple AirPods Pro ParametricEQ.txt"): AIRPODS_PRO_TEXT,
                      (OLD, f"{HD650}/Sennheiser HD 650 ParametricEQ.txt"): HD650_TEXT}
        self.requests: list[httpx.Request] = []
        self.down = False
        #? answered instead, by kind - "commit", "list" or "profile" - as (status, body)
        self.instead: dict[str, tuple[int, str]] = {}
        self.delay = 0.0

    async def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if self.delay:
            await asyncio.sleep(self.delay)
        if self.down:
            raise httpx.ConnectError("no route to host")
        url = request.url
        if url.host == "api.github.com":
            if url.raw_path.decode() != "/repos/jaakkopasanen/AutoEq/commits/master":
                return httpx.Response(404, json={"message": "Not Found"})
            if "commit" in self.instead:
                return httpx.Response(self.instead["commit"][0], text=self.instead["commit"][1])
            if request.headers.get("accept") != "application/vnd.github.sha":
                return httpx.Response(200, json={"sha": self.master})
            return httpx.Response(200, text=self.master)
        if url.host != "raw.githubusercontent.com":
            return httpx.Response(404)
        prefix = "/jaakkopasanen/AutoEq/"
        raw = url.raw_path.decode()
        if not raw.startswith(prefix):
            return httpx.Response(404, text="404: Not Found")
        sha, _, rest = raw[len(prefix):].partition("/")
        if rest == "results/INDEX.md":
            if "list" in self.instead:
                return httpx.Response(self.instead["list"][0], text=self.instead["list"][1])
            found = self.lists.get(sha)
            return httpx.Response(200, text=found) if found is not None else httpx.Response(404, text="404: Not Found")
        if "profile" in self.instead:
            return httpx.Response(self.instead["profile"][0], text=self.instead["profile"][1])
        #? decoded ONCE, as GitHub does
        found = self.files.get((sha, unquote(rest[len("results/"):]))) if rest.startswith("results/") else None
        return httpx.Response(200, text=found) if found is not None else httpx.Response(404, text="404: Not Found")

    def asked(self) -> list[str]:
        return [f"{request.url.host}{request.url.raw_path.decode()}" for request in self.requests]

    def raw_paths(self) -> list[str]:
        return [request.url.raw_path.decode() for request in self.requests]


@asynccontextmanager
async def no_lifespan(app):
    #? nothing connects: no slskd, no poller - one event loop for the whole test, so a background refresh runs
    yield


@contextmanager
def serving(store: JobStore):
    app = start()
    app.state.store = store
    app.router.lifespan_context = no_lifespan
    with TestClient(app) as client:
        yield app, client


class Env:
    pass


@pytest.fixture
def env(tmp_path):
    hub = GitHub()
    autoeq_client._client = httpx.AsyncClient(transport=httpx.MockTransport(hub.handle), follow_redirects=False)
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    e = Env()
    e.hub, e.store, e.db = hub, store, tmp_path / "deadwax.db"
    with serving(store) as (app, client):
        e.app, e.client = app, client
        yield e
    asyncio.run(autoeq_client.close_client())
    autoeq_client._client = None


def search(env, q, **params):
    return env.client.get("/deadwax/eq/autoeq", params={"q": q, **params})


def profile(env, path_or_id):
    return env.client.get(f"/deadwax/eq/autoeq/{path_or_id if '/' not in path_or_id else rid(path_or_id)}")


def settle(env) -> None:
    """Wait for a background refresh to finish (or fail)."""
    async def wait():
        task = env.app.state.autoeq.refreshing
        if task is not None:
            try:
                await task
            except Unreachable:
                pass
    env.client.portal.call(wait)


def age(env, days: float) -> None:
    """The kept list made `days` older, in memory and in the database."""
    kept = env.app.state.autoeq
    kept.fetched_at -= days * 86400
    with sqlite3.connect(env.db) as connection:
        connection.execute("UPDATE autoeq_meta SET fetched_at = ?", (kept.fetched_at,))


def kept_profiles(env) -> list[tuple[str, str]]:
    with sqlite3.connect(env.db) as connection:
        return connection.execute("SELECT id, sha FROM autoeq_profile ORDER BY id").fetchall()


def names(answer) -> list[str]:
    return [row["name"] for row in answer.json()["results"]]


def by_name(results: list[A.Result]) -> dict[str, A.Result]:
    return {result.path: result for result in results}


# ----------------------------------------------------------------- parsing

def test_the_list_is_parsed_name_path_source_rig_and_form():
    results, skipped = A.parse_index(INDEX)
    #? 43 result lines, one of them written not to parse
    assert (len(results), skipped) == (42, 1)
    found = by_name(results)

    crinacle = found[AIRPODS_PRO]
    assert (crinacle.name, crinacle.source, crinacle.rig, crinacle.form) == ("Apple AirPods Pro", "crinacle", "711", "in-ear")
    #? no rig named: the folder is the form alone
    super_review = found["Super Review/in-ear/Apple AirPods Pro"]
    assert (super_review.source, super_review.rig, super_review.form) == ("Super Review", None, "in-ear")
    #? `&` raw in the list, a rig of several words
    bk = found[BK_AIRPODS]
    assert (bk.source, bk.rig, bk.form) == ("HypetheSonics", "Bruel & Kjaer 5128", "in-ear")
    #? parentheses and `+` in the name and the path; the path decoded once
    pro2 = found[PRO2_51]
    assert pro2.name == "Apple AirPods Pro 2 (51dB + ANC)" and (pro2.rig, pro2.form) == ("711", "in-ear")
    #? a letter outside ASCII is percent-encoded in the list (A%C3%BCR), and decoded
    assert found[AUR].name == "AüR Audio Aure" and found[AUR].source == "Kazi"
    #? `+` in a rig folder, and over-ear
    abyss = found["crinacle/EARS + 711 over-ear/Abyss AB-1266 Phi CC Lite"]
    assert (abyss.rig, abyss.form) == ("EARS + 711", "over-ear")
    #? earbuds, with and without a rig
    assert (found["Rtings/HMS II.3 earbud/Apple EarPods"].rig, found["Rtings/HMS II.3 earbud/Apple EarPods"].form) == \
        ("HMS II.3", "earbud")
    assert (found["Super Review/earbud/Apple EarPods"].rig, found["Super Review/earbud/Apple EarPods"].form) == (None, "earbud")
    #? a source of two words, the path's first segment
    assert found["Headphone.com Legacy/over-ear/Sennheiser HD 650"].source == "Headphone.com Legacy"
    worn = found["crinacle/GRAS 43AG-7 over-ear/Sennheiser HD 650 (2020, worn earpads)"]
    assert worn.name == "Sennheiser HD 650 (2020, worn earpads)" and worn.rig == "GRAS 43AG-7"
    #? the list's encoding is gone from every path
    assert not any("%" in result.path for result in results)
    assert "Not a result (no source)" not in {result.name for result in results}


def test_every_id_is_sixteen_hex_of_sha1_of_the_decoded_path():
    results, _ = A.parse_index(INDEX)
    for result in results:
        assert re.fullmatch(A.ID_PATTERN, result.id)
        assert result.id == hashlib.sha1(f"autoeq:{result.path}".encode("utf-8")).hexdigest()[:16]
    assert len({result.id for result in results}) == len(results)
    #? stable: the same path, the same id, whatever else the list holds
    assert A.result_id(AIRPODS_PRO) == rid(AIRPODS_PRO) == by_name(A.parse_index(INDEX)[0])[AIRPODS_PRO].id


def test_a_line_that_doesn_t_parse_is_skipped_and_counted():
    good = "- [Apple AirPods Pro](./crinacle/711%20in-ear/Apple%20AirPods%20Pro) by crinacle on 711"
    assert A.parse_line(good) is not None
    for bad in (
        "- [Sennheiser HD 600](./oratory1990/over-ear/Sennheiser%20HD%20600)",            # no source
        "- [Sennheiser HD 600](oratory1990/over-ear/Sennheiser%20HD%20600) by oratory1990",  # no `](./`
        "- [Sennheiser HD 600](./oratory1990/Sennheiser%20HD%20600) by oratory1990",       # two segments
        "- [x](./oratory1990/../x) by oratory1990",                                       # `..`
        "- [x](./oratory1990//x) by oratory1990",                                         # an empty segment
        "- [](./oratory1990/over-ear/x) by oratory1990",                                  # no name
        "- [!!!](./oratory1990/over-ear/!!!) by oratory1990",                             # nothing to search by
        "- [x](./oratory1990/over-ear/x) by ",                                            # no source
    ):
        assert A.parse_line(bad) is None, bad
    #? the heading, its paragraph and blank lines are not results, and not counted
    assert A.parse_index("# Index\nSome words.\n\n" + good + "\n- not a result\n")[1] == 1
    assert len(A.parse_index(good + "\n" + good + "\n")[0]) == 1


def test_the_path_runs_to_the_last_by():
    """Names and paths hold parentheses (eq.md 2.1): the path ends at the LAST `) by ` - here a path written with its
    spaces raw, which AutoEq's list never has, but which must not cut the path short."""
    result = A.parse_line("- [Foo (made by Bar)](./src/in-ear/Foo (made) by Bar) by src")
    assert (result.path, result.source) == ("src/in-ear/Foo (made) by Bar", "src")


def test_a_source_with_on_in_its_name_stays_whole():
    line = "- [Thing](./Hang%20on%20Audio/in-ear/Thing) by Hang on Audio"
    assert A.parse_line(line).source == "Hang on Audio"
    line = "- [Thing](./Hang%20on%20Audio/GRAS%20in-ear/Thing) by Hang on Audio on GRAS"
    result = A.parse_line(line)
    assert (result.source, result.rig) == ("Hang on Audio", "GRAS")


# ----------------------------------------------------------------- addresses

def test_each_profile_address_has_every_segment_encoded_exactly_once():
    raw = f"https://raw.githubusercontent.com/jaakkopasanen/AutoEq/{OLD}/results/"
    assert A.profile_url(OLD, BK_AIRPODS) == (
        raw + "HypetheSonics/Bruel%20%26%20Kjaer%205128%20in-ear/Apple%20AirPods%20Pro/Apple%20AirPods%20Pro%20ParametricEQ.txt")
    assert A.profile_url(OLD, PRO2_51) == (
        raw + "crinacle/711%20in-ear/Apple%20AirPods%20Pro%202%20%2851dB%20%2B%20ANC%29/"
        "Apple%20AirPods%20Pro%202%20%2851dB%20%2B%20ANC%29%20ParametricEQ.txt")
    assert A.profile_url(OLD, AUR) == raw + "Kazi/in-ear/A%C3%BCR%20Audio%20Aure/A%C3%BCR%20Audio%20Aure%20ParametricEQ.txt"
    for result in A.parse_index(INDEX)[0]:
        url = A.profile_url(OLD, result.path)
        assert "%25" not in url and " " not in url and "&" not in url and "+" not in url and "(" not in url
        #? decoded once, it is the path again
        assert unquote(url[len(raw):]) == f"{result.path}/{result.path.rsplit('/', 1)[-1]} ParametricEQ.txt"
    assert A.index_url(OLD) == f"https://raw.githubusercontent.com/jaakkopasanen/AutoEq/{OLD}/results/INDEX.md"
    #? only ever at a commit
    with pytest.raises(ValueError):
        A.profile_url("master", AIRPODS_PRO)


# ----------------------------------------------------------------- folding and search

def test_folding_drops_marks_case_and_punctuation():
    assert A.fold("Sennheiser HD 650") == "sennheiser hd 650"
    assert A.fold("AüR Audio Aure") == "aur audio aure"
    assert A.fold("Apple AirPods Pro 2 (51dB + ANC)") == "apple airpods pro 2 51db anc"
    assert A.fold("  Bruel & Kjaer\t5128 ") == "bruel kjaer 5128"
    assert A.fold("Bose QuietComfort 35 II Gaming Headset" + chr(0x200B)) == "bose quietcomfort 35 ii gaming headset"
    assert A.fold("Straße") == "strasse"
    assert A.fold("!!!") == ""


ROWS = A.rows_of(A.parse_index(INDEX)[0])


def found(q: str) -> list[str]:
    return [row.results[0].name for row in A.search(ROWS, q)]


def test_hd650_and_hd_650_find_the_same():
    assert found("hd650") == found("HD 650") == found("hd-650") == [
        "Sennheiser HD 650", "Sennheiser HD 650 (2020)", "Sennheiser HD 650 (balanced)",
        "Sennheiser HD 650 (2020, worn earpads)", "Sennheiser HD 650 (pre-2020, worn earpads)",
        "Sennheiser HD 650 (pre-2020, semi-worn earpads)"]


def test_airpods_pro_and_the_ranking():
    #? every word starts a word of each; then shorter names, then by name - "(51dB + ANC)" and "(ANC mode)" fold
    #? to 28 letters each, and "51db" sorts before "anc"
    assert found("airpods pro")[:5] == ["Apple AirPods Pro", "Apple AirPods Pro2", "Apple Airpods Pro 2",
                                        "Apple AirPods Pro 2 (51dB + ANC)", "Apple AirPods Pro 2 (56dB + ANC)"]
    assert found("airpods pro").index("Apple AirPods Pro 2 (ANC mode)") == 14
    assert len(found("airpods pro")) == 17
    #? "2" starts no word of "Pro2": the shortest name comes last
    ranked = found("pro 2")
    assert ranked[0] == "Apple Airpods Pro 2" and ranked[-1] == "Apple AirPods Pro2"
    assert ranked[1:-1] == sorted(ranked[1:-1], key=lambda name: (len(A.fold(name)), A.fold(name)))


def test_accents_punctuation_and_no_match():
    assert found("aur") == found("AüR") == found("aür audio") == ["AüR Audio Aure"]
    assert found("airpods-pro 2 (51db + anc)") == ["Apple AirPods Pro 2 (51dB + ANC)"]
    assert found("hd 600") == []
    assert found("not a result") == []
    assert found("!!!") == []
    assert found("ear") == ["Apple EarPods", "Sennheiser HD 650 (2020, worn earpads)",
                            "Sennheiser HD 650 (pre-2020, worn earpads)", "Sennheiser HD 650 (pre-2020, semi-worn earpads)"]


def test_one_row_per_headphone_in_source_order():
    rows = {row.folded: row for row in ROWS}
    hd650 = rows["sennheiser hd 650"]
    #? SOURCE_ORDER's first, then the rest by name
    assert [result.source for result in hd650.results] == [
        "oratory1990", "crinacle", "Rtings", "Innerfidelity", "Headphone.com Legacy", "Auriculares Argentina",
        "Kuulokenurkka"]
    airpods = rows["apple airpods pro"]
    assert [result.source for result in airpods.results] == ["crinacle", "Super Review", "HypetheSonics", "Rtings"]
    #? names folding the same are one row - "AirPods" and "Airpods" - Harpo and Filk by name
    pro2 = rows["apple airpods pro 2"]
    assert [result.source for result in pro2.results] == ["HypetheSonics", "Filk", "Harpo"]
    #? "Pro2" is another name
    assert [result.source for result in rows["apple airpods pro2"].results] == ["Rtings"]
    answer = A.row_answer(airpods)
    assert answer == {"id": rid(AIRPODS_PRO), "name": "Apple AirPods Pro", "source": "crinacle", "rig": "711",
                      "form": "in-ear", "others": [
                          {"id": rid("Super Review/in-ear/Apple AirPods Pro"), "source": "Super Review", "rig": None,
                           "form": "in-ear"},
                          {"id": rid(BK_AIRPODS), "source": "HypetheSonics", "rig": "Bruel & Kjaer 5128", "form": "in-ear"},
                          {"id": rid("Rtings/HMS II.3 in-ear/Apple AirPods Pro"), "source": "Rtings", "rig": "HMS II.3",
                           "form": "in-ear"}]}
    assert A.SOURCE_ORDER == ("oratory1990", "crinacle", "Super Review", "HypetheSonics", "Rtings", "Innerfidelity",
                              "Headphone.com Legacy")


# ----------------------------------------------------------------- the routes: the list

def test_a_search_fetches_the_list_once_at_master_s_commit_and_answers(env):
    answer = search(env, "hd650")
    assert answer.status_code == 200
    body = answer.json()
    assert set(body) == {"results", "total", "list_from"}
    assert body["total"] == 6 and len(body["results"]) == 6
    assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", body["list_from"])
    first = body["results"][0]
    assert set(first) == {"id", "name", "source", "rig", "form", "others"}
    assert (first["name"], first["source"], first["rig"], first["form"]) == ("Sennheiser HD 650", "oratory1990", None, "over-ear")
    assert all(set(other) == {"id", "source", "rig", "form"} for other in first["others"])
    #? master's commit, then the list AT that commit
    assert env.hub.asked() == ["api.github.com/repos/jaakkopasanen/AutoEq/commits/master",
                               f"raw.githubusercontent.com/jaakkopasanen/AutoEq/{OLD}/results/INDEX.md"]
    assert env.hub.requests[0].headers["accept"] == "application/vnd.github.sha"

    #? asked again: nothing asked of GitHub
    assert names(search(env, "airpods pro"))[0] == "Apple AirPods Pro"
    assert len(env.hub.requests) == 2

    with sqlite3.connect(env.db) as connection:
        assert connection.execute("SELECT COUNT(*) FROM autoeq_list").fetchone()[0] == 42
        assert connection.execute("SELECT sha FROM autoeq_meta").fetchone()[0] == OLD


def test_the_unparsed_line_is_logged_at_info(env, caplog):
    caplog.set_level(logging.INFO)
    assert search(env, "hd650").status_code == 200
    said = [record for record in caplog.records if "didn't parse" in record.getMessage()]
    assert len(said) == 1 and said[0].levelno == logging.INFO and "1 line" in said[0].getMessage()
    #? deadwax's own log, never the event log a listener's page could show
    assert not getattr(said[0], "frontend", False)


def test_after_a_restart_the_list_is_answered_from_the_database(env):
    first = search(env, "hd 650").json()
    asked = len(env.hub.requests)
    with serving(env.store) as (_, client):
        again = client.get("/deadwax/eq/autoeq", params={"q": "hd 650"})
    assert again.status_code == 200 and again.json() == first
    assert len(env.hub.requests) == asked == 2


def test_limit_cuts_the_rows_and_total_counts_them_all(env):
    body = search(env, "airpods", limit=3).json()
    assert len(body["results"]) == 3 and body["total"] == 17
    assert search(env, "airpods").json()["total"] == 17
    assert len(search(env, "airpods").json()["results"]) == 17
    assert search(env, "!!!").json() == {"results": [], "total": 0, "list_from": body["list_from"]}


def test_a_list_a_week_old_is_refreshed_in_the_background_while_the_old_one_answers(env):
    old = search(env, "hd 650").json()
    env.hub.master = NEW
    env.hub.lists[NEW] = INDEX.replace(INNERFIDELITY_HD650, "")
    age(env, 7)

    #? the old list answers - with Innerfidelity's HD 650 still in it - and the new one is fetched behind it
    meanwhile = search(env, "hd 650").json()
    assert meanwhile["results"] == old["results"] and meanwhile["list_from"] < old["list_from"]
    settle(env)
    assert env.hub.asked()[2:] == ["api.github.com/repos/jaakkopasanen/AutoEq/commits/master",
                                   f"raw.githubusercontent.com/jaakkopasanen/AutoEq/{NEW}/results/INDEX.md"]
    now = search(env, "hd 650").json()
    assert "Innerfidelity" not in [other["source"] for other in now["results"][0]["others"]]
    assert now["list_from"] >= old["list_from"] > meanwhile["list_from"]
    with sqlite3.connect(env.db) as connection:
        assert connection.execute("SELECT COUNT(*) FROM autoeq_list").fetchone()[0] == 41
        assert connection.execute("SELECT sha FROM autoeq_meta").fetchone()[0] == NEW


def test_a_list_younger_than_a_week_is_not_asked_about(env):
    search(env, "hd 650")
    age(env, 6.9)
    search(env, "hd 650")
    assert env.app.state.autoeq.refreshing.done()
    assert len(env.hub.requests) == 2


def test_an_unchanged_commit_fetches_nothing_more_and_drops_nothing(env):
    search(env, "hd 650")
    assert profile(env, AIRPODS_PRO).status_code == 200
    before = env.app.state.autoeq.fetched_at
    age(env, 8)
    search(env, "hd 650")
    settle(env)
    #? the commit alone
    assert env.hub.asked()[3:] == ["api.github.com/repos/jaakkopasanen/AutoEq/commits/master"]
    assert kept_profiles(env) == [(rid(AIRPODS_PRO), OLD)]
    #? only the time moves
    assert env.app.state.autoeq.fetched_at > before
    with sqlite3.connect(env.db) as connection:
        assert connection.execute("SELECT fetched_at FROM autoeq_meta").fetchone()[0] == env.app.state.autoeq.fetched_at
    assert profile(env, AIRPODS_PRO).json()["text"] == AIRPODS_PRO_TEXT
    assert len(env.hub.requests) == 4


def test_a_new_list_drops_every_kept_profile_and_the_next_ask_fetches_it_at_the_new_commit(env):
    assert profile(env, AIRPODS_PRO).json()["text"] == AIRPODS_PRO_TEXT
    assert profile(env, HD650).status_code == 200
    assert len(kept_profiles(env)) == 2

    newer = AIRPODS_PRO_TEXT.replace("Preamp: -6.0 dB", "Preamp: -5.9 dB")
    env.hub.master = NEW
    env.hub.lists[NEW] = INDEX
    env.hub.files[(NEW, f"{AIRPODS_PRO}/Apple AirPods Pro ParametricEQ.txt")] = newer
    age(env, 8)
    search(env, "airpods")
    settle(env)
    #? even the HD 650's, whose path is still listed
    assert kept_profiles(env) == []

    asked = len(env.hub.requests)
    answer = profile(env, AIRPODS_PRO)
    assert answer.status_code == 200 and answer.json()["text"] == newer
    assert env.hub.asked()[asked:] == [
        f"raw.githubusercontent.com/jaakkopasanen/AutoEq/{NEW}/results/crinacle/711%20in-ear/Apple%20AirPods%20Pro/"
        "Apple%20AirPods%20Pro%20ParametricEQ.txt"]
    assert kept_profiles(env) == [(rid(AIRPODS_PRO), NEW)]


def test_a_profile_kept_at_an_older_commit_than_its_list_is_never_answered(env):
    """A profile fetch that crossed a new list keeps its text at the old commit; it is fetched again."""
    profile(env, AIRPODS_PRO)
    newer = AIRPODS_PRO_TEXT.replace("Preamp: -6.0 dB", "Preamp: -5.9 dB")
    env.hub.master = NEW
    env.hub.lists[NEW] = INDEX
    env.hub.files[(NEW, f"{AIRPODS_PRO}/Apple AirPods Pro ParametricEQ.txt")] = newer
    age(env, 8)
    search(env, "airpods")
    settle(env)
    #? put back as a fetch that crossed the new list would have left it
    asyncio.run(env.store.autoeq_profile_put(rid(AIRPODS_PRO), OLD, AIRPODS_PRO_TEXT, time.time()))
    assert profile(env, AIRPODS_PRO).json()["text"] == newer


def test_no_list_and_github_down_is_a_503_in_its_words(env):
    env.hub.down = True
    for answer in (search(env, "hd 650"), profile(env, AIRPODS_PRO)):
        assert answer.status_code == 503
        assert answer.json() == {"detail": "deadwax can't reach AutoEq just now."}
    #? nothing kept of a failure: the next ask tries again
    env.hub.down = False
    assert search(env, "hd 650").status_code == 200


@pytest.mark.parametrize("kind, status, body", [
    ("commit", 403, '{"message": "API rate limit exceeded"}'),
    ("commit", 200, "<html>a captive portal</html>"),
    ("list", 500, "oops"),
    ("list", 200, "<html><body>Something went wrong</body></html>"),
    ("list", 301, ""),
])
def test_github_answering_anything_but_the_list_is_a_503(env, kind, status, body):
    env.hub.instead[kind] = (status, body)
    answer = search(env, "hd 650")
    assert answer.status_code == 503 and answer.json()["detail"] == "deadwax can't reach AutoEq just now."
    #? a redirect is not followed
    assert len(env.hub.requests) == (1 if kind == "commit" else 2)


def test_no_list_at_github_s_404_either(env):
    env.hub.lists = {}
    assert search(env, "hd 650").status_code == 503


def test_a_slow_first_list_costs_that_ask_but_is_kept_for_the_next(env, monkeypatch):
    monkeypatch.setattr(eq_route, "FIRST_FETCH_SECONDS", 0.05)
    env.hub.delay = 0.2
    assert search(env, "hd 650").status_code == 503
    settle(env)
    env.hub.delay = 0
    assert search(env, "hd 650").status_code == 200
    #? one fetch, finished behind the first ask
    assert len(env.hub.requests) == 2


def test_a_failed_refresh_keeps_the_old_list_and_waits_before_asking_again(env):
    old = search(env, "hd 650").json()
    age(env, 8)
    env.hub.down = True
    assert search(env, "hd 650").json()["results"] == old["results"]
    settle(env)
    asked = len(env.hub.requests)
    #? still answering, and GitHub not asked again on every search
    assert search(env, "hd 650").json()["results"] == old["results"]
    assert len(env.hub.requests) == asked
    env.app.state.autoeq.failed_at -= A.RETRY_SECONDS
    env.hub.down = False
    search(env, "hd 650")
    settle(env)
    assert len(env.hub.requests) == asked + 1


def test_a_list_past_8_mb_is_refused(env):
    assert A.LIST_MAX_BYTES == 8 * 1024 * 1024
    env.hub.lists[OLD] = INDEX + "x" * (A.LIST_MAX_BYTES - len(INDEX.encode("utf-8")) + 1)
    assert search(env, "hd 650").status_code == 503
    env.hub.lists[OLD] = INDEX + "x" * (A.LIST_MAX_BYTES - len(INDEX.encode("utf-8")))
    assert search(env, "hd 650").status_code == 200


# ----------------------------------------------------------------- the routes: a profile

def test_a_profile_is_fetched_once_and_then_answered_without_asking(env):
    answer = profile(env, AIRPODS_PRO)
    assert answer.status_code == 200
    assert answer.json() == {"id": rid(AIRPODS_PRO), "name": "Apple AirPods Pro", "source": "crinacle", "rig": "711",
                             "form": "in-ear", "text": AIRPODS_PRO_TEXT}
    assert answer.headers["cache-control"] == "private, max-age=86400"
    assert env.hub.asked()[2:] == [
        f"raw.githubusercontent.com/jaakkopasanen/AutoEq/{OLD}/results/crinacle/711%20in-ear/Apple%20AirPods%20Pro/"
        "Apple%20AirPods%20Pro%20ParametricEQ.txt"]
    again = profile(env, AIRPODS_PRO)
    assert again.json() == answer.json() and again.headers["cache-control"] == "private, max-age=86400"
    assert len(env.hub.requests) == 3
    #? and after a restart, from the database
    with serving(env.store) as (_, client):
        assert client.get(f"/deadwax/eq/autoeq/{rid(AIRPODS_PRO)}").json() == answer.json()
    assert len(env.hub.requests) == 3
    #? the HD 650's, as AutoEq wrote it
    assert profile(env, HD650).json()["text"] == HD650_TEXT


def test_an_id_not_in_the_list_is_a_404_and_asks_github_nothing_for_it(env):
    answer = env.client.get("/deadwax/eq/autoeq/0123456789abcdef")
    assert answer.status_code == 404
    assert answer.json() == {"detail": "AutoEq doesn't have that measurement any more."}
    assert all("results/INDEX.md" in path or "commits/master" in path for path in env.hub.raw_paths())


def test_github_s_404_for_the_file_is_a_404(env):
    answer = profile(env, BK_AIRPODS)
    assert answer.status_code == 404 and answer.json()["detail"] == "AutoEq doesn't have that measurement any more."
    #? asked at its address, `&` encoded
    assert env.hub.raw_paths()[-1] == (f"/jaakkopasanen/AutoEq/{OLD}/results/HypetheSonics/Bruel%20%26%20Kjaer%205128%20in-ear/"
                                       "Apple%20AirPods%20Pro/Apple%20AirPods%20Pro%20ParametricEQ.txt")
    assert kept_profiles(env) == []


@pytest.mark.parametrize("status", [500, 502, 403, 302])
def test_github_s_other_answers_for_the_file_are_a_503(env, status):
    search(env, "hd 650")
    env.hub.instead["profile"] = (status, "nope")
    answer = profile(env, AIRPODS_PRO)
    assert answer.status_code == 503 and answer.json()["detail"] == "deadwax can't reach AutoEq just now."
    assert kept_profiles(env) == []


def test_github_down_for_the_file_is_a_503(env):
    search(env, "hd 650")
    env.hub.down = True
    assert profile(env, AIRPODS_PRO).status_code == 503


def test_a_profile_past_64_kb_is_refused(env):
    assert A.PROFILE_MAX_BYTES == 64 * 1024
    key = (OLD, f"{AIRPODS_PRO}/Apple AirPods Pro ParametricEQ.txt")
    env.hub.files[key] = "x" * (A.PROFILE_MAX_BYTES + 1)
    assert profile(env, AIRPODS_PRO).status_code == 503
    assert kept_profiles(env) == []
    env.hub.files[key] = "x" * A.PROFILE_MAX_BYTES
    assert profile(env, AIRPODS_PRO).status_code == 200


# ----------------------------------------------------------------- what GitHub is asked, and as whom

def test_github_is_told_deadwax_s_name_and_version_and_nothing_more(env, monkeypatch):
    monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "james@example.com")
    search(env, "hd 650")
    profile(env, AIRPODS_PRO)
    assert len(env.hub.requests) == 3
    for request in env.hub.requests:
        assert request.headers["user-agent"] == f"deadwax/{__version__}"
        assert "example.com" not in str(request.headers)


def test_only_github_s_three_kinds_of_address_are_asked_never_a_path_from_q_or_id(env):
    #? what a request might try to smuggle into an address
    for q in ("../../etc/passwd", "%2F..%2Fsecret", "HypetheSonics/Bruel & Kjaer 5128", "?ref=main#x", "https://evil.example/"):
        assert search(env, q).status_code == 200
    for bad in ("..%2F..%2Fsecret", "0123456789ABCDEF", "0123456789abcde", "0123456789abcdef0", "x" * 16):
        assert env.client.get(f"/deadwax/eq/autoeq/{bad}").status_code in (404, 422)
    env.client.get("/deadwax/eq/autoeq/0123456789abcdef")
    for path in (AIRPODS_PRO, HD650, BK_AIRPODS, PRO2_51, AUR):
        profile(env, path)

    listed = {result.path for result in A.parse_index(INDEX)[0]}
    allowed_profiles = {A.profile_url(OLD, path) for path in listed}
    for request in env.hub.requests:
        url = str(request.url)
        assert (url == A.COMMIT_URL or url == A.index_url(OLD) or url in allowed_profiles), url
        for smuggled in ("passwd", "secret", "evil", "ref=", "0123456789abcdef"):
            assert smuggled not in url
    #? the commit and the list once; each profile at its own address
    assert [str(request.url) for request in env.hub.requests[2:]] == [A.profile_url(OLD, path) for path in
                                                                      (AIRPODS_PRO, HD650, BK_AIRPODS, PRO2_51, AUR)]


# ----------------------------------------------------------------- bounds

@pytest.mark.parametrize("params", [
    {}, {"q": ""}, {"q": "x" * 101}, {"q": "hd", "limit": 0}, {"q": "hd", "limit": 51}, {"q": "hd", "limit": "x"},
])
def test_q_and_limit_out_of_bounds_are_a_422_and_ask_nothing(env, params):
    assert env.client.get("/deadwax/eq/autoeq", params=params).status_code == 422
    assert env.hub.requests == []


def test_q_and_limit_at_their_bounds_answer(env):
    assert search(env, "x" * 100).status_code == 200
    assert search(env, "a", limit=1).status_code == 200
    assert len(search(env, "a", limit=50).json()["results"]) <= 50


@pytest.mark.parametrize("bad", ["0123456789ABCDEF", "0123456789abcde", "0123456789abcdef0", "g123456789abcdef"])
def test_an_id_that_isn_t_sixteen_lowercase_hex_is_a_422_and_asks_nothing(env, bad):
    assert env.client.get(f"/deadwax/eq/autoeq/{bad}").status_code == 422
    assert env.hub.requests == []


def test_deadwax_s_own_client_follows_no_redirect_and_waits_15_s():
    from src.api.autoeq_endpoint import AutoEqClient
    client = AutoEqClient()
    http = client._http()
    try:
        assert http.follow_redirects is False
        assert http.timeout == httpx.Timeout(15.0, connect=10.0)
        assert AutoEqClient.user_agent() == f"deadwax/{__version__}"
    finally:
        asyncio.run(client.close_client())
