#!/usr/bin/env python3
"""Draw the app icon (the tilted feather of `DesignSystem` › Brand, white on
the accent) for every platform, and Android's vector icons.

Usage:
    python3 tools/gen_icons.py

Needs Pillow (python3 -m pip install pillow). The feather is the same path
data as `PiumaIcon.compose` and the canvas: a 64×64 grid, drawn through
translate(32 32.5) rotate(35) scale(1.04) translate(-32 -32).
"""

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
RES = APP / "android" / "app" / "src" / "main" / "res"
# The Wear OS app (`wear/`) wears the same icon; the watch crops it round.
WEAR_RES = ROOT / "wear" / "android" / "app" / "src" / "main" / "res"
ACCENT = json.loads((ROOT / "design" / "tokens.json").read_text())["color"]["light"]["accent"]
WHITE = "#FFFFFF"

OUTLINE = (
    "M32 8C41.5 12.5 45.5 22 44.5 31C43.6 38.5 38.5 43 32 45C25.5 43 21.5 39.5 "
    "20.6 35L27 30.5L20.2 27.5C20.5 18.5 24.5 11.5 32 8Z"
)
SHAFT = "M32 22V57"

# The canvas stroke; below 48px it gets thicker, as `DesignSystem` says.
STROKE = 4.33


def stroke_for(px: int) -> float:
    return STROKE if px >= 48 else STROKE + (48 - px) / 48 * 2.4


# ---------------------------------------------------------------- geometry


def parse(d: str) -> list[list[tuple[float, float]]]:
    """The subpaths of `d` (M, L, V, C, Z only) as points, curves flattened."""
    tokens = d.replace("Z", " Z ").replace("C", " C ").replace("L", " L ")
    tokens = tokens.replace("M", " M ").replace("V", " V ").split()
    out: list[list[tuple[float, float]]] = []
    i, cmd = 0, ""
    x = y = 0.0
    while i < len(tokens):
        t = tokens[i]
        if t in "MLVCZ":
            cmd = t
            i += 1
            if cmd == "Z":
                out[-1].append(out[-1][0])
            continue
        if cmd == "M":
            x, y = float(t), float(tokens[i + 1])
            out.append([(x, y)])
            i += 2
            cmd = "L"
        elif cmd == "L":
            x, y = float(t), float(tokens[i + 1])
            out[-1].append((x, y))
            i += 2
        elif cmd == "V":
            y = float(t)
            out[-1].append((x, y))
            i += 1
        elif cmd == "C":
            p = [float(v) for v in tokens[i : i + 6]]
            x0, y0 = x, y
            for s in range(1, 25):
                u = s / 24
                a, b, c, e = (1 - u) ** 3, 3 * u * (1 - u) ** 2, 3 * u * u * (1 - u), u**3
                out[-1].append(
                    (
                        a * x0 + b * p[0] + c * p[2] + e * p[4],
                        a * y0 + b * p[1] + c * p[3] + e * p[5],
                    )
                )
            x, y = p[4], p[5]
            i += 6
    return out


def feather() -> list[list[tuple[float, float]]]:
    """Both strokes on the 64×64 tile, with the icon's own transform."""
    r = math.radians(35)
    cos, sin = math.cos(r), math.sin(r)

    def move(p: tuple[float, float]) -> tuple[float, float]:
        x, y = (p[0] - 32) * 1.04, (p[1] - 32) * 1.04
        return (x * cos - y * sin + 32, x * sin + y * cos + 32.5)

    return [[move(p) for p in sub] for d in (OUTLINE, SHAFT) for sub in parse(d)]


# ---------------------------------------------------------------- raster

SUPER = 8  # drawn this many times larger, then scaled down: smooth edges


