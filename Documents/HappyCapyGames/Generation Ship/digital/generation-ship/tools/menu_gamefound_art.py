# Art for the main menu's Gamefound card (scenes/main_menu/gamefound_card.gd): the boxes-in-space
# render in each language (Marketing/Render, render_language.py), 960x540 JPG. The card shows it
# about 372 px wide on the 1080p layout and zooms in slowly, so 960 stays sharp up to 4K.
#   python tools/menu_gamefound_art.py
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, ".."))
RENDER = os.path.normpath(os.path.join(GAME, "..", "..", "Marketing", "Render"))
OUT = os.path.join(GAME, "assets", "ui", "gamefound")
LANGS = ["EN", "DE", "FR", "ES", "IT", "PL"]
SIZE = (960, 540)

os.makedirs(OUT, exist_ok=True)
for lang in LANGS:
    src = os.path.join(RENDER, f"GS_Box_Space_v7_{lang}.png")
    im = Image.open(src).convert("RGB")
    assert im.size[0] * 9 == im.size[1] * 16, (src, im.size)   # 16:9, like the card's picture
    im = im.resize(SIZE, Image.LANCZOS)
    dst = os.path.join(OUT, f"box_{lang}.jpg")
    im.save(dst, quality=88, optimize=True, progressive=False)
    print(f"{lang}: {os.path.getsize(dst) / 1024:.0f} KB")
