#!/usr/bin/env python3
"""
Render the PixelDock app icon at all macOS icon sizes.

Pixel-art style matching PixelCode: dark navy background, cyan/purple neon
accents, gold highlight. Subject is a stylized server tower (the "ship")
docked at a pier with two status LEDs — cyan for the always-on launcher,
green for the running server.

Output goes into the macOS AppIcon.appiconset alongside Contents.json.
Run from anywhere: paths are computed relative to this script.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

# ─── Pixel-art canvas (32×32) — every render scales this up with NEAREST ──

GRID = 32

# Palette tuned to PixelCode's default theme.
BG_TOP    = (12, 14, 26)       # near-black with a hint of navy
BG_BOTTOM = (24, 18, 48)       # subtle purple lift at the bottom
DOCK      = (32, 26, 60)
DOCK_LINE = (90, 70, 180)
TOWER     = (28, 28, 36)
TOWER_HI  = (70, 70, 86)
TOWER_DK  = (16, 16, 22)
SCREEN    = (0, 192, 209)      # PixelCode cyan
SCREEN_HI = (180, 240, 250)
SCREEN_DK = (0, 110, 130)
LED_ON    = (34, 220, 142)     # green = server alive
LED_IDLE  = (255, 215, 0)      # gold = launcher always on
ACCENT    = (180, 120, 255)    # purple neon

PALETTE_PIXELS = [
    # Each row is a list of (x, color). y is implicit by row index.
    # 32×32 grid; (0,0) is top-left.
]


def draw_base(draw: ImageDraw.ImageDraw) -> None:
    # Gradient background: linear top→bottom navy → deep purple.
    for y in range(GRID):
        t = y / (GRID - 1)
        r = int(BG_TOP[0] * (1 - t) + BG_BOTTOM[0] * t)
        g = int(BG_TOP[1] * (1 - t) + BG_BOTTOM[1] * t)
        b = int(BG_TOP[2] * (1 - t) + BG_BOTTOM[2] * t)
        draw.line([(0, y), (GRID - 1, y)], fill=(r, g, b))


def draw_dock(draw: ImageDraw.ImageDraw) -> None:
    # Dock line (the "pier") — 3 px tall band near the bottom.
    pier_y = 26
    draw.rectangle([(0, pier_y), (GRID - 1, pier_y + 1)], fill=DOCK)
    # Highlighted top edge of the pier.
    for x in range(0, GRID, 2):
        draw.point((x, pier_y), fill=DOCK_LINE)
    # Pillars under the pier.
    for x in (4, 11, 20, 27):
        draw.line([(x, pier_y + 1), (x, GRID - 1)], fill=DOCK)


def draw_tower(draw: ImageDraw.ImageDraw) -> None:
    # Tower body: 12 wide × 18 tall, centered horizontally.
    left, right = 10, 21
    top, bot = 7, 25

    # Outer frame (slight beveled look via two-tone outline).
    draw.rectangle([(left, top), (right, bot)], outline=TOWER_HI, fill=TOWER)
    # Inner shadow at right & bottom.
    for y in range(top + 1, bot):
        draw.point((right - 1, y), fill=TOWER_DK)
    for x in range(left + 1, right):
        draw.point((x, bot - 1), fill=TOWER_DK)

    # Top "antenna".
    draw.line([(15, 4), (15, 6)], fill=TOWER_HI)
    draw.point((15, 3), fill=ACCENT)

    # CRT-style screen.
    s_left, s_right = 12, 19
    s_top, s_bot = 9, 14
    draw.rectangle([(s_left, s_top), (s_right, s_bot)], fill=SCREEN_DK)
    draw.rectangle([(s_left + 1, s_top + 1), (s_right - 1, s_bot - 1)], fill=SCREEN)

    # Heartbeat / pulse readout — a single bright peak across the screen.
    # Reads as "alive / monitoring" at any size, even when the chevrons we
    # tried earlier collapse into noise.
    base_y = s_top + 3                # baseline pixel row
    flat_color = SCREEN_HI
    peak_color = (255, 255, 255)
    # Flat baseline on the left.
    for x in range(s_left + 1, 14):
        draw.point((x, base_y), fill=flat_color)
    # Up-stroke into the peak.
    draw.point((14, base_y - 1), fill=flat_color)
    draw.point((15, base_y - 2), fill=peak_color)   # peak top
    draw.point((15, base_y - 1), fill=peak_color)
    # Down-stroke and flat tail on the right.
    draw.point((16, base_y - 1), fill=flat_color)
    draw.point((16, base_y),     fill=flat_color)
    draw.point((17, base_y + 1), fill=flat_color)   # dip
    for x in range(18, s_right):
        draw.point((x, base_y), fill=flat_color)

    # Two LEDs below the screen.
    # Launcher LED (always on, gold).
    draw.rectangle([(13, 17), (14, 18)], fill=LED_IDLE)
    # Server LED (green = running).
    draw.rectangle([(17, 17), (18, 18)], fill=LED_ON)

    # Vent slats below LEDs to break up the front face.
    for y in (20, 21, 22):
        for x in range(13, 19):
            if (x + y) % 2 == 0:
                draw.point((x, y), fill=TOWER_HI)


def render_grid() -> Image.Image:
    base = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    draw_base(draw)
    draw_tower(draw)
    draw_dock(draw)
    return base


def add_glow(grid_img: Image.Image, scale: int) -> Image.Image:
    """Scale up with NEAREST (crisp pixels), then composite a soft glow on top.

    The glow is a Gaussian-blurred copy of just the cyan/gold/green pixels —
    gives the icon that warm CRT/neon feel without ruining pixel-art edges.
    """
    big = grid_img.resize((GRID * scale, GRID * scale), Image.Resampling.NEAREST)

    # Build a glow mask: pull bright/saturated pixels.
    glow_src = Image.new("RGBA", big.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_src)
    for y in range(GRID):
        for x in range(GRID):
            r, g, b, a = grid_img.getpixel((x, y))
            # Highlight neon-ish colors only.
            saturation = max(r, g, b) - min(r, g, b)
            brightness = (r + g + b) / 3
            if saturation > 90 and brightness > 80:
                px, py = x * scale, y * scale
                glow_draw.rectangle(
                    [(px, py), (px + scale - 1, py + scale - 1)],
                    fill=(r, g, b, 200),
                )
    blur_radius = max(scale * 0.9, 2)
    glow = glow_src.filter(ImageFilter.GaussianBlur(radius=blur_radius))

    out = Image.alpha_composite(big, glow)
    return Image.alpha_composite(out, big)  # crisp pixels on top of glow


def round_corners(img: Image.Image, radius_ratio: float = 0.22) -> Image.Image:
    """macOS Big Sur+ icon mask: rounded squircle (approximated as rounded rect)."""
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

    # Sizes used by the existing AppIcon.appiconset.
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for size in sizes:
        scale = max(1, size // GRID)
        # For sizes smaller than GRID, fall back to bicubic to keep glyph readable.
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


if __name__ == "__main__":
    main()
