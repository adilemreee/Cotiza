"""Lists raw captures (all, or the paths given) that still show the launch screen (solid brand orange) instead of the app."""
import glob
import sys

from PIL import Image

bad = []
for path in sys.argv[1:] or sorted(glob.glob("AppStore/screenshots/raw/*/*/*.png")):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    samples = [im.getpixel((round(w * x), round(h * y))) for x, y in [(0.1, 0.5), (0.9, 0.5), (0.5, 0.85), (0.2, 0.3)]]
    if all(r > 200 and 60 < g < 120 and b < 60 for r, g, b in samples):
        bad.append(path)
print("\n".join(bad) or "all captures show the app")
sys.exit(1 if bad else 0)
