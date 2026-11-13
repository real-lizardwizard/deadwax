#!/usr/bin/env python3
"""
Makes the test album Phase 0's checks play (docs/ios.md): "Start test" (2026) by "deadwax test",
ten 44.1 kHz 16-bit stereo FLACs: beeps at known times, and a tone across a join. Standard library only, so any python3
runs it - the Mac's own (`xcrun python3`), or the server's.

    python3 ios/scripts/make-test-album.py <your music folder>

    python3 ios/scripts/make-test-album.py --verifier-fixtures <folder>

The second writes the four small FLACs DeadwaxAudio's download verifier is tested on (notes/ios-specs/phase2-downloads.md
8.4, 9) - see `verifier_fixtures` - into ios/DeadwaxKit/Tests/DeadwaxAudioTests/Fixtures/verifier.

    python3 ios/scripts/make-test-album.py --deck-fixtures ios/DeadwaxKit/Tests/DeadwaxAudioTests/Fixtures/deck

The third writes the turntable's window fixtures (notes/ios-specs/turntable.md 7.2) - see `deck_fixtures`; then
ios/scripts/export-scrub-window.py cuts the server's own /scrub answer from one of them.

The first writes "<your music folder>/deadwax test/Start test (2026)/01 - ....flac" ... "10 - ....flac" (about 6 MB),
replacing the album's own files if they are there and touching nothing else. Then let
Navidrome scan. Write it into a folder of its own and copy that folder in, if you'd rather.

  1-6  three 60 ms 1 kHz beeps one second apart, after exact digital silence, the first at 0.0, 0.1,
       0.2, 0.3, 0.5 and 1.0 s: the earliest song whose first beep sounds as loud as the other two
       says how much of a start is lost (check 4).
  7    a 600 Hz beep at 1 s, 20 s of exact zeros, then the three beeps at 21 s.
  8    the same with the 20 s filled with noise about 80 dB under full scale (inaudible).
  9-10 one steady 440 Hz tone cut in two (check 5): 9 fades in and ends near the tone's peak, 10
       goes on from the very next sample and fades out. Played one into the other, any gap, or a
       sample dropped or doubled, is a plain click about 5 s in; the beeps can't show that, since
       they meet in silence. (Tapping 10 on its own starts it mid-tone, with a click of its own.)
All ten are the same format, so each runs into the next with nothing between.

The same signals as the album made for the web player's start-of-song work (peak -12 dBFS), written
here by a small FLAC encoder of its own (CONSTANT subframes for silence, VERBATIM for the rest, MD5
in STREAMINFO), checked by tests/test_ios_install.py with libsndfile and mutagen.
"""

from __future__ import annotations

import hashlib
import math
import random
import struct
import sys
from pathlib import Path

RATE = 44100
BLOCK = 4096
ARTIST = "deadwax test"
ALBUM = "Start test"
YEAR = "2026"
FOLDER = Path(ARTIST) / f"{ALBUM} ({YEAR})"


# ----------------------------------------------------------------------------- the signals

def beep(freq: float = 1000.0, ms: float = 60, level_db: float = -12.0, edge_ms: float = 2.0) -> list[float]:
    n = int(RATE * ms / 1000)
    edge = int(RATE * edge_ms / 1000)
    gain = 10 ** (level_db / 20)
    out = []
    for i in range(n):
        y = math.sin(2 * math.pi * freq * i / RATE) * gain
        if i < edge:
            y *= 0.5 - 0.5 * math.cos(math.pi * i / edge)
        elif i >= n - edge:
            y *= 0.5 - 0.5 * math.cos(math.pi * (n - 1 - i) / edge)
        out.append(y)
    return out


