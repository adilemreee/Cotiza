"""Draws the 1024x1024 images App Store Connect asks for on subscriptions and offers (win-back,
promotional). Same language as the app icon: orange field, the white estimate sheet, a Pro crown.
No text or prices, as Apple asks; the important part stays in the middle, since the App Store
rounds the corners.

    python3 Tools/make_subscription_images.py   ->  AppStore/subscription-images/*.png

Also the 3840x2160 image for the retention message (shown on the cancel screen).
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "AppStore" / "subscription-images"
K = 2                      # drawn at 2048 and scaled down for clean edges
S = 1024 * K
ORANGE = (217, 85, 26)


def background(width=None, height=None):
    W, H = width or S, height or S
    img = Image.new("RGB", (W, H))
    top, bottom = (255, 140, 64), (196, 60, 10)
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    # Soft light from the top left, like the icon's glass.
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse((-W * 0.35, -H * 0.45, W * 0.85, H * 0.55), fill=90)
    img.paste((255, 200, 150), (0, 0), glow.filter(ImageFilter.GaussianBlur(min(W, H) * 0.12)))
    return img.convert("RGBA")


def shadow(img, box, radius, blur, offset, opacity):
    layer = Image.new("L", img.size, 0)
    x0, y0, x1, y1 = box
    ImageDraw.Draw(layer).rounded_rectangle((x0, y0 + offset, x1, y1 + offset), radius, fill=opacity)
    img.paste((110, 30, 0), (0, 0), layer.filter(ImageFilter.GaussianBlur(blur)))


def sheet(img, cx, cy, w, angle=0.0, content=True):
    """The estimate sheet from the icon, centered at (cx, cy), optionally tilted."""
    h = w * 1.34
    tile = Image.new("RGBA", (int(w * 1.5), int(h * 1.5)), (0, 0, 0, 0))
    d = ImageDraw.Draw(tile)
    ox, oy = (tile.width - w) / 2, (tile.height - h) / 2
    r = w * 0.14
    d.rounded_rectangle((ox, oy, ox + w, oy + h), r, fill=(255, 255, 255, 255))
    if content:
        heights = [0.14, 0.30, 0.46, 0.24, 0.38, 0.18]
        bw, gap = w * 0.092, w * 0.056
        total = len(heights) * bw + (len(heights) - 1) * gap
        x = ox + (w - total) / 2
        wy = oy + h * 0.32
        for f in heights:
            bh = w * f
            d.rounded_rectangle((x, wy - bh / 2, x + bw, wy + bh / 2), bw / 2, fill=ORANGE + (255,))
            x += bw + gap
        lx = ox + w * 0.14
        for i, lw in enumerate([0.72, 0.72, 0.44]):
            ly = oy + h * (0.62 + i * 0.095)
            d.rounded_rectangle((lx, ly, lx + w * lw, ly + w * 0.056), w * 0.028, fill=(211, 213, 219, 255))
        tx = ox + w * 0.62
        ty = oy + h * (0.62 + 2 * 0.095)
        d.rounded_rectangle((tx, ty, tx + w * 0.24, ty + w * 0.056), w * 0.028, fill=ORANGE + (255,))
    if angle:
        tile = tile.rotate(angle, resample=Image.BICUBIC, expand=False)
    # Shadow from the sheet's own outline.
    alpha = tile.split()[3]
    sh = Image.new("L", img.size, 0)
    sh.paste(alpha, (int(cx - tile.width / 2), int(cy - tile.height / 2 + w * 0.035)))
    img.paste((120, 34, 0), (0, 0), sh.filter(ImageFilter.GaussianBlur(w * 0.06)).point(lambda v: v * 0.32))
    img.alpha_composite(tile, (int(cx - tile.width / 2), int(cy - tile.height / 2)))


CROWN = Image.open(ROOT / "Tools/assets/crown-mask.png").convert("RGBA").split()[3]  # SF Symbol crown.fill


def crown(img, cx, cy, size):
    """The SF Symbol crown (as on the paywall), filled with a warm gold gradient."""
    w = int(size)
    h = int(size * CROWN.height / CROWN.width)
    mask = CROWN.resize((w, h), Image.LANCZOS)
    fill = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(fill)
    for y in range(h):
        t = y / max(h - 1, 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip((255, 214, 112), (236, 158, 36))) + (255,))
    img.paste(fill, (int(cx - w / 2), int(cy - h / 2)), mask)


def badge(img, cx, cy, r, ring=False):
    """The Pro badge: a white disc with a gold crown."""
    sh = Image.new("L", img.size, 0)
    ImageDraw.Draw(sh).ellipse((cx - r, cy - r + r * 0.14, cx + r, cy + r + r * 0.14), fill=140)
    img.paste((110, 30, 0), (0, 0), sh.filter(ImageFilter.GaussianBlur(r * 0.25)))
    d = ImageDraw.Draw(img)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, 255))
    if ring:
        # A returning arc around the badge, for "welcome back".
        rr = r * 1.32
        width = int(r * 0.16)
        d.arc((cx - rr, cy - rr, cx + rr, cy + rr), start=-20, end=250, fill=(255, 245, 235, 255), width=width)
        a = math.radians(250)
        tipx, tipy = cx + rr * math.cos(a), cy + rr * math.sin(a)
        head = r * 0.34
        # Arrowhead pointing along the arc (clockwise) at its end.
        tx, ty = -math.sin(a), math.cos(a)  # tangent direction for increasing angle
        nx, ny = math.cos(a), math.sin(a)
        d.polygon([(tipx + tx * head, tipy + ty * head),
                   (tipx + nx * head * 0.75 - tx * head * 0.2, tipy + ny * head * 0.75 - ty * head * 0.2),
                   (tipx - nx * head * 0.75 - tx * head * 0.2, tipy - ny * head * 0.75 - ty * head * 0.2)],
                  fill=(255, 245, 235, 255))
    crown(img, cx, cy - r * 0.03, r * 1.32)


def sparkle(img, cx, cy, s, color=(255, 246, 225, 255)):
    d = ImageDraw.Draw(img)
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rad = s if i % 2 == 0 else s * 0.22
        pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    d.polygon(pts, fill=color)


def plan(sheets, sparkles=0, winback=False):
    img = background()
    cx, cy, w = S * 0.47, S * 0.53, S * 0.40
    # Extra sheets fan out behind the front one: more estimates on the bigger plan.
    # Lifted a little so their bottom corners stay hidden behind the front sheet.
    fan = [(-9, -S * 0.07, -S * 0.045), (8, S * 0.075, -S * 0.055)]
    for angle, dx, dy in fan[: sheets - 1]:
        sheet(img, cx + dx, cy + dy, w, angle=angle, content=False)
    sheet(img, cx, cy, w)
    badge(img, cx + w * 0.44, cy - w * 0.56, w * 0.29, ring=winback)
    spots = [(0.80, 0.20, 0.034), (0.16, 0.24, 0.024), (0.86, 0.72, 0.022), (0.12, 0.78, 0.030)]
    for fx, fy, fs in spots[:sparkles]:
        sparkle(img, S * fx, S * fy, S * fs)
    return img.convert("RGB").resize((1024, 1024), Image.LANCZOS)


def retention():
    """3840x2160: the three sheets and the Pro badge in the middle, sparkles around, room to breathe."""
    W, H = 3840, 2160
    img = background(W, H)
    cx, cy, w = W * 0.5, H * 0.56, H * 0.40
    for angle, dx, dy in [(-9, -H * 0.075, -H * 0.045), (8, H * 0.08, -H * 0.055)]:
        sheet(img, cx + dx, cy + dy, w, angle=angle, content=False)
    sheet(img, cx, cy, w)
    badge(img, cx + w * 0.44, cy - w * 0.56, w * 0.29)
    for fx, fy, fs in [(0.30, 0.22, 0.035), (0.70, 0.18, 0.028), (0.26, 0.74, 0.026), (0.74, 0.78, 0.034)]:
        sparkle(img, W * fx, H * fy, H * fs)
    return img.convert("RGB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, image in {
        "weekly": plan(1),
        "monthly": plan(2),
        "yearly": plan(3, sparkles=4),
        "winback": plan(2, sparkles=2, winback=True),
    }.items():
        path = OUT / f"{name}.png"
        image.save(path, optimize=True)
        print(path.relative_to(ROOT), image.size)
    path = OUT / "retention-3840x2160.png"
    retention().save(path, optimize=True)
    print(path.relative_to(ROOT), (3840, 2160))


main()
