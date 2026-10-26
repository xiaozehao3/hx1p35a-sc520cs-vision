# -*- coding: utf-8 -*-
"""生成应用图标 packaging/app.ico（蓝底车牌风格，含多分辨率）。

运行：python packaging/app_icon.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BASE = Path(__file__).resolve().parent
ROOT = BASE.parent
VENDOR_FONT = (
    ROOT / "vendor" / "Chinese_license_plate_detection_recognition-main" / "fonts" / "platech.ttf"
)
OUT_ICO = BASE / "app.ico"
OUT_PNG = BASE / "app_preview.png"
SIZES = [16, 24, 32, 48, 64, 128, 256]


def build(size: int = 256) -> Image.Image:
    scale = size / 256.0

    def sc(*values: float):
        return [v * scale for v in values]

    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    # 车牌底板 + 白色外框
    draw.rounded_rectangle(
        sc(12, 64, 244, 192),
        radius=26 * scale,
        fill=(20, 82, 186, 255),
        outline=(255, 255, 255, 255),
        width=max(2, int(round(11 * scale))),
    )
    # 内嵌细描边，模拟车牌边框
    draw.rounded_rectangle(
        sc(26, 78, 230, 178),
        radius=16 * scale,
        outline=(255, 255, 255, 170),
        width=max(1, int(round(3 * scale))),
    )

    text = "车牌"
    try:
        font = ImageFont.truetype(str(VENDOR_FONT), int(round(94 * scale)))
    except OSError:
        font = ImageFont.load_default()
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    if right - left <= 0:  # 字体缺少中文字形时退化为两个圆点
        for cx in (size * 0.38, size * 0.62):
            r = size * 0.06
            draw.ellipse([cx - r, size * 0.5 - r, cx + r, size * 0.5 + r], fill=(255, 255, 255, 255))
    else:
        draw.text(
            ((size - (right - left)) / 2 - left, (size - (bottom - top)) / 2 - top),
            text,
            font=font,
            fill=(255, 255, 255, 255),
        )
    return image


if __name__ == "__main__":
    base = build(256)
    base.save(OUT_ICO, format="ICO", sizes=[(s, s) for s in SIZES])
    base.save(OUT_PNG)
    print("wrote", OUT_ICO)
    print("wrote", OUT_PNG)
