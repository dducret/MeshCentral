# SPDX-License-Identifier: Apache-2.0
"""Draw the original test-app icon using Python stdlib, without external artwork.

All opaque RGB PNGs carry an Apache-2.0 notice. The explicit iPhone/iPad slots
do not rely on Xcode's single-size expansion. This tool changes only the icon
catalog, never Xcode signing configuration.
"""
import json
import math
import struct
import zlib
from pathlib import Path

OUTPUT = Path(__file__).resolve().parents[1] / "apple/App/MeshCentralAssets.xcassets/MeshCentralAppIcon.appiconset"
# Points and display scale, following Apple's App Icon Type catalog format.
SLOTS = (
    [("iphone", points, scale) for points in (20, 29, 40, 60) for scale in (2, 3)]
    + [("ipad", points, scale) for points in (20, 29, 40, 76) for scale in (1, 2)]
    + [("ipad", 83.5, 2), ("ios-marketing", 1024, 1)]
)


def rounded_box(x, y, cx, cy, hx, hy, radius):
    dx, dy = abs(x - cx) - hx + radius, abs(y - cy) - hy + radius
    return math.hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0) - radius


def segment(x, y, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - ax - t * dx, y - ay - t * dy)


def blend(rgb, color, distance, unit=1):
    coverage = max(0, min(1, 0.5 - distance / unit))
    return tuple(round(a + (b - a) * coverage) for a, b in zip(rgb, color))


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def render(size):
    raw = bytearray()
    unit = 1024 / size
    for row in range(size):
        raw.append(0)
        for col in range(size):
            x, y = (col + 0.5) * unit, (row + 0.5) * unit
            # Full-bleed background: iPadOS applies the outer icon mask.
            rgb = (round(18 + 9 * row / size), round(44 + 19 * row / size), round(82 + 30 * row / size))
            rgb = blend(rgb, (241, 248, 255), abs(rounded_box(x, y, 512, 512, 221, 330, 63)) - 16, unit)
            rgb = blend(rgb, (241, 248, 255), rounded_box(x, y, 512, 243, 53, 7, 7), unit)
            rgb = blend(rgb, (241, 248, 255), rounded_box(x, y, 512, 785, 51, 7, 7), unit)
            # Two connected nodes represent attended assistance.
            rgb = blend(rgb, (89, 220, 202), segment(x, y, 422, 567, 602, 457) - 18, unit)
            for cx, cy in ((422, 567), (602, 457)):
                rgb = blend(rgb, (89, 220, 202), math.hypot(x - cx, y - cy) - 56, unit)
                rgb = blend(rgb, (22, 53, 96), math.hypot(x - cx, y - cy) - 29, unit)
            raw.extend(rgb)
    png = b"\x89PNG\r\n\x1a\n"
    png += png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += png_chunk(b"sRGB", b"\x00")
    png += png_chunk(b"tEXt", b"License\x00SPDX-License-Identifier: Apache-2.0")
    png += png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += png_chunk(b"IEND", b"")
    return png


def build():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    images, pixels = [], set()
    for idiom, points, scale in SLOTS:
        size = int(points * scale)
        images.append({"filename": f"Icon-{size}.png", "idiom": idiom,
                       "size": f"{points:g}x{points:g}", "scale": f"{scale}x"})
        pixels.add(size)
    for size in sorted(pixels):
        (OUTPUT / f"Icon-{size}.png").write_bytes(render(size))
    catalog = {"images": images, "info": {"author": "MeshCentral iOS agent contributors", "version": 1}}
    (OUTPUT / "Contents.json").write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Original Apache-2.0 RGB icons: {len(pixels)} PNGs, {len(images)} slots, {OUTPUT}")


if __name__ == "__main__":
    build()
