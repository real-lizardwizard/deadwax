"""
The iPhone app's artist tools (Phase 8, slice 5 - notes/ios-specs/phase8-managing.md 4; notes/ios.md "The artist tools on
the phone") against the eight routes they ask, read from the app's own source (ios/DeadwaxKit/Sources/DeadwaxCore:
ArtistManage.swift, ArtistManageFlow.swift, ArtistManageClient.swift, Routes.swift) and held to the server's:

- what it SENDS - ArtistImagesBody, ArtistSearchBody, ArtistRefileBody - every key one the model it is posted to
  declares (pydantic drops an undeclared one without a word), and posted as the phone posts them to the real routes;
- what it READS - ArtistSummary from the real `/library/artist`, ArtistImagesPreview and its candidates, kinds and
  sources from the real images preview, ArtistImagesApplied from a real save, ArtistMatchesAnswer from the real search,
  ArtistRefilePlan and RefileMove from a real refile preview and ArtistRefileApplied from a real move - over a real
  folder of real FLACs, MusicBrainz and fanart.tv faked (nothing here calls out);
- how long it waits - each wait the server's worst case read from its source, and the relay's cap and deadline;
- who may: the tools by the permission each route needs (tests/test_logins.py ROUTES);
- and that its writes, sent with no Origin or Referer, are what the same-origin guard lets through.
"""

import re
import sys
from contextlib import asynccontextmanager
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest
from fastapi.testclient import TestClient
from mutagen.flac import FLAC

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import library  # noqa: E402
from src.api import artist_images_endpoint as images_endpoint  # noqa: E402
from src.api import same_origin  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.musicbrainz_endpoint import MusicBrainzClient, RateLimit  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import library as route  # noqa: E402
from src.store import JobStore  # noqa: E402
from tests.test_ios_contract import CORE, coding_keys, swift_function, swift_struct  # noqa: E402
from tests.test_logins import ROUTES  # noqa: E402
from tests.test_retag import write_flac  # noqa: E402

APP = CORE.parent.parent.parent / "App"
YE = "e30b8d67-3d5c-4ad3-9a8a-3a1d0c6b7c11"
OLD = "Kanye West"
NOW = "Ye"
THUMB = f"https://assets.fanart.tv/fanart/music/{YE}/artistthumb/ye-a.jpg"
BANNER = f"https://assets.fanart.tv/fanart/music/{YE}/musicbanner/ye-b.jpg"


def reads(struct: str) -> set[str]:
    """Every JSON name a Decodable struct reads: its CodingKeys (each of these models reads every key it names)."""
    keys = coding_keys(swift_struct(struct))
    assert keys is not None, f"{struct} has no CodingKeys"
    return set(keys.values())


def sends(struct: str) -> set[str]:
    """Every key an Encodable struct can send: the keys its CodingKeys name (its encode(to:) writes no other)."""
    return reads(struct)


def timeouts() -> dict[str, float]:
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    return {name: float(seconds) for name, seconds in re.findall(r"(\w+): ([\d.]+)", literal.group(1))}


def waits(name: str) -> float:
    """One of ArtistWaits' own figures, read from its source."""
    text = (CORE / "ArtistManageFlow.swift").read_text(encoding="utf-8")
    found = re.search(rf"public static let {name}(?:: Double)? = ([\d_* ]+)\n", text)
    assert found, f"ArtistWaits has no {name}"
    return float(eval(found.group(1).replace("_", "")))  # noqa: S307 - a literal of digits and *


def album(root: Path, folder: str, name: str, albumartist: str, titles=("One", "Two")) -> Path:
    """An album as deadwax files one: the album artist and its MusicBrainz id in every track."""
    directory = root / folder / name
    for n, title in enumerate(titles, start=1):
        path = write_flac(directory / f"{n:02d} {title}.flac", album=name, albumartist=albumartist,
                          artist=albumartist, title=title, tracknumber=str(n), date="2021")
        tags = FLAC(str(path))
        tags["musicbrainz_albumartistid"] = [YE]
        tags.save()
    return directory


def jpeg(name: str) -> bytes:
    return b"\xff\xd8\xff\xe0" + f"{name} ".encode() * 200


