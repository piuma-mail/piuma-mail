#!/usr/bin/env python3
"""Generate the README covers from existing branding (requires fonttools).

Only writes docs/images/cover.svg and cover-dark.svg; never changes app icons
or design tokens.
"""

import ast
import json
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
TOKENS = json.loads((ROOT / "design/tokens.json").read_text())
# File name, token theme and the background's description for each variant.
VARIANTS = (
    ("cover.svg", "light", "warm neutral"),
    ("cover-dark.svg", "dark", "dark neutral"),
)


def icon_constants():
    """Read the existing feather without importing the raster icon generator."""
    tree = ast.parse((ROOT / "tools/gen_icons.py").read_text())
    return {
        node.targets[0].id: ast.literal_eval(node.value)
        for node in tree.body
        if isinstance(node, ast.Assign)
        and isinstance(node.targets[0], ast.Name)
        and node.targets[0].id in {"OUTLINE", "SHAFT", "STROKE"}
    }


def lettering(words, size, x, y, color, weight="Regular", tracking=0):
    """Outline bundled Geist glyphs so GitHub needs no installed/web fonts."""
    with TTFont(ROOT / f"app/assets/fonts/Geist-{weight}.ttf") as font:
        glyphs = font.getGlyphSet()
        cmap = font.getBestCmap()
        scale = size / font["head"].unitsPerEm
        cursor = 0
        paths = []
        for char in words:
            glyph = glyphs[cmap[ord(char)]]
            pen = SVGPathPen(glyphs)
            glyph.draw(pen)
            paths.append(
                f'<path transform="translate({cursor:.3f} 0)" d="{pen.getCommands()}"/>'
            )
            cursor += glyph.width + tracking / scale
        return (
            f'<g fill="{color}" transform="translate({x} {y}) scale({scale} {-scale})">'
            + "".join(paths)
            + "</g>"
        )


def cover(icon, colors, background):
    """One cover in one theme; the layout is the same in light and dark."""
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 360" '
        'role="img" aria-labelledby="title desc">',
        '<title id="title">Piuma Mail — Mail, made light.</title>',
        '<desc id="desc">A clean, minimal, open-source email client in development. '
        f'The existing feather icon on a {background} background.</desc>',
        f'<rect width="1200" height="360" rx="{TOKENS["radius"]["panel"]}" fill="{colors["bg"]}"/>',
        f'<rect x="64" y="56" width="64" height="64" rx="14.08" fill="{colors["accent"]}"/>',
        '<g transform="translate(64 56)">',
        '<g transform="translate(32 32.5) rotate(35) scale(1.04) translate(-32 -32)" '
        f'fill="none" stroke="{colors["onAccent"]}" stroke-width="{icon["STROKE"]}" '
        'stroke-linecap="round" stroke-linejoin="round">',
        f'<path d="{icon["OUTLINE"]}"/><path d="{icon["SHAFT"]}"/>',
        '</g></g>',
        lettering("IN DEVELOPMENT", 18, 152, 95, colors["muted"], "Medium", 1.2),
        lettering("Mail, made light.", 72, 64, 224, colors["fg"], "SemiBold", -2),
        lettering("Open source. Clean. Minimal.", 25, 66, 292, colors["accentText"]),
        '</svg>\n',
    ]
    return "\n".join(parts)


def main():
    icon = icon_constants()
    for name, theme, background in VARIANTS:
        svg = cover(icon, TOKENS["color"][theme], background)
        (ROOT / "docs/images" / name).write_text(svg)


if __name__ == "__main__":
    main()
