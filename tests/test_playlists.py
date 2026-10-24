"""
Playlists (2.0.0-player.58) - src/playlists.py's rules and the six routes in routes/navidrome.py - through the whole
app start() builds, against test_player_as_you's fake Navidrome, whose playlist calls are shaped from Navidrome
0.64.2's source (not recorded from a real one): per-user owners, `public`, `readonly`, smart and file-synced
playlists, an admin seeing everyone's, rows numbered 1..n counting missing songs and orphans, the stored counter,
createPlaylist's replace, updatePlaylist's order (removals, additions, metadata), and form bodies read as Navidrome's
formPost reads them.

What these hold:

  - WHOSE: ethan lists his own and james's public ones, never james's private; a shared admin account (logins off)
    lists nobody else's private playlist and can't open one (404); mine is matched case-folded; editable is mine and
    not read-only - never Navidrome's `readonly` alone; none at all is [].
  - HIDDEN: GET one's `hidden` is the stored counter less the songs listed, for an editable playlist only.
  - CREATE: the name trimmed, blank or a control character refused before Navidrome is asked; the songs in order, a
    song twice kept; the owner the asker; sent as a form, nothing in the URL; an undeclared field a 422.
  - ADD: `ask` with songs there already writes nothing and says how many; `add` appends after the last row, a
    missing one included; `skip` the others only; somebody else's or a smart one refused, nothing written.
  - EDIT: `base` differing (changed in another app) is a 409 and nothing written; the new list only removes and
    reorders; the songs written by Navidrome's replace - so a song removed after a missing one is the right one,
    which a removal by `songIndexToRemove` gets wrong - and emptied by a replace with one song then its removal; the
    metadata alone touches no song; the songs saved and the metadata refused a 502 saying so.
  - DELETE: mine only; never a smart or synced one; never another user's private one, even as an admin.
  - THE CLIENT'S FORM, the same-origin guard, a session that dies mid-add, and the constants held to the page's.
"""

import re
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi.testclient import TestClient

from src import auth, playlists as rules
from src.api import navidrome_endpoint
from src.api.navidrome_endpoint import NavidromeClient, SignedOut
from src.config import Config
from tests.test_personal_libraries import failed, run, signed_in
from tests import test_player_as_you
from tests.test_player_as_you import PLAYER, SONG

#? the fixtures this file builds on: step 5's `on`, and the player's `player`
on = test_player_as_you.on
player = test_player_as_you.player

ROOT = Path(__file__).resolve().parent.parent


def songs(fake, *ids: str) -> list[str]:
    """Songs the fake Navidrome has, by id, each on Dummy - and their ids back."""
    for at, song in enumerate(ids):
        fake.songs[song] = {"id": song, "title": f"Song {song}", "albumId": "nd-dummy", "album": "Dummy",
                            "artist": "Portishead", "duration": 100 + at, "contentType": "audio/flac", "suffix": "flac"}
    return list(ids)


def writes(fake) -> list[tuple[str, str]]:
    """(user, endpoint) of every playlist write since forget()."""
    return [(call["user"], call["endpoint"]) for call in fake.playlist_calls if call["endpoint"] in ("createPlaylist", "updatePlaylist", "deletePlaylist")]


def forget(fake) -> None:
    fake.forget()
    fake.playlist_calls.clear()


def logins_off(env, monkeypatch) -> TestClient:
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    return TestClient(env.app)


# ----------------------------------------------------------------- the rules, pure

def test_mine_is_the_asker_case_folded_and_a_blank_asker_owns_nothing():
    assert rules.is_mine({"owner": "James"}, "james") and rules.is_mine({"owner": "james"}, "JAMES")
    assert not rules.is_mine({"owner": "james"}, "ethan")
    assert not rules.is_mine({"owner": ""}, "") and not rules.is_mine({}, "") and not rules.is_mine({"owner": "james"}, " ")


def test_listed_is_mine_or_shared_and_editable_is_mine_and_not_read_only():
    theirs_private, theirs_public = {"owner": "james", "public": False}, {"owner": "james", "public": True}
    assert not rules.is_listed(theirs_private, "ethan") and rules.is_listed(theirs_public, "ethan")
    #? an admin sees readonly: true on others' - never what decides; and readonly missing reads as False
    assert not rules.is_editable({"owner": "james", "readonly": False}, "ethan")
    assert rules.is_editable({"owner": "ethan"}, "ethan") and not rules.is_editable({"owner": "ethan", "readonly": True}, "ethan")


def test_duplicates_are_counted_once_per_song_asked():
    present = ["a", "b", "b"]
    assert rules.split_duplicates(present, ["b", "c"], "skip") == (["c"], 1)
    assert rules.split_duplicates(present, ["b", "c"], "add") == (["b", "c"], 1)
    assert rules.split_duplicates(present, ["c"], "ask") == (["c"], 0)


def test_a_rearrangement_only_removes_and_reorders():
    assert rules.is_rearrangement(["a", "b", "a"], ["a", "a", "b"]) and rules.is_rearrangement(["a", "b"], [])
    assert not rules.is_rearrangement(["a", "b"], ["a", "c"])
    assert not rules.is_rearrangement(["a", "b", "a"], ["a", "a", "a"])


def test_names_and_descriptions_are_cleaned():
    assert rules.clean_name("  Late night ") == "Late night"
    assert [rules.clean_name(text) for text in ("", "   ", "Late\x00night", "Late\nnight", None)] == [None] * 5
    assert rules.clean_comment(" Songs\nfor\tafter midnight. ") == "Songs\nfor\tafter midnight."
    assert rules.clean_comment("") == "" and rules.clean_comment("a\x07b") is None


