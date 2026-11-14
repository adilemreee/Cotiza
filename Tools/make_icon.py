"""Renders the 1024px app icon: a speech waveform that resolves into estimate lines."""
import sys
from PIL import Image, ImageDraw

SIZE = 1024
out = sys.argv[1]

# Diagonal warm gradient.
top, bottom = (255, 138, 61), (201, 62, 10)
img = Image.new("RGB", (SIZE, SIZE))
px = img.load()
for y in range(SIZE):
    for x in range(SIZE):
        t = (x * 0.35 + y * 0.65) / SIZE
        px[x, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))

draw = ImageDraw.Draw(img, "RGBA")

# Paper sheet.
sheet = (262, 190, 762, 834)
draw.rounded_rectangle((sheet[0] + 10, sheet[1] + 22, sheet[2] + 10, sheet[3] + 22), radius=64, fill=(120, 30, 0, 70))
draw.rounded_rectangle(sheet, radius=64, fill=(255, 255, 255, 255))

# Waveform bars across the top of the sheet.
ink = (201, 62, 10, 255)
heights = [70, 150, 230, 120, 190, 90]
bar_w, gap = 44, 30
total = len(heights) * bar_w + (len(heights) - 1) * gap
x = (sheet[0] + sheet[2] - total) // 2
center_y = 400
for h in heights:
    draw.rounded_rectangle((x, center_y - h // 2, x + bar_w, center_y + h // 2), radius=bar_w // 2, fill=ink)
    x += bar_w + gap

# Estimate lines below.
grey = (214, 216, 222, 255)
for i, width in enumerate([360, 360, 230]):
    y = 580 + i * 62
    draw.rounded_rectangle((332, y, 332 + width, y + 26), radius=13, fill=grey)
# Total pill.
draw.rounded_rectangle((572, 704, 692, 730), radius=13, fill=ink)

img.save(out, "PNG")
