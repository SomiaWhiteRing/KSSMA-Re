from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks


ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
OUT_LIB = ROOT / "librooneyj-exploration-setrecords-flooronly-classifier.so"

PREUPDATE_PATCH = 0x003420CC
PREUPDATE_RESUME = 0x003420D2
CREATE_FLOOR_LIST = 0x003419CC
SET_RECORDS_PATCH = 0x002D2D8C
SET_RECORDS_RESUME = 0x002D2D90
CAVE_BASE = 0x003E7720
SET_RECORDS_CAVE = 0x003E7760
SAVED_EXPLORATION_AREA = 0x004493AC


def assemble_thumb(code: str, addr: int) -> bytes:
    ks = Ks(KS_ARCH_ARM, KS_MODE_THUMB | KS_MODE_LITTLE_ENDIAN)
    encoded, _ = ks.asm(code, addr=addr, as_bytes=True)
    if encoded is None:
        raise RuntimeError(f"keystone failed at {addr:#x}")
    return bytes(encoded)


def disasm_thumb(blob: bytes, addr: int) -> str:
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB + CS_MODE_LITTLE_ENDIAN)
    return "\n".join(
        f"{ins.address:08x}: {ins.bytes.hex():10} {ins.mnemonic:8} {ins.op_str}"
        for ins in md.disasm(blob, addr)
    )


def require(blob: bytes, offset: int, expected: bytes) -> None:
    actual = blob[offset : offset + len(expected)]
    if actual != expected:
        raise SystemExit(
            f"unexpected bytes at {offset:#x}: got {actual.hex()}, expected {expected.hex()}"
        )


def patch_branch(blob: bytearray, offset: int, target: int) -> None:
    blob[offset : offset + 4] = assemble_thumb(f"b.w 0x{target:x}", offset)


def patch_bl(blob: bytearray, offset: int, target: int) -> None:
    blob[offset : offset + 4] = assemble_thumb(f"bl 0x{target:x}", offset)


def load_pc_relative(reg: str, addr: int, target: int) -> bytes:
    # Thumb reads PC as current instruction address + 4 for this add form.
    add_addr = addr + 8
    delta = target - (add_addr + 4)
    if delta < 0:
        raise SystemExit(f"negative PC-relative delta from {addr:#x} to {target:#x}")
    return assemble_thumb(
        f"""
        movw {reg}, #{delta & 0xffff}
        movt {reg}, #{(delta >> 16) & 0xffff}
        add {reg}, pc
        """,
        addr,
    )


def main() -> None:
    blob = bytearray(STOCK_LIB.read_bytes())
    require(blob, PREUPDATE_PATCH, bytes.fromhex("201cfff7"))
    require(blob, PREUPDATE_PATCH + 4, bytes.fromhex("7dfc"))
    require(blob, SET_RECORDS_PATCH, bytes.fromhex("f0b55f46"))
    require(blob, CAVE_BASE, b"\x00" * 0xC0)

    first_cave = bytearray()
    first_cave += assemble_thumb("push {r1,r2}", CAVE_BASE + len(first_cave))
    first_cave += load_pc_relative("r1", CAVE_BASE + len(first_cave), SAVED_EXPLORATION_AREA)
    first_cave += assemble_thumb(
        """
        str r4, [r1]
        pop {r1,r2}
        adds r0, r4, #0
        """,
        CAVE_BASE + len(first_cave),
    )
    first_cave += b"\x00\x00\x00\x00"  # bl createFloorList patched below.
    first_cave += b"\x00\x00\x00\x00"  # branch back patched below.
    if len(first_cave) > SET_RECORDS_CAVE - CAVE_BASE:
        raise SystemExit(f"first cave too large: {len(first_cave)}")

    second_prefix = bytearray()
    second_prefix += assemble_thumb("push {r2,r3}", SET_RECORDS_CAVE + len(second_prefix))
    second_prefix += load_pc_relative(
        "r2", SET_RECORDS_CAVE + len(second_prefix), SAVED_EXPLORATION_AREA
    )
    second_cave = second_prefix + assemble_thumb(
        """
        ldr r3, [r2]
        cmp r3, #0
        beq replay
        adds r2, r3, #0x7c
        cmp r1, r2
        beq floor
        b replay
    floor:
        udf #1
    replay:
        pop {r2,r3}
        push {r4,r5,r6,r7,lr}
        mov r7, fp
        nop.w
        """,
        SET_RECORDS_CAVE + len(second_prefix),
    )
    if len(second_cave) > SAVED_EXPLORATION_AREA - SET_RECORDS_CAVE:
        raise SystemExit(f"second cave too large: {len(second_cave)}")
    blob[CAVE_BASE : CAVE_BASE + len(first_cave)] = first_cave
    blob[SET_RECORDS_CAVE : SET_RECORDS_CAVE + len(second_cave)] = second_cave

    # Keystone is reliable for single branch instructions, but can be off by one
    # Thumb halfword when assembling multi-instruction blocks with absolute
    # branch targets. Patch the branch instructions separately at exact PCs.
    patch_bl(blob, CAVE_BASE + len(first_cave) - 8, CREATE_FLOOR_LIST)
    patch_branch(blob, CAVE_BASE + len(first_cave) - 4, PREUPDATE_RESUME)
    patch_branch(blob, SET_RECORDS_CAVE + len(second_cave) - 4, SET_RECORDS_RESUME)
    patch_branch(blob, PREUPDATE_PATCH, CAVE_BASE)
    blob[PREUPDATE_PATCH + 4 : PREUPDATE_PATCH + 6] = bytes.fromhex("00bf")
    patch_branch(blob, SET_RECORDS_PATCH, SET_RECORDS_CAVE)

    OUT_LIB.write_bytes(blob)
    digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"sha256={digest}")
    print("\n-- preUpdate patch --")
    print(disasm_thumb(bytes(blob[PREUPDATE_PATCH : PREUPDATE_PATCH + 8]), PREUPDATE_PATCH))
    print("\n-- setRecords patch --")
    print(disasm_thumb(bytes(blob[SET_RECORDS_PATCH : SET_RECORDS_PATCH + 8]), SET_RECORDS_PATCH))
    print("\n-- cave --")
    print(disasm_thumb(bytes(blob[CAVE_BASE : CAVE_BASE + 0xC0]), CAVE_BASE))


if __name__ == "__main__":
    main()
