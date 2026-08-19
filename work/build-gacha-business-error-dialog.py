from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks


ROOT = Path(__file__).resolve().parent
SOURCE_LIB = ROOT / "librooneyj-gacha-cardget-inner-touch-nullguard.so"
OUT_LIB = ROOT / "librooneyj-gacha-business-error-dialog.so"

SOURCE_SHA256 = "DEC36585CA0129AA19E68CC53898D95DE41067AA5D380B23218F3E88273CD40F"

BUSINESS_ERROR_PATCH = 0x001C3BA8
BUSINESS_ERROR_CAVE = 0x003E7FA0
BUSINESS_ERROR_RETURN = 0x001C3BAE
CAVE_CAPACITY = 0xB0


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


def disasm(blob: bytes, addr: int) -> str:
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB + CS_MODE_LITTLE_ENDIAN)
    return "\n".join(
        f"{ins.address:08x}: {ins.bytes.hex():8} {ins.mnemonic:8} {ins.op_str}"
        for ins in md.disasm(blob, addr)
    )


def assert_branch_target(blob: bytes, offset: int, target: int) -> None:
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB + CS_MODE_LITTLE_ENDIAN)
    ins = next(md.disasm(blob[offset : offset + 4], offset), None)
    if ins is None or ins.mnemonic != "b.w":
        rendered = "none" if ins is None else f"{ins.mnemonic} {ins.op_str}"
        raise SystemExit(f"expected b.w at {offset:#x}, got {rendered}")
    actual = int(ins.op_str.removeprefix("#"), 16)
    if actual != target:
        raise SystemExit(f"bad branch target at {offset:#x}: got {actual:#x}, expected {target:#x}")


def cave_block(base: int) -> bytes:
    # _Main::connect already constructed DialogData(type=2) from header/error/message
    # and called DialogModel::initDialog. Restore the missing producer only for the
    # generic business-error code used by the local server, then replay stock cleanup.
    return asm(
        f"""
        add r0, sp, #0x364
        bl 0x1c1d58
        ldr r2, [sp, #4]
        cmp r2, #1
        bne return_path
        add r0, sp, #0x108
        mov r1, r7
        bl 0x1c1de4
        ldr r3, [sp, #0x10c]
        cmp r3, #0
        beq cleanup_scene_control
        ldr r0, [r3]
        movw r1, #0x5ff4
        movt r1, #1
        bl 0x1f6950
    cleanup_scene_control:
        add.w r3, r8, #8
        str.w r3, [sp, #0x108]
        add r0, sp, #0x108
        bl 0x1c2ddc
    return_path:
        b.w 0x{BUSINESS_ERROR_RETURN:x}
        """,
        base,
    )


def main() -> None:
    digest = sha256_file(SOURCE_LIB)
    if digest != SOURCE_SHA256:
        raise SystemExit(f"source lib sha256 mismatch: got {digest}, expected {SOURCE_SHA256}")

    blob = bytearray(SOURCE_LIB.read_bytes())
    require(blob, BUSINESS_ERROR_PATCH, bytes.fromhex("d9a8fef7d5f8"))
    require(blob, BUSINESS_ERROR_CAVE, b"\x00" * CAVE_CAPACITY)

    block = cave_block(BUSINESS_ERROR_CAVE)
    if len(block) > CAVE_CAPACITY:
        raise SystemExit(f"business-error cave too large: {len(block)} > {CAVE_CAPACITY}")

    entry = asm(f"b.w 0x{BUSINESS_ERROR_CAVE:x}; nop", BUSINESS_ERROR_PATCH)
    if len(entry) != 6:
        raise SystemExit(f"unexpected entry patch size: {len(entry)}")
    blob[BUSINESS_ERROR_PATCH : BUSINESS_ERROR_PATCH + len(entry)] = entry
    blob[BUSINESS_ERROR_CAVE : BUSINESS_ERROR_CAVE + len(block)] = block

    assert_branch_target(blob, BUSINESS_ERROR_PATCH, BUSINESS_ERROR_CAVE)
    cave_disassembly = disasm(bytes(blob[BUSINESS_ERROR_CAVE : BUSINESS_ERROR_CAVE + len(block)]), BUSINESS_ERROR_CAVE)
    if f"#{BUSINESS_ERROR_RETURN:#x}" not in cave_disassembly:
        raise SystemExit("business-error cave does not branch back to the stock return path")

    OUT_LIB.write_bytes(blob)
    patched = sha256_file(OUT_LIB)

    print(f"wrote {OUT_LIB}")
    print(f"source_sha256={digest}")
    print(f"patched_sha256={patched}")
    print("request/path map:")
    print("  HTTP header/error/code=1 + message -> _Main::connect -> DialogModel::initDialog(type=2)")
    print(
        f"  0x{BUSINESS_ERROR_PATCH:08x} -> 0x{BUSINESS_ERROR_CAVE:08x}: "
        "replay DialogData cleanup, gate error code 1, acquire Main SceneControl, push dialog_scene 90100"
    )
    print(f"  0x{BUSINESS_ERROR_CAVE:08x} -> 0x{BUSINESS_ERROR_RETURN:08x}: resume stock special-code checks")
    print("trap map: none")
    print("code cave:")
    print(
        f"  0x{BUSINESS_ERROR_CAVE:08x}..0x{BUSINESS_ERROR_CAVE + CAVE_CAPACITY:08x} "
        "verified zero in the accepted source"
    )
    print("\npatched _Main::connect entry:")
    print(disasm(bytes(blob[BUSINESS_ERROR_PATCH : BUSINESS_ERROR_PATCH + 12]), BUSINESS_ERROR_PATCH))
    print("\nbusiness-error cave:")
    print(cave_disassembly)


if __name__ == "__main__":
    main()
