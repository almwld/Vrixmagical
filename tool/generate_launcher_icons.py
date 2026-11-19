#!/usr/bin/env python3
"""Generate Android launcher/adaptive icons from the canonical VRIX SVG."""
from __future__ import annotations
import argparse
import re
import struct
from pathlib import Path
import cairosvg

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "launcher_logo.svg"
RES = ROOT / "android/app/src/main/res"
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
BACKGROUND = "#0B1524"

def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(f"Not a valid PNG: {path}")
    return struct.unpack(">II", header[16:24])

def render(svg: bytes, destination: Path, size: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(bytestring=svg, write_to=str(destination), output_width=size, output_height=size)

def generate() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Canonical launcher SVG not found: {SOURCE}")
    svg = SOURCE.read_bytes()
    if b"<svg" not in svg or b"</svg>" not in svg:
        raise SystemExit("launcher_logo.svg is not a complete SVG document")
    for density, size in DENSITIES.items():
        folder = RES / f"mipmap-{density}"
        render(svg, folder / "ic_launcher.png", size)
        render(svg, folder / "ic_launcher_round.png", size)

    # Keep the authored mark, but remove the tile and decorative wave so
    # Android can apply the adaptive-icon mask over a transparent foreground.
    foreground = re.sub(
        rb'\s*<rect x="72" y="72" width="880" height="880" rx="224" fill="url\(#vrix-dark\)"/>',
        b"", svg, count=1,
    )
    foreground = re.sub(
        rb'\s*<path d="M72 760C240 660 334 690 490 788C630 876 782 884 952 782V952H72V760Z" fill="#102638" opacity="\.72"/>',
        b"", foreground, count=1,
    )
    render(foreground, RES / "drawable-nodpi/ic_launcher_foreground.png", 432)

    values = RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{BACKGROUND}</color>\n</resources>\n',
        encoding="utf-8",
    )
    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_foreground" />\n'
        '</adaptive-icon>\n'
    )
    folder = RES / "mipmap-anydpi-v33"
    folder.mkdir(parents=True, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        (folder / name).write_text(adaptive, encoding="utf-8")
    legacy = adaptive.replace('    <monochrome android:drawable="@drawable/ic_launcher_foreground" />\n', "")
    folder = RES / "mipmap-anydpi-v26"
    folder.mkdir(parents=True, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        (folder / name).write_text(legacy, encoding="utf-8")

def verify() -> None:
    if not SOURCE.is_file():
        raise SystemExit("Canonical SVG is missing")
    for density, size in DENSITIES.items():
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            path = RES / f"mipmap-{density}" / name
            if png_size(path) != (size, size):
                raise SystemExit(f"Incorrect launcher icon dimensions: {path}")
    if png_size(RES / "drawable-nodpi/ic_launcher_foreground.png") != (432, 432):
        raise SystemExit("Adaptive foreground must be 432x432")
    for folder in ("mipmap-anydpi-v26", "mipmap-anydpi-v33"):
        for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
            if not (RES / folder / name).is_file():
                raise SystemExit(f"Missing adaptive icon resource: {folder}/{name}")
    print("Verified SVG-derived launcher icons: 5 legacy densities + adaptive/round resources.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.verify:
        verify()
    else:
        generate()
        verify()