def track(seconds: float, beeps: list[tuple[float, float]], noise_db: float | None = None,
          noise_from: float = 0.0, noise_to: float = 0.0, seed: int = 1) -> list[int]:
    y = [0.0] * int(RATE * seconds)
    if noise_db is not None:
        rng = random.Random(seed)
        scale = 10 ** (noise_db / 20) * math.sqrt(6)      # TPDF noise at about noise_db dBFS RMS
        for i in range(int(RATE * noise_from), int(RATE * noise_to)):
            y[i] = (rng.random() - rng.random()) * scale
    for at, freq in beeps:
        start = int(round(RATE * at))
        for k, value in enumerate(beep(freq)):
            y[start + k] += value
    return [max(-32768, min(32767, int(round(v * 32767)))) for v in y]


JOIN_HZ = 440.0
# 5 s, plus a quarter of the tone's period: the join falls near a peak, not a zero crossing
JOIN_AT = int(RATE * 5.0) + 25


def tone_across(level_db: float = -12.0, fade_s: float = 0.5) -> tuple[list[int], list[int]]:
    """One continuous tone, cut at JOIN_AT: (the first part, the second part)."""
    total = JOIN_AT + int(RATE * 5.0)
    gain = 10 ** (level_db / 20)
    fade = int(RATE * fade_s)
    out = []
    for i in range(total):
        y = math.sin(2 * math.pi * JOIN_HZ * i / RATE) * gain
        if i < fade:
            y *= 0.5 - 0.5 * math.cos(math.pi * i / fade)
        elif i >= total - fade:
            y *= 0.5 - 0.5 * math.cos(math.pi * (total - 1 - i) / fade)
        out.append(max(-32768, min(32767, int(round(y * 32767)))))
    return out[:JOIN_AT], out[JOIN_AT:]


def tracks() -> list[tuple[str, list[int]]]:
    made = []
    for start in (0.0, 0.1, 0.2, 0.3, 0.5, 1.0):
        made.append((f"Three beeps, the first at {start:.1f} s",
                     track(start + 4.0, [(start + k, 1000.0) for k in range(3)])))
    tail = [(1.0, 600.0)] + [(21.0 + k, 1000.0) for k in range(3)]
    made.append(("Three beeps after 20 s of digital silence", track(26.0, tail)))
    made.append(("Three beeps after 20 s of near-silence",
                 track(26.0, tail, noise_db=-80.0, noise_from=1.1, noise_to=21.0)))
    first, second = tone_across()
    made.append(("A tone across the join, part 1", first))
    made.append(("A tone across the join, part 2", second))
    return made


# ----------------------------------------------------------------------------- FLAC

def _table(poly: int, width: int) -> list[int]:
    top, mask = 1 << (width - 1), (1 << width) - 1
    table = []
    for byte in range(256):
        crc = byte << (width - 8)
        for _ in range(8):
            crc = ((crc << 1) ^ poly) & mask if crc & top else (crc << 1) & mask
        table.append(crc)
    return table


CRC8 = _table(0x07, 8)
CRC16 = _table(0x8005, 16)


def crc8(data: bytes) -> int:
    crc = 0
    for byte in data:
        crc = CRC8[crc ^ byte]
    return crc


def crc16(data: bytes) -> int:
    crc = 0
    for byte in data:
        crc = ((crc << 8) & 0xFFFF) ^ CRC16[(crc >> 8) ^ byte]
    return crc


def coded_number(n: int) -> bytes:
    """FLAC's frame number, in UTF-8's extended form."""
    if n < 0x80:
        return bytes([n])
    for length, top in ((2, 0xC0), (3, 0xE0), (4, 0xF0), (5, 0xF8), (6, 0xFC), (7, 0xFE)):
        if n < 1 << (6 * (length - 1) + (7 - length)):
            tail = [0x80 | ((n >> (6 * i)) & 0x3F) for i in range(length - 1)][::-1]
            return bytes([top | (n >> (6 * (length - 1)))] + tail)
    raise ValueError(n)


