"""Mockup leaderboard for the main menu's Leaderboard tile -> assets/ui/menu_leaderboard.png"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = r"C:\Users\ptmaz\Documents\HappyCapyGames\Generation Ship\digital\generation-ship"
FONT = os.path.join(ROOT, "assets/fonts/Ethnocentric-Regular.otf")
OUT = os.path.join(ROOT, "assets/ui/menu_leaderboard.png")
W, H = 600, 440
BG_TOP, BG_BOT = (10, 18, 40), (4, 8, 20)
CYAN = (90, 200, 255)
GOLD, SILVER, BRONZE = (255, 214, 80), (205, 215, 230), (205, 140, 80)
TEXT = (215, 225, 240)
DIM = (120, 140, 170)
STAR = (255, 210, 60)

ROWS = [("NOVA", 214), ("ORBITER", 198), ("CAPY", 187), ("STARDUST", 171), ("ZEPHYR", 158)]

img = Image.new("RGB", (W, H))
d = ImageDraw.Draw(img)
for y in range(H):  # vertical gradient
    t = y / H
    d.line([(0, y), (W, y)], fill=tuple(int(BG_TOP[i] * (1 - t) + BG_BOT[i] * t) for i in range(3)))
# faint grid like the cockpit screens
for x in range(0, W, 30):
    d.line([(x, 0), (x, H)], fill=(18, 32, 60))
for y in range(0, H, 30):
    d.line([(0, y), (W, y)], fill=(18, 32, 60))

title_f = ImageFont.truetype(FONT, 40)
row_f = ImageFont.truetype(FONT, 28)
rank_f = ImageFont.truetype(FONT, 30)

# title with a soft glow
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.text((W / 2, 44), "LEADERBOARD", font=title_f, fill=CYAN + (255,), anchor="mm")
img.paste(Image.new("RGB", (W, H), CYAN), (0, 0), glow.filter(ImageFilter.GaussianBlur(8)).split()[3].point(lambda v: int(v * 0.8)))
d = ImageDraw.Draw(img)
d.text((W / 2, 44), "LEADERBOARD", font=title_f, fill=(235, 248, 255), anchor="mm")
d.line([(40, 82), (W - 40, 82)], fill=CYAN, width=2)


def star(cx, cy, r, fill):
    import math
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = r if k % 2 == 0 else r * 0.45
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=fill)


y0, step = 122, 64
for i, (name, score) in enumerate(ROWS):
    y = y0 + i * step
    medal = [GOLD, SILVER, BRONZE][i] if i < 3 else DIM
    # row plate
    plate = (22, 38, 72) if i % 2 == 0 else (16, 28, 56)
    d.rounded_rectangle([30, y - 26, W - 30, y + 26], radius=10, fill=plate,
                        outline=medal if i == 0 else None, width=2)
    # rank badge
    if i < 3:
        d.ellipse([46, y - 21, 88, y + 21], fill=medal)
        d.text((67, y + 1), str(i + 1), font=rank_f, fill=(20, 24, 40), anchor="mm")
    else:
        d.text((67, y + 1), str(i + 1), font=rank_f, fill=DIM, anchor="mm")
    d.text((108, y + 1), name, font=row_f, fill=TEXT if i < 3 else DIM, anchor="lm")
    d.text((W - 80, y + 1), str(score), font=row_f, fill=medal if i < 3 else TEXT, anchor="rm")
    star(W - 56, y, 13, STAR)

img.save(OUT)
print(OUT, img.size)
