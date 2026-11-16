"""Draws assets/logo.png (512 px) and assets/logo-400.png: a folded map with a numbered route
and a guide arrow leading to the next stop. Needs Pillow. Run: python3 assets/make_logo.py"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

S = 4  # supersampling factor for smooth edges
OUT = Path(__file__).resolve().parent
GREEN, RED, INK = (84, 227, 59, 255), (196, 62, 46, 255), (40, 24, 18, 255)


def scaled(points):
    return [(x * S, y * S) for x, y in points]


def main():
    img = Image.new("RGBA", (512 * S, 512 * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, 512 * S, 512 * S], radius=96 * S, fill=(13, 33, 43, 255))
    d.rounded_rectangle([14 * S, 14 * S, 498 * S, 498 * S], radius=84 * S, fill=(22, 52, 64, 255))

    # Folded parchment with a drop shadow and two shaded panels.
    parch = [(84, 118), (170, 96), (262, 120), (350, 98), (430, 122), (436, 400), (352, 380), (262, 404),
             (170, 382), (80, 404)]
    d.polygon(scaled([(x + 10, y + 12) for x, y in parch]), fill=(8, 22, 28, 255))
    d.polygon(scaled(parch), fill=(232, 208, 160, 255))
    for a in (1, 3):
        d.polygon(scaled([parch[a], parch[a + 1], parch[8 - a], parch[9 - a]]), fill=(214, 186, 134, 255))

    # Terrain hints: a river and two hills.
    d.line(scaled([(110, 340), (160, 312), (200, 332), (250, 304)]), fill=(120, 168, 190, 255), width=9 * S, joint="curve")
    for cx, cy in ((352, 168), (394, 184)):
        d.polygon(scaled([(cx - 26, cy + 20), (cx, cy - 22), (cx + 26, cy + 20)]), fill=(168, 140, 96, 255))

    stops = [(128, 176), (222, 226), (372, 306)]
    # Dotted trail already walked, from stop 1 to stop 2.
    a, b = stops[0], stops[1]
    n = int(math.dist(a, b) // 20)
    for i in range(1, n):
        x, y = a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n
        d.ellipse([(x - 5) * S, (y - 5) * S, (x + 5) * S, (y + 5) * S], fill=(150, 52, 40, 255))

    # Guide arrow from stop 2 towards stop 3, stopping short of both pins.
    a, b = stops[1], stops[2]
    length = math.dist(a, b)
    ux, uy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
    start, tip = 34, length - 36

    def at(along, across):
        return (a[0] + ux * along - uy * across, a[1] + uy * along + ux * across)

    arrow = [at(tip, 0), at(tip - 52, -36), at(tip - 42, -13), at(start, -13), at(start, 13), at(tip - 42, 13),
             at(tip - 52, 36)]
    d.polygon(scaled([(x + 6, y + 8) for x, y in arrow]), fill=(8, 22, 28, 150))
    d.polygon(scaled(arrow), fill=GREEN, outline=(20, 70, 26, 255), width=5 * S)

    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 30 * S)
    for i, (x, y) in enumerate(stops, 1):
        last = i == len(stops)
        d.ellipse([(x - 27) * S, (y - 27) * S, (x + 27) * S, (y + 27) * S], fill=INK)
        d.ellipse([(x - 22) * S, (y - 22) * S, (x + 22) * S, (y + 22) * S], fill=GREEN if last else RED)
        d.text((x * S, y * S), str(i), font=font, fill=(18, 40, 22, 255) if last else (255, 240, 220, 255), anchor="mm")

    img = img.resize((512, 512), Image.LANCZOS)
    img.save(OUT / "logo.png")
    img.resize((400, 400), Image.LANCZOS).save(OUT / "logo-400.png")


if __name__ == "__main__":
    main()
