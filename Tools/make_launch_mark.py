"""Renders the launch-screen mark: the white estimate sheet with its waveform, as on the app icon.

The geometry must match `SplashView.Mark` exactly so iOS's static launch screen hands over to the
animated splash without a jump. Both derive from the 1024-pt icon, scaled so the sheet is 120 pt wide.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(sys.argv[1])
S = 120 / 500            # points per icon pixel
SHEET_W, SHEET_H, SHEET_R = 500 * S, 644 * S, 64 * S
ORANGE = (201, 62, 10, 255)
GREY = (214, 216, 222, 255)
HEIGHTS = [70, 150, 230, 120, 190, 90]

def render(scale: int) -> Image.Image:
    k = S * scale
    img = Image.new("RGBA", (round(SHEET_W * scale), round(SHEET_H * scale)), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=SHEET_R * scale, fill=(255, 255, 255, 255))
    # Bars: 44 wide, 30 apart, centred on icon y=400 (sheet top is icon y=190).
    x = (500 - (6 * 44 + 5 * 30)) / 2
    for h in HEIGHTS:
        top = 400 - 190 - h / 2
        d.rounded_rectangle((x * k, top * k, (x + 44) * k, (top + h) * k), radius=22 * k, fill=ORANGE)
        x += 44 + 30
    for i, w in enumerate([360, 360, 230]):
        y = 580 - 190 + i * 62
        d.rounded_rectangle((70 * k, y * k, (70 + w) * k, (y + 26) * k), radius=13 * k, fill=GREY)
    d.rounded_rectangle((310 * k, 514 * k, 430 * k, 540 * k), radius=13 * k, fill=ORANGE)
    return img

OUT.mkdir(parents=True, exist_ok=True)
for scale in (2, 3):
    render(scale).save(OUT / f"LaunchMark@{scale}x.png")
print("ok", [render(s).size for s in (2, 3)])
