#!/usr/bin/env python3
"""
Upload DOOM binary + WAD to FPGA bootloader over UART,
then switch to keyboard input mode.

Protocol (same as bootloader expects):
  1. Send 4-byte little-endian total size
  2. Send raw data

Keyboard protocol (matches doomgeneric_riscv.c process_uart_input):
  Press:   0x80 | ascii_key
  Release: 0x00 | ascii_key

Usage:
  python3 upload_doom.py <doom.bin> <doom1.wad> [serial_port]

Default port: /dev/ttyUSB1 (Linux/Mac) or COM9 (Windows)
Baud: 921600
"""

import sys
import os
import struct
import time
import threading
import serial
import platform

WAD_OFFSET      = 0x100000   # 1MB -- where WAD starts relative to DDR3 base
WAD_SIZE_OFFSET = 0x0FFFF0   # Where to store WAD size (4 bytes)

# ---------------------------------------------------------------------------
# Key maps
# ---------------------------------------------------------------------------

KEY_MAP = {
    'w': ord('w'),
    's': ord('s'),
    'a': ord('a'),
    'd': ord('d'),
    ' ': ord(' '),
    'e': ord('e'),
    '\r': ord('\r'),
    '\n': ord('\r'),
    'q': ord('q'),
    'r': ord('r'),
    ',': ord(','),
    '.': ord('.'),
}

# Unix escape-sequence map  (ESC [ X)
UNIX_ESC_SEQ_MAP = {
    'A': ord('w'),   # Up    -> W
    'B': ord('s'),   # Down  -> S
    'D': ord('a'),   # Left  -> A
    'C': ord('d'),   # Right -> D
}

# Windows msvcrt map  (0xE0 prefix byte, then one of these)
WIN_ARROW_MAP = {
    b'H': ord('w'),  # Up
    b'P': ord('s'),  # Down
    b'K': ord('a'),  # Left
    b'M': ord('d'),  # Right
}

# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------

def upload(ser, binfile, wadfile):
    with open(binfile, "rb") as f:
        code = f.read()
    with open(wadfile, "rb") as f:
        wad = f.read()

    print(f"DOOM binary: {len(code)} bytes")
    print(f"WAD file:    {len(wad)} bytes")

    if len(code) > WAD_SIZE_OFFSET:
        print(f"ERROR: DOOM binary too large ({len(code)} > {WAD_SIZE_OFFSET})")
        sys.exit(1)

    data = bytearray(WAD_OFFSET + len(wad))
    data[0:len(code)] = code
    struct.pack_into("<I", data, WAD_SIZE_OFFSET, len(wad))
    data[WAD_OFFSET:WAD_OFFSET + len(wad)] = wad

    while len(data) % 4 != 0:
        data += b'\x00'

    total = len(data)
    print(f"Total payload: {total} bytes ({total/1024:.1f} KB)")
    print(f"Uploading to {ser.port} at 921600 baud...")

    ser.write(struct.pack("<I", total))
    ser.flush()

    chunk_size = 256
    sent = 0
    t0 = time.time()
    for i in range(0, total, chunk_size):
        chunk = data[i:i + chunk_size]
        ser.write(chunk)
        ser.flush()
        sent += len(chunk)
        pct     = 100 * sent // total
        elapsed = time.time() - t0
        rate    = sent / elapsed if elapsed > 0 else 0
        print(f"\r  {sent}/{total} bytes ({pct}%) {rate/1024:.1f} KB/s", end="")

    elapsed = time.time() - t0
    print(f"\nUpload done in {elapsed:.1f}s.")

# ---------------------------------------------------------------------------
# Cross-platform raw key reader
# ---------------------------------------------------------------------------

IS_WINDOWS = platform.system() == "Windows"