def test_hidden_is_the_counter_less_the_songs_listed():
    assert rules.hidden_count(12, 10) == 2 and rules.hidden_count(3, 5) == 0 and rules.hidden_count(None, 0) == 0


def test_the_page_holds_the_same_limits():
    page = (ROOT / "ui" / "src" / "lib" / "playlists.ts").read_text()
    held = {name: int(value.replace("_", "")) for name, value in re.findall(r"export const (PLAYLIST_\w+_MAX) = ([\d_]+)", page)}
    assert held == {"PLAYLIST_NAME_MAX": rules.PLAYLIST_NAME_MAX, "PLAYLIST_COMMENT_MAX": rules.PLAYLIST_COMMENT_MAX,
                    "PLAYLIST_SONGS_MAX": rules.PLAYLIST_SONGS_MAX}


# ----------------------------------------------------------------- reading

def test_ethan_lists_his_own_and_jamess_shared_never_jamess_private(player):
    fake = player.fake
    fake.playlist("pl-shared", "Sunday", "james", [SONG], public=True)
    listed = signed_in(player, "ethan").get(f"{PLAYER}/playlists").json()["playlists"]

    assert [(row["id"], row["mine"], row["editable"]) for row in listed] == [("pl-ethan", True, True), ("pl-shared", False, False)]
    assert listed[1]["owner"] == "james" and listed[1]["public"] is True
    assert {call["user"] for call in fake.playlist_calls} == {"ethan"}
    #? the shape: every field, '' or None for what Navidrome left out
    assert set(listed[0]) == {"id", "name", "comment", "songCount", "duration", "created", "changed", "owner", "public", "coverArt", "mine", "editable"}
    assert (listed[0]["comment"], listed[0]["public"], listed[0]["coverArt"]) == ("", False, "pl-pl-ethan_5f3a")


def test_a_shared_admin_account_never_lists_nor_opens_another_users_private_playlist(player, monkeypatch):
    fake = player.fake
    fake.admins.add("demo")
    nobody = logins_off(player, monkeypatch)

    listed = nobody.get(f"{PLAYER}/playlists").json()["playlists"]
    assert [row["id"] for row in listed] == ["pl-demo"]
    #? Navidrome hands it over to an admin; deadwax doesn't
    answer = nobody.get(f"{PLAYER}/playlists/pl-james")
    assert answer.status_code == 404 and answer.json()["detail"] == rules.GONE
    assert ("demo", "getPlaylist") in [(call["user"], call["endpoint"]) for call in fake.playlist_calls]


def test_mine_matches_the_owner_as_navidrome_stored_it(player):
    player.fake.playlists["pl-james"]["owner"] = "James"
    row = signed_in(player, "james").get(f"{PLAYER}/playlists").json()["playlists"]
    assert [(each["id"], each["mine"], each["editable"]) for each in row] == [("pl-james", True, True)]


def test_smart_and_synced_playlists_are_mine_and_not_editable(player):
    fake = player.fake
    fake.playlist("pl-smart", "Recently played", "ethan", [SONG], smart=True)
    fake.playlist("pl-file", "From an m3u", "ethan", [SONG], sync=True)
    listed = {row["id"]: row for row in signed_in(player, "ethan").get(f"{PLAYER}/playlists").json()["playlists"]}
    assert [(listed[key]["mine"], listed[key]["editable"]) for key in ("pl-smart", "pl-file")] == [(True, False), (True, False)]


def test_none_at_all_is_an_empty_list(player):
    player.fake.playlists.clear()
    assert signed_in(player, "ethan").get(f"{PLAYER}/playlists").json() == {"playlists": []}


def test_one_playlist_says_how_many_of_its_songs_arent_in_the_library(player):
    fake = player.fake
    ids = songs(fake, "s1", "s2", "s3", "s4")
    fake.playlist("pl-mine", "Late night", "ethan", ids)
    fake.missing.update({"s2", "s3"})
    answer = signed_in(player, "ethan").get(f"{PLAYER}/playlists/pl-mine").json()

    assert [song["id"] for song in answer["songs"]] == ["s1", "s4"]
    assert answer["hidden"] == 2
    #? on one playlist, the count and the length are the songs listed
    assert (answer["playlist"]["songCount"], answer["playlist"]["duration"]) == (2, 100 + 103)


def test_hidden_is_nought_for_a_smart_playlist_and_one_the_list_lacks(player, monkeypatch):
    fake = player.fake
    ids = songs(fake, "s1", "s2")
    fake.playlist("pl-smart", "Smart", "ethan", ids, smart=True)
    fake.missing.add("s2")
    ethan = signed_in(player, "ethan")
    assert ethan.get(f"{PLAYER}/playlists/pl-smart").json()["hidden"] == 0

    fake.playlist("pl-mine", "Mine", "ethan", ids)
    real = fake.playlist_call

    def lacking(endpoint, user, values):
        answer = real(endpoint, user, values)
        if endpoint != "getPlaylists":
            return answer
        body = answer.json()
        body["subsonic-response"]["playlists"]["playlist"] = [each for each in body["subsonic-response"]["playlists"]["playlist"] if each["id"] != "pl-mine"]
        return httpx.Response(200, json=body)

    monkeypatch.setattr(fake, "playlist_call", lacking)
    assert ethan.get(f"{PLAYER}/playlists/pl-mine").json()["hidden"] == 0


