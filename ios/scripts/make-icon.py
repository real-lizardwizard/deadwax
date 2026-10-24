#!/usr/bin/env python3
"""
Draws the app's icon - a record seen from above: the grooves, the smooth "dead wax" ring between the
last groove and the label, and the label in deadwax's purple - as the loose PNGs Info.plist names
(CFBundleIconFiles: AppIcon60x60, at @2x and @3x). Loose PNGs, not an asset catalog: actool needs a
Simulator runtime, which James's Mac doesn't have (the plan's risk R2).

Opaque RGB (iOS refuses an icon with transparency), drawn at 4x and averaged down for smooth edges.
Needs numpy (the repo's .venv has it):

    .venv/bin/python ios/scripts/make-icon.py
"""

import struct
import sys
import zlib
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "App" / "Icon"

# interface/styles/theme.css: --dw-bg-now-playing, --dw-bg-sheet and --accent-hover (the app's accent)
BACKGROUND = (0x12, 0x10, 0x16)
VINYL = (0x0B, 0x0A, 0x10)
GROOVE = (0x2A, 0x28, 0x33)
DEAD_WAX = (0x1C, 0x1B, 0x22)
LABEL = (0xC0, 0x84, 0xFC)
SHEEN = (0x4A, 0x45, 0x58)

SIZES = {"AppIcon60x60@2x.png": 120, "AppIcon60x60@3x.png": 180}
SUPER = 4


def draw(size: int) -> np.ndarray:
    n = size * SUPER
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    c = (n - 1) / 2
    r = np.hypot(x - c, y - c) / (n / 2)          # 0 at the centre, 1 at the edge's midpoint
    angle = np.arctan2(y - c, x - c)

    image = np.empty((n, n, 3))
    image[:] = BACKGROUND

    disc = r <= 0.86
    image[disc] = VINYL
    grooves = disc & (r > 0.50) & (np.sin(r * 260) > 0.55)
    image[grooves] = GROOVE
    # a soft sheen across the grooves, as light catches a record
    weight = (np.maximum(np.cos(2 * (angle - 0.8)), 0) ** 6 * 0.45)[..., None]
    sheen = (disc & (r > 0.50))[..., None]
    image = np.where(sheen, image * (1 - weight) + np.array(SHEEN) * weight, image)
    image[disc & (r > 0.40) & (r <= 0.50)] = DEAD_WAX
    image[r <= 0.40] = LABEL
    image[r <= 0.045] = BACKGROUND

    small = image.reshape(size, SUPER, size, SUPER, 3).mean(axis=(1, 3))
    return np.clip(small.round(), 0, 255).astype(np.uint8)


def png(pixels: np.ndarray) -> bytes:
    height, width, _ = pixels.shape
    raw = b"".join(b"\x00" + pixels[row].tobytes() for row in range(height))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)   # 8-bit RGB, no alpha
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, size in SIZES.items():
        (OUT / name).write_bytes(png(draw(size)))
        print(f"wrote {OUT / name} ({size}x{size})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
