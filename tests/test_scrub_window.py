"""
The turntable's sound, the server's half (2.0.0-player.14): a stretch of a FLAC song as a FLAC file
of its own, cut from the MP4 deadwax keeps of it (src/flac_window.py), and the route the phone asks
for it by (GET /deadwax/navidrome/scrub/{song_id}).

What it pins:

  - a window is a STANDALONE FLAC: 'fLaC', STREAMINFO alone and rewritten for it (its total samples,
    its frames' smallest and largest sizes, the MD5 zeroed; the song's block sizes, rate, channels
    and depth), then the song's frames, their audio untouched and renumbered from 0 - each header's
    CRC-8 and each frame's CRC-16 right, which deadwax's own strict find_frames() checks, and which
    `flac` itself is asked about where it is installed;
  - the CRC-16 carried over to a new header by arithmetic equals summing the frame again;
  - it covers what was asked: it starts on a frame (a fragment of the gapless player's MP4) at or
    before `at`, runs to or past `at + seconds` - or the song's end - and says exactly where it sits;
    and a hi-res song's is shorter than asked, never more than WINDOW_MAX_BYTES bar the frame `at`
    falls in;
  - through the real app: audio/flac, never gzipped, under the media headers; the MP4 the cache
    already holds is cut from - Safari's or the gapless player's - and only when there is neither is
    the plain one made, once; a song that isn't a FLAC is a 415 saying so, as is one too big to hold
    or one whose MP4 was refused (nothing fetched for the first); a start past the end 416;
  - a hi-res song the page plays resampled (`max_rate=48000`): cut from the resampled copy the phone
    plays - its rate, its level - with nothing downloaded again and no full-rate copy made beside it
    (review: the first cut did both); made resampled when there is none; the song as it is when that
    copy is refused, or the audio libraries aren't there;
  - declared, bounded parameters: only `at`, `seconds` and `max_rate`, in their bounds, or a 422 with
    Navidrome asked nothing - and the route is on the player's fixed list on purpose.

Navidrome is test_navidrome.py's fake, and the app is the real one start() builds, without its
lifespan, so nothing connects anywhere.
"""

import json
import random
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import flac_window, player_cache, resample  # noqa: E402
from src.flac_mp4 import _SHORTEST, _crc16, _frame_header, find_frames, flac_to_fmp4, flac_to_mp4  # noqa: E402
from src.flac_window import (CannotCut, PastTheEnd, coded_number, cut_window, flac_of_frames,  # noqa: E402
                             renumber, song_index)
from src.routes import navidrome as navidrome_routes  # noqa: E402
import test_navidrome as navidrome_tests  # noqa: E402
from test_flac_mp4 import coded, crc16, encode  # noqa: E402
from test_navidrome import MEDIA_HEADERS, STAMP, navidrome_file, query  # noqa: E402

configured, upstream, client, mp4_cache = (navidrome_tests.configured, navidrome_tests.upstream,
                                           navidrome_tests.client, navidrome_tests.mp4_cache)

RATE = 44100
#? 40 frames of 4096 and a short last one: 164,840 samples, 3.74 s
SONG, SONG_FRAMES = encode(blocks=(4096,) * 40 + (1000,), seed=11)
SONG_SAMPLES = 40 * 4096 + 1000
INFO = find_frames(SONG).info


def reader(data: bytes):
    return lambda offset, length: data[offset:offset + length]


def frames_of(window: bytes):
    """The window's frames as find_frames() splits them - which refuses a first frame that isn't 0,
    a number out of order, a header whose CRC-8 is wrong and a last frame whose CRC-16 is."""
    found = find_frames(window)
    bounds = found.starts + (found.end,)
    return found, [window[a:b] for a, b in zip(bounds, bounds[1:])]


