"""UART protocol shared by the plate GUI and FPGA OSD link."""

from __future__ import annotations

from typing import Iterable, Optional

UART_BAUD = 115200
MAX_PLATE_CHARS = 11
FRAME_PREFIX = bytes((0xA5, 0x5A))
CMD_CLEAR = 0x00
CMD_SET_PLATE = 0x01

PROVINCE_CHARS = "京沪津渝冀晋蒙辽吉黑苏浙皖闽赣鲁豫鄂湘粤桂琼川贵云藏陕甘青宁新"
SPECIAL_CHARS = "学警港澳挂使领民航危险品"
FPGA_HANZI = PROVINCE_CHARS + SPECIAL_CHARS


def _character_codes() -> dict[str, int]:
    codes: dict[str, int] = {}
    for index, char in enumerate(FPGA_HANZI):
        if index < 39:
            codes[char] = 0xD9 + index
        else:
            codes[char] = 0x1C + index - 39
    for char in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        codes[char] = ord(char)
    return codes


CHARACTER_CODES = _character_codes()


def crc8(data: Iterable[int], initial: int = 0) -> int:
    """CRC-8/ATM (poly 0x07, non-reflected, xorout 0)."""
    value = initial & 0xFF
    for byte in data:
        value ^= int(byte) & 0xFF
        for _ in range(8):
            value = ((value << 1) ^ 0x07) & 0xFF if value & 0x80 else (value << 1) & 0xFF
    return value


def encode_plate(plate_no: str) -> bytes:
    """Return the FPGA glyph-code payload for one recognized plate."""
    if not plate_no:
        raise ValueError("车牌号不能为空")
    if len(plate_no) > MAX_PLATE_CHARS:
        raise ValueError(f"车牌字符数超过 FPGA 显示上限 {MAX_PLATE_CHARS}")
    unsupported = [char for char in plate_no if char not in CHARACTER_CODES]
    if unsupported:
        raise ValueError("FPGA 字库不支持字符: " + "".join(dict.fromkeys(unsupported)))
    return bytes(CHARACTER_CODES[char] for char in plate_no)


def build_frame(command: int, payload: bytes = b"") -> bytes:
    if command not in (CMD_CLEAR, CMD_SET_PLATE):
        raise ValueError(f"不支持的命令: 0x{command:02X}")
    if len(payload) > MAX_PLATE_CHARS:
        raise ValueError(f"数据长度超过 FPGA 上限 {MAX_PLATE_CHARS}")
    if command == CMD_CLEAR and payload:
        raise ValueError("清除命令不能包含数据")
    if command == CMD_SET_PLATE and not payload:
        raise ValueError("设置车牌命令必须包含字符")
    body = bytes((command, len(payload))) + payload
    return FRAME_PREFIX + body + bytes((crc8(body),))


def plate_frame(plate_no: str) -> bytes:
    return build_frame(CMD_SET_PLATE, encode_plate(plate_no))


def clear_frame() -> bytes:
    return build_frame(CMD_CLEAR)


class PlateSerialLink:
    """Synchronous writer for plate text and complete still-image frames."""

    def __init__(self, port: str, baud: int = UART_BAUD) -> None:
        try:
            import serial
        except ImportError as exc:  # pragma: no cover - depends on runtime packaging
            raise RuntimeError("缺少 pyserial，请安装 requirements.txt 中的依赖") from exc
        self.port = port
        self._serial = serial.Serial(
            port=port,
            baudrate=baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.05,
            write_timeout=10,
        )

    @property
    def is_open(self) -> bool:
        return bool(self._serial.is_open)

    def send_plate(self, plate_no: str) -> None:
        self._write(plate_frame(plate_no))

    def send_image(self, image_bgr, plate_no: str = "", sequence: int = 0) -> None:
        from pc_image_sender import image_packet_from_bgr_array

        label = f"识别: {plate_no}" if plate_no else "未检出车牌"
        self._write(image_packet_from_bgr_array(image_bgr, sequence, label))

    def clear(self) -> None:
        self._write(clear_frame())

    def _write(self, packet: bytes) -> None:
        if not self.is_open:
            raise RuntimeError("串口未连接")
        written = self._serial.write(packet)
        self._serial.flush()
        if written != len(packet):
            raise IOError(f"串口只发送了 {written}/{len(packet)} 字节")

    def close(self) -> None:
        if self.is_open:
            self._serial.close()


def list_serial_ports() -> list[tuple[str, str]]:
    try:
        from serial.tools import list_ports
    except ImportError as exc:  # pragma: no cover - depends on runtime packaging
        raise RuntimeError("缺少 pyserial，请安装 requirements.txt 中的依赖") from exc
    return [(port.device, port.description or port.device) for port in list_ports.comports()]
