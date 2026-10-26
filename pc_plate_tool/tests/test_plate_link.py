import unittest

from plate_link import (
    CHARACTER_CODES,
    CMD_CLEAR,
    CMD_SET_PLATE,
    FPGA_HANZI,
    MAX_PLATE_CHARS,
    build_frame,
    clear_frame,
    crc8,
    encode_plate,
    plate_frame,
)


class PlateLinkTests(unittest.TestCase):
    def test_crc8_known_vector(self):
        self.assertEqual(crc8(b"123456789"), 0xF4)

    def test_clear_packet(self):
        frame = clear_frame()
        self.assertEqual(frame[:4], bytes((0xA5, 0x5A, CMD_CLEAR, 0)))
        self.assertEqual(frame[-1], crc8(frame[2:-1]))

    def test_plate_packet_preserves_supported_characters(self):
        plate = "苏A12345"
        frame = plate_frame(plate)
        self.assertEqual(frame[:4], bytes((0xA5, 0x5A, CMD_SET_PLATE, len(plate))))
        self.assertEqual(frame[4:-1], encode_plate(plate))
        self.assertEqual(frame[-1], crc8(frame[2:-1]))

    def test_all_model_chinese_characters_have_unique_codes(self):
        self.assertEqual(len(set(FPGA_HANZI)), len(FPGA_HANZI))
        self.assertTrue(all(char in CHARACTER_CODES for char in FPGA_HANZI))
        self.assertEqual(len({CHARACTER_CODES[char] for char in FPGA_HANZI}), len(FPGA_HANZI))

    def test_maximum_plate_length_and_validation(self):
        plate = "WJ1693015"
        self.assertLessEqual(len(plate), MAX_PLATE_CHARS)
        self.assertEqual(plate_frame(plate)[3], len(plate))
        with self.assertRaises(ValueError):
            plate_frame("京" + "A" * MAX_PLATE_CHARS)
        with self.assertRaises(ValueError):
            plate_frame("京A-12345")
        with self.assertRaises(ValueError):
            build_frame(CMD_SET_PLATE)


if __name__ == "__main__":
    unittest.main()
