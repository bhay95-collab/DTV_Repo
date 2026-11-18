"""Connect to an FTMS treadmill from a Mac/PC and print every Treadmill Data packet.

Quick way to check what the treadmill really reports, without building the iOS app.

    pip install bleak
    python3 tools/ftms_logger.py            # first treadmill found
    python3 tools/ftms_logger.py YPTM       # name must contain "YPTM"

Close the vendor app first: the treadmill accepts only one connection.
"""
from __future__ import annotations

import asyncio
import csv
import datetime as dt
import sys
from pathlib import Path

from bleak import BleakClient, BleakScanner

from ftms import parse_treadmill_data

FTMS_SERVICE = "00001826-0000-1000-8000-00805f9b34fb"
TREADMILL_DATA = "00002acd-0000-1000-8000-00805f9b34fb"


async def main(name_filter: str | None) -> None:
    print("Scanning for FTMS treadmills…")
    device = await BleakScanner.find_device_by_filter(
        lambda d, adv: FTMS_SERVICE in [u.lower() for u in adv.service_uuids]
        and (name_filter is None or name_filter.lower() in (d.name or "").lower()),
        timeout=20,
    )
    if device is None:
        sys.exit("No treadmill found. Is it on, and is the vendor app closed?")
    print(f"Connecting to {device.name} ({device.address})")

    log_path = Path(f"treadmill-{dt.datetime.now():%Y%m%d-%H%M%S}.csv")
    with log_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["time", "hex", "decoded"])

        def on_packet(_, data: bytearray) -> None:
            now = dt.datetime.now().isoformat(timespec="milliseconds")
            decoded = parse_treadmill_data(bytes(data))
            writer.writerow([now, data.hex(" ").upper(), decoded])
            f.flush()
            print(now, data.hex(" ").upper(), decoded)

        async with BleakClient(device) as client:
            await client.start_notify(TREADMILL_DATA, on_packet)
            print(f"Logging to {log_path}. Walk a bit; Ctrl+C to stop.")
            while client.is_connected:
                await asyncio.sleep(1)


if __name__ == "__main__":
    try:
        asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else None))
    except KeyboardInterrupt:
        pass
