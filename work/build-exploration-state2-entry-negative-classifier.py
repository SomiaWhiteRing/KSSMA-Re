from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks

ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
OUT_LIB = ROOT / "librooneyj-exploration-state2-entry-negative-classifier.so"

POST_FLOOR_PATCH = 0x00342108
POST_FLOOR_RESUME = 0x00341FAE
FOCUS_ZERO_PATCH = 0x003415E2
FOCUS_ZERO_RESUME = 0x003415E6
SET_RECORDS_POST_PATCH = 0x002D2ED8
SET_RECORDS_POST_RESUME = 0x002D2EDC
ACTION_84_PATCH = 0x002D332C
ACTION_84_RESUME = 0x002D3332
STATE2_ENTRY_PATCH = 0x003413B2
STATE2_ENTRY_RESUME = 0x003413B8
FLOOR2_AFTER_CALL_PATCH = 0x003413CA
FLOOR2_AFTER_CALL_RESUME = 0x003413CE

STATE_ADDR = 0x004493AC
CAVE_POST = 0x003E7720
CAVE_FOCUS = 0x003E7760
CAVE_SAVE_PICKLIST = 0x003E77A0
CAVE_ACTION84 = 0x003E7E60
CAVE_STATE2_ENTRY = 0x003E7EC0
CAVE_FLOOR2_RETURN = 0x003E7F00


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


def post_floor_block(base: int) -> bytes:
    block = bytearray()
    block += asm("push {r4,r5,lr}", base + len(block))
    block += load_addr("r2", base + len(block), STATE_ADDR)
    block += asm(
        """
        movs r3, #1
        str r3, [r2]
        movs r3, #2
        str r3, [r4, #0x3c]
        pop {r4,r5,r6}
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def focus_zero_block(base: int) -> bytes:
    block = bytearray()
    block += asm("push {r2,r3}", base + len(block))
    block += load_addr("r2", base + len(block), STATE_ADDR)
    block += asm(
        """
        ldr r3, [r2]
        cmp r3, #1
        beq keep_floor
        movs r3, #0
        b store
    keep_floor:
        movs r3, #2
    store:
        str r3, [r4, #0x3c]
        pop {r2,r3}
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def save_picklist_block(base: int) -> bytes:
    block = bytearray()
    block += asm("push {r2,r3}", base + len(block))
    block += load_addr("r2", base + len(block), STATE_ADDR)
    block += asm(
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
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def action84_block(base: int) -> bytes:
    block = bytearray()
    block += asm("push {r0,r1}", base + len(block))
    block += load_addr("r0", base + len(block), STATE_ADDR)
    block += asm(
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
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def state2_entry_block(base: int) -> bytes:
    block = bytearray()
    block += asm("ldr r3, [r4, #0x3c]", base + len(block))
    block += asm(
        """
        cmp r3, #2
        bne replay
        udf #0xa0
    replay:
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def floor2_return_block(base: int) -> bytes:
    block = bytearray()
    block += asm(
        """
        cmp r0, #0
        blt selected_negative
        udf #0xa2
    selected_negative:
        udf #0xa1
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def main() -> None:
    blob = bytearray(STOCK_LIB.read_bytes())
    require(blob, POST_FLOOR_PATCH, bytes.fromhex("0223e3634fe7"))
    require(blob, FOCUS_ZERO_PATCH, bytes.fromhex("0023e363"))
    require(blob, SET_RECORDS_POST_PATCH, bytes.fromhex("49464a68"))
    require(blob, ACTION_84_PATCH, bytes.fromhex("fa2284235200"))
    require(blob, STATE2_ENTRY_PATCH, bytes.fromhex("e36b022baad1"))
    require(blob, FLOOR2_AFTER_CALL_PATCH, bytes.fromhex("061eeddb"))
    require(blob, 0x003E7720, b"\x00" * 0xC0)
    require(blob, 0x003E7E60, b"\x00" * 0x1A0)

    blocks = [
        (CAVE_POST, post_floor_block(CAVE_POST), POST_FLOOR_PATCH, POST_FLOOR_RESUME, True),
        (CAVE_FOCUS, focus_zero_block(CAVE_FOCUS), FOCUS_ZERO_PATCH, FOCUS_ZERO_RESUME, False),
        (CAVE_SAVE_PICKLIST, save_picklist_block(CAVE_SAVE_PICKLIST), SET_RECORDS_POST_PATCH, SET_RECORDS_POST_RESUME, False),
        (CAVE_ACTION84, action84_block(CAVE_ACTION84), ACTION_84_PATCH, ACTION_84_RESUME, False),
        (CAVE_STATE2_ENTRY, state2_entry_block(CAVE_STATE2_ENTRY), STATE2_ENTRY_PATCH, STATE2_ENTRY_RESUME, True),
        (CAVE_FLOOR2_RETURN, floor2_return_block(CAVE_FLOOR2_RETURN), FLOOR2_AFTER_CALL_PATCH, FLOOR2_AFTER_CALL_RESUME, False),
    ]

    # ponytail: this probe intentionally crashes at state2 entry before the call;
    # if it fires, rebuild a second no-entry-trap version to classify return value.
    for cave, block, patch, resume, patch_six_bytes in blocks:
        if any(blob[cave : cave + len(block)]):
            raise SystemExit(f"cave at {cave:#x} overlaps nonzero bytes")
        blob[cave : cave + len(block)] = block
        branch(blob, cave + len(block) - 4, resume)
        branch(blob, patch, cave)
        if patch_six_bytes:
            blob[patch + 4 : patch + 6] = bytes.fromhex("c046")

    blob[ACTION_84_PATCH + 4 : ACTION_84_PATCH + 6] = asm("nop", ACTION_84_PATCH + 4)

    OUT_LIB.write_bytes(blob)
    digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"sha256={digest}")
    for title, base, size in [
        ("post-floor", POST_FLOOR_PATCH, 8),
        ("focus-zero", FOCUS_ZERO_PATCH, 8),
        ("setRecords-save", SET_RECORDS_POST_PATCH, 8),
        ("action84", ACTION_84_PATCH, 10),
        ("state2-entry", STATE2_ENTRY_PATCH, 8),
        ("floor2-return", FLOOR2_AFTER_CALL_PATCH, 8),
        ("cave-low", 0x003E7720, 0xC0),
        ("cave-high", 0x003E7E60, 0x1A0),
    ]:
        print(f"\n-- {title} --")
        print(disasm(bytes(blob[base : base + size]), base))


if __name__ == "__main__":
    main()
