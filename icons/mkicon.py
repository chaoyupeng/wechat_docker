"""Generate .icns files for the launcher apps: a chat bubble behind a shield,
green for start, grey for stop."""
import subprocess, sys, os
from PIL import Image, ImageDraw

OUT = sys.argv[1]
MODE = sys.argv[2]  # start | stop
S = 1024

if MODE == "start":
    bg1, bg2, fg = (7, 193, 96), (4, 150, 76), (255, 255, 255)
else:
    bg1, bg2, fg = (140, 146, 156), (104, 110, 120), (255, 255, 255)

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# rounded-rect background with a soft vertical gradient
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
for y in range(S):
    t = y / S
    gd.line([(0, y), (S, y)], fill=(
        int(bg1[0] + (bg2[0] - bg1[0]) * t),
        int(bg1[1] + (bg2[1] - bg1[1]) * t),
        int(bg1[2] + (bg2[2] - bg1[2]) * t), 255))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([80, 80, S - 80, S - 80], radius=200, fill=255)
img.paste(grad, (0, 0), mask)

# shield outline, centred
cx, cy = S // 2, S // 2 - 20
w, h = 300, 360
top, bot = cy - h // 2, cy + h // 2
shield = [
    (cx - w // 2, top + 40), (cx, top - 30), (cx + w // 2, top + 40),
    (cx + w // 2, cy + 40), (cx, bot + 40), (cx - w // 2, cy + 40),
]
d.polygon(shield, outline=fg, width=34)

# chat bubble inside the shield
bx0, by0, bx1, by1 = cx - 105, cy - 95, cx + 105, cy + 35
d.rounded_rectangle([bx0, by0, bx1, by1], radius=44, fill=fg)
d.polygon([(cx - 40, by1 - 6), (cx + 6, by1 - 6), (cx - 34, by1 + 62)], fill=fg)

if MODE == "stop":  # a bar across it
    d.line([(cx - 190, cy + 200), (cx + 190, cy + 200)], fill=fg, width=48)

iconset = OUT.replace(".icns", ".iconset")
os.makedirs(iconset, exist_ok=True)
for size in (16, 32, 64, 128, 256, 512):
    img.resize((size, size), Image.LANCZOS).save(f"{iconset}/icon_{size}x{size}.png")
    img.resize((size * 2, size * 2), Image.LANCZOS).save(f"{iconset}/icon_{size}x{size}@2x.png")
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", OUT], check=True)
print("wrote", OUT)