def assert_is_the_songs_audio(window_frames: list[bytes], first_frame: int):
    """Every frame of the window is the song's frame at that place, from its header on - and each
    sums to zero with its own CRC-16, as a frame must."""
    for at, frame in enumerate(window_frames):
        _, original, _ = SONG_FRAMES[first_frame + at]
        _, _, window_head = _frame_header(frame, 0, INFO)
        _, _, song_head = _frame_header(original, 0, INFO)
        assert frame[window_head:-2] == original[song_head:-2], "the audio is the song's, untouched"
        assert crc16(frame) == 0, f"frame {at}'s CRC-16 checks out"


# ---------------------------------------------------------------- numbers and checksums

@pytest.mark.parametrize("number", [0, 1, 127, 128, 2047, 2048, 65535, 65536, (1 << 21) - 1, 1 << 21,
                                    (1 << 26) - 1, 1 << 26, (1 << 31) - 1, 1 << 31, (1 << 36) - 1])
def test_a_number_is_coded_the_shortest_way_flac_reads(number):
    assert coded_number(number) == coded(number), "as the test encoder codes it"
    length = len(coded_number(number))
    assert length == next(n for n, least in enumerate(_SHORTEST[1:] + (1 << 36,), start=1) if number < least)


@pytest.mark.parametrize("number", [-1, 1 << 36])
def test_a_number_flac_cant_carry_is_refused(number):
    with pytest.raises(CannotCut):
        coded_number(number)


def test_the_checksum_carried_through_zeros_is_the_checksum_summed_through_them():
    rng = random.Random(5)
    for _ in range(300):
        start = rng.randrange(1 << 16)
        length = rng.choice([0, 1, 2, 3, 7, 100, 4093, rng.randrange(1, 70000)])
        assert flac_window._crc16_after(start, length) == _crc16(bytes(length), start), (start, length)


def test_a_new_number_carries_the_checksum_over_exactly():
    """Every length of coded number, growing and shrinking the header: the header reads back with the
    new number and a right CRC-8, the frame sums to zero, and the audio is as it was."""
    frame = SONG_FRAMES[5][1]
    for number in (0, 1, 127, 128, 5000, 70000, 3_000_000, 1 << 30, (1 << 36) - 1):
        moved = renumber(frame, INFO, number)
        read = _frame_header(moved, 0, INFO)
        assert read is not None and read[0] == number and read[1] == 4096
        assert crc16(moved) == 0
        _, _, old_length = _frame_header(frame, 0, INFO)
        assert moved[read[2]:-2] == frame[old_length:-2]
    assert renumber(frame, INFO, 5) == frame, "its own number: the very same bytes"


def test_a_variable_block_stream_is_renumbered_by_its_samples():
    data, frames = encode(blocks=(4096, 1152, 4608, 576, 2304), variable=True, seed=2)
    info = find_frames(data).info
    window = flac_of_frames(info, [(frame, block) for _, frame, block in frames[1:]], first=4096)
    found, split = frames_of(window.data)
    assert [_frame_header(f, 0, info)[0] for f in split] == [0, 1152, 1152 + 4608, 1152 + 4608 + 576]
    assert found.block_sizes == (1152, 4608, 576, 2304) and all(crc16(f) == 0 for f in split)


def test_bytes_that_arent_a_frame_of_this_stream_are_refused():
    frame = SONG_FRAMES[3][1]
    with pytest.raises(CannotCut):
        renumber(b"\x00\x01" + frame[2:], INFO, 0)
    with pytest.raises(CannotCut):
        renumber(frame[:5], INFO, 0)


# ---------------------------------------------------------------- the window as a FLAC of its own

