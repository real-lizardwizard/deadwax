"""
A download's FLACs checked whole before filing (src/flac_check.py) - damaged downloads, asked for 27 Nov.

Every file here is synthetic, made by tests/test_flac_mp4.py's encoder (real FLAC frames, each with its CRC-8 and
CRC-16) and damaged the ways the report found and the ways a transfer can: the sharer's copy loop writing its
whole 6,144-byte buffer on the last read, a stream cut short, a frame broken in the middle. Tags are added at
either end as real files carry them.
"""

import os
import random

import pytest

from src import flac_check
from src.flac_check import CUT_SHORT, DAMAGED_INSIDE, OK, STALE_TAIL, UNCHECKED, check, check_file, damage_reason
from src.flac_mp4 import _crc16
from tests.test_flac_mp4 import encode, id3v2

ID3V1 = b"TAG" + bytes(125)
#? an APEv2 footer alone: "APETAGEX", version 2000, tag size 32 (the footer, no items), no items, no header
APEV2 = b"APETAGEX" + (2000).to_bytes(4, "little") + (32).to_bytes(4, "little") + bytes(16)


def clean(**options):
    data, _ = encode(**options)
    return data


def copy_loop(data: bytes, extra: int) -> bytes:
    """What the report's sharer sent: after the true end, `extra` bytes that repeat the stretch 6,144 bytes back."""
    end = len(data)
    return data + data[end - 6144:end - 6144 + extra]


# --- whole files ---------------------------------------------------------------------------------------------

@pytest.mark.parametrize("options", [
    {},
    {"variable": True},
    {"channels": 1, "bps": 24, "rate": 96000},
    {"rate": 48000, "blocks": (1152,) * 9 + (300,)},
    {"constant": True},
])
def test_a_whole_file_reads_ok(options):
    assert check(clean(**options)).kind == OK


@pytest.mark.parametrize("front, back", [
    (b"", ID3V1),
    (b"", APEV2),
    (b"", APEV2 + ID3V1),
    (id3v2(400), b""),
    (id3v2(58_000), ID3V1),
])
def test_a_file_tagged_at_either_end_reads_ok(front, back):
    data, _ = encode(id3=front, trailer=back)
    verdict = check(data)
    assert verdict.kind == OK and not verdict.damaged


def id3v2_behind(size: int = 300) -> bytes:
    """An ID3v2.4 tag written at the END of a file, as the spec allows: its footer flag set, "3DI" closing it."""
    sizes = bytes([(size >> 21) & 0x7F, (size >> 14) & 0x7F, (size >> 7) & 0x7F, size & 0x7F])
    return b"ID3\x04\x00\x10" + sizes + bytes(size) + b"3DI\x04\x00\x10" + sizes


@pytest.mark.parametrize("back", [
    ID3V1 + ID3V1,
    id3v2_behind(),
    id3v2_behind() + ID3V1,
    APEV2 + id3v2_behind() + ID3V1,
    b"TAG+" + bytes(223) + ID3V1,
], ids=["id3v1 twice", "id3v2 behind", "id3v2 behind then id3v1", "apev2, id3v2, id3v1", "id3v1 with TAG+"])
def test_every_known_tag_behind_the_audio_is_stripped_however_many(back):
    """(review) The tags behind are taken off the end one at a time, again and again: an ID3v1 written twice, an
    ID3v2 written at the end with its "3DI" footer, and any of them behind another, are all tags."""
    data, _ = encode(trailer=back)
    verdict = check(data)
    assert verdict.kind == OK, verdict


def test_extra_data_behind_a_stripped_tag_is_still_found():
    """The stripping is only of tags: junk after the audio, with a tag after the junk, is still extra data."""
    data, _ = encode(trailer=bytes(range(256)) * 4 + ID3V1 + ID3V1)
    assert check(data).kind == STALE_TAIL


