#!/usr/bin/env python3
"""
Draws the app's icon - a record seen from above: the grooves, the smooth "dead wax" ring between the
last groove and the label, and the label in deadwax's purple - as the loose PNGs Info.plist names
(CFBundleIconFiles: AppIcon60x60, at @2x and @3x). Loose PNGs, not an asset catalog: actool needs a
Simulator runtime, which James's Mac doesn't have (the plan's risk R2).

Opaque RGB (iOS refuses an icon with transparency), drawn at 4x and averaged down for smooth edges.

And the Mac's (the Mac app, slice 1 - notes/ios.md): the same record on macOS's rounded square, at 16 to 1024 pixels,
written as AppIcon.icns, which Info-Mac.plist names (CFBundleIconFile). macOS's grid: on a 1024-pixel canvas the square
is 824 across, 100 in from each edge, its corners' radius 185, and outside it the icon is transparent - so these are
RGBA, drawn at 4x (2x for 1024) with the square's edge averaged too. The icns is PNGs in Apple's container, written
here with the standard library: no iconutil or actool. The phone's PNGs come out byte for byte as before.

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

# The Mac's: macOS's icon grid, in 1024ths of the canvas
MAC_ICNS = "AppIcon.icns"
MAC_SQUARE = 824
MAC_RADIUS = 185
# each image in the icns, by its type - what Apple's iconutil writes for an iconset of 16 to 512@2x, the 16 and 32 as
# PNGs too (icp4, icp5) rather than the old packed bitmaps
MAC_TYPES = (("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64), ("ic07", 128), ("ic13", 256), ("ic08", 256),
             ("ic14", 512), ("ic09", 512), ("ic10", 1024))


def record(x: np.ndarray, y: np.ndarray, c: float, half: float) -> np.ndarray:
    """The record's colours at the points (x, y): centred on (c, c), its design's 1.0 `half` from the centre."""
    r = np.hypot(x - c, y - c) / half          # 0 at the centre, 1 at the edge's midpoint
    angle = np.arctan2(y - c, x - c)

    image = np.empty(x.shape + (3,))
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
    return image


def draw(size: int) -> np.ndarray:
    """The phone's: the record filling the square, opaque."""
    n = size * SUPER
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    c = (n - 1) / 2
    image = record(x, y, c, n / 2)
    small = image.reshape(size, SUPER, size, SUPER, 3).mean(axis=(1, 3))
    return np.clip(small.round(), 0, 255).astype(np.uint8)


def draw_mac(size: int) -> np.ndarray:
    """The Mac's: the record on macOS's rounded square, transparent outside it (RGBA, straight alpha)."""
    scale = SUPER if size <= 512 else 2
    n = size * scale
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    c = (n - 1) / 2
    half = n * MAC_SQUARE / 1024 / 2
    radius = n * MAC_RADIUS / 1024
    dx = np.maximum(np.abs(x - c) - (half - radius), 0)
    dy = np.maximum(np.abs(y - c) - (half - radius), 0)
    inside = (np.hypot(dx, dy) <= radius) & (np.abs(x - c) <= half) & (np.abs(y - c) <= half)
    colour = record(x, y, c, half)
    blocks = inside.reshape(size, scale, size, scale)
    count = blocks.sum(axis=(1, 3))
    summed = (colour * inside[..., None]).reshape(size, scale, size, scale, 3).sum(axis=(1, 3))
    rgb = summed / np.maximum(count, 1)[..., None]
    alpha = count / (scale * scale) * 255
    rgba = np.concatenate([rgb, alpha[..., None]], axis=-1)
    return np.clip(rgba.round(), 0, 255).astype(np.uint8)


def png(pixels: np.ndarray) -> bytes:
    height, width, channels = pixels.shape
    raw = b"".join(b"\x00" + pixels[row].tobytes() for row in range(height))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    colour = {3: 2, 4: 6}[channels]                                  # 8-bit RGB (no alpha), or RGBA
    header = struct.pack(">IIBBBBB", width, height, 8, colour, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def icns(images: dict) -> bytes:
    """Apple's icon container: "icns" and its whole length, then each image as its type, its length (with these 8
    bytes) and its PNG."""
    body = b"".join(kind.encode("ascii") + struct.pack(">I", 8 + len(images[size])) + images[size]
                    for kind, size in MAC_TYPES)
    return b"icns" + struct.pack(">I", 8 + len(body)) + body


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, size in SIZES.items():
        (OUT / name).write_bytes(png(draw(size)))
        print(f"wrote {OUT / name} ({size}x{size})")
    images = {size: png(draw_mac(size)) for size in sorted({size for _, size in MAC_TYPES})}
    (OUT / MAC_ICNS).write_bytes(icns(images))
    print(f"wrote {OUT / MAC_ICNS} ({', '.join(str(size) for size in images)} pixels)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
