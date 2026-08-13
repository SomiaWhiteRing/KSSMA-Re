from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks


ROOT = Path(__file__).resolve().parent
SOURCE_LIB = ROOT / "librooneyj-exploration-area-return-rerequest.so"
OUT_LIB = ROOT / "librooneyj-gacha-touchscreen-nullthis-guard.so"

SOURCE_SHA256 = "8D214198BFC69CC9D523BB645B0DA1FF75ABFA109A271E850F4B463FA96DD80D"

TOUCH_GETSELECTED_PATCH = 0x0022C63C
TOUCH_GETSELECTED_RESUME = 0x0022C640
TOUCH_GETSELECTED_CAVE = 0x003E7F20


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


def write_branch(blob: bytearray, offset: int, target: int) -> None:
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


def guard_block(base: int) -> bytes:
    block = bytearray()
    block += asm(
        f"""
        cmp r0, #0
        beq null_this
        ldr r2, [r1, #4]
        movs r3, #0
        b.w 0x{TOUCH_GETSELECTED_RESUME:x}
    null_this:
        movs r0, #0
        bx lr
        """,
        base,
    )
    return bytes(block)


def main() -> None:
    digest = sha256_file(SOURCE_LIB)
    if digest != SOURCE_SHA256:
        raise SystemExit(f"source lib sha256 mismatch: got {digest}, expected {SOURCE_SHA256}")

    blob = bytearray(SOURCE_LIB.read_bytes())
    require(blob, TOUCH_GETSELECTED_PATCH, bytes.fromhex("4a680023"))
    block = guard_block(TOUCH_GETSELECTED_CAVE)
    if len(block) > 0x40:
        raise SystemExit(f"guard cave too large: {len(block)}")
    require(blob, TOUCH_GETSELECTED_CAVE, b"\x00" * 0x40)

    blob[TOUCH_GETSELECTED_CAVE : TOUCH_GETSELECTED_CAVE + len(block)] = block
    write_branch(blob, TOUCH_GETSELECTED_PATCH, TOUCH_GETSELECTED_CAVE)
    assert_branch_target(blob, TOUCH_GETSELECTED_PATCH, TOUCH_GETSELECTED_CAVE)
    assert_branch_target(blob, TOUCH_GETSELECTED_CAVE + 8, TOUCH_GETSELECTED_RESUME)

    OUT_LIB.write_bytes(blob)
    patched = sha256_file(OUT_LIB)

    print(f"wrote {OUT_LIB}")
    print(f"source_sha256={digest}")
    print(f"patched_sha256={patched}")
    print("branch map:")
    print(
        f"  _AnmTouchScreen::getSelected null-this guard: "
        f"0x{TOUCH_GETSELECTED_PATCH:08x} -> 0x{TOUCH_GETSELECTED_CAVE:08x}; "
        f"non-null resumes 0x{TOUCH_GETSELECTED_RESUME:08x}; null returns 0"
    )
    print("trap map: none")
    print("code cave:")
    print(f"  0x{TOUCH_GETSELECTED_CAVE:08x}..0x{TOUCH_GETSELECTED_CAVE + 0x40:08x} verified zero")
    print("\npatched _AnmTouchScreen::getSelected entry:")
    print(disasm(bytes(blob[TOUCH_GETSELECTED_PATCH : TOUCH_GETSELECTED_PATCH + 0x28]), TOUCH_GETSELECTED_PATCH))
    print("\nnull guard cave:")
    print(disasm(bytes(blob[TOUCH_GETSELECTED_CAVE : TOUCH_GETSELECTED_CAVE + len(block)]), TOUCH_GETSELECTED_CAVE))


if __name__ == "__main__":
    main()
