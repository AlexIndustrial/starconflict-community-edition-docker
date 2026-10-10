#!/usr/bin/env python3
import glob
import os
import sys

PATTERN = bytes([0x74, 0x05, 0x85, 0xDB, 0x74, 0x09, 0xCC, 0x85, 0xDB])
PATCHED = bytes([0x74, 0x05, 0x85, 0xDB, 0x74, 0x09, 0x90, 0x85, 0xDB])
CC_OFFSET_IN_PATTERN = 6


def patch_file(path: str) -> str:
    with open(path, "rb") as f:
        data = bytearray(f.read())
    if PATTERN not in data:
        if PATCHED in data:
            return "already-patched"
        return "no-pattern"
    if data.count(PATTERN) != 1:
        return f"UNEXPECTED-MATCH-COUNT={data.count(PATTERN)}"
    data = data.replace(PATTERN, PATCHED)
    with open(path, "wb") as f:
        f.write(data)
    return "patched"


def main() -> int:
    roots = sys.argv[1:] or ["cloud"]
    targets = []
    for root in roots:
        targets += sorted(glob.glob(os.path.join(root, "*.exe")))
    if not targets:
        print("no .exe found", file=sys.stderr)
        return 1
    rc = 0
    for t in targets:
        try:
            res = patch_file(t)
        except OSError as e:
            res = f"ERROR: {e}"
        print(f"{os.path.basename(t):28s} {res}")
        if res.startswith(("UNEXPECTED", "ERROR")):
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
