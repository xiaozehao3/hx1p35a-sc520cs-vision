import unittest

import numpy as np
from PIL import Image

from pc_image_sender import (
    HEIGHT,
    WIDTH,
    build_packet,
    crc16_ccitt,
    image_packet_from_bgr_array,
    main,
    rgb565_payload_from_image,
)


class PcImageSenderTests(unittest.TestCase):
    def test_rgb565_red_pixel_is_little_endian(self):
        payload = rgb565_payload_from_image(Image.new("RGB", (2, 2), (255, 0, 0)))
        self.assertEqual(len(payload), WIDTH * HEIGHT * 2)
        self.assertEqual(payload[:2], b"\x00\xF8")
        self.assertEqual(payload[-2:], b"\x00\xF8")

    def test_image_packet_layout_crc_and_size(self):
        payload = bytes(WIDTH * HEIGHT * 2)
        packet = build_packet(payload, 0x12345678)

        self.assertEqual(len(packet), 28818)
        self.assertEqual(packet[:14], bytes.fromhex(
            "55 AA 5A A5 01 01 A0 00 5A 00 78 56 34 12"
        ))
        self.assertEqual(packet[14:-4], payload)
        self.assertEqual(packet[-4:], bytes((
            crc16_ccitt(payload) & 0xFF,
            crc16_ccitt(payload) >> 8,
            0x0D,
            0x0A,
        )))

    def test_bgr_annotated_array_is_converted_to_rgb565(self):
        image = np.zeros((4, 4, 3), dtype=np.uint8)
        image[:, :, 2] = 255
        packet = image_packet_from_bgr_array(image, sequence=3, plate_text="TEST")

        self.assertEqual(len(packet), 28818)
        self.assertEqual(packet[:14][-4:], b"\x03\x00\x00\x00")
        first_unannotated_pixel = 14 + (15 * WIDTH * 2)
        self.assertEqual(packet[first_unannotated_pixel:first_unannotated_pixel + 2], b"\x00\xF8")

    def test_nonstandard_baud_is_rejected_before_opening_port(self):
        with self.assertRaisesRegex(SystemExit, "115200 baud 8N1"):
            main(["--port", "COM_DOES_NOT_EXIST", "--input", "missing.jpg", "--baud", "2000000"])


if __name__ == "__main__":
    unittest.main()