def test_a_first_frame_numbered_other_than_0_is_damaged_inside():
    """A stream copied from the middle of another (ffmpeg -c copy of a cut, its first frame numbered 14 - the
    review's real encode) has lost its start: it is refused, and the docstring says so."""
    data, frames = encode(blocks=(4096,) * 4 + (1000,))
    start = frames[0][0]
    data = data[:start] + data[frames[1][0]:]
    assert check(data).kind == DAMAGED_INSIDE
    assert "isn't frame 0" in flac_check.__doc__


def test_a_frame_planted_with_thousands_of_the_next_header_costs_a_bounded_walk():
    """(review) 8,000 copies of frame 1's header inside frame 0 each carry the next number, so each was summed from
    the frame's start: quadratic, over a second for a 131 KB frame. The walk's summing is capped (SUM_BUDGET) - the
    file is UNCHECKED, filed as before - and a whole file's walk sums each frame about once."""
    blocks = (32768, 4096, 4096, 100)
    data, _ = encode(blocks=blocks, plant={0: (0, lambda heads: heads[1] * 8000)})
    spent = []
    real_spend = flac_check._Spend

    class Counting(real_spend):
        def __call__(self, count):
            spent.append(count)
            super().__call__(count)

    flac_check._Spend = Counting
    try:
        verdict = check(data)
    finally:
        flac_check._Spend = real_spend
    assert verdict.kind == UNCHECKED and "summing" in verdict.why
    assert sum(spent) <= flac_check.SUM_BUDGET[0] + flac_check.SUM_BUDGET[1] * len(data) + len(data)

    whole, _ = encode(blocks=blocks)
    spent.clear()
    flac_check._Spend = Counting
    try:
        assert check(whole).kind == OK
    finally:
        flac_check._Spend = real_spend
    assert sum(spent) <= len(whole)


def test_one_or_two_zero_bytes_after_the_audio_are_not_called_damage():
    """They can't be told from the last frame's own CRC-16 ending in zeros, as flac_mp4 reads it too."""
    data = clean()
    assert check(data + bytes(1)).kind == OK
    assert check(data + bytes(2)).kind == OK


# --- a stale tail ------------------------------------------------------------------------------------------

@pytest.mark.parametrize("extra", [807, 3000, 6140])
def test_the_copy_loops_tail_is_extra_data_found_to_the_byte(extra):
    verdict = check(copy_loop(clean(), extra))
    assert verdict.kind == STALE_TAIL and verdict.damaged
    assert verdict.extra == extra


def test_the_copy_loops_tail_behind_an_id3v2_tag_is_found_too():
    data, _ = encode(id3=id3v2(58_000))
    assert check(copy_loop(data, 2000)).kind == STALE_TAIL


def test_junk_after_the_end_is_extra_data():
    rng = random.Random(4)
    data = clean()
    assert check(data + bytes(rng.randrange(256) for _ in range(2000))).kind == STALE_TAIL


def test_three_zero_bytes_after_the_end_are_extra_data():
    verdict = check(clean() + bytes(3))
    assert verdict.kind == STALE_TAIL and verdict.extra >= 1


def test_junk_after_an_id3v1_tag_is_not_taken_for_the_tag():
    """The tag has to be the file's last 128 bytes to count as one."""
    assert check(clean() + ID3V1 + b"after the tag").kind == STALE_TAIL


# --- cut short ----------------------------------------------------------------------------------------------

@pytest.mark.parametrize("cut", [1, 1000, 30_000])
def test_a_file_cut_short_reads_cut_short(cut):
    data = clean()
    assert check(data[:-cut]).kind == CUT_SHORT


@pytest.mark.parametrize("seed", range(12))
def test_a_hi_res_file_cut_inside_its_last_frame_reads_cut_short(seed):
    """Big frames hold chance CRC zeros (one byte in 65,536) - a cut one must not read as a whole one with a tail."""
    data, frames = encode(rate=96000, bps=24, blocks=(4096,) * 4, seed=seed)
    last = frames[-1][0]
    cut = random.Random(seed).randrange(last + 200, len(data) - 1)
    assert check(data[:cut]).kind == CUT_SHORT


def test_a_file_ending_inside_its_metadata_is_cut_short():
    data = clean()
    assert check(data[:60]).kind == CUT_SHORT


