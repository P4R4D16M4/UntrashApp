#!/usr/bin/env python3
"""App icons from the Untrash logo mark (assets/logo-mark-512.png).

  python3 tool/make_icons.py

Look of the Desk's icon tiles (UntrashOS design/assets/icons, the
"untrash icons" set): the mark on a near-black blue-grey tile with a
faint light edge. Writes
- Android: legacy mipmaps (rounded tile), the adaptive icon (background
  colour, foreground mark in the 66 dp safe zone, monochrome layer for
  themed icons) and the 512 px store icon (assets/icon-512.png),
- iOS: every size of AppIcon.appiconset (square, no alpha; iOS rounds).
Needs Pillow. The outputs are checked in; run again after a logo change.
"""
import json
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RES = os.path.join(ROOT, "android/app/src/main/res")
IOS = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
BG = (13, 17, 21)            # --ut-bg-1
TILE = (18, 23, 28)          # --ut-bg-2
EDGE = (255, 255, 255, 30)   # --ut-line-2
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def mark():
    """The logo mark, trimmed to what is visible (its edge has alpha 1)."""
    im = Image.open(os.path.join(ROOT, "assets/logo-mark-512.png")).convert("RGBA")
    a = im.getchannel("A").point(lambda v: v if v > 8 else 0)
    im.putalpha(a)
    return im.crop(a.getbbox())


def fit(im, box):
    """im scaled to fit a box x box square, centred on a transparent canvas."""
    s = box / max(im.size)
    m = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    c = Image.new("RGBA", (box, box), (0, 0, 0, 0))
    c.alpha_composite(m, ((box - m.width) // 2, (box - m.height) // 2))
    return c


def glow(art, size):
    """A soft teal glow under the mark, like the Desk's focus glow."""
    a = art.getchannel("A").filter(ImageFilter.GaussianBlur(size * 0.06))
    g = Image.new("RGBA", art.size, (5, 199, 175, 0))
    g.putalpha(a.point(lambda v: v * 0.35))
    return g


def tile(size, rounded=True, scale=0.68):
    """Square icon: tile, edge, glow, mark (4x supersampled)."""
    S = size * 4
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0) if rounded else BG + (255,))
    d = ImageDraw.Draw(im)
    r = round(S * 0.19) if rounded else 0          # 19 % like the Desk's tiles
    inset = round(S * 0.04) if rounded else 0
    d.rounded_rectangle([inset, inset, S - 1 - inset, S - 1 - inset], r, fill=TILE + (255,),
                        outline=EDGE if rounded else None, width=max(1, S // 128))
    art = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    m = fit(mark(), round(S * scale))
    art.alpha_composite(m, ((S - m.width) // 2, (S - m.height) // 2))
    im.alpha_composite(glow(art, S))
    im.alpha_composite(art)
    return im.resize((size, size), Image.LANCZOS)


def foreground(size):
    """Adaptive foreground: 108 dp canvas, mark inside the 66 dp safe zone."""
    S = size * 4
    art = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    m = fit(mark(), round(S * 60 / 108))
    art.alpha_composite(m, ((S - m.width) // 2, (S - m.height) // 2))
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.alpha_composite(glow(art, S))
    out.alpha_composite(art)
    return out.resize((size, size), Image.LANCZOS)


def monochrome(size):
    """Themed-icon layer: the mark's shape in white (Android tints it); the
    dark parts of the mark stay open so the drive bays remain readable."""
    S = size * 4
    fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    m = fit(mark(), round(S * 60 / 108))
    fg.alpha_composite(m, ((S - m.width) // 2, (S - m.height) // 2))
    fg = fg.resize((size, size), Image.LANCZOS)
    a = ImageChops.multiply(fg.getchannel("A").point(lambda v: 255 if v > 40 else 0),
                            fg.convert("L").point(lambda v: 255 if v > 28 else 0))
    out = Image.new("RGBA", fg.size, (255, 255, 255, 0))
    out.putalpha(a)
    return out


def main():
    for name, f in DENSITIES.items():
        d = os.path.join(RES, "mipmap-" + name)
        os.makedirs(d, exist_ok=True)
        tile(round(48 * f)).save(os.path.join(d, "ic_launcher.png"))
        foreground(round(108 * f)).save(os.path.join(d, "ic_launcher_foreground.png"))
        monochrome(round(108 * f)).save(os.path.join(d, "ic_launcher_monochrome.png"))
    v26 = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(v26, exist_ok=True)
    open(os.path.join(v26, "ic_launcher.xml"), "w").write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n')
    open(os.path.join(RES, "values", "ic_launcher_background.xml"), "w").write(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#%02X%02X%02X</color>\n</resources>\n' % TILE)
    tile(512).save(os.path.join(ROOT, "assets/icon-512.png"))
    for img in json.load(open(os.path.join(IOS, "Contents.json")))["images"]:
        px = round(float(img["size"].split("x")[0]) * int(img["scale"][0]))
        tile(px, rounded=False, scale=0.62).convert("RGB").save(os.path.join(IOS, img["filename"]))
    print("icons written")


if __name__ == "__main__":
    main()