def test_an_unknown_playlist_is_gone(player):
    answer = signed_in(player, "ethan").get(f"{PLAYER}/playlists/pl-nothing")
    assert answer.status_code == 404 and answer.json()["detail"] == rules.GONE


def test_an_id_too_long_is_refused_before_navidrome_is_asked(player):
    forget(player.fake)
    assert signed_in(player, "ethan").get(f"{PLAYER}/playlists/{'x' * 257}").status_code == 422
    assert player.fake.playlist_calls == []


# ----------------------------------------------------------------- making one

def test_a_new_playlist_is_the_askers_with_its_songs_in_order_sent_as_a_form(player):
    fake = player.fake
    ids = songs(fake, "s1", "s2")
    forget(fake)
    answer = signed_in(player, "ethan").post(f"{PLAYER}/playlists", json={"name": "  Late night  ", "song_ids": ["s2", "s1", "s2"]})

    assert answer.status_code == 200, answer.text
    body = answer.json()
    assert body["playlist"]["name"] == "Late night" and body["playlist"]["owner"] == "ethan" and body["playlist"]["mine"]
    assert [song["id"] for song in body["songs"]] == ["s2", "s1", "s2"] and body["hidden"] == 0
    made = next(call for call in fake.playlist_calls if call["endpoint"] == "createPlaylist")
    assert made["form"] is True and made["values"]["songId"] == ["s2", "s1", "s2"] and made["values"]["name"] == ["Late night"]
    #? nothing in the URL - no songs, no name, no login
    assert made["query"] == ""
    assert ids and fake.playlists[body["playlist"]["id"]]["rows"] == ["s2", "s1", "s2"]


@pytest.mark.parametrize("name", ["", "   ", "Late\x00night", "Late\nnight", "x" * 201])
def test_a_name_blank_too_long_or_with_a_control_character_is_refused_asking_nothing(player, name):
    forget(player.fake)
    assert signed_in(player, "ethan").post(f"{PLAYER}/playlists", json={"name": name}).status_code == 422
    assert player.fake.playlist_calls == []


@pytest.mark.parametrize("body, words", [
    ({"name": "x" * 201}, rules.NAME_TOO_LONG),
    ({"name": "   "}, rules.BLANK_NAME),
    ({"name": "Late\x00night"}, rules.CONTROL_NAME),
    ({"name": "Late night", "song_ids": ["s"] * 2001}, rules.SONGS_TOO_MANY),
])
def test_a_refused_new_playlist_says_why_in_words(player, body, words):
    forget(player.fake)
    answer = signed_in(player, "ethan").post(f"{PLAYER}/playlists", json=body)
    assert answer.status_code == 422 and answer.json()["detail"] == words
    assert player.fake.playlist_calls == []


def test_a_field_the_page_didnt_declare_is_refused_never_dropped(player):
    ethan = signed_in(player, "ethan")
    forget(player.fake)
    assert ethan.post(f"{PLAYER}/playlists", json={"name": "Late night", "public": True}).status_code == 422
    assert ethan.post(f"{PLAYER}/playlists/pl-ethan/add", json={"song_ids": [SONG], "at": 0}).status_code == 422
    assert ethan.post(f"{PLAYER}/playlists/pl-ethan/edit", json={"base": [SONG], "song_ids": [SONG], "cover": "x"}).status_code == 422
    assert player.fake.playlist_calls == []


# ----------------------------------------------------------------- adding

def eleven(fake) -> list[str]:
    """A playlist of ethan's holding two of eleven songs, a missing one between them."""
    ids = songs(fake, *[f"t{n}" for n in range(1, 12)], "gone")
    fake.playlist("pl-late", "Late night", "ethan", ["t1", "gone", "t2"])
    fake.missing.add("gone")
    return ids[:11]


def test_ask_with_songs_there_already_writes_nothing_and_says_how_many(player):
    album = eleven(player.fake)
    forget(player.fake)
    answer = signed_in(player, "ethan").post(f"{PLAYER}/playlists/pl-late/add", json={"song_ids": album})
    assert answer.json() == {"done": False, "already": 2, "asked": 11}
    assert writes(player.fake) == []


def test_ask_with_one_song_there_already_asks_too(player):
    """The one-song question ("Add it again") - asked for a single song as for several."""
    eleven(player.fake)
    forget(player.fake)
    answer = signed_in(player, "ethan").post(f"{PLAYER}/playlists/pl-late/add", json={"song_ids": ["t1"]})
    assert answer.json() == {"done": False, "already": 1, "asked": 1}
    assert writes(player.fake) == []


def test_navidrome_saying_only_the_owner_may_is_a_403_in_the_owners_words(player):
    """Navidrome's 50 for a write deadwax's own owner check let through (an owner stored another way, an admin flag
    changed) - the owner's words, never a 502 "user not authorized"."""
    player.fake.errors[("ethan", "updatePlaylist")] = httpx.Response(200, json=failed(50, "user not authorized"))
    answer = signed_in(player, "ethan").post(f"{PLAYER}/playlists/pl-ethan/add", json={"song_ids": [SONG], "duplicates": "add"})
    assert answer.status_code == 403 and answer.json()["detail"] == rules.NOT_THE_OWNER


def test_add_appends_every_song_after_the_last_row_a_missing_one_included(player):
    album = eleven(player.fake)
    answer = signed_in(player, "ethan").post(f"{PLAYER}/playlists/pl-late/add", json={"song_ids": album, "duplicates": "add"})
    assert answer.json() == {"done": True, "added": 11, "already": 2}
    assert player.fake.playlists["pl-late"]["rows"] == ["t1", "gone", "t2", *album]
    added = next(call for call in player.fake.playlist_calls if call["endpoint"] == "updatePlaylist")
    assert added["form"] and added["values"]["songIdToAdd"] == album and added["query"] == ""