def frame(number: int, left: list[int], right: list[int]) -> bytes:
    # fixed block size; size from the header's end (0111); 44.1 kHz (1001); left/right (0001); 16-bit (100)
    header = bytes([0xFF, 0xF8, 0x79, 0x18]) + coded_number(number) + struct.pack(">H", len(left) - 1)
    header += bytes([crc8(header)])
    body = b""
    for channel in (left, right):
        if all(sample == channel[0] for sample in channel):
            body += b"\x00" + struct.pack(">h", channel[0])                          # CONSTANT
        else:
            body += b"\x02" + struct.pack(f">{len(channel)}h", *channel)            # VERBATIM
    data = header + body
    return data + struct.pack(">H", crc16(data))


def flac(samples: list[int], tags: dict[str, str]) -> bytes:
    md5 = hashlib.md5()
    for start in range(0, len(samples), 65536):
        piece = samples[start:start + 65536]
        md5.update(struct.pack(f"<{2 * len(piece)}h", *[s for v in piece for s in (v, v)]))
    # STREAMINFO: block sizes, frame sizes unknown (0), then rate (20 bits), channels-1 (3), bits-1 (5),
    # total samples (36), and the MD5 of the decoded samples
    packed = (RATE << 44) | (1 << 41) | (15 << 36) | len(samples)
    info = struct.pack(">HH", BLOCK, BLOCK) + b"\x00" * 6 + packed.to_bytes(8, "big") + md5.digest()
    vendor = b"deadwax make-test-album"
    comments = [f"{key}={value}".encode("utf-8") for key, value in tags.items()]
    comment = struct.pack("<I", len(vendor)) + vendor + struct.pack("<I", len(comments))
    comment += b"".join(struct.pack("<I", len(c)) + c for c in comments)
    out = b"fLaC" + bytes([0x00]) + len(info).to_bytes(3, "big") + info
    out += bytes([0x80 | 0x04]) + len(comment).to_bytes(3, "big") + comment
    for number, start in enumerate(range(0, len(samples), BLOCK)):
        block = samples[start:start + BLOCK]
        out += frame(number, block, block)
    return out


# ----------------------------------------------------------------------------- the download verifier's fixtures

# FLAC's frame-header codes: the sample rate (4 bits) and the sample size (3 bits)
RATE_CODES = {22050: 0x6, 44100: 0x9, 48000: 0xA, 96000: 0xB, 192000: 0xD}
BITS_CODES = {16: 0b100, 24: 0b110}


def encode(channels: list[list[int]], rate: int, bits: int, block: int = 1024, md5_of: list[list[int]] | None = None,
           md5_known: bool = True) -> bytes:
    """A FLAC of any channels at `rate` and `bits` (16 or 24), fixed blocks of `block` frames, CONSTANT and VERBATIM
    subframes, every CRC right - and STREAMINFO's MD5 of `md5_of`'s samples (the file's own when None; all zeros when
    `md5_known` is false). An MD5 of other samples is a copy whose sound doesn't match, though every frame decodes."""
    frames = len(channels[0])
    width = (bits + 7) // 8
    hashed = md5_of if md5_of is not None else channels
    md5 = hashlib.md5()
    for at in range(frames):
        for channel in hashed:
            md5.update((channel[at] & ((1 << (8 * width)) - 1)).to_bytes(width, "little"))
    digest = md5.digest() if md5_known else bytes(16)
    packed = (rate << 44) | ((len(channels) - 1) << 41) | ((bits - 1) << 36) | frames
    info = struct.pack(">HH", block, block) + b"\x00" * 6 + packed.to_bytes(8, "big") + digest
    vendor = b"deadwax make-test-album"
    comment = struct.pack("<I", len(vendor)) + vendor + struct.pack("<I", 0)
    out = b"fLaC" + bytes([0x00]) + len(info).to_bytes(3, "big") + info
    out += bytes([0x80 | 0x04]) + len(comment).to_bytes(3, "big") + comment
    assignment = len(channels) - 1          # independent channels
    for number, start in enumerate(range(0, frames, block)):
        size = min(block, frames - start)
        header = bytes([0xFF, 0xF8, 0x70 | RATE_CODES[rate], (assignment << 4) | (BITS_CODES[bits] << 1)])
        header += coded_number(number) + struct.pack(">H", size - 1)
        header += bytes([crc8(header)])
        body = b""
        for channel in channels:
            piece = channel[start:start + size]
            mask = (1 << bits) - 1
            if all(sample == piece[0] for sample in piece):
                body += b"\x00" + (piece[0] & mask).to_bytes(width, "big")              # CONSTANT
            else:
                body += b"\x02" + b"".join((v & mask).to_bytes(width, "big") for v in piece)   # VERBATIM
        data = header + body
        out += data + struct.pack(">H", crc16(data))
    return out


