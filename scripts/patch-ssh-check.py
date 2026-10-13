#!/usr/bin/env python3
"""Null out the spurious RSA_check_key failure in Hub.exe's SSH host-key loader.

Background: Hub loads the SSH host key pair (ssh_privateKeyFile PEM +
ssh_publicKeyFile OpenSSH .pub), then validates it as
  BN_num_bits(n) >= 2048, RSA_check_key(rsa) == 1,
  BN_cmp(n_pub, n_priv) == 0, BN_cmp(e_pub, e_priv) == 0.
On Wine (seen with Wine 9.x under qemu/Rosetta on ARM hosts) RSA_check_key
fails even for a perfectly valid pair, so Hub logs
"SSH server is disabled: failed to load matching RSA host keys" and never
listens on 2222. The pair itself is fine (ssh-keygen -y matches, modern
OpenSSH clients accept the host key and the handshake signatures verify),
only the self-test misfires — same class of issue as patch-addr-assert.py.

Fix: replace the `jne fail` after `RSA_check_key` with NOPs (6 bytes).
Hub.exe 1.99.0.167293, single strict match, idempotent.
"""
import os
import sys


# add esp,4; cmp eax,1 (RSA_check_key result); jne ->fail
CHECK_PATTERN = bytes([
    0x00, 0x00,
    0x56,
    0xE8, 0x69, 0x7B, 0x00, 0x00,          # call RSA_check_key thunk
    0x83, 0xC4, 0x04,                      # add esp, 4
    0x83, 0xF8, 0x01,                      # cmp eax, 1
    0x0F, 0x85, 0x9D, 0x00, 0x00, 0x00,    # jne fail
    0x8B, 0x44, 0x24, 0x14,
])
CHECK_PATCHED = bytes([
    0x00, 0x00,
    0x56,
    0xE8, 0x69, 0x7B, 0x00, 0x00,
    0x83, 0xC4, 0x04,
    0x83, 0xF8, 0x01,
    0x90, 0x90, 0x90, 0x90, 0x90, 0x90,    # jne -> NOPs
    0x8B, 0x44, 0x24, 0x14,
])

PAIRS = [
    ("rsa-check-key", CHECK_PATTERN, CHECK_PATCHED),
]


def patch_file(path: str) -> str:
    with open(path, "rb") as f:
        data = bytearray(f.read())
    states = [(n, (p in data), (q in data)) for n, p, q in PAIRS]
    if all(d for _, _, d in states):
        return "already-patched"
    if not all(c for _, c, _ in states):
        done = sorted(n for n, _, d in states if d)
        if done:
            return "PARTIAL(" + ",".join(done) + ")"
        return "no-pattern"
    bad = [(n, data.count(p)) for n, p, _ in PAIRS if data.count(p) != 1]
    if bad:
        return "COUNT(" + ",".join(f"{n}:{c}" for n, c in bad) + ")"
    for _, p, q in PAIRS:
        data[:] = data.replace(p, q)
    with open(path, "wb") as f:
        f.write(data)
    return "patched"


def main() -> int:
    cloud_dir = sys.argv[1] if len(sys.argv) > 1 else "cloud"
    path = os.path.join(cloud_dir, "Hub.exe")
    if not os.path.isfile(path):
        print(f"no {path}", file=sys.stderr)
        return 1
    try:
        res = patch_file(path)
    except OSError as e:
        res = f"ERROR: {e}"
    print(f"Hub.exe {res}")
    return 1 if res.startswith(("UNEXPECTED", "ERROR", "PARTIAL", "no-pattern", "COUNT")) else 0


if __name__ == "__main__":
    sys.exit(main())
