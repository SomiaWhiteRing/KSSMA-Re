from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks


ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
OUT_LIB = ROOT / "librooneyj-exploration-y-source-probe.so"

POST_FLOOR_PATCH = 0x00342108
POST_FLOOR_RESUME = 0x00341FAE
SET_RECORDS_POST_PATCH = 0x002D2ED8
SET_RECORDS_POST_RESUME = 0x002D2EDC
DRAW_RECORD_PATCH = 0x002D1ED0
DRAW_RECORD_RESUME = 0x002D1ED4

CAVE_BASE = 0x003E7720
SAVE_PICKLIST_CAVE = 0x003E7760
DRAW_RECORD_CAVE = 0x003E7E60

STATE_ADDR = 0x004493AC


def asm(code: str, addr: int) -> bytes:
    ks = Ks(KS_ARCH_ARM, KS_MODE_THUMB | KS_MODE_LITTLE_ENDIAN)
    encoded, _ = ks.asm(code, addr=addr, as_bytes=True)
    if encoded is None:
        raise RuntimeError(f"keystone failed at {addr:#x}")
    return bytes(encoded)


def disasm(blob: bytes, addr: int) -> str:
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


def branch(blob: bytearray, offset: int, target: int) -> None:
    blob[offset : offset + 4] = asm(f"b.w 0x{target:x}", offset)


def load_addr(reg: str, addr: int, target: int) -> bytes:
    # Thumb add-reg PC uses the PC of the add instruction plus 4.
    add_addr = addr + 8
    delta = target - (add_addr + 4)
    if delta < 0:
        raise SystemExit(f"negative PC-relative delta from {addr:#x} to {target:#x}")
    return asm(
        f"""
        movw {reg}, #{delta & 0xffff}
        movt {reg}, #{(delta >> 16) & 0xffff}
        add {reg}, pc
        """,
        addr,
    )


def main() -> None:
    blob = bytearray(STOCK_LIB.read_bytes())
    require(blob, POST_FLOOR_PATCH, bytes.fromhex("0223e3634fe7"))
    require(blob, SET_RECORDS_POST_PATCH, bytes.fromhex("49464a68"))
    require(blob, DRAW_RECORD_PATCH, bytes.fromhex("f0b55f46"))
    require(blob, CAVE_BASE, b"\x00" * 0xC0)
    require(blob, DRAW_RECORD_CAVE, b"\x00" * 0xA0)

    cave = bytearray()
    cave += asm("push {r4,r5,lr}", CAVE_BASE + len(cave))
    cave += load_addr("r2", CAVE_BASE + len(cave), STATE_ADDR)
    cave += asm(
        """
        movs r3, #1
        str r3, [r2]
        movs r3, #2
        str r3, [r4, #0x3c]
        pop {r4,r5,r6}
        """,
        CAVE_BASE + len(cave),
    )
    cave += b"\x00\x00\x00\x00"

    save_cave = bytearray()
    save_cave += asm("push {r2,r3}", SAVE_PICKLIST_CAVE + len(save_cave))
    save_cave += load_addr("r2", SAVE_PICKLIST_CAVE + len(save_cave), STATE_ADDR)
    save_cave += asm(
        """
        ldr r3, [r2]
        cmp r3, #1
        bne replay
        mov r3, r8
        str r3, [r2, #4]
    replay:
        pop {r2,r3}
        mov r1, sb
        ldr r2, [r1, #4]
        """,
        SAVE_PICKLIST_CAVE + len(save_cave),
    )
    save_cave += b"\x00\x00\x00\x00"

    draw_cave = bytearray()
    draw_cave += asm("push {r2,r3}", DRAW_RECORD_CAVE + len(draw_cave))
    draw_cave += load_addr("r2", DRAW_RECORD_CAVE + len(draw_cave), STATE_ADDR)
    draw_cave += asm(
        """
        ldr r3, [r2]
        cmp r3, #1
        bne replay
        ldr r3, [r2, #4]
        cmp r3, #0
        beq replay
        cmp r0, r3
        bne replay
        movs r2, #0x84
        ldr r3, [r0, r2]
        cmp r3, #0
        beq offset_zero
        movs r2, #0xfa
        lsls r2, r2, #1
        cmp r3, r2
        beq offset_500
        ldr r2, [sp, #4]
        cmp r2, r3
        beq final_equals_offset
        b other
    offset_zero:
        udf #0x30
    offset_500:
        udf #0x31
    final_equals_offset:
        udf #0x32
    other:
        udf #0x33
    replay:
        pop {r2,r3}
        push {r4,r5,r6,r7,lr}
        mov r7, fp
        """,
        DRAW_RECORD_CAVE + len(draw_cave),
    )
    draw_cave += b"\x00\x00\x00\x00"

    if len(cave) > SAVE_PICKLIST_CAVE - CAVE_BASE:
        raise SystemExit(f"post-floor cave too large: {len(cave)}")
    if len(save_cave) > (DRAW_RECORD_CAVE - SAVE_PICKLIST_CAVE):
        raise SystemExit(f"save cave too large: {len(save_cave)}")
    if len(draw_cave) > 0xA0:
        raise SystemExit(f"draw cave too large: {len(draw_cave)}")

    blob[CAVE_BASE : CAVE_BASE + len(cave)] = cave
    blob[SAVE_PICKLIST_CAVE : SAVE_PICKLIST_CAVE + len(save_cave)] = save_cave
    blob[DRAW_RECORD_CAVE : DRAW_RECORD_CAVE + len(draw_cave)] = draw_cave

    branch(blob, CAVE_BASE + len(cave) - 4, POST_FLOOR_RESUME)
    branch(blob, SAVE_PICKLIST_CAVE + len(save_cave) - 4, SET_RECORDS_POST_RESUME)
    branch(blob, DRAW_RECORD_CAVE + len(draw_cave) - 4, DRAW_RECORD_RESUME)

    branch(blob, POST_FLOOR_PATCH, CAVE_BASE)
    blob[POST_FLOOR_PATCH + 4 : POST_FLOOR_PATCH + 6] = bytes.fromhex("c046")
    branch(blob, SET_RECORDS_POST_PATCH, SAVE_PICKLIST_CAVE)
    branch(blob, DRAW_RECORD_PATCH, DRAW_RECORD_CAVE)

    OUT_LIB.write_bytes(blob)
    digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"sha256={digest}")
    for title, base, size in [
        ("post-floor patch", POST_FLOOR_PATCH, 8),
        ("setRecords-save patch", SET_RECORDS_POST_PATCH, 8),
        ("drawRecord patch", DRAW_RECORD_PATCH, 8),
        ("cave", CAVE_BASE, 0x90),
        ("draw cave", DRAW_RECORD_CAVE, 0xA0),
    ]:
        print(f"\n-- {title} --")
        print(disasm(bytes(blob[base : base + size]), base))


if __name__ == "__main__":
    main()
