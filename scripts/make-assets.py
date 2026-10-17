#!/usr/bin/env python3
"""Generate the Genesis OS branding assets from the two source images.

    make-assets.py SRC_DIR OUT_DIR

SRC_DIR must contain logo.webp (square, logo on black) and wallpaper.webp
(16:9, logo on dark background with a small sparkle watermark bottom-right).

Produces in OUT_DIR:
  icons/hicolor/<size>x<size>/apps/genesis-os.png   transparent app/menu icon (mark only)
  icons/genesis-os-tile-512.png                      mark on a dark glass tile (launcher art)
  splash/splash.png                                  1920x1080 boot splash, logo centred
  wallpapers/*.jpg                                   1920x1080 (and 2560x1440 for generated ones)

Only Pillow is required.  Deterministic: no randomness without a fixed seed.
"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
ICON_SIZES = (16, 22, 24, 32, 48, 64, 96, 128, 256, 512)

# Palette sampled from the logo strokes and the wallpaper.
NAVY_DEEP = (5, 7, 9)
NAVY = (11, 20, 32)
NAVY_LIGHT = (32, 44, 59)
STEEL = (95, 125, 154)
STEEL_LIGHT = (138, 164, 189)
SILVER = (205, 218, 230)


def ensure(path):
    os.makedirs(path, exist_ok=True)
    return path


def bright_bbox(gray, box, threshold=40):
    """Bounding box of pixels brighter than threshold inside box (x0,y0,x1,y1)."""
    region = gray.crop(box).point(lambda v: 255 if v > threshold else 0)
    bb = region.getbbox()
    if bb is None:
        return None
    return (bb[0] + box[0], bb[1] + box[1], bb[2] + box[0], bb[3] + box[1])


# ---------------------------------------------------------------- logo pieces
logo = Image.open(os.path.join(SRC, "logo.webp")).convert("RGB")
gray = logo.convert("L")
W, H = logo.size
rows = [gray.crop((0, y, W, y + 1)).getextrema()[1] for y in range(H)]
lit = [y for y, v in enumerate(rows) if v > 40]
# first dark gap taller than 25 px below the mark separates mark and wordmark
gap_start = None
mark_bottom = lit[-1]
for y in range(lit[0], lit[-1]):
    if rows[y] <= 40:
        gap_start = y if gap_start is None else gap_start
    else:
        if gap_start is not None and y - gap_start > 25:
            mark_bottom = gap_start
            break
        gap_start = None
mark_box = bright_bbox(gray, (0, lit[0], W, mark_bottom))
print("mark bbox", mark_box)

# Transparent mark: colour from the logo, alpha from luminance (black -> transparent).
mark_rgb = logo.crop(mark_box)
mark_alpha = gray.crop(mark_box).point(lambda v: min(255, int(v * 1.6)))
mark = mark_rgb.copy()
mark.putalpha(mark_alpha)
side = int(max(mark.size) * 1.12)
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.paste(mark, ((side - mark.width) // 2, (side - mark.height) // 2), mark)
for s in ICON_SIZES:
    d = ensure(os.path.join(OUT, "icons", "hicolor", f"{s}x{s}", "apps"))
    square.resize((s, s), Image.LANCZOS).save(os.path.join(d, "genesis-os.png"), optimize=True)

# Launcher tile: dark glass rounded square with a soft highlight behind the mark.
tile = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
draw = ImageDraw.Draw(tile)
draw.rounded_rectangle((8, 8, 504, 504), radius=112, fill=(14, 22, 34, 255))
glow = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse((96, 96, 416, 416), fill=STEEL + (110,))
glow = glow.filter(ImageFilter.GaussianBlur(70))
tile.alpha_composite(glow)
tile.alpha_composite(square.resize((392, 392), Image.LANCZOS), (60, 60))
tile.save(os.path.join(ensure(os.path.join(OUT, "icons")), "genesis-os-tile-512.png"), optimize=True)

# ---------------------------------------------------------------- boot splash
full_box = bright_bbox(gray, (0, 0, W, H))
full = logo.crop(full_box)
splash = Image.new("RGB", (1920, 1080), (0, 0, 0))
target_h = int(1080 * 0.46)
scaled = full.resize((int(full.width * target_h / full.height), target_h), Image.LANCZOS)
splash.paste(scaled, ((1920 - scaled.width) // 2, (1080 - scaled.height) // 2))
splash.save(os.path.join(ensure(os.path.join(OUT, "splash")), "splash.png"), optimize=True)

# ---------------------------------------------------------------- wallpapers
wdir = ensure(os.path.join(OUT, "wallpapers"))
wall = Image.open(os.path.join(SRC, "wallpaper.webp")).convert("RGB")
WW, WH = wall.size
wgray = wall.convert("L")
wm = bright_bbox(wgray, (int(WW * 0.88), int(WH * 0.85), WW, WH), threshold=120)
if wm:
    # Fill the watermark with the strip immediately to its left, feathered.
    pad = 28
    x0, y0, x1, y1 = wm[0] - pad, wm[1] - pad, wm[2] + pad, wm[3] + pad
    w, h = x1 - x0, y1 - y0
    patch = wall.crop((x0 - w - 10, y0, x1 - w - 10, y1)).transpose(Image.FLIP_LEFT_RIGHT)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).ellipse((4, 4, w - 4, h - 4), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(10))
    wall.paste(patch, (x0, y0), mask)
    print("watermark removed at", wm)

def fit_16_9(im, width, height):
    ratio = width / height
    w, h = im.size
    if w / h > ratio:
        nw = int(h * ratio)
        im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:
        nh = int(w / ratio)
        im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    return im.resize((width, height), Image.LANCZOS)

fit_16_9(wall, 1920, 1080).save(os.path.join(wdir, "genesis-horizon.jpg"), quality=92, optimize=True)
fit_16_9(wall, 2560, 1440).save(os.path.join(wdir, "genesis-horizon-2560.jpg"), quality=90, optimize=True)


def gradient(width, height, top, bottom):
    base = Image.new("RGB", (1, height))
    for y in range(height):
        t = y / (height - 1)
        base.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return base.resize((width, height), Image.BILINEAR)


def glow_layer(width, height, blobs, blur):
    layer = Image.new("RGB", (width, height), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    for (cx, cy, rx, ry, colour) in blobs:
        d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=colour)
    return layer.filter(ImageFilter.GaussianBlur(blur))


def constellation(width, height, seed, count, colour, alpha):
    rnd = random.Random(seed)
    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts = [(rnd.randint(0, width), rnd.randint(0, height)) for _ in range(count)]
    for i, p in enumerate(pts):
        near = sorted(pts, key=lambda q: (q[0] - p[0]) ** 2 + (q[1] - p[1]) ** 2)[1:3]
        for q in near:
            d.line([p, q], fill=colour + (alpha,), width=1)
        d.ellipse((p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2), fill=colour + (alpha + 60,))
    return layer


def save_variant(name, im):
    im.save(os.path.join(wdir, f"{name}-2560.jpg"), quality=90, optimize=True)
    im.resize((1920, 1080), Image.LANCZOS).save(os.path.join(wdir, f"{name}.jpg"), quality=92, optimize=True)


WV, HV = 2560, 1440

# 1. Midnight: the original's mood without the logo, for people who want a clean desk.
im = gradient(WV, HV, NAVY_LIGHT, NAVY_DEEP)
im = ImageChops.add(im, glow_layer(WV, HV, [(0, int(HV * 0.68), 1500, 70, (70, 95, 120)), (WV, int(HV * 0.2), 900, 500, (20, 30, 44))], 90))
im.paste(constellation(WV, HV, 7, 28, STEEL, 28), (0, 0), constellation(WV, HV, 7, 28, STEEL, 28))
save_variant("genesis-midnight", im)

# 2. Aurora glass: large soft orbs in steel and teal, the backdrop blur was made for this.
im = gradient(WV, HV, (8, 14, 24), NAVY_DEEP)
im = ImageChops.add(im, glow_layer(WV, HV, [
    (int(WV * 0.22), int(HV * 0.3), 700, 520, (34, 70, 100)),
    (int(WV * 0.74), int(HV * 0.62), 820, 600, (60, 88, 116)),
    (int(WV * 0.55), int(HV * 0.15), 420, 300, (40, 110, 120)),
], 160))
save_variant("genesis-aurora", im)

# 3. Graphite mesh: near-black with a faint constellation, maximum contrast for glass panels.
im = gradient(WV, HV, (16, 18, 22), (4, 5, 7))
im = ImageChops.add(im, glow_layer(WV, HV, [(int(WV * 0.5), int(HV * 1.05), 1400, 500, (24, 34, 46))], 140))
mesh = constellation(WV, HV, 42, 60, STEEL_LIGHT, 22)
im.paste(mesh, (0, 0), mesh)
save_variant("genesis-graphite", im)

# 4. Silver wave: diagonal light sweep, brighter, for well-lit rooms.
im = gradient(WV, HV, (18, 28, 42), (6, 10, 16))
sweep = Image.new("RGB", (WV, HV), (0, 0, 0))
ImageDraw.Draw(sweep).polygon([(0, int(HV * 0.9)), (WV, int(HV * 0.25)), (WV, int(HV * 0.45)), (0, int(HV * 1.1))], fill=(70, 92, 116))
im = ImageChops.add(im, sweep.filter(ImageFilter.GaussianBlur(120)))
save_variant("genesis-silverwave", im)

print("done:", sorted(os.listdir(wdir)))
