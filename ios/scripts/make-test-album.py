#!/usr/bin/env python3
"""
Makes the test album Phase 0's checks play (docs/ios.md): "Start test" (2026) by "deadwax test",
ten 44.1 kHz 16-bit stereo FLACs: beeps at known times, and a tone across a join. Standard library only, so any python3
runs it - the Mac's own (`xcrun python3`), or the server's.

    python3 ios/scripts/make-test-album.py <your music folder>

writes "<your music folder>/deadwax test/Start test (2026)/01 - ....flac" ... "10 - ....flac" (about 6 MB),
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


def main(argv: list[str]) -> int:
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