def test_skip_adds_only_the_others_and_all_there_writes_nothing(player):
    album = eleven(player.fake)
    ethan = signed_in(player, "ethan")
    assert ethan.post(f"{PLAYER}/playlists/pl-late/add", json={"song_ids": album, "duplicates": "skip"}).json() == {"done": True, "added": 9, "already": 2}
    assert player.fake.playlists["pl-late"]["rows"] == ["t1", "gone", "t2", *album[2:]]
    forget(player.fake)
    assert ethan.post(f"{PLAYER}/playlists/pl-late/add", json={"song_ids": album, "duplicates": "skip"}).json() == {"done": True, "added": 0, "already": 11}
    assert writes(player.fake) == []


def test_jamess_playlist_as_ethan_and_a_smart_one_are_refused_with_nothing_written(player):
    fake = player.fake
    fake.playlist("pl-shared", "Sunday", "james", [SONG], public=True)
    fake.playlist("pl-smart", "Smart", "ethan", [SONG], smart=True)
    ethan = signed_in(player, "ethan")
    forget(fake)
    theirs = ethan.post(f"{PLAYER}/playlists/pl-shared/add", json={"song_ids": [SONG], "duplicates": "add"})
    assert theirs.status_code == 403 and theirs.json()["detail"] == rules.NOT_YOURS.format(owner="james")
    smart = ethan.post(f"{PLAYER}/playlists/pl-smart/add", json={"song_ids": [SONG], "duplicates": "add"})
    assert smart.status_code == 403 and smart.json()["detail"] == rules.FROM_FILE
    private = ethan.post(f"{PLAYER}/playlists/pl-james/add", json={"song_ids": [SONG], "duplicates": "add"})
    assert private.status_code == 404
    assert writes(fake) == []


def test_an_add_to_an_unknown_playlist_too_many_or_no_songs_is_refused(player):
    ethan = signed_in(player, "ethan")
    assert ethan.post(f"{PLAYER}/playlists/pl-nothing/add", json={"song_ids": [SONG]}).status_code == 404
    forget(player.fake)
    too_many = ethan.post(f"{PLAYER}/playlists/pl-ethan/add", json={"song_ids": ["s"] * 2001})
    #? in deadwax's words, a plain detail - FastAPI's list of errors reached the page as "POST ... failed"
    assert too_many.status_code == 422 and too_many.json()["detail"] == rules.SONGS_TOO_MANY
    assert ethan.post(f"{PLAYER}/playlists/pl-ethan/add", json={"song_ids": []}).status_code == 422
    assert ethan.post(f"{PLAYER}/playlists/pl-ethan/add", json={"song_ids": [SONG], "duplicates": "maybe"}).status_code == 422
    assert player.fake.playlist_calls == []


def test_navidrome_refusing_the_login_mid_add_ends_the_session(player):
    ethan = signed_in(player, "ethan")
    player.fake.errors[("ethan", "updatePlaylist")] = httpx.Response(200, json=failed(40, "Wrong username or password"))
    answer = ethan.post(f"{PLAYER}/playlists/pl-ethan/add", json={"song_ids": [SONG], "duplicates": "add"})
    assert answer.status_code == 401 and answer.json()["detail"] == auth.LOGIN_GONE


# ----------------------------------------------------------------- editing

def base_of(client, playlist_id: str) -> list[str]:
    return [song["id"] for song in client.get(f"{PLAYER}/playlists/{playlist_id}").json()["songs"]]


def test_a_playlist_changed_in_another_app_since_edit_began_is_a_409_and_nothing_written(player):
    fake = player.fake
    songs(fake, "s1", "s2", "s3")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "s2"])
    ethan = signed_in(player, "ethan")
    base = base_of(ethan, "pl-mine")
    #? Amperfy adds one between the read and the save
    fake.playlists["pl-mine"]["rows"].append("s3")
    forget(fake)
    answer = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": base, "song_ids": base[::-1], "name": "Renamed"})
    assert answer.status_code == 409 and answer.json()["detail"] == rules.CHANGED
    assert writes(fake) == [] and fake.playlists["pl-mine"]["name"] == "Mine"


def test_an_edit_can_only_remove_and_reorder(player):
    fake = player.fake
    songs(fake, "s1", "s2", "s3")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "s2", "s1"])
    ethan = signed_in(player, "ethan")
    forget(fake)
    for wanted in (["s1", "s3"], ["s1", "s1", "s1"]):
        answer = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2", "s1"], "song_ids": wanted})
        assert answer.status_code == 422 and answer.json()["detail"] == rules.ONLY_REARRANGES
    assert writes(fake) == []


def test_a_reorder_is_navidromes_replace_exact_from_position_one_its_missing_rows_gone(player):
    fake = player.fake
    songs(fake, "s1", "s2", "s3", "gone")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "gone", "s2", "s3"])
    fake.missing.add("gone")
    ethan = signed_in(player, "ethan")
    forget(fake)
    answer = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2", "s3"], "song_ids": ["s3", "s1", "s2"]})

    assert answer.status_code == 200, answer.text
    assert fake.playlists["pl-mine"]["rows"] == ["s3", "s1", "s2"]
    replace = [call for call in fake.playlist_calls if call["endpoint"] in ("createPlaylist", "updatePlaylist")]
    assert [(call["endpoint"], call["values"].get("playlistId"), call["values"].get("songId"), call["form"]) for call in replace] == [
        ("createPlaylist", ["pl-mine"], ["s3", "s1", "s2"], True)]
    #? the final read: the playlist as Navidrome has it now
    assert [song["id"] for song in answer.json()["songs"]] == ["s3", "s1", "s2"] and answer.json()["hidden"] == 0


