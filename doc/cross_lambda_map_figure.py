# Compose the cross-lambda map figure from the GeoDMS viewport capture: crop the map view
# (drop the layer-control panel at the right and the empty north beyond Svalbard), add a title
# and a legend with the full class labels (the GeoDMS layer control truncates them).
#   PYTHONIOENCODING=utf-8 python cross_lambda_map_figure.py
#   in : doc/charts/cross_lambda_map_viewport.png  (scratch/run_cross_lambda_map.ps1)
#   out: doc/charts/cross_lambda_map_LINEAR.png, doc/img/cross_lambda_map_LINEAR.png
import os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
src = Image.open(os.path.join(HERE, "charts", "cross_lambda_map_viewport.png")).convert("RGB")
# crop box in the capture's pixels: left, top, right, bottom (the panel starts at x ~1035)
L, T, R, B = [int(v) for v in (sys.argv[1:5] if len(sys.argv) >= 5 else (200, 120, 1035, 757))]
map_img = src.crop((L, T, R, B))

CLASSES = [("#ebebeb", "not in the study"), ("#1a9850", "< 9 000"), ("#66bd63", "9 000 – 11 000"), ("#a6d96a", "11 000 – 13 000"),
           ("#fee08b", "13 000 – 16 000"), ("#fdae61", "16 000 – 20 000"), ("#f46d43", "20 000 – 30 000"), ("#d73027", "≥ 30 000")]
INK, MUTED = (18, 35, 58), (91, 107, 123)

def font(size, bold=False):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), ("arialbd.ttf" if bold else "arial.ttf")):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()

legend_w = 300
W = map_img.width + legend_w + 40
title_h = 70
H = map_img.height + title_h + 30
fig = Image.new("RGB", (W, H), "white")
fig.paste(map_img, (20, title_h))
d = ImageDraw.Draw(fig)
d.text((20, 14), "Cross-lambda per study area — LINEAR travel cost", fill=INK, font=font(22, True))
d.text((20, 44), "λ at the balanced-improvement crossing of the frontier, EUR per location via the placeholder 100 000 (= w · 100 000); 16 countries + 28 NUTS-1 regions",
       fill=MUTED, font=font(12))
x0, y0 = map_img.width + 45, title_h + 10
d.text((x0, y0), "cross-λ (EUR per location)", fill=INK, font=font(14, True))
y = y0 + 32
for color, label in CLASSES:
    d.rectangle((x0, y, x0 + 26, y + 18), fill=color, outline=(80, 80, 80))
    d.text((x0 + 36, y - 1), label, fill=INK, font=font(14))
    y += 28
y += 10
for line in ("low λ = a location buys little travel", "high λ = a location buys much travel", "",
             "Map: GeoDMS 20.19, NUTS 2021 (EPSG:3035);", "Portugal = mainland, Norway incl. Svalbard;",
             "grey: not in the study."):
    d.text((x0, y), line, fill=MUTED, font=font(11)); y += 17
out = os.path.join(HERE, "charts", "cross_lambda_map_LINEAR.png")
fig.save(out)
img_dir = os.path.join(HERE, "img")
if os.path.isdir(img_dir):
    fig.save(os.path.join(img_dir, "cross_lambda_map_LINEAR.png"))
print("wrote", out, fig.size)