def draw(
    px: int,
    *,
    tile: float = 1.0,
    radius: float = 0.22,
    background: str | None = ACCENT,
    ink: str = WHITE,
) -> Image.Image:
    """The icon at `px`: the 64-grid tile takes `tile` of the side, centered,
    with corners of `radius` of its side (0 for square)."""
    big = px * SUPER
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    g = ImageDraw.Draw(img)
    side = big * tile
    left = (big - side) / 2
    if background:
        g.rounded_rectangle(
            (left, left, left + side, left + side),
            radius=side * radius,
            fill=background,
        )
    k = side / 64
    width = stroke_for(round(px * tile)) * k
    for sub in feather():
        pts = [(left + x * k, left + y * k) for x, y in sub]
        g.line(pts, fill=ink, width=round(width), joint="curve")
        for x, y in (pts[0], pts[-1]):
            g.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=ink)
    return img.resize((px, px), Image.LANCZOS)


def flat(img: Image.Image) -> Image.Image:
    """No transparency, as the App Store wants."""
    out = Image.new("RGB", img.size, ACCENT)
    out.paste(img, mask=img)
    return out


# ---------------------------------------------------------------- vectors


def vector(viewport: int, size: str, color: str, place: str, stroke: float) -> str:
    """An Android vector drawable of the feather, the tile placed by `place`."""
    paths = "\n".join(
        f'            <path android:pathData="{d}" android:strokeColor="{color}"\n'
        f'                android:strokeWidth="{stroke}" android:strokeLineCap="round"\n'
        f'                android:strokeLineJoin="round" />'
        for d in (OUTLINE, SHAFT)
    )
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!-- GENERATED by tools/gen_icons.py. Do not edit by hand. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="{size}"
    android:height="{size}"
    android:viewportWidth="{viewport}"
    android:viewportHeight="{viewport}">
    <group {place}>
        <group android:pivotX="32" android:pivotY="32" android:rotation="35"
            android:scaleX="1.04" android:scaleY="1.04" android:translateY="0.5">
{paths}
        </group>
    </group>
</vector>
"""


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def main() -> None:
    for res in (RES, WEAR_RES):
        # Android: adaptive (8.0+) and themed (13+) from vectors; the 108dp
        # canvas shows its middle 72dp, which the 64 tile fills.
        write(
            res / "drawable" / "ic_launcher_foreground.xml",
            vector(
                108,
                "108dp",
                WHITE,
                'android:scaleX="1.125" android:scaleY="1.125" '
                'android:translateX="18" android:translateY="18"',
                STROKE,
            ),
        )
        write(
            res / "values" / "ic_launcher_background.xml",
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- GENERATED by tools/gen_icons.py. Do not edit by hand. -->\n"
            f'<resources>\n    <color name="ic_launcher_background">{ACCENT}</color>\n</resources>\n',
        )
        write(
            res / "mipmap-anydpi-v26" / "ic_launcher.xml",
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- GENERATED by tools/gen_icons.py. Do not edit by hand. -->\n"
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background" />\n'
            '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
            '    <monochrome android:drawable="@drawable/ic_launcher_foreground" />\n'
            "</adaptive-icon>\n",
        )
        # The status bar shows only the shape: the feather alone, thicker.
        write(
            res / "drawable" / "ic_notification.xml",
            vector(64, "24dp", WHITE, "", 5.6),
        )
        # Before 8.0: the tile itself.
        for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
            draw(px).save(res / f"mipmap-{folder}" / "ic_launcher.png")

    # iOS: square and opaque; the system rounds the corners.
    for png in (APP / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset").glob("*.png"):
        px = Image.open(png).size[0]
        flat(draw(px, radius=0)).save(png)

    # macOS: the tile sits inside the canvas, with the usual shadow room.
    for png in (APP / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset").glob("*.png"):
        px = Image.open(png).size[0]
        draw(px, tile=824 / 1024, radius=185 / 824).save(png)

    # Windows: one .ico with the usual sizes.
    sizes = [16, 24, 32, 48, 64, 128, 256]
    draw(256).save(APP / "windows" / "runner" / "resources" / "app_icon.ico", sizes=[(s, s) for s in sizes])


if __name__ == "__main__":
    main()
