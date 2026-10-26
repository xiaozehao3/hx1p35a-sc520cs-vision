#!/usr/bin/env python3
"""接收 FPGA K2 图传模式发送的 160x90 RGB565 图像。

协议由 user_source/hdl_source/pc_image_uart_tx.v 定义：
    55 AA 5A A5 01 01
    width(u16 little) height(u16 little) payload_len(u16 little)
    frame_seq(u32 little) payload RGB565 little-endian
    crc16-ccitt(payload, init=0xffff) little-endian 0D 0A

示例：
    python pc_image_receiver.py --port COM7 --baud 2000000 --scale 4
"""

from __future__ import annotations

import argparse
import pathlib
import queue
import sys
import threading
import time
from dataclasses import dataclass
from typing import Optional

try:
    import serial
    from serial.tools import list_ports
except ImportError as exc:  # pragma: no cover - friendly command-line error
    print("缺少 pyserial，请先执行：python -m pip install -r requirements.txt")
    raise SystemExit(2) from exc

MAGIC = b"\x55\xAA\x5A\xA5"
HEADER_LEN = 16
TAIL = b"\x0D\x0A"
MAX_PAYLOAD = 160 * 90 * 2


def crc16_ccitt(data: bytes, crc: int = 0xFFFF) -> int:
    """与 FPGA 端完全一致的 CRC16-CCITT。"""
    for value in data:
        crc ^= value << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


@dataclass
class ImageFrame:
    width: int
    height: int
    sequence: int
    payload: bytes


class FrameParser:
    """允许串口读到任意分片，并在丢字节后自动寻找下一帧。"""

    def __init__(self) -> None:
        self.buffer = bytearray()
        self.good_frames = 0
        self.bad_frames = 0
        self.bad_crc = 0

    def feed(self, data: bytes) -> list[ImageFrame]:
        self.buffer.extend(data)
        frames: list[ImageFrame] = []

        while True:
            if len(self.buffer) < len(MAGIC):
                break

            start = self.buffer.find(MAGIC)
            if start < 0:
                # 保留最后三个字节，防止帧头跨越本次串口 read。
                del self.buffer[:-3]
                break
            if start:
                del self.buffer[:start]

            if len(self.buffer) < HEADER_LEN:
                break

            version = self.buffer[4]
            frame_type = self.buffer[5]
            width = int.from_bytes(self.buffer[6:8], "little")
            height = int.from_bytes(self.buffer[8:10], "little")
            payload_len = int.from_bytes(self.buffer[10:12], "little")
            sequence = int.from_bytes(self.buffer[12:16], "little")

            # 当前硬件版本固定为 RGB565 160x90。遇到明显错误的头，
            # 只丢一个字节，然后重新搜索，避免卡死在坏帧上。
            if (
                version != 1
                or frame_type != 1
                or width <= 0
                or height <= 0
                or payload_len <= 0
                or payload_len > MAX_PAYLOAD
                or payload_len != width * height * 2
            ):
                del self.buffer[0]
                self.bad_frames += 1
                continue

            total_len = HEADER_LEN + payload_len + 2 + len(TAIL)
            if len(self.buffer) < total_len:
                break

            payload_start = HEADER_LEN
            payload_end = payload_start + payload_len
            payload = bytes(self.buffer[payload_start:payload_end])
            crc_wire = int.from_bytes(self.buffer[payload_end:payload_end + 2], "little")
            tail = bytes(self.buffer[payload_end + 2:total_len])
            del self.buffer[:total_len]

            if tail != TAIL:
                self.bad_frames += 1
                continue
            crc_calc = crc16_ccitt(payload)
            if crc_calc != crc_wire:
                self.bad_crc += 1
                continue

            self.good_frames += 1
            frames.append(ImageFrame(width, height, sequence, payload))

        return frames


def rgb565_to_image(frame: ImageFrame):
    """把小端 RGB565 payload 转为 Pillow RGB 图像。"""
    from PIL import Image

    expected = frame.width * frame.height * 2
    if len(frame.payload) != expected:
        raise ValueError(f"payload 长度错误：{len(frame.payload)} != {expected}")

    pixels = []
    payload = frame.payload
    for pos in range(0, len(payload), 2):
        word = payload[pos] | (payload[pos + 1] << 8)
        r = ((word >> 11) & 0x1F) * 255 // 31
        g = ((word >> 5) & 0x3F) * 255 // 63
        b = (word & 0x1F) * 255 // 31
        pixels.append((r, g, b))

    image = Image.new("RGB", (frame.width, frame.height))
    image.putdata(pixels)
    return image


class SerialReader(threading.Thread):
    def __init__(self, port: str, baud: int, output: queue.Queue, stop_event: threading.Event):
        super().__init__(daemon=True)
        self.port = port
        self.baud = baud
        self.output = output
        self.stop_event = stop_event
        self.parser = FrameParser()

    def run(self) -> None:
        try:
            with serial.Serial(self.port, self.baud, timeout=0.2) as ser:
                self.output.put(("status", f"已打开 {self.port}，波特率 {self.baud}"))
                while not self.stop_event.is_set():
                    chunk = ser.read(8192)
                    if not chunk:
                        continue
                    for frame in self.parser.feed(chunk):
                        self.output.put(("frame", frame))
        except Exception as exc:  # 线程中转给 GUI 主线程显示
            self.output.put(("error", f"串口接收失败：{exc}"))
        finally:
            self.output.put(("stopped", self.parser))


def available_ports() -> list[str]:
    return [item.device for item in list_ports.comports()]


