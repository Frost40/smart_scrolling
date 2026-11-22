"""Draws the sample box pictures (covers and image cards) with plain Python, so no copyrighted image is used.

    python tools/content/sample/draw_images.py
"""

import math
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))


def save_png(path, w, h, pixel):
    rows = b"".join(b"\x00" + b"".join(bytes(pixel(x, y)) for x in range(w)) for y in range(h))
    chunk = lambda tag, data: struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


TEAL, DEEP, SAND, WHITE, INK = (15, 110, 120), (8, 48, 56), (240, 214, 160), (250, 250, 245), (30, 40, 45)


def book_cover(x, y):
    # A teal page with three rings: "curiosity spreading out".
    d = math.hypot(x - 200, y - 260)
    if any(abs(d - r) < 6 for r in (50, 95, 140)):
        return SAND
    return mix(TEAL, DEEP, y / 600)


def paper_cover(x, y):
    # Evenly spaced bars of growing height: "spacing practice".
    if 60 < x < 340 and 120 < y < 480:
        col = (x - 60) // 40
        if (x - 60) % 40 < 24 and y > 480 - 45 * (col + 1):
            return TEAL
        return WHITE
    return DEEP


def forgetting_curve(x, y):
    # A fast-falling memory curve, lifted again by three reviews.
    if (38 <= x <= 41 and 40 <= y <= 361) or (358 <= y <= 361 and x >= 38):
        return INK
    if x < 40 or y > 360:
        return WHITE
    t, level = (x - 40) / 560, 1.0
    for review in (0.0, 0.25, 0.55):
        if t >= review:
            since = t - review
            level = math.exp(-since * (6 - review * 8))
    curve_y = 360 - level * 300
    return TEAL if abs(y - curve_y) < 3 else WHITE


def light_bands(x, y):
    # White light split into its colors by a prism.
    if y < 120:
        return mix((250, 250, 250), (210, 210, 210), x / 600)
    hue = x / 600
    r = max(0, min(1, abs(hue * 6 - 3) - 1))
    g = max(0, min(1, 2 - abs(hue * 6 - 2)))
    b = max(0, min(1, 2 - abs(hue * 6 - 4)))
    return (round(r * 255), round(g * 255), round(b * 255))


if __name__ == "__main__":
    save_png(os.path.join(HERE, "sample-curious-learner", "cover.png"), 400, 600, book_cover)
    save_png(os.path.join(HERE, "sample-spacing-study", "cover.png"), 400, 600, paper_cover)
    save_png(os.path.join(HERE, "sample-curious-learner", "cards", "forgetting-curve", "image.png"), 600, 400, forgetting_curve)
    save_png(os.path.join(HERE, "sample-everyday-light", "cards", "prism-colors", "image.png"), 600, 400, light_bands)
    print("Drew 4 sample pictures.")
