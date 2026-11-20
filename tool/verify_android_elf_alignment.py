#!/usr/bin/env python3
"""Verify 16 KiB ELF LOAD alignment for a native library inside an APK/AAB."""
from __future__ import annotations

import argparse
import subprocess
import tempfile
import zipfile
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--entry", required=True)
    args = parser.parse_args()

    with zipfile.ZipFile(args.archive) as archive:
        try:
            payload = archive.read(args.entry)
        except KeyError:
            raise SystemExit(f"Missing native library: {args.entry}")

    with tempfile.NamedTemporaryFile(suffix=".so") as native:
        native.write(payload)
        native.flush()
        result = subprocess.run(
            ["readelf", "-lW", native.name],
            check=True,
            capture_output=True,
            text=True,
        )

    alignments = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if fields and fields[0] == "LOAD":
            try:
                alignments.append(int(fields[-1], 16))
            except ValueError:
                raise SystemExit(f"Cannot parse LOAD alignment: {line}")

    if not alignments:
        raise SystemExit("ELF contains no LOAD program headers")
    if min(alignments) < 0x4000:
        raise SystemExit(
            "16 KiB page alignment failed for "
            + args.entry
            + ": "
            + ", ".join(hex(value) for value in alignments)
        )
    print(
        f"16 KiB ELF alignment OK for {args.entry}: "
        + ", ".join(hex(value) for value in alignments)
    )


if __name__ == "__main__":
    main()
