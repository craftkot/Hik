#!/usr/bin/env python3
"""Materialize the compact, generated brand PNG on Linux/macOS/Windows.

No network, Pillow, or external dependencies required.
"""
from __future__ import annotations

import base64
from pathlib import Path
import struct


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    encoded = (root / "assets/brand/logo.png.b64").read_text(encoding="ascii").strip()
    image = base64.b64decode(encoded, validate=True)
    if not image.startswith(b"\x89PNG\r\n\x1a\n") or len(image) > 128_000:
        raise ValueError("Invalid EHTID logo PNG")
    width, height = struct.unpack(">II", image[16:24])
    if (width, height) != (64, 64):
        raise ValueError(f"Unexpected brand asset dimensions: {width}x{height}")
    dest = root / "assets/brand/logo.png"
    dest.write_bytes(image)
    print(f"Prepared {dest.relative_to(root)} ({len(image)} bytes)")


if __name__ == "__main__":
    main()