def test_removing_a_song_after_a_missing_one_removes_that_song(player):
    """The case removing by `songIndexToRemove` gets wrong: the page sees s2 at index 1, but Navidrome's row 2 is
    the missing one - removed by index, the missing row would go and s2 stay."""
    fake = player.fake
    songs(fake, "s1", "s2", "s3", "gone")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "gone", "s2", "s3"])
    fake.missing.add("gone")
    ethan = signed_in(player, "ethan")
    answer = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2", "s3"], "song_ids": ["s1", "s3"]})
    assert answer.status_code == 200, answer.text
    fake.missing.clear()
    assert fake.playlists["pl-mine"]["rows"] == ["s1", "s3"]
    assert all("songIndexToRemove" not in call["values"] for call in fake.playlist_calls)


def test_emptying_a_playlist_with_a_missing_and_an_orphan_row_leaves_none(player):
    fake = player.fake
    songs(fake, "s1", "s2", "gone")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "gone", "orphan", "s2"])
    fake.missing.add("gone")
    ethan = signed_in(player, "ethan")
    forget(fake)
    answer = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2"], "song_ids": []})

    assert answer.status_code == 200, answer.text
    assert fake.playlists["pl-mine"]["rows"] == []
    calls = [(call["endpoint"], call["values"].get("songId"), call["values"].get("songIndexToRemove")) for call in fake.playlist_calls
             if call["endpoint"] in ("createPlaylist", "updatePlaylist")]
    assert calls == [("createPlaylist", ["s1"], None), ("updatePlaylist", None, ["0"])]
    assert answer.json()["songs"] == [] and answer.json()["hidden"] == 0


def test_an_empty_base_and_an_empty_list_write_nothing(player):
    fake = player.fake
    fake.playlist("pl-empty", "Empty", "ethan", [])
    forget(fake)
    assert signed_in(player, "ethan").post(f"{PLAYER}/playlists/pl-empty/edit", json={"base": [], "song_ids": []}).status_code == 200
    assert writes(fake) == []


def test_the_metadata_alone_touches_no_song_and_keeps_a_missing_row(player):
    fake = player.fake
    songs(fake, "s1", "gone")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "gone"], comment="Old words.")
    fake.missing.add("gone")
    ethan = signed_in(player, "ethan")
    forget(fake)
    answer = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1"], "song_ids": ["s1"], "name": "Late night", "comment": "Old words."})

    assert answer.status_code == 200, answer.text
    sent = [call for call in fake.playlist_calls if call["endpoint"] in ("createPlaylist", "updatePlaylist")]
    assert len(sent) == 1 and sent[0]["endpoint"] == "updatePlaylist" and sent[0]["form"]
    assert {key: value for key, value in sent[0]["values"].items() if key in ("name", "comment", "public", "songId", "songIdToAdd")} == {"name": ["Late night"]}
    assert fake.playlists["pl-mine"]["rows"] == ["s1", "gone"]
    assert answer.json()["playlist"]["name"] == "Late night" and answer.json()["hidden"] == 1


def test_a_description_cleared_and_sharing_both_ways(player):
    fake = player.fake
    fake.playlists["pl-ethan"]["comment"] = "Words."
    ethan = signed_in(player, "ethan")
    assert ethan.post(f"{PLAYER}/playlists/pl-ethan/edit", json={"base": [SONG], "song_ids": [SONG], "comment": "", "public": True}).status_code == 200
    assert (fake.playlists["pl-ethan"]["comment"], fake.playlists["pl-ethan"]["public"]) == ("", True)
    assert ethan.post(f"{PLAYER}/playlists/pl-ethan/edit", json={"base": [SONG], "song_ids": [SONG], "public": False}).json()["playlist"]["public"] is False
    assert fake.playlists["pl-ethan"]["public"] is False


def test_the_songs_saved_and_the_metadata_refused_is_a_502_saying_so(player):
    fake = player.fake
    songs(fake, "s1", "s2")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "s2"])
    ethan = signed_in(player, "ethan")
    real = fake.playlist_call

    def refusing(endpoint, user, values):
        if endpoint == "updatePlaylist" and "name" in values:
            return httpx.Response(200, json=failed(0, "database is locked"))
        return real(endpoint, user, values)

    fake.playlist_call = refusing
    answer = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2"], "song_ids": ["s2", "s1"], "name": "Renamed"})
    #? (2.0.4) the sentence for anyone, Navidrome's own words as the why (src/auth.py Explained)
    assert answer.status_code == 502 and answer.json()["detail"] == rules.PART_SAVED
    assert "database is locked" in answer.json()["why"]
    assert fake.playlists["pl-mine"]["rows"] == ["s2", "s1"] and fake.playlists["pl-mine"]["name"] == "Mine"