def fixture_signal(frames: int, bits: int, seed: int) -> list[list[int]]:
    """Two channels unlike each other, every sample its own: a tone and noise, both signs, the extremes once each, and
    one block of digital silence (a CONSTANT subframe)."""
    top = (1 << (bits - 1)) - 1
    rng = random.Random(seed)
    left, right = [], []
    for n in range(frames):
        if 1024 <= n < 2048:
            left.append(0)
            right.append(0)
            continue
        tone = math.sin(2 * math.pi * 997 * n / 44100) * top * 0.6
        left.append(int(round(tone + rng.randint(-top // 8, top // 8))))
        right.append(int(round(-tone * 0.5 + rng.randint(-top // 4, top // 4))))
    left[5], right[5] = top, -top - 1
    return [left, right]


def verifier_fixtures() -> dict[str, bytes]:
    """The verifier's four FLACs: CD's 16/44.1 and 24/96 (each matched), the 24/96 with one sample changed and STREAMINFO
    still the original's (its frame CRCs right, so it decodes - and doesn't match), and the 16/44.1 with no MD5 (by
    size)."""
    cd = fixture_signal(3072, 16, 1)
    hires = fixture_signal(3072, 24, 2)
    changed = [list(hires[0]), list(hires[1])]
    changed[1][2500] += 1
    return {
        "verify-16-44k.flac": encode(cd, 44100, 16),
        "verify-24-96k.flac": encode(hires, 96000, 24),
        "verify-24-96k-changed.flac": encode(changed, 96000, 24, md5_of=hires),
        "verify-16-44k-no-md5.flac": encode(cd, 44100, 16, md5_known=False),
    }


# ----------------------------------------------------------------------------- the turntable's window fixtures

#? turntable.md 7.2: the window maker on the grid (4.4 (a)) at 22.05, 44.1, 48 and 96 kHz, the seam off it (4.4 (b)),
#? and the window made in pieces. VERBATIM is the encoder's only way to hold a varying sample, so each file is CONSTANT
#? (a few bytes a block) until just before the stretch a test reads, and short: the window's grid start is 2.0 s, its
#? pre-roll from 1.8 s, twice the pre-roll from 1.6 s - so the signal begins at 1.5 s
DECK_SIGNAL_FROM = 1.5
DECK_SECONDS = 2.3
#? the three tones of 4.4 (b): 1, 5 and 12 kHz, each at -12 dBFS, from 1.7 s (before the window's pre-roll at 1.8 s)
DECK_TONES = (1000.0, 5000.0, 12000.0)
DECK_TONES_FROM = 1.7
DECK_TONES_SECONDS = 2.6
#? the 40 s window of a 96 kHz song made in pieces: 40.5 s of CONSTANT blocks, a staircase (nothing all zeros)
DECK_LONG_SECONDS = 40.5


def deck_signal(rate: int, seconds: float, bits: int, seed: int) -> list[list[int]]:
    """Two channels unlike each other: exact zeros until DECK_SIGNAL_FROM, then a rising sweep under noise on the left
    and a falling one on the right, at about -6 dBFS - every sample its own."""
    top = (1 << (bits - 1)) - 1
    rng = random.Random(seed)
    frames = int(round(seconds * rate))
    begin = int(round(DECK_SIGNAL_FROM * rate))
    left, right = [0] * frames, [0] * frames
    for n in range(begin, frames):
        t = (n - begin) / rate
        up = math.sin(2 * math.pi * (300 * t + 2000 * t * t))
        down = math.sin(2 * math.pi * (6000 * t - 1500 * t * t))
        left[n] = int(round(top * (0.4 * up + 0.05 * (rng.random() * 2 - 1))))
        right[n] = int(round(top * (0.4 * down + 0.05 * (rng.random() * 2 - 1))))
    return [left, right]


def deck_tones(rate: int = 44100, bits: int = 16) -> list[list[int]]:
    """The three tones, both channels: zeros until DECK_TONES_FROM, then sum of sin(2 pi f n / rate) at -12 dBFS each,
    rounded - so every sample's true value is known to within half a step."""
    top = (1 << (bits - 1)) - 1
    level = 10 ** (-12 / 20)
    frames = int(round(DECK_TONES_SECONDS * rate))
    begin = int(round(DECK_TONES_FROM * rate))
    one = [0] * frames
    for n in range(begin, frames):
        one[n] = int(round(top * level * sum(math.sin(2 * math.pi * f * n / rate) for f in DECK_TONES)))
    return [one, list(one)]


def deck_long(rate: int = 96000, bits: int = 24, block: int = 1024) -> list[list[int]]:
    """40.5 s of blocks each one value (CONSTANT subframes): a staircase on the left, its negative on the right."""
    frames = int(round(DECK_LONG_SECONDS * rate))
    step = 1 << (bits - 6)
    left = [((n // block) % 31 - 15) * step for n in range(frames)]
    return [left, [-v for v in left]]


def deck_fixtures() -> dict[str, bytes]:
    """The deck engine's FLACs (DeadwaxAudioTests/Fixtures/deck): `deck-<rate>.flac` at 22.05, 44.1, 48 and 96 kHz,
    `deck-tones.flac` (44.1 kHz) and `deck-long-96k.flac`."""
    made = {name: encode(deck_signal(rate, DECK_SECONDS, 16, seed), rate, 16)
            for name, rate, seed in (("deck-22k.flac", 22050, 3), ("deck-44k.flac", 44100, 4),
                                     ("deck-48k.flac", 48000, 5), ("deck-96k.flac", 96000, 6))}
    made["deck-tones.flac"] = encode(deck_tones(), 44100, 16)
    made["deck-long-96k.flac"] = encode(deck_long(), 96000, 24)
    return made


def main(argv: list[str]) -> int:
    if len(argv) == 3 and argv[1] == "--deck-fixtures":
        folder = Path(argv[2])
        folder.mkdir(parents=True, exist_ok=True)
        for name, data in deck_fixtures().items():
            (folder / name).write_bytes(data)
            print(f"{name}  {len(data)} bytes")
        return 0
    if len(argv) == 3 and argv[1] == "--verifier-fixtures":
        folder = Path(argv[2])
        folder.mkdir(parents=True, exist_ok=True)
        for name, data in verifier_fixtures().items():
            (folder / name).write_bytes(data)
            print(f"{name}  {len(data)} bytes")
        return 0
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    music = Path(argv[1]).expanduser()
    if not music.is_dir():
        print(f"There's no folder {music}.", file=sys.stderr)
        return 1
    album = music / FOLDER
    album.mkdir(parents=True, exist_ok=True)
    made = tracks()
    for n, (title, samples) in enumerate(made, 1):
        tags = {"ARTIST": ARTIST, "ALBUMARTIST": ARTIST, "ALBUM": ALBUM, "TITLE": title,
                "TRACKNUMBER": str(n), "TRACKTOTAL": str(len(made)), "DATE": YEAR}
        path = album / f"{n:02d} - {title}.flac"
        path.write_bytes(flac(samples, tags))
        print(f"{path.name}  {len(samples) / RATE:.1f} s")
    print(f"Made {album}. Let Navidrome scan it, then press Check in the app.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
