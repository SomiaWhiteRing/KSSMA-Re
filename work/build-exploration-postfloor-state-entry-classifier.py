from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks

ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
OUT_LIB = ROOT / "librooneyj-exploration-postfloor-state-entry-classifier.so"

POST_FLOOR_PATCH = 0x00342108
POST_FLOOR_RESUME = 0x00341FAE
FOCUS_ZERO_PATCH = 0x003415E2
FOCUS_ZERO_RESUME = 0x003415E6
STATE_ENTRY_PATCH = 0x003413B2
STATE_ENTRY_STATE2_TARGET = 0x003413B8
STATE_ENTRY_NONSTATE_TARGET = 0x0034130E

STATE_ADDR = 0x004493AC
CAVE_POST = 0x003E7720
CAVE_FOCUS = 0x003E7760
CAVE_STATE_ENTRY = 0x003E77A0


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


def state_entry_block(base: int) -> bytes:
    # PC map:
    #   exact PCs are printed by the build log; traps only fire after the post-floor flag is set.
    return asm(
        f"""
        push {{r2,r3}}
        {load_addr_source("r2", base + 2, STATE_ADDR)}
        ldr r2, [r2]
        cmp r2, #1
        pop {{r2,r3}}
        ldr r3, [r4, #0x3c]
        beq flagged
        cmp r3, #2
        beq unflagged_state2
        b.w 0x{STATE_ENTRY_NONSTATE_TARGET:x}
    flagged:
        cmp r3, #2
        beq flagged_state2
        udf #0xa3
    flagged_state2:
        udf #0xa0
    unflagged_state2:
        b.w 0x{STATE_ENTRY_STATE2_TARGET:x}
        """,
        base,
    )


def load_addr_source(reg: str, addr: int, target: int) -> str:
    add_addr = addr + 8
    delta = target - (add_addr + 4)
    if delta < 0:
        raise SystemExit(f"negative PC-relative delta from {addr:#x} to {target:#x}")
    return f"""
        movw {reg}, #{delta & 0xffff}
        movt {reg}, #{(delta >> 16) & 0xffff}
        add {reg}, pc
    """


def main() -> None:
    blob = bytearray(STOCK_LIB.read_bytes())
    require(blob, POST_FLOOR_PATCH, bytes.fromhex("0223e3634fe7"))
    require(blob, FOCUS_ZERO_PATCH, bytes.fromhex("0023e363"))
    require(blob, STATE_ENTRY_PATCH, bytes.fromhex("e36b022baad1"))
    require(blob, CAVE_POST, b"\x00" * 0xC0)

    for cave, block, patch, resume, patch_six_bytes in [
        (CAVE_POST, post_floor_block(CAVE_POST), POST_FLOOR_PATCH, POST_FLOOR_RESUME, True),
        (CAVE_FOCUS, focus_zero_block(CAVE_FOCUS), FOCUS_ZERO_PATCH, FOCUS_ZERO_RESUME, False),
    ]:
        if any(blob[cave : cave + len(block)]):
            raise SystemExit(f"cave at {cave:#x} overlaps nonzero bytes")
        blob[cave : cave + len(block)] = block
        branch(blob, cave + len(block) - 4, resume)
        branch(blob, patch, cave)
        if patch_six_bytes:
            blob[patch + 4 : patch + 6] = bytes.fromhex("c046")

    entry = state_entry_block(CAVE_STATE_ENTRY)
    if any(blob[CAVE_STATE_ENTRY : CAVE_STATE_ENTRY + len(entry)]):
        raise SystemExit(f"cave at {CAVE_STATE_ENTRY:#x} overlaps nonzero bytes")
    blob[CAVE_STATE_ENTRY : CAVE_STATE_ENTRY + len(entry)] = entry
    branch(blob, STATE_ENTRY_PATCH, CAVE_STATE_ENTRY)
    blob[STATE_ENTRY_PATCH + 4 : STATE_ENTRY_PATCH + 6] = bytes.fromhex("c046")

    OUT_LIB.write_bytes(blob)
    digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"sha256={digest}")
    for title, base, size in [
        ("post-floor", POST_FLOOR_PATCH, 8),
        ("focus-zero", FOCUS_ZERO_PATCH, 8),
        ("state-entry", STATE_ENTRY_PATCH, 8),
        ("cave-low", CAVE_POST, 0xC0),
    ]:
        print(f"\n-- {title} --")
        print(disasm(bytes(blob[base : base + size]), base))


if __name__ == "__main__":
    main()
