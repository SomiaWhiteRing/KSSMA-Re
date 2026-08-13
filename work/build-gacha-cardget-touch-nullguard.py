from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs


ROOT = Path(__file__).resolve().parent
SOURCE_LIB = ROOT / "librooneyj-exploration-area-return-rerequest.so"
OUT_LIB = ROOT / "librooneyj-gacha-cardget-touch-nullguard.so"

SOURCE_SHA256 = "8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D"

NULL_TOUCH_BRANCH_1 = 0x00258B72
NULL_TOUCH_BRANCH_2 = 0x00258B8C

PATCHES = (
    {
        "name": "skip initial touch getSelected when cardget touch child is null",
        "offset": NULL_TOUCH_BRANCH_1,
        "expected": bytes.fromhex("00d0"),
        "patched": bytes.fromhex("0fd0"),
        "target": 0x00258B94,
    },
    {
        "name": "skip touch startAnimation when cardget touch child is null",
        "offset": NULL_TOUCH_BRANCH_2,
        "expected": bytes.fromhex("00d0"),
        "patched": bytes.fromhex("02d0"),
        "target": 0x00258B94,
    },
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def require(blob: bytes, offset: int, expected: bytes) -> None:
    actual = blob[offset : offset + len(expected)]
    if actual != expected:
        raise SystemExit(
            f"unexpected bytes at {offset:#x}: got {actual.hex()}, expected {expected.hex()}"
        )


def disasm(blob: bytes, addr: int) -> str:
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB + CS_MODE_LITTLE_ENDIAN)
    return "\n".join(
        f"{ins.address:08x}: {ins.bytes.hex():8} {ins.mnemonic:8} {ins.op_str}"
        for ins in md.disasm(blob, addr)
    )


def assert_branch_target(blob: bytes, offset: int, target: int) -> None:
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB + CS_MODE_LITTLE_ENDIAN)
    ins = next(md.disasm(blob[offset : offset + 2], offset), None)
    if ins is None:
        raise SystemExit(f"no instruction at {offset:#x}")
    if ins.mnemonic != "beq":
        raise SystemExit(f"expected beq at {offset:#x}, got {ins.mnemonic} {ins.op_str}")
    actual = int(ins.op_str.removeprefix("#"), 16)
    if actual != target:
        raise SystemExit(f"bad branch target at {offset:#x}: got {actual:#x}, expected {target:#x}")


def main() -> None:
    digest = sha256_file(SOURCE_LIB)
    if digest != SOURCE_SHA256:
        raise SystemExit(f"source lib sha256 mismatch: got {digest}, expected {SOURCE_SHA256}")

    blob = bytearray(SOURCE_LIB.read_bytes())
    for patch in PATCHES:
        require(blob, patch["offset"], patch["expected"])
        blob[patch["offset"] : patch["offset"] + len(patch["patched"])] = patch["patched"]
        assert_branch_target(blob, patch["offset"], patch["target"])

    OUT_LIB.write_bytes(blob)
    patched = sha256_file(OUT_LIB)

    print(f"wrote {OUT_LIB}")
    print(f"source_sha256={digest}")
    print(f"patched_sha256={patched}")
    print("branch map:")
    for patch in PATCHES:
        print(
            f"  {patch['name']}: 0x{patch['offset']:08x} -> 0x{patch['target']:08x}; "
            "scope=_AnmCmnCardGetWindow::getSelected only"
        )
    print("trap map: none")
    print("code cave: none; in-place conditional branch widening only")
    print("\npatched _AnmCmnCardGetWindow::getSelected:")
    start = 0x00258B68
    end = 0x00258B9C
    print(disasm(bytes(blob[start:end]), start))


if __name__ == "__main__":
    main()
