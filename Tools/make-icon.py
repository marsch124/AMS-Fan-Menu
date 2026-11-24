#!/usr/bin/env python3
"""Builds the AMS Fan Menu app icon: a flat calm blue tile with the white hand-drawn three-blade fan.

Writes, all from the same numbers (the same way AMS Mic Check does it):
  App/Resources/AppIcon.icon   layered icon (Icon Composer format): blue background, ONE layer (the fan),
                               every glass effect off, same by day and night.
  App/Resources/AppIcon.icns   loose picture on Apple's tile shape (824 px tile on a 1024 canvas, radius 185.4).
  Docs/icon-1024.png           the same picture as a PNG.

Run:  python3 Tools/make-icon.py        (needs Pillow and the Mac's own iconutil)
"""
import json, math, os, shutil, subprocess, tempfile
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BLUE = (0.15, 0.45, 0.78)
WHITE = (1.0, 1.0, 1.0)
GLYPH = 0.74            # the fan's 24-unit grid takes this share of the tile's width
STROKE = 2.1
STROKE_SMALL = 2.4      # heavier line for the 64 px and smaller pictures in the .icns
CANVAS, TILE, RADIUS = 1024, 824, 185.4

# One blade relative to the centre, pointing up: start, then three cubic curves. Open: both ends meet the hub.
BLADE = [(-0.86, -1.73), ((-2.11, -4.42), (-4.42, -6.34), (-3.46, -8.64)),
         ((-2.5, -10.18), (2.5, -9.98), (4.42, -7.3)), ((5.18, -5.95), (3.07, -3.46), (1.63, -1.06))]
HUB_R = 2.0


def rot(p, deg):
    a = math.radians(deg)
    return (12 + p[0] * math.cos(a) - p[1] * math.sin(a), 12 + p[0] * math.sin(a) + p[1] * math.cos(a))


def blades():
    """Each blade as [start, (c1, c2, end), ...] in absolute grid coordinates."""
    return [[rot(BLADE[0], d)] + [tuple(rot(p, d) for p in seg) for seg in BLADE[1:]] for d in (0, 120, 240)]


def rgb8(c):
    return tuple(round(v * 255) for v in c) + (255,)


def colour(c):
    return "srgb:" + ",".join(f"{v:.5f}" for v in c) + ",1.00000"


def fan_svg_paths(size):
    """The fan as stroked SVG path data on a square canvas of `size`."""
    k = size * GLYPH / 24.0
    o = size / 2 - 12 * k
    P = lambda p: f"{o + p[0] * k:.3f} {o + p[1] * k:.3f}"
    d = ""
    for b in blades():
        d += f"M{P(b[0])} " + " ".join("C" + " ".join(P(p) for p in seg) for seg in b[1:]) + " "
    cx, cy = o + 12 * k, o + 12 * k
    return d.strip(), (cx, cy, HUB_R * k)


def write_layered_icon(folder):
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(os.path.join(folder, "Assets"))
    d, (cx, cy, hr) = fan_svg_paths(CANVAS)
    sw = STROKE * CANVAS * GLYPH / 24
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">'
           f'<g fill="none" stroke="#FFFFFF" stroke-width="{sw:.3f}" stroke-linecap="round" stroke-linejoin="round">'
           f'<path d="{d}"/><circle cx="{cx:.3f}" cy="{cy:.3f}" r="{hr:.3f}"/></g></svg>\n')
    with open(os.path.join(folder, "Assets", "fan.svg"), "w") as f:
        f.write(svg)

    def same(c):
        return [{"value": {"solid": colour(c)}}, {"appearance": "dark", "value": {"solid": colour(c)}}]

    doc = {
        "fill-specializations": same(BLUE),
        "groups": [{"layers": [{"fill-specializations": same(WHITE), "glass": False,
                                "image-name": "fan.svg", "name": "Fan"}], "name": "Fan",
                    "blur-material": None, "lighting": "individual",
                    "shadow": {"kind": "none", "opacity": 0}, "specular": False,
                    "translucency": {"enabled": False, "value": 0}}],
        "supported-platforms": {"squares": ["macOS"]},
    }
    with open(os.path.join(folder, "icon.json"), "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")


