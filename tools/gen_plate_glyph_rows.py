#!/usr/bin/env python3
"""Rasterize glyphs missing from the shared OSD font table into JSON rows."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "pc_plate_tool"))

from plate_link import CHARACTER_CODES, FPGA_HANZI  # noqa: E402


SOURCE_CODES = {0x31, 0x32, 0x33, 0x34, 0x3A, 0x4D, 0x64, 0x65, 0x6C, 0x6F}
PLATE_ASCII = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", default=r"C:\Windows\Fonts\msyh.ttc")
    parser.add_argument(
        "--out", default=str(ROOT / "tools" / "plate_extra_glyphs.json")
    )
    args = parser.parse_args()

    from PIL import Image, ImageDraw, ImageFont

    font = ImageFont.truetype(args.font, 16)
    chars_by_code = {CHARACTER_CODES[char]: char for char in FPGA_HANZI}
    chars_by_code.update({ord(char): char for char in PLATE_ASCII})
    extra_codes = {code for code in chars_by_code if code not in SOURCE_CODES}
    glyphs: dict[str, list[str]] = {}
    for code in sorted(extra_codes):
        char = chars_by_code[code]
        image = Image.new("L", (16, 16), 0)
        ImageDraw.Draw(image).text((8, 8), char, fill=255, font=font, anchor="mm")
        rows = []
        for y in range(16):
            bits = 0
            for x in range(16):
                if image.getpixel((x, y)) >= 96:
                    bits |= 1 << (15 - x)
            rows.append(f"{bits:04X}")
        if not any(int(row, 16) for row in rows):
            raise SystemExit(f"font produced a blank glyph for {char!r} (0x{code:02X})")
        glyphs[f"{code:02X}"] = rows

    output = pathlib.Path(args.out)
    output.write_text(
        json.dumps(
            {"font": pathlib.Path(args.font).name, "glyphs": glyphs},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"wrote {len(glyphs)} glyphs to {output}")


if __name__ == "__main__":
    main()
