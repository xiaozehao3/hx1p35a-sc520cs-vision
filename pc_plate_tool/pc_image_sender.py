"""Send one still image to the FPGA HDMI image page."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path
from typing import Optional

from PIL import Image

try:
    import serial
except ImportError as exc:  # pragma: no cover - environment dependent
    raise SystemExit("缺少 pyserial，请在 pc_plate_tool/.venv 中运行") from exc


WIDTH = 160
HEIGHT = 90
BAUD = 115_200


def crc16_ccitt(data: bytes) -> int:
    value = 0xFFFF
    for byte in data:
        value ^= byte << 8
        for _ in range(8):
            value = ((value << 1) ^ 0x1021) & 0xFFFF if value & 0x8000 else (value << 1) & 0xFFFF
    return value


def rgb565_payload(path: Path) -> bytes:
    with Image.open(path) as image:
        return rgb565_payload_from_image(image)


def rgb565_payload_from_image(image: Image.Image, plate_text: Optional[str] = None) -> bytes:
    image = image.convert("RGB").resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
    if plate_text:
        from PIL import ImageDraw, ImageFont

        draw = ImageDraw.Draw(image)
        draw.rectangle((0, 0, WIDTH - 1, 14), fill=(15, 31, 48))
        font_candidates = (
            Path(__file__).parent
            / "vendor"
            / "Chinese_license_plate_detection_recognition-main"
            / "fonts"
            / "platech.ttf",
            Path("C:/Windows/Fonts/msyh.ttc"),
            Path("C:/Windows/Fonts/simhei.ttf"),
        )
        font_path = next((path for path in font_candidates if path.is_file()), None)
        font = ImageFont.truetype(str(font_path), 10) if font_path else ImageFont.load_default()
        draw.text((3, 1), plate_text[:16], fill=(255, 255, 255), font=font)

    payload = bytearray()
    for red, green, blue in image.getdata():
        pixel = ((red & 0xF8) << 8) | ((green & 0xFC) << 3) | (blue >> 3)
        payload.extend((pixel & 0xFF, pixel >> 8))
    return bytes(payload)


def image_packet_from_bgr_array(image, sequence: int = 0, plate_text: Optional[str] = None) -> bytes:
    if getattr(image, "ndim", 0) != 3 or image.shape[2] != 3:
        raise ValueError("标注图必须是 HxWx3 的 BGR 图像")
    rgb = image[:, :, ::-1].copy()
    return build_packet(rgb565_payload_from_image(Image.fromarray(rgb), plate_text), sequence)


def build_packet(payload: bytes, sequence: int) -> bytes:
    if len(payload) != WIDTH * HEIGHT * 2:
        raise ValueError("RGB565 数据长度错误")
    header = bytes((
        0x55, 0xAA, 0x5A, 0xA5, 0x01, 0x01,
        WIDTH & 0xFF, WIDTH >> 8, HEIGHT & 0xFF, HEIGHT >> 8,
        sequence & 0xFF, (sequence >> 8) & 0xFF,
        (sequence >> 16) & 0xFF, (sequence >> 24) & 0xFF,
    ))
    crc = crc16_ccitt(payload)
    return header + payload + bytes((crc & 0xFF, crc >> 8, 0x0D, 0x0A))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="向 FPGA HDMI 发送一张静态图片")
    parser.add_argument("--port", required=True, help="CH340 串口，例如 COM7")
    parser.add_argument("--input", required=True, type=Path, help="待发送图片")
    parser.add_argument("--baud", type=int, default=BAUD)
    parser.add_argument("--sequence", type=int, default=0)
    args = parser.parse_args(argv)

    if args.baud != BAUD:
        raise SystemExit(
            f"当前 FPGA 图片接收器固定为 {BAUD} baud 8N1；"
            "不要使用旧图传命令中的 2000000 baud。"
        )

    payload = rgb565_payload(args.input)
    packet = build_packet(payload, args.sequence)
    print(f"图片: {args.input}")
    print(f"尺寸: {WIDTH}x{HEIGHT}, 数据: {len(payload)} 字节, 总帧: {len(packet)} 字节")
    print(f"串口: {args.port}, {args.baud} baud, 预计约 {len(packet) * 10 / args.baud:.2f} 秒")

    try:
        with serial.Serial(
            args.port,
            args.baud,
            bytesize=8,
            parity="N",
            stopbits=1,
            timeout=1,
            xonxoff=False,
            rtscts=False,
            dsrdtr=False,
        ) as link:
            started = time.perf_counter()
            link.write(packet)
            link.flush()
            elapsed = time.perf_counter() - started
    except serial.SerialException as exc:
        print(f"串口打开/发送失败: {exc}", file=sys.stderr)
        return 2

    print(f"发送完成: {elapsed:.2f} 秒。请等待 FPGA 完成 CRC 校验后查看 HDMI。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
