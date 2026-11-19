"""Run: python3 -m unittest discover tools"""
import unittest

from ftms import from_hex, parse_treadmill_data


class ParseTreadmillData(unittest.TestCase):
    def test_full_packet(self):
        t = parse_treadmill_data(from_hex("8C 04 5E 01 D2 04 00 14 00 00 00 2D 00 2C 01 05 58 02"))
        self.assertEqual(t["speed_kmh"], 3.5)
        self.assertEqual(t["total_distance_m"], 1234)
        self.assertEqual(t["incline_percent"], 2.0)
        self.assertEqual(t["total_energy_kcal"], 45)
        self.assertEqual(t["energy_per_hour_kcal"], 300)
        self.assertEqual(t["energy_per_minute_kcal"], 5)
        self.assertEqual(t["elapsed_time_s"], 600)
        self.assertNotIn("unparsed_trailing_bytes", t)

    def test_real_rhythm_fun_packet(self):
        # Captured from the YPTM02f470 walking pad with nRF Connect, belt at 7.5 km/h.
        t = parse_treadmill_data(from_hex("9E04 EE02 0000 A600 0000 0000 0000 0000 0008 0000 0000 B201"))
        self.assertEqual(t["flags"], "0x049E")
        self.assertEqual(t["speed_kmh"], 7.5)
        self.assertEqual(t["total_distance_m"], 166)
        self.assertEqual(t["incline_percent"], 0.0)
        self.assertEqual(t["total_energy_kcal"], 8)
        self.assertEqual(t["elapsed_time_s"], 434)
        self.assertNotIn("unparsed_trailing_bytes", t)

    def test_more_data_bit_means_no_speed(self):
        t = parse_treadmill_data(from_hex("05 00 10 27 00"))
        self.assertNotIn("speed_kmh", t)
        self.assertEqual(t["total_distance_m"], 10000)

    def test_negative_incline(self):
        t = parse_treadmill_data(from_hex("08 00 00 00 F1 FF 00 00"))
        self.assertEqual(t["incline_percent"], -1.5)

    def test_truncated(self):
        t = parse_treadmill_data(from_hex("04 00 5E 01 D2"))
        self.assertEqual(t["speed_kmh"], 3.5)
        self.assertNotIn("total_distance_m", t)

    def test_trailing_bytes_reported(self):
        # A pace field sent as 2 bytes (non-spec) would show up here.
        t = parse_treadmill_data(from_hex("00 00 5E 01 AA"))
        self.assertEqual(t["unparsed_trailing_bytes"], "AA")

    def test_too_short(self):
        self.assertIsNone(parse_treadmill_data(b"\x04"))


if __name__ == "__main__":
    unittest.main()
