from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks


ROOT = Path(__file__).resolve().parent
SOURCE_LIB = ROOT / "librooneyj-exploration-area-return-rerequest.so"
OUT_LIB = ROOT / "librooneyj-gacha-cardget-inner-touch-nullguard.so"

SOURCE_SHA256 = "8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D"

GETSELECTED_PATCH = 0x00258B68
GETSELECTED_CAVE = 0x003E7F60
RETURN_PATH = 0x00258B94


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


def asm(code: str, addr: int) -> bytes:
    ks = Ks(KS_ARCH_ARM, KS_MODE_THUMB | KS_MODE_LITTLE_ENDIAN)
    encoded, _ = ks.asm(code, addr=addr, as_bytes=True)
    if encoded is None:
        raise SystemExit(f"assembly failed at {addr:#x}")
    return bytes(encoded)


def branch(blob: bytearray, offset: int, target: int) -> None:
    blob[offset : offset + 4] = asm(f"b.w 0x{target:x}", offset)


def disasm(blob: bytes, addr: int) -> str:
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB + CS_MODE_LITTLE_ENDIAN)
    return "\n".join(
        f"{ins.address:08x}: {ins.bytes.hex():8} {ins.mnemonic:8} {ins.op_str}"
        for ins in md.disasm(blob, addr)
    )


def assert_branch_target(blob: bytes, offset: int, target: int) -> None:
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB + CS_MODE_LITTLE_ENDIAN)
    ins = next(md.disasm(blob[offset : offset + 4], offset), None)
    if ins is None:
        raise SystemExit(f"no instruction at {offset:#x}")
    if ins.mnemonic != "b.w":
        raise SystemExit(f"expected b.w at {offset:#x}, got {ins.mnemonic} {ins.op_str}")
    actual = int(ins.op_str.removeprefix("#"), 16)
    if actual != target:
        raise SystemExit(f"bad branch target at {offset:#x}: got {actual:#x}, expected {target:#x}")


def cave_block(base: int) -> bytes:
    return asm(
        f"""
        push {{r4, lr}}
        ldr r3, [r0, #0x60]
        mov r4, r0
        cmp r3, #0
        beq return_path
        ldr r0, [r3]
        cmp r0, #0
        beq return_path
        movs r2, #1
        bl 0x22c63c
        cmp r0, #0
        ble return_path
        mov r0, r4
        bl 0x258b24
        ldr r3, [r4, #0x60]
        cmp r3, #0
        beq return_path
        ldr r0, [r3]
        cmp r0, #0
        beq return_path
        bl 0x22c628
    return_path:
        mov r0, r4
        bl 0x258ab4
        pop {{r4, pc}}
        """,
        base,
    )


def main() -> None:
    digest = sha256_file(SOURCE_LIB)
    if digest != SOURCE_SHA256:
        raise SystemExit(f"source lib sha256 mismatch: got {digest}, expected {SOURCE_SHA256}")

    blob = bytearray(SOURCE_LIB.read_bytes())
    require(blob, GETSELECTED_PATCH, bytes.fromhex("10b5036e"))
    block = cave_block(GETSELECTED_CAVE)
    if len(block) > 0x80:
        raise SystemExit(f"cardget cave too large: {len(block)}")
    require(blob, GETSELECTED_CAVE, b"\x00" * 0x80)

    blob[GETSELECTED_CAVE : GETSELECTED_CAVE + len(block)] = block
    branch(blob, GETSELECTED_PATCH, GETSELECTED_CAVE)
    assert_branch_target(blob, GETSELECTED_PATCH, GETSELECTED_CAVE)

    OUT_LIB.write_bytes(blob)
    patched = sha256_file(OUT_LIB)

    print(f"wrote {OUT_LIB}")
    print(f"source_sha256={digest}")
    print(f"patched_sha256={patched}")
    print("branch map:")
    print(
        f"  _AnmCmnCardGetWindow::getSelected entry: "
        f"0x{GETSELECTED_PATCH:08x} -> 0x{GETSELECTED_CAVE:08x}; "
        "replays stock logic with inner touch null checks; return path calls base getSelected"
    )
    print("trap map: none")
    print("code cave:")
    print(f"  0x{GETSELECTED_CAVE:08x}..0x{GETSELECTED_CAVE + 0x80:08x} verified zero")
    print("\npatched _AnmCmnCardGetWindow::getSelected entry:")
    print(disasm(bytes(blob[GETSELECTED_PATCH : GETSELECTED_PATCH + 0x38]), GETSELECTED_PATCH))
    print("\ncardget cave:")
    print(disasm(bytes(blob[GETSELECTED_CAVE : GETSELECTED_CAVE + len(block)]), GETSELECTED_CAVE))


if __name__ == "__main__":
    main()
