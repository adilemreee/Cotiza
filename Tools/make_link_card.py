"""Draws the link-preview card WhatsApp and iMessage show for a signing link (1200x630, EN, ES and TR).

    python3 Tools/make_link_card.py   ->  Server/sign/card-en.png, card-es.png, card-tr.png
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = "/System/Library/Fonts/SFNS.ttf"
W, H = 1200, 630
TEXT = {
    "en": ("Your estimate is ready", "Review it and approve it with your signature, right from your phone."),
    "es": ("Su cotización está lista", "Revísela y apruébela con su firma, desde su teléfono."),
    "tr": ("Teklifiniz hazır", "Telefonunuzdan inceleyip imzanızla onaylayın."),
}


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def wrap(draw, text, face, width):
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=face) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    return lines + [line]


for lang, (title, sub) in TEXT.items():
    # Plain orange, a little lighter at the top, like the App Store slides.
    img = Image.new("RGB", (W, H))
    top, bottom = (255, 138, 61), (212, 80, 15)
    for y in range(H):
        t = y / (H - 1)
        ImageDraw.Draw(img).line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    draw = ImageDraw.Draw(img)

    # The app icon on a soft shadow.
    icon = Image.open(ROOT / "AppStore/icon/AppIcon-1024.png").convert("RGBA").resize((200, 200), Image.LANCZOS)
    mask = Image.new("L", icon.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 199, 199), 46, fill=255)
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((90, 222, 290, 422), 46, fill=110)
    img.paste((120, 40, 5), (0, 0), shadow.filter(ImageFilter.GaussianBlur(18)))
    img.paste(icon, (90, 205), mask)

    x, width = 350, W - 350 - 80
    title_font, sub_font = font(64, "Bold"), font(34, "Medium")
    lines = wrap(draw, title, title_font, width)
    subs = wrap(draw, sub, sub_font, width)
    block = len(lines) * 74 + 20 + len(subs) * 46
    y = (H - block) / 2
    for line in lines:
        draw.text((x, y), line, font=title_font, fill="white")
        y += 74
    y += 20
    for line in subs:
        draw.text((x, y), line, font=sub_font, fill=(255, 240, 228))
        y += 46
    draw.text((x, H - 80), "Cotiza", font=font(30, "Semibold"), fill=(255, 225, 205))
    out = ROOT / f"Server/sign/card-{lang}.png"
    img.save(out, optimize=True)
    print(out.name, out.stat().st_size // 1024, "KB")
