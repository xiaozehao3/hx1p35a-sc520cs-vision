#!/usr/bin/env python3
"""Generate a compact synchronous-ROM image of the OSD glyph table."""

from __future__ import annotations

import argparse
import json
import pathlib
import re


ENTRY_RE = re.compile(
    r"8'h([0-9a-fA-F]{2})\s*:\s*begin(.*?)(?=\n\s*8'h[0-9a-fA-F]{2}\s*:"
    r"\s*begin|\n\s*default:\s*glyph_row)",
    re.DOTALL,
)
ROW_RE = re.compile(r"4'd(\d+)\s*:\s*glyph_row\s*=\s*16'h([0-9a-fA-F]{4})")

SOURCE_ASCII_CODES = (0x31, 0x32, 0x33, 0x34, 0x3A, 0x4D, 0x64, 0x65, 0x6C, 0x6F)
ASCII_CODES = tuple(ord(char) for char in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ") + (
    0x3A,
    0x64,
    0x65,
    0x6C,
    0x6F,
)
PLATE_HANZI = "京沪津渝冀晋蒙辽吉黑苏浙皖闽赣鲁豫鄂湘粤桂琼川贵云藏陕甘青宁新学警港澳挂使领民航危险品"
PLATE_CODES = {
    char: (0xD9 + index if index < 39 else 0x1C + index - 39)
    for index, char in enumerate(PLATE_HANZI)
}
CHINESE_FIRST = 0x80
CHINESE_LAST = 0xD8
EXTRA_CHINESE_FIRST = 0xD9
EXTRA_CHINESE_LAST = 0xFF
PC_CONTROL_FIRST = 0x1C
PC_CONTROL_LAST = 0x1F
CHINESE_COUNT = EXTRA_CHINESE_LAST - CHINESE_FIRST + 1
PC_CONTROL_COUNT = PC_CONTROL_LAST - PC_CONTROL_FIRST + 1
GLYPH_COUNT = CHINESE_COUNT + PC_CONTROL_COUNT + len(ASCII_CODES)
ASCII_BASE = CHINESE_COUNT + PC_CONTROL_COUNT + 1
ROM_DEPTH = (GLYPH_COUNT + 1) * 16


def glyph_index(code: int) -> int:
    if CHINESE_FIRST <= code <= EXTRA_CHINESE_LAST:
        return code - CHINESE_FIRST + 1
    if PC_CONTROL_FIRST <= code <= PC_CONTROL_LAST:
        return CHINESE_COUNT + code - PC_CONTROL_FIRST + 1
    if code in ASCII_CODES:
        return ASCII_BASE + ASCII_CODES.index(code)
    return 0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, help="path to my_osd.v")
    parser.add_argument("--out", required=True, help="output hex memory file")
    parser.add_argument(
        "--extra-glyphs",
        default=str(pathlib.Path(__file__).with_name("plate_extra_glyphs.json")),
        help="JSON bitmap rows for the added plate glyphs",
    )
    args = parser.parse_args()

    source = pathlib.Path(args.source).read_text(encoding="utf-8", errors="strict")
    module_start = source.find("module osd_char_lib")
    case_start = source.find("case (c)", module_start)
    if module_start < 0 or case_start < 0:
        raise SystemExit("osd_char_lib glyph table not found")

    table_source = source[case_start:]
    glyphs: dict[int, list[int]] = {}
    for match in ENTRY_RE.finditer(table_source):
        code = int(match.group(1), 16)
        rows = [0] * 16
        rows_seen: set[int] = set()
        for row_match in ROW_RE.finditer(match.group(2)):
            row = int(row_match.group(1), 10)
            if not 0 <= row < 16:
                raise SystemExit(f"glyph 0x{code:02X} has invalid row {row}")
            if row in rows_seen:
                raise SystemExit(f"glyph 0x{code:02X} repeats row {row}")
            rows_seen.add(row)
            rows[row] = int(row_match.group(2), 16)
        if rows_seen != set(range(16)):
            raise SystemExit(f"glyph 0x{code:02X} does not define all 16 rows")
        if code in glyphs:
            raise SystemExit(f"duplicate glyph 0x{code:02X}")
        glyphs[code] = rows

    expected_source = set(range(CHINESE_FIRST, CHINESE_LAST + 1)) | set(SOURCE_ASCII_CODES)
    if set(glyphs) != expected_source:
        missing = sorted(expected_source - set(glyphs))
        extra = sorted(set(glyphs) - expected_source)
        raise SystemExit(f"source glyph map mismatch; missing={missing}, extra={extra}")

    extra_data = json.loads(pathlib.Path(args.extra_glyphs).read_text(encoding="utf-8"))
    extra_glyphs = {
        int(code, 16): [int(row, 16) for row in rows]
        for code, rows in extra_data.get("glyphs", {}).items()
    }
    source_codes = set(glyphs)
    required_codes = set(PLATE_CODES.values()) | set(ASCII_CODES)
    expected_extra = required_codes - source_codes
    if set(extra_glyphs) != expected_extra:
        missing = sorted(expected_extra - set(extra_glyphs))
        extra = sorted(set(extra_glyphs) - expected_extra)
        raise SystemExit(f"extra glyph map mismatch; missing={missing}, extra={extra}")
    for code, rows in extra_glyphs.items():
        if len(rows) != 16 or any(not 0 <= row <= 0xFFFF for row in rows):
            raise SystemExit(f"glyph 0x{code:02X} must contain 16 16-bit rows")
    glyphs.update(extra_glyphs)

    memory = [0] * ROM_DEPTH
    for code, rows in glyphs.items():
        index = glyph_index(code)
        if index == 0:
            raise SystemExit(f"character code 0x{code:02X} has no ROM address")
        for row, bits in enumerate(rows):
            memory[index * 16 + row] = bits

    output = pathlib.Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="ascii", newline="\n") as stream:
        stream.writelines(f"{word:04x}\n" for word in memory)

    written = [int(line, 16) for line in output.read_text(encoding="ascii").splitlines()]
    if written != memory:
        raise SystemExit("generated ROM readback does not match parsed source table")
    for code in range(256):
        index = glyph_index(code)
        expected_rows = glyphs.get(code, [0] * 16)
        if written[index * 16:(index + 1) * 16] != expected_rows:
            raise SystemExit(f"ROM address mapping mismatch for character 0x{code:02X}")

    print(f"glyphs: {len(glyphs)}; words: {len(memory)}; width: 16 bits")
    print(f"initialized glyph words: {(GLYPH_COUNT + 1) * 16}")
    print("source-to-ROM mapping check: PASS (256 character codes x 16 rows)")
    print(f"wrote: {output}")


if __name__ == "__main__":
    main()