@pytest.mark.parametrize("extra, words", [
    ({"name": "   "}, rules.BLANK_NAME),
    ({"name": "Late\x00night"}, rules.CONTROL_NAME),
    ({"name": "x" * 201}, rules.NAME_TOO_LONG),
    ({"comment": "a\x07b"}, rules.CONTROL_COMMENT),
    ({"comment": "a" * 1001}, rules.COMMENT_TOO_LONG),
    ({"base": ["s"] * 2001}, rules.TOO_LONG),
    ({"song_ids": ["s"] * 2001}, rules.TOO_LONG),
    ({"tried": ["s"] * 2001}, rules.TOO_LONG),
])
def test_an_edit_refused_by_its_limits_says_why_and_asks_navidrome_nothing(player, extra, words):
    forget(player.fake)
    answer = signed_in(player, "ethan").post(f"{PLAYER}/playlists/pl-ethan/edit", json={"base": [SONG], "song_ids": [SONG], **extra})
    assert answer.status_code == 422 and answer.json()["detail"] == words
    assert player.fake.playlist_calls == []


def test_a_description_of_new_lines_and_tabs_and_a_thousand_characters_is_taken(player):
    ethan = signed_in(player, "ethan")
    comment = "Songs\nfor\tlate." + "a" * (rules.PLAYLIST_COMMENT_MAX - 15)
    answer = ethan.post(f"{PLAYER}/playlists/pl-ethan/edit", json={"base": [SONG], "song_ids": [SONG], "comment": comment})
    assert answer.status_code == 200, answer.text
    assert player.fake.playlists["pl-ethan"]["comment"] == comment and len(comment) == rules.PLAYLIST_COMMENT_MAX


def test_another_routes_422_is_fastapis_own(player):
    """Only the playlist routes' refusals are put in words; every other route answers as FastAPI always did - one
    whose own validator raises a ValueError too (an album pin with nothing to know it by), which validation_words
    would put in words but for its path check (review)."""
    ethan = signed_in(player, "ethan")
    answer = ethan.post("/deadwax/me/pins/toggle", json={"nothing": True})
    assert answer.status_code == 422 and isinstance(answer.json()["detail"], list)
    answer = ethan.post("/deadwax/me/pins/toggle", json={"kind": "album", "pinned": True})
    assert answer.status_code == 422, answer.text
    detail = answer.json()["detail"]
    assert isinstance(detail, list) and [error["type"] for error in detail] == ["value_error"]
    assert "an album needs its release_mbid or its navidrome_id" in detail[0]["msg"]


def refuse(fake, when):
    """fake's playlist calls, with those `when(endpoint, values)` picks answered as Navidrome refusing them."""
    real = fake.playlist_call

    def refusing(endpoint, user, values):
        if when(endpoint, values):
            return httpx.Response(200, json=failed(0, "database is locked"))
        return real(endpoint, user, values)

    fake.playlist_call = refusing
    return lambda: setattr(fake, "playlist_call", real)


def test_a_refused_rename_that_touched_no_song_is_navidromes_words_never_songs_saved(player):
    fake = player.fake
    songs(fake, "s1", "s2")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "s2"])
    ethan = signed_in(player, "ethan")
    refuse(fake, lambda endpoint, values: endpoint == "updatePlaylist" and "name" in values)
    answer = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2"], "song_ids": ["s1", "s2"], "name": "Renamed"})
    assert answer.status_code == 502 and "database is locked" in answer.json()["detail"]
    assert not answer.json()["detail"].startswith("The songs were saved")
    assert fake.playlists["pl-mine"]["rows"] == ["s1", "s2"] and fake.playlists["pl-mine"]["name"] == "Mine"


def test_done_again_after_the_songs_saved_and_the_name_refused_saves_the_name_and_writes_no_song(player):
    """The retry the page makes after PART_SAVED: `tried` the songs it sent - found there, they are its own save, not
    a change made in another app (which a 409 CHANGED would have said, and that nothing was saved)."""
    fake = player.fake
    songs(fake, "s1", "s2")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "s2"])
    ethan = signed_in(player, "ethan")
    body = {"base": ["s1", "s2"], "song_ids": ["s2", "s1"], "name": "Renamed"}
    let_go = refuse(fake, lambda endpoint, values: endpoint == "updatePlaylist" and "name" in values)
    assert ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json=body).status_code == 502
    let_go()
    #? the old page's retry, without `tried`, is what the review found: a 409 saying nothing was saved
    assert ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json=body).status_code == 409
    forget(fake)
    again = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={**body, "tried": ["s2", "s1"]})
    assert again.status_code == 200, again.text
    assert [call["endpoint"] for call in fake.playlist_calls if call["endpoint"] in ("createPlaylist", "updatePlaylist")] == ["updatePlaylist"]
    assert fake.playlists["pl-mine"]["rows"] == ["s2", "s1"] and fake.playlists["pl-mine"]["name"] == "Renamed"
    #? ...and the songs changed again since the failed Done: written from where that one left them
    assert ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2"], "song_ids": ["s1"], "tried": ["s2", "s1"]}).status_code == 200
    assert fake.playlists["pl-mine"]["rows"] == ["s1"]


def test_tried_never_excuses_a_change_made_in_another_app(player):
    fake = player.fake
    songs(fake, "s1", "s2", "s3")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "s2", "s3"])
    forget(fake)
    answer = signed_in(player, "ethan").post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2"], "song_ids": ["s2"], "tried": ["s2", "s1"]})
    assert answer.status_code == 409 and answer.json()["detail"] == rules.CHANGED
    assert writes(fake) == []
    #? ...nor lets an edit add what isn't there now
    answer = signed_in(player, "ethan").post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2", "s3", "s3"], "song_ids": ["s3", "s3"], "tried": ["s1", "s2", "s3"]})
    assert answer.status_code == 422 and writes(fake) == []


