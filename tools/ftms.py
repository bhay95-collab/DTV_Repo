"""Decode Bluetooth FTMS Treadmill Data (0x2ACD) packets.

Mirrors ios/TreadSync/Core/FTMS.swift. Usable on its own to decode hex copied
from nRF Connect:

    python3 tools/ftms.py "8C 04 5E 01 D2 04 00 14 00 00 00 2D 00 2C 01 05 58 02"
"""
from __future__ import annotations

import struct
import sys

# (flag bit, field name(s), struct format, scale). Bit 0 is inverted: speed is present when it is 0.
_FIELDS = [
    (1, ("average_speed_kmh",), "<H", 0.01),
    (2, ("total_distance_m",), "u24", 1),
    (3, ("incline_percent", "ramp_angle_deg"), "<hh", 0.1),
    (4, ("elevation_gain_pos_m", "elevation_gain_neg_m"), "<HH", 0.1),
    (5, ("pace_km_per_min",), "<B", 0.1),
    (6, ("average_pace_km_per_min",), "<B", 0.1),
    (7, ("total_energy_kcal", "energy_per_hour_kcal", "energy_per_minute_kcal"), "<HHB", 1),
    (8, ("heart_rate_bpm",), "<B", 1),
    (9, ("metabolic_equivalent",), "<B", 0.1),
    (10, ("elapsed_time_s",), "<H", 1),
    (11, ("remaining_time_s",), "<H", 1),
    (12, ("force_on_belt_n", "power_w"), "<hh", 1),
]


def parse_treadmill_data(payload: bytes) -> dict | None:
    if len(payload) < 2:
        return None
    flags = payload[0] | payload[1] << 8
    i = 2
    out: dict = {"flags": f"0x{flags:04X}"}

    if not flags & 1:
        if i + 2 > len(payload):
            return out
        out["speed_kmh"] = round(struct.unpack_from("<H", payload, i)[0] * 0.01, 2)
        i += 2

    for bit, names, fmt, scale in _FIELDS:
        if not flags & (1 << bit):
            continue
        if fmt == "u24":
            if i + 3 > len(payload):
                return out
            values = (payload[i] | payload[i + 1] << 8 | payload[i + 2] << 16,)
            i += 3
        else:
            size = struct.calcsize(fmt)
            if i + size > len(payload):
                return out
            values = struct.unpack_from(fmt, payload, i)
            i += size
        for name, v in zip(names, values):
            out[name] = round(v * scale, 2) if scale != 1 else v

    if i < len(payload):
        out["unparsed_trailing_bytes"] = payload[i:].hex(" ").upper()
    return out


def from_hex(text: str) -> bytes:
    cleaned = text.replace("0x", "").replace("-", " ").replace(",", " ")
    return bytes.fromhex("".join(cleaned.split()))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(f"usage: {sys.argv[0]} '<hex bytes>' ['<hex bytes>' ...]")
    for arg in sys.argv[1:]:
        print(parse_treadmill_data(from_hex(arg)))