def test_a_window_is_a_flac_of_its_own_with_streaminfo_rewritten():
    picked = [(frame, block) for _, frame, block in SONG_FRAMES[10:20]]
    window = flac_of_frames(INFO, picked, first=10 * 4096, song_samples=SONG_SAMPLES)
    data = window.data
    assert data[:4] == b"fLaC" and data[4:8] == bytes((0x80, 0, 0, 34)), "STREAMINFO, alone, the last block"
    raw = data[8:42]
    found, split = frames_of(data)
    sizes = [len(f) for f in split]
    assert raw[0:4] == INFO.raw[0:4], "the song's block sizes"
    assert int.from_bytes(raw[4:7], "big") == min(sizes) and int.from_bytes(raw[7:10], "big") == max(sizes)
    packed = int.from_bytes(raw[10:18], "big")
    assert packed >> 36 == int.from_bytes(INFO.raw[10:18], "big") >> 36, "the song's rate, channels and depth"
    assert packed & 0xFFFFFFFFF == 10 * 4096 == window.samples
    assert raw[18:34] == bytes(16), "the MD5 zeroed: not known"
    assert found.starts[0] == 42, "the frames straight after STREAMINFO"
    assert [_frame_header(f, 0, INFO)[0] for f in split] == list(range(10)), "renumbered from 0"
    assert_is_the_songs_audio(split, 10)
    assert (window.first, window.rate, window.song_samples) == (10 * 4096, RATE, SONG_SAMPLES)