def test_written_and_only_the_read_after_failing_says_it_was_saved_and_done_again_shows_it(player):
    fake = player.fake
    songs(fake, "s1", "s2")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "s2"])
    ethan = signed_in(player, "ethan")
    seen = {"wrote": False}

    def after_the_write(endpoint, values):
        seen["wrote"] = seen["wrote"] or endpoint == "createPlaylist"
        return endpoint == "getPlaylist" and seen["wrote"]

    let_go = refuse(fake, after_the_write)
    body = {"base": ["s1", "s2"], "song_ids": ["s2", "s1"]}
    answer = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json=body)
    assert answer.status_code == 502 and answer.json()["detail"] == rules.SAVED_UNREAD
    assert "database is locked" in answer.json()["why"]
    assert fake.playlists["pl-mine"]["rows"] == ["s2", "s1"]
    let_go()
    forget(fake)
    again = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={**body, "tried": ["s2", "s1"]})
    assert again.status_code == 200 and [song["id"] for song in again.json()["songs"]] == ["s2", "s1"]
    assert writes(fake) == []


def test_emptying_stopped_after_its_first_step_is_finished_by_done_again(player):
    fake = player.fake
    songs(fake, "s1", "s2")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "s2"])
    ethan = signed_in(player, "ethan")
    let_go = refuse(fake, lambda endpoint, values: endpoint == "updatePlaylist" and "songIndexToRemove" in values)
    assert ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2"], "song_ids": []}).status_code == 502
    assert fake.playlists["pl-mine"]["rows"] == ["s1"]
    let_go()
    again = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2"], "song_ids": [], "tried": []})
    assert again.status_code == 200, again.text
    assert fake.playlists["pl-mine"]["rows"] == [] and again.json()["songs"] == []


def test_emptying_after_two_dones_that_failed_is_finished_by_a_third_never_a_409(player):
    """(review) Done 1 saved [s2, s3] and only its read failed; Done 2, emptying from there, stopped after its first
    step at [s2] - not base's first song. Done 3 (tried: the [] Done 2 sent) finds [s2] and finishes the emptying."""
    fake = player.fake
    songs(fake, "s1", "s2", "s3")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "s2", "s3"])
    ethan = signed_in(player, "ethan")
    base = ["s1", "s2", "s3"]
    seen = {"wrote": False}

    def after_the_write(endpoint, values):
        seen["wrote"] = seen["wrote"] or endpoint == "createPlaylist"
        return endpoint == "getPlaylist" and seen["wrote"]

    let_go = refuse(fake, after_the_write)
    first = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": base, "song_ids": ["s2", "s3"]})
    assert first.status_code == 502 and first.json()["detail"].startswith("Saved - but")
    let_go()
    let_go = refuse(fake, lambda endpoint, values: endpoint == "updatePlaylist" and "songIndexToRemove" in values)
    second = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": base, "song_ids": [], "tried": ["s2", "s3"]})
    assert second.status_code == 502 and fake.playlists["pl-mine"]["rows"] == ["s2"]
    let_go()
    third = ethan.post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": base, "song_ids": [], "tried": []})
    assert third.status_code == 200, third.text
    assert fake.playlists["pl-mine"]["rows"] == [] and third.json()["songs"] == []


def test_an_emptying_retry_never_excuses_one_song_that_isnt_bases(player):
    """...but a lone song the edit never began with is a change made in another app: a 409, nothing written."""
    fake = player.fake
    songs(fake, "s1", "s2", "s9")
    fake.playlist("pl-mine", "Mine", "ethan", ["s9"])
    forget(fake)
    answer = signed_in(player, "ethan").post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2"], "song_ids": [], "tried": []})
    assert answer.status_code == 409 and answer.json()["detail"] == rules.CHANGED and writes(fake) == []


def test_a_playlist_deleted_elsewhere_right_after_the_write_is_gone_never_saved(player):
    """(review) The read after a write answering Navidrome's 70 is the playlist gone (404), not "Saved - but…"."""
    fake = player.fake
    songs(fake, "s1", "s2")
    fake.playlist("pl-mine", "Mine", "ethan", ["s1", "s2"])
    real = fake.playlist_call
    seen = {"wrote": False}

    def deleted_after(endpoint, user, values):
        seen["wrote"] = seen["wrote"] or endpoint == "createPlaylist"
        if endpoint == "getPlaylist" and seen["wrote"]:
            return httpx.Response(200, json=failed(70, "playlist not found"))
        return real(endpoint, user, values)

    fake.playlist_call = deleted_after
    try:
        answer = signed_in(player, "ethan").post(f"{PLAYER}/playlists/pl-mine/edit", json={"base": ["s1", "s2"], "song_ids": ["s2", "s1"]})
    finally:
        fake.playlist_call = real
    assert seen["wrote"]
    assert answer.status_code == 404 and answer.json()["detail"] == rules.GONE


def test_only_the_metadata_that_changed_is_written_and_none_changed_writes_nothing(player):
    """(review) Sharing, the name and the description each sent as they are now, the songs unchanged: no write."""
    fake = player.fake
    fake.playlists["pl-ethan"].update({"public": True, "comment": "Words."})
    ethan = signed_in(player, "ethan")
    name = ethan.get(f"{PLAYER}/playlists/pl-ethan").json()["playlist"]["name"]
    forget(fake)
    for same in ({"public": True}, {"name": name}, {"comment": "Words."}, {"public": True, "name": name, "comment": "Words."}):
        answer = ethan.post(f"{PLAYER}/playlists/pl-ethan/edit", json={"base": [SONG], "song_ids": [SONG], **same})
        assert answer.status_code == 200, answer.text
    assert writes(fake) == []


