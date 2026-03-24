#!/usr/bin/env python3
"""
Upload a binary to the FPGA bootloader over UART.

Protocol:
  1. Send 4-byte little-endian size
  2. Send raw binary data

Usage:
  python3 upload.py <binary_file> [serial_port]

Default port: /dev/ttyUSB0
Baud: 921600
"""

import sys
import struct
import time
import serial

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <binary_file> [serial_port]")
        sys.exit(1)

    binfile = sys.argv[1]
    port = sys.argv[2] if len(sys.argv) > 2 else "/dev/ttyUSB0"

    with open(binfile, "rb") as f:
        data = f.read()

    # Pad to word alignment
    while len(data) % 4 != 0:
        data += b'\x00'

    print(f"Uploading {len(data)} bytes from {binfile} to {port} at 921600 baud")

    ser = serial.Serial(port, 921600, timeout=2)
    time.sleep(0.1)  # let bootloader initialize

    # Send size (4 bytes, little-endian)
    size_bytes = struct.pack("<I", len(data))
    ser.write(size_bytes)
    ser.flush()

    # Send data in chunks
    chunk_size = 256
    sent = 0
    for i in range(0, len(data), chunk_size):
        chunk = data[i:i+chunk_size]
        ser.write(chunk)
        ser.flush()
        sent += len(chunk)
        pct = 100 * sent // len(data)
        print(f"\r  {sent}/{len(data)} bytes ({pct}%)", end="")

    print(f"\nDone. Sent {sent} bytes.")
    ser.close()

if __name__ == "__main__":
    main()
