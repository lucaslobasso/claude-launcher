# Makes assets/claude.ico: Claude's app icon (colours unchanged) grown so the tile fills ~96% of the frame, like most
# taskbar icons (Claude's own icon leaves ~8% padding on each side, so it looked smaller than its neighbours).
# The launcher uses it for its shortcut, taskbar pin, Terminal profile and window.
# Input: claude.exe's 256 px icon saved as PNG (e.g. PrivateExtractIcons at 256x256 from ~/.local/bin/claude.exe).
# Run from the repo root: python assets/make_icon.py claude.png assets/claude.ico
import sys
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
FILL = 0.96  # tile size relative to the frame
im = Image.open(src).convert('RGBA')
tile = im.crop(im.getbbox()); side = round(256 * FILL)
tile = tile.resize((side, round(side * tile.height / tile.width)), Image.LANCZOS)
im = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
im.alpha_composite(tile, ((256 - tile.width) // 2, (256 - tile.height) // 2))
if out.endswith('.ico'):
    im.save(out, sizes=[(16,16),(20,20),(24,24),(32,32),(40,40),(48,48),(64,64),(128,128),(256,256)])
else:
    im.save(out)
