#!/usr/bin/env python3
"""
Render the PixelDock app icon at all macOS icon sizes.

Pixel-art rubber duck on a navy gradient — bright yellow body, orange beak,
tiny black eye, and a few cyan ripples that hint at bathwater.

Output goes into the macOS AppIcon.appiconset alongside Contents.json.
Run from anywhere: paths are computed relative to this script.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
ASSETS_LOGO = ROOT / "assets" / "logo.png"

GRID = 32

BG_TOP    = (12, 14, 26)
BG_BOTTOM = (24, 18, 48)

DUCK     = (255, 213, 0)
DUCK_HI  = (255, 240, 140)
DUCK_DK  = (210, 155, 0)
BEAK     = (255, 140, 0)
BEAK_DK  = (200, 90, 0)
EYE      = (16, 16, 22)
EYE_HI   = (240, 240, 250)
WATER    = (0, 160, 200)
WATER_HI = (140, 220, 240)


def draw_base(draw: ImageDraw.ImageDraw) -> None:
    for y in range(GRID):
        t = y / (GRID - 1)
        r = int(BG_TOP[0] * (1 - t) + BG_BOTTOM[0] * t)
        g = int(BG_TOP[1] * (1 - t) + BG_BOTTOM[1] * t)
        b = int(BG_TOP[2] * (1 - t) + BG_BOTTOM[2] * t)
        draw.line([(0, y), (GRID - 1, y)], fill=(r, g, b))


def draw_duck(draw: ImageDraw.ImageDraw) -> None:
    # Head — soft circle around (12, 11).
    head_rows = {
        7:  range(11, 14),
        8:  range(10, 15),
        9:  range(9, 16),
        10: range(8, 16),
        11: range(8, 16),
        12: range(9, 16),
        13: range(10, 15),
    }
    for y, xs in head_rows.items():
        for x in xs:
            draw.point((x, y), fill=DUCK)

    # Body — oval, wider than head, sitting low.
    body_rows = {
        14: range(10, 23),
        15: range(9, 24),
        16: range(9, 25),
        17: range(9, 25),
        18: range(9, 25),
        19: range(10, 25),
        20: range(11, 24),
        21: range(13, 22),
    }
    for y, xs in body_rows.items():
        for x in xs:
            draw.point((x, y), fill=DUCK)

    # Highlights — top-left of head and body.
    for x, y in [(10, 8), (11, 8), (10, 9),
                 (11, 15), (12, 15), (10, 16), (11, 16)]:
        draw.point((x, y), fill=DUCK_HI)

    # Shading — bottom-right of body.
    for x, y in [(24, 17), (24, 18), (23, 19), (24, 19),
                 (22, 20), (23, 20), (20, 21), (21, 21)]:
        draw.point((x, y), fill=DUCK_DK)

    # Beak — orange wedge to the right of the head.
    draw.point((15, 10), fill=BEAK)
    draw.point((16, 10), fill=BEAK)
    draw.point((15, 11), fill=BEAK)
    draw.point((16, 11), fill=BEAK)
    draw.point((17, 11), fill=BEAK)
    draw.point((15, 12), fill=BEAK_DK)
    draw.point((16, 12), fill=BEAK_DK)

    # Eye — single dark pixel + a tiny highlight.
    draw.point((12, 10), fill=EYE)
    draw.point((13, 10), fill=EYE_HI)


def draw_water(draw: ImageDraw.ImageDraw) -> None:
    # Cute wave dashes — bath-water hint, kept short so they don't
    # compete with the duck silhouette at small sizes.
    bright = [
        (4, 24), (5, 24),
        (10, 24), (11, 24),
        (20, 24), (21, 24),
        (26, 24), (27, 24),
        (7, 26), (8, 26),
        (14, 26), (15, 26), (16, 26),
        (23, 26), (24, 26),
    ]
    for x, y in bright:
        draw.point((x, y), fill=WATER_HI)
    for x, y in [(3, 24), (12, 24), (22, 24), (28, 24),
                 (6, 26), (13, 26), (17, 26), (25, 26)]:
        draw.point((x, y), fill=WATER)


def render_grid() -> Image.Image:
    base = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    draw_base(draw)
    draw_duck(draw)
    draw_water(draw)
    return base


def add_glow(grid_img: Image.Image, scale: int) -> Image.Image:
    """Scale up with NEAREST (crisp pixels), then composite a soft glow on top.

    The glow is a Gaussian-blurred copy of just the saturated pixels —
    gives the duck a warm rubber sheen without ruining pixel-art edges.
    """
    big = grid_img.resize((GRID * scale, GRID * scale), Image.Resampling.NEAREST)

    glow_src = Image.new("RGBA", big.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_src)
    for y in range(GRID):
        for x in range(GRID):
            r, g, b, a = grid_img.getpixel((x, y))
            saturation = max(r, g, b) - min(r, g, b)
            brightness = (r + g + b) / 3
            is_white_peak = r > 235 and g > 235 and b > 235
            if (saturation > 100 and brightness > 90) or is_white_peak:
                px, py = x * scale, y * scale
                glow_draw.rectangle(
                    [(px, py), (px + scale - 1, py + scale - 1)],
                    fill=(r, g, b, 160),
                )
    blur_radius = max(scale * 0.9, 2)
    glow = glow_src.filter(ImageFilter.GaussianBlur(radius=blur_radius))

    out = Image.alpha_composite(big, glow)
    return Image.alpha_composite(out, big)


def round_corners(img: Image.Image, radius_ratio: float = 0.22) -> Image.Image:
    w, h = img.size
    radius = int(min(w, h) * radius_ratio)
    mask = Image.new("L", (w, h), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.rounded_rectangle([(0, 0), (w - 1, h - 1)], radius=radius, fill=255)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    grid = render_grid()

    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for size in sizes:
        scale = max(1, size // GRID)
        if size < GRID:
            scaled = grid.resize((size, size), Image.Resampling.BILINEAR)
        else:
            scaled = add_glow(grid, scale)
            if scaled.size != (size, size):
                scaled = scaled.resize((size, size), Image.Resampling.LANCZOS)
        scaled = round_corners(scaled)
        path = OUT_DIR / f"app_icon_{size}.png"
        scaled.save(path)
        print(f"  wrote {path.relative_to(ROOT)}  ({size}×{size})")
        if size == 256:
            ASSETS_LOGO.parent.mkdir(parents=True, exist_ok=True)
            scaled.save(ASSETS_LOGO)
            print(f"  wrote {ASSETS_LOGO.relative_to(ROOT)}  (in-app logo)")


if __name__ == "__main__":
    main()