def test_a_file_with_no_audio_where_streaminfo_counts_some_is_cut_short():
    data, frames = encode()
    assert check(data[:frames[0][0]]).kind == CUT_SHORT


# --- damaged inside -----------------------------------------------------------------------------------------

def test_a_frame_broken_in_the_middle_is_damaged_inside():
    data, frames = encode(blocks=(4096,) * 6 + (1000,))
    broken = bytearray(data)
    broken[frames[2][0] + 500] ^= 0x10
    verdict = check(bytes(broken))
    assert verdict.kind == DAMAGED_INSIDE and verdict.damaged


def test_a_frame_header_broken_in_the_middle_is_damaged_inside():
    data, frames = encode(blocks=(4096,) * 6 + (1000,))
    broken = bytearray(data)
    broken[frames[3][0] + 1] ^= 0x01
    assert check(bytes(broken)).kind == DAMAGED_INSIDE


def test_a_last_frame_broken_inside_is_damage_not_a_whole_file():
    data, frames = encode()
    broken = bytearray(data)
    broken[frames[-1][0] + 100] ^= 0x40
    assert check(bytes(broken)).damaged


# --- what it can't judge passes as before ---------------------------------------------------------------------

@pytest.mark.parametrize("data", [b"one", b"", b"RIFF" + bytes(100), b"\xff\xfb\x90\x00" + bytes(400)])
def test_what_is_not_a_flac_is_unchecked(data):
    assert check(data).kind == UNCHECKED


def test_a_streaminfo_with_no_length_and_no_audio_is_unchecked():
    data, frames = encode(total=0)
    assert check(data[:frames[0][0]]).kind == UNCHECKED


def test_check_file_reads_the_file_and_one_it_cant_read_is_unchecked(tmp_path):
    path = tmp_path / "01.flac"
    path.write_bytes(copy_loop(clean(), 1000))
    assert check_file(path).kind == STALE_TAIL
    assert check_file(tmp_path / "gone.flac").kind == UNCHECKED


def test_checking_changes_no_byte(tmp_path):
    path = tmp_path / "01.flac"
    data = copy_loop(clean(), 1000)
    path.write_bytes(data)
    before = os.stat(path).st_mtime_ns
    check_file(path)
    assert path.read_bytes() == data and os.stat(path).st_mtime_ns == before


# --- the fast CRC ---------------------------------------------------------------------------------------------

def test_the_folded_crc_is_flac_mp4s_crc():
    rng = random.Random(7)
    for length in [0, 1, 2, 95, 96, 97, 200, 1023, 4096, 20_000, 70_001]:
        data = bytes(rng.randrange(256) for _ in range(length))
        assert flac_check._sums_to_zero(data, 0, length) == (_crc16(data) == 0)
        #? and a stretch that does come to zero: the bytes with their own CRC-16 after them
        whole = data + _crc16(data).to_bytes(2, "big")
        assert flac_check._sums_to_zero(whole, 0, len(whole))


def test_the_folded_crc_over_a_stretch_inside_the_data():
    data, frames = encode()
    for (start, frame, _), following in zip(frames, frames[1:]):
        assert flac_check._sums_to_zero(data, start, following[0])
        assert not flac_check._sums_to_zero(data, start, following[0] - 1)


# --- the words ------------------------------------------------------------------------------------------------

def test_the_reason_in_a_listeners_words():
    assert damage_reason([STALE_TAIL] * 3, 11) == "extra data after the end of 3 of 11 songs"
    assert damage_reason([CUT_SHORT], 11) == "1 of 11 songs is cut short"
    assert damage_reason([DAMAGED_INSIDE, DAMAGED_INSIDE], 11) == "2 of 11 songs are damaged inside"
    assert damage_reason([CUT_SHORT, STALE_TAIL], 1) == \
        "extra data after the end of 1 of 2 songs; 1 of 2 songs is cut short"
    assert damage_reason([STALE_TAIL], 1) == "extra data after the end of 1 of 1 song"