def test_others_and_one_too_long_to_edit_are_refused(player):
    fake = player.fake
    fake.playlist("pl-shared", "Sunday", "james", [SONG], public=True)
    ids = songs(fake, *[f"b{n}" for n in range(2001)])
    fake.playlist("pl-big", "Big", "ethan", ids)
    ethan = signed_in(player, "ethan")
    forget(fake)
    theirs = ethan.post(f"{PLAYER}/playlists/pl-shared/edit", json={"base": [SONG], "song_ids": []})
    assert theirs.status_code == 403
    big = ethan.post(f"{PLAYER}/playlists/pl-big/edit", json={"base": ids[:2000], "song_ids": ids[:2000]})
    assert big.status_code == 409 and big.json()["detail"] == rules.TOO_LONG
    assert writes(fake) == []


# ----------------------------------------------------------------- deleting

def test_delete_takes_mine_and_refuses_theirs_and_a_file_synced_one(player):
    fake = player.fake
    fake.playlist("pl-shared", "Sunday", "james", [SONG], public=True)
    fake.playlist("pl-file", "From an m3u", "ethan", [SONG], sync=True)
    fake.playlist("pl-smart", "Smart", "ethan", [SONG], smart=True)
    ethan = signed_in(player, "ethan")
    assert ethan.post(f"{PLAYER}/playlists/pl-ethan/delete").json() == {"deleted": True}
    assert "pl-ethan" not in fake.playlists
    deleted = next(call for call in fake.playlist_calls if call["endpoint"] == "deletePlaylist")
    assert deleted["form"] and deleted["values"]["id"] == ["pl-ethan"] and deleted["query"] == ""
    forget(fake)
    assert ethan.post(f"{PLAYER}/playlists/pl-shared/delete").status_code == 403
    for fixed in ("pl-file", "pl-smart"):
        answer = ethan.post(f"{PLAYER}/playlists/{fixed}/delete")
        assert answer.status_code == 403 and answer.json()["detail"] == rules.FROM_FILE
    assert writes(fake) == [] and {"pl-shared", "pl-file", "pl-smart"} <= set(fake.playlists)
    assert ethan.post(f"{PLAYER}/playlists/pl-nothing/delete").status_code == 404


def test_a_shared_admin_account_never_deletes_another_users_private_playlist(player, monkeypatch):
    player.fake.admins.add("demo")
    nobody = logins_off(player, monkeypatch)
    assert nobody.post(f"{PLAYER}/playlists/pl-james/delete").status_code == 404
    assert "pl-james" in player.fake.playlists and writes(player.fake) == []


# ----------------------------------------------------------------- as whom

def test_with_logins_off_and_for_break_glass_every_playlist_call_is_the_shared_accounts(player, monkeypatch):
    glass = signed_in(player, auth.BREAK_GLASS_USER)
    made = glass.post(f"{PLAYER}/playlists", json={"name": "Glass"}).json()
    assert made["playlist"]["owner"] == "demo" and made["playlist"]["mine"]
    nobody = logins_off(player, monkeypatch)
    assert [row["id"] for row in nobody.get(f"{PLAYER}/playlists").json()["playlists"]] == ["pl-demo", made["playlist"]["id"]]
    assert {call["user"] for call in player.fake.playlist_calls} == {"demo"}


def test_a_cross_origin_delete_is_refused_and_navidrome_never_asked(player):
    forget(player.fake)
    answer = signed_in(player, "ethan").post(f"{PLAYER}/playlists/pl-ethan/delete", headers={"Origin": "https://evil.example"})
    assert answer.status_code == 403
    assert player.fake.playlist_calls == [] and "pl-ethan" in player.fake.playlists


# ----------------------------------------------------------------- the client's form

def test_a_write_with_no_usable_login_is_a_401_in_words_never_a_500():
    client = navidrome_endpoint._NoLogin(auth.SIGN_IN)
    with pytest.raises(SignedOut):
        run(client.call("createPlaylist", {"name": "x"}, form=True))


def test_a_form_call_posts_its_parameters_and_the_login_in_the_body_and_a_get_is_as_before(monkeypatch):
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome.test:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "demo")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "demo-pw")
    seen: list[httpx.Request] = []

    def answer(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"subsonic-response": {"status": "ok", "version": "1.16.1"}})

    client = NavidromeClient()
    client.client = httpx.AsyncClient(transport=httpx.MockTransport(answer), base_url="http://navidrome.test:4533/rest")
    run(client.call("createPlaylist", {"name": "Late night", "songId": ["a", "b", "a"]}, form=True))
    run(client.call("getPlaylists"))
    run(client.close_client())

    posted, got = seen
    assert posted.method == "POST" and posted.url.query == b""
    assert posted.headers["content-type"] == "application/x-www-form-urlencoded"
    body = posted.content.decode()
    assert re.search(r"songId=a&songId=b&songId=a", body)
    values = parse_qs(body)
    assert values["name"] == ["Late night"] and values["u"] == ["demo"] and "t" in values and "s" in values
    assert got.method == "GET" and got.content == b"" and parse_qs(urlparse(str(got.url)).query)["u"] == ["demo"]


def test_a_signed_in_users_form_carries_their_login_in_the_body(player):
    ethan = signed_in(player, "ethan")
    ethan.post(f"{PLAYER}/playlists/pl-ethan/add", json={"song_ids": [SONG], "duplicates": "add"})
    added = next(call for call in player.fake.playlist_calls if call["endpoint"] == "updatePlaylist")
    assert added["query"] == "" and added["values"]["u"] == ["ethan"]
