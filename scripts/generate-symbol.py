#!/usr/bin/env python3
"""
generate-symbol.py — Renders TinyMark's M+ibeam symbol as a 355x355 PNG.

Uses SF Compact Rounded for the "M" letter and draws the ibeam cursor
from the original SVG path data. Output matches SF Symbol proportions
used by the other Tiny* apps.

Usage:
  python3 scripts/generate-symbol.py [output_path]
  Default output: Sources/TinyMark/Resources/AppIcon.icon/Assets/symbol.png
"""

import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Pillow required: pip3 install Pillow")
    sys.exit(1)

SIZE = 355
FONT_PATH = "/System/Library/Fonts/SFCompactRounded.ttf"

# Original SVG dimensions: 139x149
SVG_W, SVG_H = 139, 149
TARGET_W = 185  # tuned to match other SF Symbol icon sizes


def render_symbol(output_path: str):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    scale = TARGET_W / SVG_W
    ox = (SIZE - SVG_W * scale) / 2
    oy = (SIZE - SVG_H * scale) / 2

    # M letter
    font = ImageFont.truetype(FONT_PATH, int(124 * scale))
    bbox = font.getbbox("M")
    my = oy + (118 * scale) - (bbox[3] - bbox[1]) - bbox[1]
    draw.text((ox, my), "M", fill="white", font=font)

    # Ibeam cursor (from SVG path coordinates, scaled)
    # Top serif
    draw.rectangle(
        [ox + 100.1 * scale, oy + 13 * scale,
         ox + 134.3 * scale, oy + 19.8 * scale],
        fill="white",
    )
    # Bottom serif
    draw.rectangle(
        [ox + 100.1 * scale, oy + 128.1 * scale,
         ox + 134.3 * scale, oy + 135 * scale],
        fill="white",
    )
    # Vertical bar
    draw.rectangle(
        [ox + 113.2 * scale, oy + 19.8 * scale,
         ox + 121.1 * scale, oy + 128.1 * scale],
        fill="white",
    )

    img.save(output_path)
    content = img.getbbox()
    print(f"Saved {output_path}  (content: {content[2]-content[0]}x{content[3]-content[1]}px)")


if __name__ == "__main__":
    default = str(
        Path(__file__).resolve().parent.parent
        / "Sources/TinyMark/Resources/AppIcon.icon/Assets/symbol.png"
    )
    out = sys.argv[1] if len(sys.argv) > 1 else default
    render_symbol(out)