class MusicBrainz:
    """Ye, as MusicBrainz answers for them: their name now, an alias the old folder goes by."""

    async def get_artist(self, mbid):
        return {"id": mbid, "name": NOW, "disambiguation": "rapper", "type": "Person", "country": "US",
                "aliases": [{"name": OLD}], "relations": [], "genres": [], "tags": []}

    async def search_artists(self, name, limit=5):
        return {"artists": [{"id": YE, "name": NOW, "score": 100, "disambiguation": "rapper", "type": "Person",
                             "country": "US", "aliases": [{"name": OLD}]},
                            {"name": "no id at all", "score": 40}]}


def fanarttv(request: httpx.Request) -> httpx.Response:
    if request.url.host == "webservice.fanart.tv":
        return httpx.Response(200, json={
            "artistthumb": [{"url": THUMB.replace("https://", "http://"), "likes": "3"}],
            "musicbanner": [{"url": BANNER.replace("https://", "http://")}],
        })
    if str(request.url).startswith("https://assets.fanart.tv/"):
        return httpx.Response(200, headers={"content-type": "image/jpeg"}, content=jpeg(request.url.path))
    return httpx.Response(404)


@asynccontextmanager
async def no_lifespan(app):
    yield


@pytest.fixture
def env(tmp_path, monkeypatch):
    root = tmp_path / "music"
    album(root, OLD, "Donda (2021)", OLD)
    album(root, OLD, "Jesus Is King (2019)", OLD)
    album(root, NOW, "Vultures 1 (2024)", NOW)
    (root / OLD / "artist.jpg").write_bytes(jpeg("portrait"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(root))
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    monkeypatch.setattr(Config, "FANARTTV_KEY", "a-project-key")
    monkeypatch.setattr(Config, "FANARTTV_PERSONAL_KEY", None)
    monkeypatch.setattr(Config, "THEAUDIODB_KEY", None)
    monkeypatch.setattr(route, "_cache_loaded_for", None)
    monkeypatch.setattr(route.artist_images_client, "_client",
                        httpx.AsyncClient(transport=httpx.MockTransport(fanarttv), follow_redirects=True))
    library.clear_scan_cache()
    store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    store.init()
    app = start()
    app.router.lifespan_context = no_lifespan
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    app.state.store = store
    app.state.musicbrainz_client = MusicBrainz()
    with TestClient(app) as client:
        yield SimpleNamespace(client=client, root=root)
    library.clear_scan_cache()


# ---------------------------------------------------------------------------- what the phone sends

def test_every_body_the_phone_posts_is_the_servers_model():
    assert sends("ArtistImagesBody") == {"artist", "artist_mbid", "choices", "replace"}
    assert sends("ArtistImagesBody") <= set(route.ArtistImagesRequest.model_fields)
    assert sends("ArtistSearchBody") == {"query"} <= set(route.ArtistSearchRequest.model_fields)
    assert sends("ArtistRefileBody") == {"artist", "artist_mbid"} <= set(route.ArtistRefileRequest.model_fields)
    # no id is no key at all (Swift's encodeIfPresent): the model's own default, as the web's null is
    assert route.ArtistImagesRequest(artist="Ye").artist_mbid is None
    assert route.ArtistRefileRequest(artist="Ye").artist_mbid is None


def test_the_writes_pass_the_same_origin_guard():
    assert same_origin.refusal("POST", {"content-type": "application/json"}) is None
    for file in ("DeadwaxClient.swift", "ArtistManageClient.swift"):
        text = (CORE / file).read_text(encoding="utf-8")
        assert '"Origin"' not in text and '"Referer"' not in text, file


def test_the_routes_are_the_servers_by_method_path_and_query():
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    for name, method, path, query in (
            ("libraryArtist", "GET", "/deadwax/library/artist", '["name"]'),
            ("artistArt", "GET", "/deadwax/library/artist/art", '["artist", "kind"]'),
            ("artistImagesPreview", "POST", "/deadwax/library/artist/images/preview", "[]"),
            ("artistImagesApply", "POST", "/deadwax/library/artist/images/apply", "[]"),
            ("artistPicture", "GET", "/deadwax/library/artist/picture", '["url"]'),
            ("artistSearch", "POST", "/deadwax/library/artist/search", "[]"),
            ("refilePreview", "POST", "/deadwax/library/artist/refile/preview", "[]"),
            ("refileApply", "POST", "/deadwax/library/artist/refile/apply", "[]")):
        line = f'public static let {name} = Endpoint(method: "{method}", path: "{path}", query: {query})'
        assert line in text, line
        assert (method, path) in ROUTES, (method, path)


# ---------------------------------------------------------------------------- what the phone reads, from real routes

def test_a_name_the_library_files_them_under_is_what_the_phone_reads(env):
    answer = env.client.get("/deadwax/library/artist", params={"name": OLD})
    assert answer.status_code == 200, answer.text
    summary = answer.json()
    assert reads("ArtistSummary") <= set(summary), reads("ArtistSummary") - set(summary)
    assert summary["path"] == OLD and summary["album_count"] == 2 and summary["art"] == {"thumb": "artist.jpg"}
    # a name with no album: a 404, which the phone reads as none (libraryArtist accepts it)
    gone = env.client.get("/deadwax/library/artist", params={"name": "Nobody"})
    assert gone.status_code == 404 and gone.json()["detail"] == "no such artist"
    assert "accept: [200, 404]" in swift_function("ArtistManageClient.swift", "libraryArtist")
    # a picture in their folder, by the summary's path; none of a kind is a 404 (none, not a failure)
    art = env.client.get("/deadwax/library/artist/art", params={"artist": OLD, "kind": "thumb"})
    assert art.status_code == 200 and art.content == jpeg("portrait")
    assert env.client.get("/deadwax/library/artist/art", params={"artist": OLD, "kind": "logo"}).status_code == 404
    assert "accept: [200, 404]" in swift_function("ArtistManageClient.swift", "artistArt")


def test_artist_images_preview_and_save_are_what_the_phone_reads(env):
    preview = env.client.post("/deadwax/library/artist/images/preview", json={"artist": NOW, "choices": {}, "replace": False})
    assert preview.status_code == 200, preview.text
    look = preview.json()
    assert reads("ArtistImagesPreview") <= set(look), reads("ArtistImagesPreview") - set(look)
    # the id from the tags, the facts from MusicBrainz, the candidates from fanart.tv - offered over https
    assert (look["mbid"], look["mbid_source"], look["facts"]["name"]) == (YE, "tags", NOW)
    assert [c["url"] for c in look["candidates"]] == [THUMB, BANNER]
    for candidate in look["candidates"]:
        assert reads("ArtistImageCandidate") <= set(candidate)
    assert set(look["best"]) == {"thumb", "banner"} and reads("ArtistImageCandidate") <= set(look["best"]["thumb"])
    for kind in look["kinds"]:
        assert reads("ArtistImageKind") <= set(kind)
    # the sources read from their own object (ArtistImagesPreview's SourceKeys)
    sources = re.search(r"enum SourceKeys: String, CodingKey \{ case ([^}]*)\}", (CORE / "ArtistManage.swift")
                        .read_text(encoding="utf-8"))
    assert {one.strip() for one in sources.group(1).split(",")} <= set(look["sources"])

    choices = {kind: candidate["url"] for kind, candidate in look["best"].items()}
    applied = env.client.post("/deadwax/library/artist/images/apply",
                              json={"artist": NOW, "artist_mbid": look["mbid"], "choices": choices, "replace": False})
    assert applied.status_code == 200, applied.text
    saved = applied.json()
    assert reads("ArtistImagesApplied") <= set(saved) and reads("ArtistImagesResults") <= set(saved["results"])
    assert sorted(saved["results"]["written"]) == ["artist.jpg", "banner.jpg"]
    assert saved["art"] == {"thumb": "artist.jpg", "banner": "banner.jpg"}
    # a choice its sources didn't offer: a 400 with deadwax's words - nothing written, said as it came
    refused = env.client.post("/deadwax/library/artist/images/apply",
                              json={"artist": NOW, "artist_mbid": YE, "choices": {"thumb": "https://example.com/a.jpg"}})
    assert refused.status_code == 400 and "not one of this artist's own pictures" in refused.json()["detail"]


def test_the_search_is_what_the_phone_reads(env):
    answer = env.client.post("/deadwax/library/artist/search", json={"query": OLD})
    assert answer.status_code == 200, answer.text
    found = answer.json()
    assert reads("ArtistMatchesAnswer") <= set(found)
    assert [match["mbid"] for match in found["matches"]] == [YE], "a match with no id is the server's to leave out"
    assert reads("MBArtistMatch") <= set(found["matches"][0])
    assert found["matches"][0]["matched_as"] == OLD


def test_move_albums_preview_and_apply_are_what_the_phone_reads(env):
    preview = env.client.post("/deadwax/library/artist/refile/preview", json={"artist": OLD, "artist_mbid": YE})
    assert preview.status_code == 200, preview.text
    plan = preview.json()
    assert reads("ArtistRefilePlan") <= set(plan), reads("ArtistRefilePlan") - set(plan)
    assert (plan["current_name"], plan["to_folder"]) == (NOW, NOW)
    assert sorted(move["target_path"] for move in plan["moves"]) == ["Ye/Donda (2021)", "Ye/Jesus Is King (2019)"]
    for move in plan["moves"]:
        assert reads("RefileMove") <= set(move)
        for retag in move["retag"]:
            assert reads("RefileRetag") <= set(retag)
    # the phone's own name is nothing to move
    own = env.client.post("/deadwax/library/artist/refile/preview", json={"artist": NOW, "artist_mbid": YE}).json()
    assert own["empty"] is True and own["moves"] == []

    applied = env.client.post("/deadwax/library/artist/refile/apply", json={"artist": OLD, "artist_mbid": YE})
    assert applied.status_code == 200, applied.text
    moved = applied.json()
    assert reads("ArtistRefileApplied") <= set(moved) and reads("ArtistRefilePlan") <= set(moved["plan"])
    assert reads("ArtistRefileResults") <= set(moved["results"])
    assert {"from", "to"} <= set(moved["results"]["moved"][0])
    assert moved["results"]["pictures_moved"] == ["artist.jpg"]
    assert moved["results"]["removed_folders"] == [OLD]
    assert (env.root / NOW / "Donda (2021)").is_dir() and not (env.root / OLD).exists()


def test_a_move_refused_is_a_4xx_with_deadwaxs_words(env, monkeypatch):
    # who they are unsettled: the apply refuses, writing nothing - the phone says it as it came
    class Nobody(MusicBrainz):
        async def get_artist(self, mbid):
            return {"error": True}

    env.client.app.state.musicbrainz_client = Nobody()
    refused = env.client.post("/deadwax/library/artist/refile/apply", json={"artist": OLD, "artist_mbid": YE})
    assert refused.status_code == 400 and "MusicBrainz could not be reached just now" in refused.json()["detail"]
    # a 4xx is a refusal: said as it came, never "may have finished" (RetagFlow.outcome)
    outcome = swift_function("RetagFlow.swift", "outcome")
    assert "(400..<500).contains(answer.status) { return .refused }" in outcome
    models = (APP / "Artist" / "ArtistToolModels.swift").read_text(encoding="utf-8")
    assert models.count("RetagFlow.outcome(of: error)") == 2, "Save's and Move's failures, each through the rule"
    assert (env.root / OLD / "Donda (2021)").is_dir()


# ---------------------------------------------------------------------------- how long it waits

def test_each_wait_is_past_the_servers_own_worst_case():
    given = timeouts()
    # one MusicBrainz lookup: its ten tries a busy 3 s apart, and the rate limit's window
    assert given["artistFacts"] > MusicBrainzClient.RETRIES * 3.0 + RateLimit.time_window
    # the sources and the pictures: httpx's connection and read, each request
    assert waits("sourceRequest") == images_endpoint.JSON_TIMEOUT.connect + images_endpoint.JSON_TIMEOUT.read
    assert waits("pictureRequest") == images_endpoint.IMAGE_TIMEOUT.connect + images_endpoint.IMAGE_TIMEOUT.read
    # Commons' Special:FilePath redirects twice before its picture (notes/ios.md, the relay: seen by hand)
    assert waits("pictureHops") >= 3
    # the sources asked in turn: TheAudioDB, fanart.tv, Wikidata
    candidates = (Path(images_endpoint.__file__)).read_text(encoding="utf-8")
    assert waits("sources") >= 3 and "theaudiodb" in candidates and "fanarttv" in candidates
    # the floors: the scan's as the library's own, an apply's never less than its preview's
    assert given["libraryArtist"] >= given["libraryAlbums"]
    assert given["artistImagesApply"] >= given["artistImagesPreview"] >= given["artistFacts"] + 3 * waits("sourceRequest")
    assert given["refileApply"] >= given["refilePreview"] >= given["libraryArtist"] + given["artistFacts"]
    assert given["artistSearch"] >= given["artistFacts"]
    # the relay: no wait of the route's own - the transport's 8 s, past its 7 s deadline - and its cap, read as is
    assert "artistPicture" not in given
    assert images_endpoint.PICTURE_DEADLINE_SECONDS < 8
    assert waits("pictureMostBytes") == images_endpoint.PICTURE_MAX_BYTES
    # Save's and Move's waits are worked out for what is in hand, never less than the route's
    apply = swift_function("ArtistManageFlow.swift", "imagesApply")
    assert "EditWaits.wait(scan + musicBrainz + candidates + fetches + margin, floor: floor)" in apply
    refile = swift_function("ArtistManageFlow.swift", "refileApply")
    assert "EditWaits.wait(floor + rewrite, floor: floor)" in refile
    client = (CORE / "ArtistManageClient.swift").read_text(encoding="utf-8")
    assert "built.timeout = ArtistWaits.imagesApply(pictures: body.choices.count, commons: commons)" in client
    assert "built.timeout = ArtistWaits.refileApply(bytes: bytes)" in client
    assert "built.mostBytes = ArtistWaits.pictureMostBytes" in client


# ---------------------------------------------------------------------------- who may, and the app

def test_the_tools_are_by_the_permission_each_route_needs():
    managing = swift_function("Managing.swift", "artistManaging")
    assert "ArtistManaging(images: edit, whichArtist: edit, move: library, any: edit || library)" in managing
    for path in ("/deadwax/library/artist/images/preview", "/deadwax/library/artist/images/apply",
                 "/deadwax/library/artist/search"):
        assert ROUTES[("POST", path)] == "edit", path
    assert ROUTES[("GET", "/deadwax/library/artist/picture")] == "edit"
    for path in ("/deadwax/library/artist/refile/preview", "/deadwax/library/artist/refile/apply"):
        assert ROUTES[("POST", path)] == "library", path


def test_the_app_draws_every_picture_through_deadwax():
    folder = APP / "Artist"
    for file in sorted(folder.glob("*.swift")):
        text = file.read_text(encoding="utf-8")
        # the phone talks only to deadwax: no picture asked of another host, by any means
        assert "AsyncImage" not in text and "URLSession" not in text and "URL(string:" not in text, file.name
    cache = (folder / "ArtistToolsModel.swift").read_text(encoding="utf-8")
    assert "try await client.artistPicture(url: url)" in cache
    assert "try await client.artistArt(folder: path, kind: kind)" in cache
    # never more than a few at once, the busy relay asked again
    assert re.search(r"static let atOnce = [1-6]\n", cache)
    assert "(error as? APIFailure)?.status == 503, tries < 2" in cache


def test_the_writes_are_held_and_said_as_maybe_finished():
    models = (APP / "Artist" / "ArtistToolModels.swift").read_text(encoding="utf-8")
    assert 'BackgroundHold(named: "Artist images: Save")' in models
    assert 'BackgroundHold(named: "Move albums")' in models
    assert models.count("AccessibilityNotification.Announcement(EditWords.mayHaveFinished).post()") == 1
    assert "again ? EditWords.mayHaveFinished" in models
    # nothing after a write touches the pages past a sign-out
    assert models.count("guard samePerson else { return }") >= 3
    view = (APP / "Artist" / "ArtistView.swift").read_text(encoding="utf-8")
    assert "Managing.artistManaging(server.access.permissions)" in view
    assert "guard navigation.session == session else { return }" in view
