from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks


ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
OUT_LIB = ROOT / "librooneyj-exploration-action84-fix-ycheck.so"

POST_FLOOR_PATCH = 0x00342108
POST_FLOOR_RESUME = 0x00341FAE
SET_RECORDS_POST_PATCH = 0x002D2ED8
SET_RECORDS_POST_RESUME = 0x002D2EDC
ACTION_84_PATCH = 0x002D332C
ACTION_84_RESUME = 0x002D3332
DRAW_RECORD_PATCH = 0x002D1ED0
DRAW_RECORD_RESUME = 0x002D1ED4

CAVE_BASE = 0x003E7720
SAVE_PICKLIST_CAVE = 0x003E7760
ACTION_84_CAVE = 0x003E7E60
DRAW_RECORD_CAVE = 0x003E7EE0

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
    require(blob, ACTION_84_PATCH, bytes.fromhex("fa2284235200"))
    require(blob, DRAW_RECORD_PATCH, bytes.fromhex("f0b55f46"))
    require(blob, CAVE_BASE, b"\x00" * 0xC0)
    require(blob, ACTION_84_CAVE, b"\x00" * 0x1A0)

    post_floor = bytearray()
    post_floor += asm("push {r4,r5,lr}", CAVE_BASE + len(post_floor))
    post_floor += load_addr("r2", CAVE_BASE + len(post_floor), STATE_ADDR)
    post_floor += asm(
        """
        movs r3, #1
        str r3, [r2]
        movs r3, #2
        str r3, [r4, #0x3c]
        pop {r4,r5,r6}
        """,
        CAVE_BASE + len(post_floor),
    )
    post_floor += b"\x00\x00\x00\x00"

    save_picklist = bytearray()
    save_picklist += asm("push {r2,r3}", SAVE_PICKLIST_CAVE + len(save_picklist))
    save_picklist += load_addr("r2", SAVE_PICKLIST_CAVE + len(save_picklist), STATE_ADDR)
    save_picklist += asm(
        """
        ldr r3, [r2]
        cmp r3, #1
        bne replay
        mov r3, r8
        str r3, [r2, #4]
        movs r2, #0
        str r2, [r3, #0x84]
    replay:
        pop {r2,r3}
        mov r1, sb
        ldr r2, [r1, #4]
        """,
        SAVE_PICKLIST_CAVE + len(save_picklist),
    )
    save_picklist += b"\x00\x00\x00\x00"

    action_fix = bytearray()
    action_fix += asm("push {r0,r1}", ACTION_84_CAVE + len(action_fix))
    action_fix += load_addr("r0", ACTION_84_CAVE + len(action_fix), STATE_ADDR)
    action_fix += asm(
        """
        ldr r1, [r0, #4]
        cmp r1, r6
        bne stock_500
        movs r2, #0
        b done
    stock_500:
        movs r2, #0xfa
        lsls r2, r2, #1
    done:
        movs r3, #0x84
        pop {r0,r1}
        """,
        ACTION_84_CAVE + len(action_fix),
    )
    action_fix += b"\x00\x00\x00\x00"

    draw_check = bytearray()
    draw_check += asm("push {r2,r3}", DRAW_RECORD_CAVE + len(draw_check))
    draw_check += load_addr("r2", DRAW_RECORD_CAVE + len(draw_check), STATE_ADDR)
    draw_check += asm(
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
        b offset_other
    offset_zero:
        udf #0x40
    offset_500:
        udf #0x41
    offset_other:
        udf #0x42
    replay:
        pop {r2,r3}
        push {r4,r5,r6,r7,lr}
        mov r7, fp
        """,
        DRAW_RECORD_CAVE + len(draw_check),
    )
    draw_check += b"\x00\x00\x00\x00"

    for name, offset, data in [
        ("post_floor", CAVE_BASE, post_floor),
        ("save_picklist", SAVE_PICKLIST_CAVE, save_picklist),
        ("action_fix", ACTION_84_CAVE, action_fix),
        ("draw_check", DRAW_RECORD_CAVE, draw_check),
    ]:
        if any(blob[offset : offset + len(data)]):
            raise SystemExit(f"{name} overlaps nonzero bytes")
        blob[offset : offset + len(data)] = data

    branch(blob, CAVE_BASE + len(post_floor) - 4, POST_FLOOR_RESUME)
    branch(blob, SAVE_PICKLIST_CAVE + len(save_picklist) - 4, SET_RECORDS_POST_RESUME)
    branch(blob, ACTION_84_CAVE + len(action_fix) - 4, ACTION_84_RESUME)
    branch(blob, DRAW_RECORD_CAVE + len(draw_check) - 4, DRAW_RECORD_RESUME)

    branch(blob, POST_FLOOR_PATCH, CAVE_BASE)
    blob[POST_FLOOR_PATCH + 4 : POST_FLOOR_PATCH + 6] = bytes.fromhex("c046")
    branch(blob, SET_RECORDS_POST_PATCH, SAVE_PICKLIST_CAVE)
    branch(blob, ACTION_84_PATCH, ACTION_84_CAVE)
    blob[ACTION_84_PATCH + 4 : ACTION_84_PATCH + 6] = asm("nop", ACTION_84_PATCH + 4)
    branch(blob, DRAW_RECORD_PATCH, DRAW_RECORD_CAVE)

    OUT_LIB.write_bytes(blob)
    digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"sha256={digest}")
    for title, base, size in [
        ("post-floor patch", POST_FLOOR_PATCH, 8),
        ("setRecords-save patch", SET_RECORDS_POST_PATCH, 8),
        ("action84 patch", ACTION_84_PATCH, 10),
        ("drawRecord patch", DRAW_RECORD_PATCH, 8),
        ("cave", CAVE_BASE, 0xC0),
        ("action/draw cave", ACTION_84_CAVE, 0x1A0),
    ]:
        print(f"\n-- {title} --")
        print(disasm(bytes(blob[base : base + size]), base))


if __name__ == "__main__":
    main()
