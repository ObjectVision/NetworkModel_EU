# Compose the cross-lambda map figure from the GeoDMS viewport capture: crop the map view
# (drop the layer-control panel at the right and the empty north beyond Svalbard), add a
# legend with the full class labels (the GeoDMS layer control truncates them) and, for the
# mail version, a title. The slide version has no title: the slide carries it.
#   PYTHONIOENCODING=utf-8 python cross_lambda_map_figure.py [LINEAR|LOGISTIC] [L T R B]
#   in : doc/charts/cross_lambda_map_viewport_<FN>.png  (doc/run_cross_lambda_map.ps1)
#   out: doc/charts/cross_lambda_map_<FN>.png + doc/img/…      (title, for the mail)
#        doc/charts/cross_lambda_map_<FN>_slide.png              (no title, for the deck)
import os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FN = (sys.argv[1] if len(sys.argv) > 1 else "LINEAR").upper()
src = Image.open(os.path.join(HERE, "charts", f"cross_lambda_map_viewport_{FN}.png")).convert("RGB")
# crop box in the capture's pixels: left, top, right, bottom (the panel starts at x ~1035)
L, T, R, B = [int(v) for v in (sys.argv[2:6] if len(sys.argv) >= 6 else (200, 130, 1035, 757))]
map_img = src.crop((L, T, R, B))

COLORS = ["#ebebeb", "#1a9850", "#66bd63", "#a6d96a", "#fee08b", "#fdae61", "#f46d43", "#d73027"]
LABELS = {"LINEAR":   ["not in the study", "< 9 000", "9 000 – 11 000", "11 000 – 13 000", "13 000 – 16 000", "16 000 – 20 000", "20 000 – 30 000", "≥ 30 000"],
          "LOGISTIC": ["not in the study", "< 90", "90 – 110", "110 – 130", "130 – 160", "160 – 200", "200 – 300", "≥ 300"]}[FN]
INK, MUTED = (18, 35, 58), (91, 107, 123)


def font(size, bold=False):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), ("arialbd.ttf" if bold else "arial.ttf")):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def compose(with_title):
    legend_w = 300
    title_h = 70 if with_title else 10
    W = map_img.width + legend_w + 40
    H = map_img.height + title_h + 30
    fig = Image.new("RGB", (W, H), "white")
    fig.paste(map_img, (20, title_h))
    d = ImageDraw.Draw(fig)
    if with_title:
        d.text((20, 14), f"Cross-lambda per study area — {FN} travel cost", fill=INK, font=font(22, True))
        d.text((20, 44), "λ at the balanced-improvement crossing of the frontier, EUR per location via the placeholder 100 000 (= w · 100 000); 15 countries + 28 NUTS-1 regions",
               fill=MUTED, font=font(12))
    x0, y0 = map_img.width + 45, title_h + 10
    d.text((x0, y0), "cross-λ (EUR per location)", fill=INK, font=font(14, True))
    y = y0 + 32
    for color, label in zip(COLORS, LABELS):
        d.rectangle((x0, y, x0 + 26, y + 18), fill=color, outline=(80, 80, 80))
        d.text((x0 + 36, y - 1), label, fill=INK, font=font(14))
        y += 28
    y += 10
    lines = ["low λ = a location buys little travel", "high λ = a location buys much travel", ""]
    if FN == "LOGISTIC":
        lines += ["LOGISTIC λ is on its own scale: the", "cost c(t) is dimensionless, so λ per", "location is ~1/100 of the LINEAR one;", "compare areas, not functions.", ""]
    lines += ["Map: GeoDMS 20.19, NUTS 2021 (EPSG:3035);", "Portugal = mainland, Norway incl. Svalbard;",
              "FR/IT/SE/PL as NUTS-1 regions; grey: not", "in the study."]
    for line in lines:
        d.text((x0, y), line, fill=MUTED, font=font(11)); y += 17
    return fig


fig = compose(True)
out = os.path.join(HERE, "charts", f"cross_lambda_map_{FN}.png")
fig.save(out)
img_dir = os.path.join(HERE, "img")
if os.path.isdir(img_dir):
    fig.save(os.path.join(img_dir, f"cross_lambda_map_{FN}.png"))
slide = compose(False)
slide_out = os.path.join(HERE, "charts", f"cross_lambda_map_{FN}_slide.png")
slide.save(slide_out)
print("wrote", out, fig.size, "and", slide_out, slide.size)