class Viewer:
    def __init__(self, root, frame_queue: queue.Queue, scale: int, save_dir: pathlib.Path, save_every: int):
        from PIL import ImageTk
        import tkinter as tk

        self.root = root
        self.frame_queue = frame_queue
        self.scale = max(1, scale)
        self.save_dir = save_dir
        self.save_every = max(0, save_every)
        self.ImageTk = ImageTk
        self.tk = tk
        self.photo = None
        self.last_frame: Optional[ImageFrame] = None
        self.received = 0
        self.last_status = "等待 FPGA 图像帧……"

        self.root.title("FPGA 上位机图传")
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        self.root.bind("<Key-s>", self.save_current)
        self.root.bind("<Key-S>", self.save_current)

        self.image_label = tk.Label(root, text="等待图像", bg="black", fg="white")
        self.image_label.pack(padx=8, pady=8)
        self.status_label = tk.Label(root, text=self.last_status, anchor="w")
        self.status_label.pack(fill="x", padx=8, pady=(0, 8))
        self.root.after(10, self.poll)

    def poll(self) -> None:
        try:
            while True:
                kind, value = self.frame_queue.get_nowait()
                if kind == "frame":
                    self.show_frame(value)
                elif kind == "status":
                    self.set_status(value)
                elif kind == "error":
                    self.set_status(value)
                elif kind == "stopped":
                    parser: FrameParser = value
                    self.set_status(
                        f"接收结束：有效 {parser.good_frames} 帧，坏帧 {parser.bad_frames}，CRC 错误 {parser.bad_crc}"
                    )
        except queue.Empty:
            pass
        if self.root.winfo_exists():
            self.root.after(10, self.poll)

    def set_status(self, text: str) -> None:
        self.last_status = text
        self.status_label.configure(text=text)

    def show_frame(self, frame: ImageFrame) -> None:
        image = rgb565_to_image(frame)
        if self.scale != 1:
            image = image.resize(
                (frame.width * self.scale, frame.height * self.scale),
                resample=Image.Resampling.NEAREST,
            )
        self.photo = self.ImageTk.PhotoImage(image=image)
        self.image_label.configure(image=self.photo, text="")
        self.last_frame = frame
        self.received += 1
        self.set_status(
            f"帧 {frame.sequence}，{frame.width}x{frame.height} RGB565，"
            f"已接收 {self.received} 帧（按 S 保存当前帧）"
        )
        if self.save_every and self.received % self.save_every == 0:
            self.save_current()

    def save_current(self, _event=None) -> None:
        if self.last_frame is None:
            return
        self.save_dir.mkdir(parents=True, exist_ok=True)
        image = rgb565_to_image(self.last_frame)
        path = self.save_dir / f"frame_{self.last_frame.sequence:06d}.png"
        image.save(path)
        self.set_status(f"已保存：{path}")

    def close(self) -> None:
        self.root.destroy()


def run_no_gui(reader: SerialReader, frame_queue: queue.Queue, save_dir: pathlib.Path, save_every: int) -> int:
    """无图形桌面时的接收/保存模式，便于测试协议和串口。"""
    from PIL import Image

    received = 0
    try:
        while reader.is_alive() or not frame_queue.empty():
            try:
                kind, value = frame_queue.get(timeout=0.5)
            except queue.Empty:
                continue
            if kind == "frame":
                received += 1
                frame: ImageFrame = value
                print(f"收到帧 {frame.sequence}: {frame.width}x{frame.height}")
                if save_every and received % save_every == 0:
                    save_dir.mkdir(parents=True, exist_ok=True)
                    path = save_dir / f"frame_{frame.sequence:06d}.png"
                    image = rgb565_to_image(frame)
                    image.save(path)
                    print(f"已保存 {path}")
            elif kind == "error":
                print(value, file=sys.stderr)
                return 1
    except KeyboardInterrupt:
        pass
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="FPGA K2 UART 图传接收与显示")
    parser.add_argument("--port", help="串口号，例如 COM7")
    parser.add_argument("--baud", type=int, default=2_000_000, help="波特率，默认 2000000")
    parser.add_argument("--scale", type=int, default=4, help="窗口显示放大倍数，默认 4")
    parser.add_argument("--save-dir", type=pathlib.Path, default=pathlib.Path("pc_captures"))
    parser.add_argument("--save-every", type=int, default=0, help="每收到多少帧自动保存；0 表示只按 S 保存")
    parser.add_argument("--no-gui", action="store_true", help="不打开窗口，只接收并按 --save-every 保存")
    args = parser.parse_args()

    port = args.port
    if not port:
        ports = available_ports()
        if len(ports) == 1:
            port = ports[0]
            print(f"未指定 --port，自动使用 {port}")
        else:
            print("当前可用串口：" + (", ".join(ports) if ports else "无"))
            print("请把 USB-UART 的端口填入，例如：--port COM7")
            return 2

    try:
        import tkinter as tk
    except ImportError:
        if not args.no_gui:
            print("当前 Python 没有 tkinter，请加 --no-gui 运行。", file=sys.stderr)
            return 2

    frame_queue: queue.Queue = queue.Queue(maxsize=3)
    stop_event = threading.Event()
    reader = SerialReader(port, args.baud, frame_queue, stop_event)
    reader.start()

    if args.no_gui:
        try:
            return run_no_gui(reader, frame_queue, args.save_dir, args.save_every)
        finally:
            stop_event.set()
            reader.join(timeout=1.0)

    root = tk.Tk()
    Viewer(root, frame_queue, args.scale, args.save_dir, args.save_every)
    try:
        root.mainloop()
    finally:
        stop_event.set()
        reader.join(timeout=1.0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