@pytest.mark.parametrize("container", ["mp4", "fmp4"])
@pytest.mark.parametrize("at, seconds", [(0.0, 1.0), (1.0, 1.5), (2.3, 30.0), (3.7, 0.2), (0.93, 0.01)])
def test_the_window_covers_what_was_asked_from_a_boundary(container, at, seconds):
    mp4 = flac_to_mp4(SONG) if container == "mp4" else flac_to_fmp4(SONG)
    window = cut_window(reader(mp4), len(mp4), at, seconds, 8 << 20)
    found, split = frames_of(window.data)
    start, end = int(at * RATE), min(int((at + seconds) * RATE), SONG_SAMPLES)
    assert window.first <= start < window.first + window.samples, "it starts at or before `at`"
    assert window.first + window.samples >= end, "and runs to or past its end - or the song's"
    assert window.first % 4096 == 0, "on a frame of the song"
    if container == "fmp4":
        index = song_index(reader(mp4), len(mp4))
        assert window.first in index.firsts, "on a fragment of the gapless player's MP4"
    assert sum(found.block_sizes) == window.samples
    assert_is_the_songs_audio(split, window.first // 4096)


def test_the_last_frame_short_or_not_is_carried_to_the_end_of_the_song():
    mp4 = flac_to_mp4(SONG)
    window = cut_window(reader(mp4), len(mp4), 3.6, 5.0, 8 << 20)
    found, split = frames_of(window.data)
    assert window.first + window.samples == SONG_SAMPLES and found.block_sizes[-1] == 1000


def test_a_start_past_the_end_of_the_song_is_said_so():
    mp4 = flac_to_mp4(SONG)
    with pytest.raises(PastTheEnd):
        cut_window(reader(mp4), len(mp4), SONG_SAMPLES / RATE, 1.0, 8 << 20)
    with pytest.raises(PastTheEnd):
        cut_window(reader(mp4), len(mp4), 60.0, 1.0, 8 << 20)


def test_a_window_is_never_more_than_the_budget_bar_the_frame_it_starts_in():
    mp4 = flac_to_mp4(SONG)
    frame = len(SONG_FRAMES[1][1])
    window = cut_window(reader(mp4), len(mp4), 0.0, 30.0, 3 * frame)
    assert window.samples == 3 * 4096, "three frames' worth, and the page reads how long it got"
    tiny = cut_window(reader(mp4), len(mp4), 0.5, 30.0, 1)
    assert tiny.samples == 4096, "however small the budget, the frame `at` falls in"


@pytest.mark.parametrize("damage", ["noise", "truncated", "flac"])
def test_a_file_not_laid_out_as_deadwax_lays_them_out_is_refused(damage):
    mp4 = flac_to_mp4(SONG)
    data = {"noise": random.Random(1).randbytes(5000), "truncated": mp4[:200], "flac": SONG}[damage]
    with pytest.raises(CannotCut):
        cut_window(reader(data), len(data), 0.0, 1.0, 8 << 20)


def test_an_mp4_laid_out_otherwise_is_refused_even_when_it_could_be_read():
    """Only deadwax's own layout is read - ftyp, moov, mdat - never guessed at: a well-formed MP4 with a
    box between (here a 'free', its chunk offsets moved to match, so every table is right) is refused."""
    mp4 = flac_to_mp4(SONG)
    ftyp = int.from_bytes(mp4[0:4], "big")
    moov = int.from_bytes(mp4[ftyp:ftyp + 4], "big")
    body = bytearray(mp4[ftyp:ftyp + moov])
    at = body.find(b"stco")
    count = int.from_bytes(body[at + 8:at + 12], "big")
    for row in range(count):
        place = at + 12 + 4 * row
        body[place:place + 4] = (int.from_bytes(body[place:place + 4], "big") + 8).to_bytes(4, "big")
    other = mp4[:ftyp] + (8).to_bytes(4, "big") + b"free" + bytes(body) + mp4[ftyp + moov:]
    with pytest.raises(CannotCut, match="laid out"):
        cut_window(reader(other), len(other), 1.0, 1.0, 8 << 20)


@pytest.mark.skipif(shutil.which("flac") is None, reason="needs the flac command")
def test_flac_itself_decodes_a_window_to_the_songs_own_samples(tmp_path):
    """libFLAC, which every decoder is measured against: the window decodes, and its samples are the
    song's at that place. (Measured beside this, not in it: ffmpeg's decoder and macOS's own -
    afconvert, AudioToolbox, the family an iPhone's decodeAudioData is - agree.)"""
    for container in (flac_to_mp4, flac_to_fmp4):
        mp4 = container(SONG)
        window = cut_window(reader(mp4), len(mp4), 1.2, 1.0, 8 << 20)
        (tmp_path / "window.flac").write_bytes(window.data)
        (tmp_path / "song.flac").write_bytes(SONG)
        for name in ("window", "song"):
            subprocess.run(["flac", "-d", "-s", "-f", "--force-raw-format", "--endian=little", "--sign=signed",
                            "-o", str(tmp_path / f"{name}.raw"), str(tmp_path / f"{name}.flac")], check=True)
        song = (tmp_path / "song.raw").read_bytes()
        assert (tmp_path / "window.raw").read_bytes() == song[window.first * 4:(window.first + window.samples) * 4]


# ---------------------------------------------------------------- through the real app

SCRUB = "/deadwax/navidrome/scrub/song-1"


def window_of(response) -> tuple[int, int, int]:
    first, samples, rate = (int(part) for part in response.headers["x-deadwax-window"].split("/"))
    return first, samples, rate


def test_a_window_through_the_app(upstream, client, mp4_cache):
    state, seen = upstream
    fake, state["handler"] = navidrome_file(SONG)

    response = client.get(SCRUB, params={"at": 1.5, "seconds": 1.0}, headers={"Accept-Encoding": "gzip"})

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/flac"
    assert response.headers["cache-control"] == player_cache.WINDOW_CACHE
    assert "content-encoding" not in response.headers, "FLAC: never gzipped"
    assert response.headers["content-length"] == str(len(response.content))
    for name, value in MEDIA_HEADERS.items():
        assert response.headers[name] == value
    first, samples, rate = window_of(response)
    assert rate == RATE and first <= int(1.5 * RATE) and first + samples >= int(2.5 * RATE)
    found, split = frames_of(response.content)
    assert sum(found.block_sizes) == samples
    assert_is_the_songs_audio(split, first // 4096)
    assert fake["whole"] == 1, "the song fetched once, whole, to make its MP4"
    assert all(query(request)["format"] == "raw" and query(request)["id"] == "song-1" for request in seen)


def test_the_mp4_made_for_the_first_window_is_cut_from_again(upstream, client, mp4_cache):
    state, _ = upstream
    fake, state["handler"] = navidrome_file(SONG)
    client.get(SCRUB, params={"at": 0.0})
    made = sorted(mp4_cache.directory.glob("*.mp4"))

    again = client.get(SCRUB, params={"at": 2.0, "seconds": 1.0})

    assert again.status_code == 200 and window_of(again)[0] <= int(2.0 * RATE)
    assert fake["whole"] == 1, "nothing fetched again"
    assert sorted(mp4_cache.directory.glob("*.mp4")) == made


def test_safaris_mp4_is_cut_from_and_nothing_is_made(upstream, client, mp4_cache):
    """The iPhone's songs are in the cache already - it asks for them in an MP4 to play them."""
    state, _ = upstream
    fake, state["handler"] = navidrome_file(SONG)
    assert client.get("/deadwax/navidrome/stream/song-1?format=raw&wrap=mp4").status_code == 200
    made = sorted(mp4_cache.directory.glob("*.mp4"))

    response = client.get(SCRUB, params={"at": 1.0})

    assert response.status_code == 200 and fake["whole"] == 1
    assert sorted(mp4_cache.directory.glob("*.mp4")) == made


def test_the_gapless_players_mp4_is_cut_from_and_no_plain_one_is_made(upstream, client, mp4_cache):
    state, _ = upstream
    fake, state["handler"] = navidrome_file(SONG)
    assert client.get("/deadwax/navidrome/stream/song-1?format=raw&wrap=fmp4").status_code == 200

    response = client.get(SCRUB, params={"at": 1.0, "seconds": 1.0})

    assert response.status_code == 200 and fake["whole"] == 1
    first, samples, _ = window_of(response)
    index = song_index(reader(flac_to_fmp4(SONG)), len(flac_to_fmp4(SONG)))
    assert first in index.firsts, "cut on the fragments of the gapless player's MP4"
    assert [path.name for path in mp4_cache.directory.glob("*.mp4") if not path.name.endswith(".f.mp4")] == []


@pytest.mark.parametrize("kind", ["mp3", "empty"])
def test_a_song_that_isnt_a_flac_is_a_415_saying_so(upstream, client, kind):
    state, _ = upstream
    if kind == "mp3":
        _, state["handler"] = navidrome_file(b"ID3" + bytes(5000), content_type="audio/mpeg")
    else:
        state["handler"] = lambda request: httpx.Response(416, headers={"content-range": "bytes */0"})

    response = client.get(SCRUB, params={"at": 1.0})

    assert response.status_code == 415
    assert response.json()["detail"] == {"mp3": "it isn't a FLAC file", "empty": "the file is empty"}[kind]
    assert response.headers["cache-control"] == "no-store"


def test_a_start_past_the_end_is_a_416(upstream, client):
    state, _ = upstream
    _, state["handler"] = navidrome_file(SONG)

    response = client.get(SCRUB, params={"at": 30.0})

    assert response.status_code == 416 and "past the end" in response.json()["detail"]


@pytest.mark.parametrize("params", [
    {"at": "1", "format": "mp3"}, {"at": "1", "u": "admin"}, {"at": "1", "id": "song-2"},
    {"at": "-1"}, {"at": "86401"}, {"at": "nan"}, {"at": "inf"}, {"at": "soon"},
    {"at": "1", "seconds": "0.5"}, {"at": "1", "seconds": "61"}, {},
    {"at": "1", "max_rate": "96000"}, {"at": "1", "max_rate": "44100"}, {"at": "1", "max_rate": "original"},
    {"at": "1", "max_rate": ""},
])
def test_only_at_seconds_and_max_rate_in_their_bounds(upstream, client, params):
    state, seen = upstream
    _, state["handler"] = navidrome_file(SONG)

    response = client.get(SCRUB, params=params)

    assert response.status_code == 422
    assert seen == [], "Navidrome asked nothing"


def test_the_bounds_themselves_are_allowed(upstream, client):
    state, _ = upstream
    _, state["handler"] = navidrome_file(SONG)
    assert client.get(SCRUB, params={"at": "0", "seconds": "1"}).status_code == 200
    assert client.get(SCRUB, params={"at": "0", "seconds": "60"}).status_code == 200
    #? a day in is in bounds, and past this song's end
    assert client.get(SCRUB, params={"at": "86400"}).status_code == 416


def test_navidrome_not_set_up_is_a_503(monkeypatch, client):
    monkeypatch.setattr(navidrome_tests.Config, "NAVIDROME_URL", None)

    response = client.get(SCRUB, params={"at": 1.0})

    assert response.status_code == 503 and "settings tab" in response.json()["detail"]


def test_the_window_is_on_the_players_fixed_list_on_purpose():
    """The one route added in 2.0.0-player.14: it reads deadwax's own cache, and asks Navidrome
    only the version check every MP4 answer makes - nothing passed on."""
    assert "/scrub/{song_id}" in {route.path for route in navidrome_routes.router.routes}
    assert navidrome_routes.SCRUB_PARAMETERS == frozenset({"at", "seconds", "max_rate"})


def test_the_window_header_is_exact_against_a_hi_res_song(upstream, client, mp4_cache, monkeypatch):
    """A window shorter than asked - the budget, WINDOW_MAX_BYTES - still says exactly where it sits."""
    data, frames = encode(rate=96000, bps=24, blocks=(4096,) * 30, seed=3)
    state, _ = upstream
    _, state["handler"] = navidrome_file(data)
    monkeypatch.setattr(player_cache, "WINDOW_MAX_BYTES", 4 * len(frames[1][1]))

    response = client.get(SCRUB, params={"at": 0.1, "seconds": 30})

    first, samples, rate = window_of(response)
    assert (rate, first, samples) == (96000, 2 * 4096, 4 * 4096), "from the frame 0.1 s falls in, four frames: the budget"
    assert sum(find_frames(response.content).block_sizes) == samples
    assert struct.unpack(">H", response.content[8:10])[0] == 4096


# ---------------------------------------------------------------- the cap, and the refusals

def test_a_song_too_big_to_hold_is_a_415_and_never_fetched(upstream, client, tmp_path, monkeypatch):
    """The window's own guard on WRAP_MAX_BYTES: _mp4() doesn't hold the cap itself - each caller does
    - so without it a turntable showing an hour-long rip would have deadwax hold the whole file to make
    a plain MP4, the very thing Safari's own path refuses to do."""
    state, _ = upstream
    fake, state["handler"] = navidrome_file(SONG)
    monkeypatch.setattr(player_cache, "cache", player_cache.Mp4Cache(tmp_path / "small", wrap_max_bytes=len(SONG) - 1))

    first = client.get(SCRUB, params={"at": 1.0})
    second = client.get(SCRUB, params={"at": 2.0})

    for response in (first, second):
        assert response.status_code == 415
        assert "held in memory" in response.json()["detail"]
        assert response.headers["cache-control"] == "no-store"
    assert fake["whole"] == 0, "never fetched: it is judged by its size before anything is"


def test_a_song_whose_mp4_was_refused_is_a_415_saying_why(upstream, client, mp4_cache):
    """A stream the muxer won't vouch for is refused once, and its window is a 415 with the reason -
    the turntable is silent for it - not a 503 inviting the page to ask again and again."""
    state, _ = upstream
    fake, state["handler"] = navidrome_file(SONG[:-700])

    first = client.get(SCRUB, params={"at": 1.0})
    second = client.get(SCRUB, params={"at": 1.0})

    for response in (first, second):
        assert response.status_code == 415
        assert "checksum" in response.json()["detail"]
    assert fake["whole"] == 1, "fetched once, to try: the refusal is remembered"


# ---------------------------------------------------------------- a hi-res song played resampled

HIRES, _ = encode(rate=192000, bps=24, blocks=(4096,) * 60, seed=5)
AS_48K, _ = encode(rate=48000, bps=24, blocks=(4096,) * 15, seed=6)
PLAN = resample.ResamplePlan(max_rate=48000, source_rate=192000, out_rate=48000, channels=2, bits=24,
                             total_samples=60 * 4096)
#? the version exactly as the cache builds it from the fake's answer
HIRES_VERSION = player_cache.Version(song_id="song-1", size=len(HIRES), stamp=json.dumps([STAMP, None]))


@pytest.fixture
def resampling(monkeypatch, mp4_cache):
    """Resampling as if the audio libraries were there, and the song's plan as the album would make
    it - the copy itself is put in the cache by the test, exactly where a make would put it."""
    monkeypatch.setattr(player_cache.resample, "missing_libraries", lambda: None)

    async def plan(version, max_rate):
        return PLAN if max_rate == 48000 else None

    monkeypatch.setattr(mp4_cache.albums, "plan", plan)
    folder = mp4_cache.directory
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    folder.chmod(0o700)
    return folder


def files_in(folder: Path) -> list[str]:
    return sorted(path.name for path in folder.iterdir())


@pytest.mark.parametrize("wrap", [player_cache.MP4_WRAP, player_cache.FMP4_WRAP], ids=["safari's mp4", "the gapless player's"])
def test_a_resampled_songs_window_is_cut_from_the_copy_the_phone_plays(upstream, client, mp4_cache, resampling, wrap):
    """Under "Up to 48 kHz" the phone plays a 192 kHz song resampled, from a copy kept under its plan's
    key: the window is cut from that - 48 kHz, as loud as the song - with nothing downloaded again and
    no full-rate copy made beside it (review: the first cut made one for every hi-res window)."""
    state, _ = upstream
    fake, state["handler"] = navidrome_file(HIRES)
    copy = resampling / f"{HIRES_VERSION.key_for(wrap, PLAN)[:40]}{wrap.suffix}"
    copy.write_bytes(flac_to_mp4(AS_48K) if wrap is player_cache.MP4_WRAP else flac_to_fmp4(AS_48K))
    before = files_in(resampling)

    response = client.get(SCRUB, params={"at": 0.5, "seconds": 40, "max_rate": "48000"})

    assert response.status_code == 200
    first, samples, rate = window_of(response)
    assert rate == 48000, "the rate the phone plays, not the original's"
    assert first <= int(0.5 * 48000) < first + samples
    assert fake["whole"] == 0, "nothing downloaded again"
    assert files_in(resampling) == before, "no second copy beside the phone's"


def test_without_the_cap_the_song_as_it_is_is_cut_from(upstream, client, mp4_cache, resampling):
    """A page playing the song as it is ("Original") asks without max_rate, and gets the original."""
    state, _ = upstream
    fake, state["handler"] = navidrome_file(HIRES)
    (resampling / f"{HIRES_VERSION.key_for(player_cache.FMP4_WRAP, PLAN)[:40]}.f.mp4").write_bytes(flac_to_fmp4(AS_48K))

    response = client.get(SCRUB, params={"at": 0.5, "seconds": 1})

    assert window_of(response)[2] == 192000
    assert fake["whole"] == 1, "the plain MP4 made, as Safari's would be"


def test_the_resampled_copy_made_without_a_neighbour_is_cut_from(upstream, client, mp4_cache, resampling):
    """A make that lost a side of its plan keeps its file under the plan it really had (_lost_side):
    the window finds it there too."""
    state, _ = upstream
    fake, state["handler"] = navidrome_file(HIRES)
    had = resample.ResamplePlan(max_rate=48000, source_rate=192000, out_rate=48000, channels=2, bits=24,
                                total_samples=60 * 4096, phase=1)
    mp4_cache._lose(HIRES_VERSION.key_for(player_cache.FMP4_WRAP, PLAN), had)
    (resampling / f"{HIRES_VERSION.key_for(player_cache.FMP4_WRAP, had)[:40]}.f.mp4").write_bytes(flac_to_fmp4(AS_48K))

    response = client.get(SCRUB, params={"at": 0.5, "max_rate": "48000"})

    assert (response.status_code, window_of(response)[2], fake["whole"]) == (200, 48000, 0)


def test_with_no_resampled_copy_one_is_made_resampled_as_safaris_would_be(upstream, client, mp4_cache, resampling,
                                                                          monkeypatch):
    """None in the cache (the phone played it some other way): the plain MP4 made resampled, as
    Safari's would be - never a full-rate one."""
    state, _ = upstream
    fake, state["handler"] = navidrome_file(HIRES)
    asked = []

    async def made(version, folder, wrap=player_cache.MP4_WRAP, plan=None):
        asked.append((wrap.name, plan))
        path = folder / f"{version.key_for(wrap, plan)[:40]}{wrap.suffix}"
        path.write_bytes(flac_to_mp4(AS_48K if plan is not None else HIRES))
        return path

    monkeypatch.setattr(mp4_cache, "_mp4", made)

    response = client.get(SCRUB, params={"at": 0.5, "max_rate": "48000"})

    assert (response.status_code, window_of(response)[2]) == (200, 48000)
    assert asked == [(player_cache.MP4_WRAP.name, PLAN)]


def test_a_resampled_copy_refused_leaves_the_window_to_the_song_as_it_is(upstream, client, mp4_cache, resampling):
    """Refused resampled - the page then plays the song as it is (usePlayer's `refused`) - so is the
    window: from the plain MP4 the phone was given."""
    state, _ = upstream
    fake, state["handler"] = navidrome_file(HIRES)
    mp4_cache._refuse(HIRES_VERSION, "the resampler won't take it", warn=False, plan=PLAN)
    (resampling / f"{HIRES_VERSION.key_for(player_cache.MP4_WRAP)[:40]}.mp4").write_bytes(flac_to_mp4(HIRES))

    response = client.get(SCRUB, params={"at": 0.5, "seconds": 1, "max_rate": "48000"})

    assert (response.status_code, window_of(response)[2], fake["whole"]) == (200, 192000, 0)


def test_a_resampled_copy_refused_as_it_is_made_leaves_the_window_to_the_song_as_it_is(upstream, client, mp4_cache,
                                                                                    resampling, monkeypatch):
    """Refused only as the make tries it (the resampler won't take the stream): the song as it is,
    made as Safari's would be - not a 503 for a window that can never be resampled."""
    state, _ = upstream
    fake, state["handler"] = navidrome_file(HIRES)
    asked = []

    async def made(version, folder, wrap=player_cache.MP4_WRAP, plan=None):
        asked.append(plan)
        if plan is not None:
            mp4_cache._refuse(version, "the resampler won't take it", warn=False, plan=plan)
            return None
        path = folder / f"{version.key_for(wrap)[:40]}{wrap.suffix}"
        path.write_bytes(flac_to_mp4(HIRES))
        return path

    monkeypatch.setattr(mp4_cache, "_mp4", made)

    response = client.get(SCRUB, params={"at": 0.5, "seconds": 1, "max_rate": "48000"})

    assert (response.status_code, window_of(response)[2], asked) == (200, 192000, [PLAN, None])


def test_without_the_audio_libraries_the_cap_is_ignored(upstream, client, mp4_cache, monkeypatch):
    """A deadwax that can't resample sends every song as it is - and its windows are of that."""
    monkeypatch.setattr(player_cache.resample, "missing_libraries", lambda: "numpy, soxr")
    state, _ = upstream
    _, state["handler"] = navidrome_file(HIRES)

    response = client.get(SCRUB, params={"at": 0.5, "seconds": 1, "max_rate": "48000"})

    assert (response.status_code, window_of(response)[2]) == (200, 192000)
