"""Tekent het Kniv-icoon: een gestileerd wit lemmet op zakmesrood. python scripts/maak_icoon.py"""
import math
import pathlib
from PIL import Image, ImageDraw

ROOD_BOVEN, ROOD_ONDER = (226, 52, 40), (196, 36, 28)
S = 4096  # 4x supersampling, daarna terug naar 1024 voor gladde randen


def bezier(p0, p1, p2, n=40):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]) for t in (i / n for i in range(n + 1))]


def teken(pad):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):  # zachte verticale gloed
        f = y / S
        d.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * f) for a, b in zip(ROOD_BOVEN, ROOD_ONDER)))

    # Lemmet in eigen assen: rug recht, snede buigt naar de punt.
    L, H = 2700, 560
    vorm = [(0, 0), (L * 0.78, 0)] + bezier((L * 0.78, 0), (L * 0.97, H * 0.05), (L, H * 0.42))[1:] \
        + bezier((L, H * 0.42), (L * 0.62, H * 1.08), (L * 0.18, H))[1:] + [(0, H)]
    hoek = math.radians(-38)
    cx, cy = L / 2, H / 2
    punten = [(S / 2 + (x - cx) * math.cos(hoek) - (y - cy) * math.sin(hoek),
               S / 2 + (x - cx) * math.sin(hoek) + (y - cy) * math.cos(hoek)) for x, y in vorm]
    d.polygon(punten, fill=(255, 255, 255))

    # Scharnierpunt aan het einde van het lemmet.
    px, py = S / 2 + (H * 0.5 - cx) * math.cos(hoek), S / 2 + (H * 0.5 - cx) * math.sin(hoek)
    r = H * 0.17
    d.ellipse([px - r, py - r, px + r, py + r], fill=ROOD_ONDER)

    img.resize((1024, 1024), Image.LANCZOS).save(pad)


if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parent.parent
    uit = root / "Kniv" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"
    uit.parent.mkdir(parents=True, exist_ok=True)
    teken(uit)
    print("Icoon:", uit)