def apple_tile(size, tile, radius, steps=48):
    x0 = y0 = (size - tile) / 2
    x1 = y1 = x0 + tile
    r = radius

    def bez(p0, p1, p2, p3):
        out = []
        for i in range(1, steps + 1):
            t = i / steps
            a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
            out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
        return out

    corner = [(1.528665, 0), (1.088493, 0), (0.868407, 0), (0.631494, 0.074911),
              (0.372824, 0.169060), (0.169060, 0.372824), (0.074911, 0.631494),
              (0, 0.868407), (0, 1.088493), (0, 1.528665)]
    pts = []
    for (cx, cy), (ax, ay), (bx, by) in (((x1, y0), (-1, 0), (0, 1)), ((x1, y1), (0, -1), (-1, 0)),
                                         ((x0, y1), (1, 0), (0, -1)), ((x0, y0), (0, 1), (1, 0))):
        p = [(cx + ax * u * r + bx * v * r, cy + ay * u * r + by * v * r) for u, v in corner]
        pts.append(p[0])
        pts += bez(p[0], p[1], p[2], p[3]) + bez(p[3], p[4], p[5], p[6]) + bez(p[6], p[7], p[8], p[9])
    return pts


def render_flat(stroke, ss=4):
    s = CANVAS * ss
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).polygon([(x * ss, y * ss) for x, y in apple_tile(CANVAS, TILE, RADIUS)], fill=255)
    tile = Image.new("RGBA", (s, s), rgb8(BLUE))
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    img.paste(tile, (0, 0), mask)

    d = ImageDraw.Draw(img)
    scale = TILE * GLYPH * ss / 24
    ox = oy = s / 2 - 12 * scale
    P = lambda p: (ox + p[0] * scale, oy + p[1] * scale)
    r = stroke * scale / 2
    step = 1.5 * ss
    white = rgb8(WHITE)

    def dab(pt):
        d.ellipse([pt[0] - r, pt[1] - r, pt[0] + r, pt[1] + r], fill=white)

    for b in blades():
        cur = b[0]
        for c1, c2, end in b[1:]:
            pts = [P(cur), P(c1), P(c2), P(end)]
            n = 200
            for i in range(n + 1):
                t = i / n
                a, bb, c, e = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
                dab((a * pts[0][0] + bb * pts[1][0] + c * pts[2][0] + e * pts[3][0],
                     a * pts[0][1] + bb * pts[1][1] + c * pts[2][1] + e * pts[3][1]))
            cur = end
    hc = P((12, 12))
    hr = HUB_R * scale
    for i in range(361):
        a = math.radians(i)
        dab((hc[0] + hr * math.cos(a), hc[1] + hr * math.sin(a)))
    return img.convert("RGBa")


def shrink(master, px):
    return master.reduce(master.width // px).convert("RGBA")


def write_icns(path, img, heavy):
    tmp = tempfile.mkdtemp()
    iconset = os.path.join(tmp, "AppIcon.iconset")
    os.makedirs(iconset)
    for base in (16, 32, 128, 256, 512):
        for mult, suffix in ((1, ""), (2, "@2x")):
            px = base * mult
            shrink(heavy if px <= 64 else img, px).save(os.path.join(iconset, f"icon_{base}x{base}{suffix}.png"))
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", path], check=True)
    shutil.rmtree(tmp)


if __name__ == "__main__":
    os.makedirs(os.path.join(ROOT, "Docs"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "App", "Resources"), exist_ok=True)
    write_layered_icon(os.path.join(ROOT, "App", "Resources", "AppIcon.icon"))
    img = render_flat(STROKE)
    shrink(img, CANVAS).save(os.path.join(ROOT, "Docs", "icon-1024.png"))
    write_icns(os.path.join(ROOT, "App", "Resources", "AppIcon.icns"), img, render_flat(STROKE_SMALL))
    print("ok")
