"""Generate app icons for all platforms from assets/images/logo/hc.png (WebP)."""
import json
import os
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "assets", "images", "logo", "hc.png")

img = Image.open(SRC)
print("source:", img.format, img.size, img.mode)
if img.mode != "RGBA":
    img = img.convert("RGBA")

def resized(size):
    return img.resize((size, size), Image.LANCZOS)

# ── Windows: multi-size .ico ────────────────────────────────────────────
ico_path = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
resized(256).save(ico_path, format="ICO",
                  sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
                         (64, 64), (128, 128), (256, 256)])
print("windows ico:", ico_path)

# ── Android: mipmap-*/ic_launcher.png ───────────────────────────────────
android_sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
res_dir = os.path.join(ROOT, "android", "app", "src", "main", "res")
for d, size in android_sizes.items():
    out = os.path.join(res_dir, d, "ic_launcher.png")
    resized(size).save(out, format="PNG")
    print("android:", out, size)

# ── iOS: AppIcon.appiconset per Contents.json ───────────────────────────
appiconset = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
with open(os.path.join(appiconset, "Contents.json"), "r", encoding="utf-8") as f:
    contents = json.load(f)
def parse_size(s):
    """'20x20' or '20' -> 20.0"""
    return float(str(s).split("x")[0])

def parse_scale(s):
    """'2x' or 2 -> 2.0"""
    return float(str(s).replace("x", "") or 1)

for entry in contents.get("images", []):
    name = entry.get("filename")
    scale = entry.get("scale")
    point = entry.get("expected-size") or entry.get("size")
    if not name or scale is None or point is None:
        continue
    size = int(round(parse_size(point) * parse_scale(scale)))
    out = os.path.join(appiconset, name)
    resized(size).save(out, format="PNG")
    print("ios:", name, size)

# ── Web: Icon-192 / Icon-512 / favicon ──────────────────────────────────
web_dir = os.path.join(ROOT, "web")
if os.path.isdir(web_dir):
    for name, size in (("Icon-192.png", 192), ("Icon-512.png", 512), ("favicon.png", 16)):
        out = os.path.join(web_dir, "icons", name)
        if os.path.isdir(os.path.dirname(out)):
            resized(size).save(out, format="PNG")
            print("web:", out, size)

print("done")
