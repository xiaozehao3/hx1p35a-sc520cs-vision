#!/usr/bin/env python3
"""把 OSD 字模表（osd_char_lib 的 case 表）渲染成 PNG，便于人工辨认字形。

用法：
  python render_osd_glyphs.py --source ../user_source/hdl_source/my_algo/my_osd.v \
                              --out ../td_project_osd_fix_rebuild_20261009/doc/refs/osd_glyphs_live.png
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

from PIL import Image, ImageDraw

ENTRY_RE = re.compile(r"8'h([0-9A-Fa-f]{2})\s*:\s*begin(.*?)"
                      r"(?=8'h[0-9A-Fa-f]{2}\s*:\s*begin|endcase)", re.DOTALL)
ROW_RE = re.compile(r"4'd(\d+)\s*:\s*glyph_row\s*=\s*16'h([0-9A-Fa-f]{4})")


def parse(source: Path) -> dict[int, list[int]]:
    text = source.read_text(encoding="utf-8", errors="replace")
    start = text.find("module osd_char_lib")
    case_start = text.find("case (c)", start)
    if start < 0 or case_start < 0:
        raise SystemExit("osd_char_lib glyph table not found")
    glyphs: dict[int, list[int]] = {}
    for match in ENTRY_RE.finditer(text[case_start:]):
        code = int(match.group(1), 16)
        rows = [0] * 16
        seen = 0
        for row_match in ROW_RE.finditer(match.group(2)):
            row = int(row_match.group(1), 10)
            if 0 <= row < 16:
                rows[row] = int(row_match.group(2), 16)
                seen += 1
        if seen >= 8:
            glyphs[code] = rows
    return glyphs


def render(glyphs: dict[int, list[int]], out: Path) -> None:
    codes = sorted(glyphs)
    scale, label_h, cols = 5, 20, 8
    cell = 16 * scale
    cw, ch = cell + 8, cell + label_h
    rows_n = (len(codes) + cols - 1) // cols
    img = Image.new("RGB", (cols * cw + 8, rows_n * ch + 8), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    for i, code in enumerate(codes):
        gx = (i % cols) * cw + 4
        gy = (i // cols) * ch + 4
        label = "0x%02X" % code
        if 0x20 <= code < 0x7F:
            label += " '%s'" % chr(code)
        draw.text((gx, gy), label, fill=(200, 0, 0))
        for r in range(16):
            v = glyphs[code][r]
            for b in range(16):
                if (v >> (15 - b)) & 1:
                    draw.rectangle([gx + b * scale, gy + label_h + r * scale,
                                    gx + b * scale + scale - 1, gy + label_h + r * scale + scale - 1],
                                   fill=(0, 0, 0))
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print("glyphs=%d codes=%s" % (len(codes), ' '.join('%02X' % c for c in codes)))
    print("wrote", out, img.size)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    render(parse(Path(args.source)), Path(args.out))


if __name__ == "__main__":
    main()