def _make_unix_reader(stop_event, key_callback):
    """
    Returns a callable that reads raw keypresses on Unix/Mac using termios.
    Handles regular keys and arrow-key escape sequences.
    """
    import tty
    import termios
    import select

    def run():
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            while not stop_event.is_set():
                if not select.select([sys.stdin], [], [], 0.1)[0]:
                    continue

                ch = os.read(fd, 1).decode('ascii', errors='ignore')

                if ch == '\x03':        # Ctrl+C
                    stop_event.set()
                    break

                if ch == '\x1b':        # ESC or start of arrow sequence
                    if select.select([sys.stdin], [], [], 0.05)[0]:
                        ch2 = os.read(fd, 1).decode('ascii', errors='ignore')
                        if ch2 == '[' and select.select([sys.stdin], [], [], 0.05)[0]:
                            ch3 = os.read(fd, 1).decode('ascii', errors='ignore')
                            if ch3 in UNIX_ESC_SEQ_MAP:
                                key_callback(UNIX_ESC_SEQ_MAP[ch3])
                                continue
                    # Bare ESC
                    key_callback(0x1b)
                    continue

                key = ch.lower()
                if key in KEY_MAP:
                    key_callback(KEY_MAP[key])

        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

    return run


def _make_windows_reader(stop_event, key_callback):
    """
    Returns a callable that reads raw keypresses on Windows using msvcrt.
    msvcrt.getch() is blocking but instant — no terminal-mode changes needed.
    Arrow keys arrive as two bytes: b'\\xe0' (or b'\\x00') then the key code.
    """
    import msvcrt

    def run():
        while not stop_event.is_set():
            # kbhit() lets us poll without blocking so we can respect stop_event
            if not msvcrt.kbhit():
                time.sleep(0.01)
                continue

            ch = msvcrt.getch()

            # Ctrl+C  (msvcrt delivers it as \x03 in raw mode)
            if ch == b'\x03':
                stop_event.set()
                break

            # Arrow / function keys arrive as a two-byte sequence
            if ch in (b'\xe0', b'\x00'):
                if msvcrt.kbhit():
                    ch2 = msvcrt.getch()
                    if ch2 in WIN_ARROW_MAP:
                        key_callback(WIN_ARROW_MAP[ch2])
                continue

            # Regular printable / control key
            try:
                decoded = ch.decode('ascii').lower()
            except UnicodeDecodeError:
                continue

            if decoded == '\r':
                key_callback(KEY_MAP['\r'])
            elif decoded in KEY_MAP:
                key_callback(KEY_MAP[decoded])

    return run


# ---------------------------------------------------------------------------
# Keyboard mode (shared logic)
# ---------------------------------------------------------------------------

def keyboard_mode(ser):
    print()
    print("=== DOOM Keyboard Mode ===")
    print("  WASD / Arrow keys = move    Space = fire")
    print("  E                 = use     Enter = menu select")
    print("  ESC               = menu    Q/R   = strafe L/R")
    print("  ,/.               = strafe/run")
    print("  Ctrl+C            = quit")
    print()

    stop = threading.Event()

    # Background thread: print anything DOOM sends back over UART
    def uart_reader():
        while not stop.is_set():
            try:
                data = ser.read(64)
                if data:
                    sys.stdout.write(data.decode('ascii', errors='replace'))
                    sys.stdout.flush()
            except Exception:
                break

    threading.Thread(target=uart_reader, daemon=True).start()

    def send_key(key_byte):
        ser.write(bytes([0x80 | key_byte]))   # press
        ser.flush()
        time.sleep(0.05)
        ser.write(bytes([key_byte]))           # release
        ser.flush()

    # Pick the right reader for this OS
    if IS_WINDOWS:
        reader_fn = _make_windows_reader(stop, send_key)
    else:
        reader_fn = _make_unix_reader(stop, send_key)

    try:
        reader_fn()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        print("\nQuitting.")

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <doom.bin> <doom1.wad> [serial_port]")
        print()
        print("  Default port: COM9 (Windows) or /dev/ttyUSB1 (Linux/Mac)")
        sys.exit(1)

    binfile = sys.argv[1]
    wadfile = sys.argv[2]

    if len(sys.argv) > 3:
        port = sys.argv[3]
    else:
        port = "COM9" if IS_WINDOWS else "/dev/ttyUSB1"

    ser = serial.Serial(port, 921600, timeout=0.1)
    time.sleep(0.1)

    try:
        upload(ser, binfile, wadfile)
        print("Waiting for DOOM to start...")
        time.sleep(2)
        keyboard_mode(ser)
    finally:
        ser.close()

if __name__ == "__main__":
    main()