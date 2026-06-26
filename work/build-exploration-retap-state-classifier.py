from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks

ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
OUT_LIB = ROOT / "librooneyj-exploration-retap-state-classifier.so"

POST_FLOOR_PATCH = 0x00342108
POST_FLOOR_RESUME = 0x00341FAE
UPDATE_ENTRY_PATCH = 0x003412B4
UPDATE_ENTRY_RESUME = 0x003412BA
CAVE_BASE = 0x003E7720
UPDATE_CAVE = 0x003E7760
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
    require(blob, UPDATE_ENTRY_PATCH, bytes.fromhex("f0b54746"))
    require(blob, CAVE_BASE, b"\x00" * 0xC0)

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

    update = bytearray()
    update += asm("push {r1,r2,r3}", UPDATE_CAVE + len(update))
    update += load_addr("r1", UPDATE_CAVE + len(update), STATE_ADDR)
    update += asm(
        """
        ldr r2, [r1]
        cmp r2, #1
        bne replay
        ldr r3, [r0, #0x3c]
        cmp r3, #0
        beq state0
        cmp r3, #2
        beq state2
        cmp r3, #4
        beq state4
        b state_other
    state0:
        udf #0x50
    state2:
        udf #0x52
    state4:
        udf #0x54
    state_other:
        udf #0x5f
    replay:
        pop {r1,r2,r3}
        push {r4,r5,r6,r7,lr}
        mov r7, r8
        """,
        UPDATE_CAVE + len(update),
    )
    update += b"\x00\x00\x00\x00"

    if len(post_floor) > UPDATE_CAVE - CAVE_BASE:
        raise SystemExit(f"post_floor cave too large: {len(post_floor)}")
    if len(update) > (CAVE_BASE + 0xC0) - UPDATE_CAVE:
        raise SystemExit(f"update cave too large: {len(update)}")
    blob[CAVE_BASE : CAVE_BASE + len(post_floor)] = post_floor
    blob[UPDATE_CAVE : UPDATE_CAVE + len(update)] = update

    branch(blob, CAVE_BASE + len(post_floor) - 4, POST_FLOOR_RESUME)
    branch(blob, UPDATE_CAVE + len(update) - 4, UPDATE_ENTRY_RESUME)
    branch(blob, POST_FLOOR_PATCH, CAVE_BASE)
    blob[POST_FLOOR_PATCH + 4 : POST_FLOOR_PATCH + 6] = bytes.fromhex("c046")
    branch(blob, UPDATE_ENTRY_PATCH, UPDATE_CAVE)
    blob[UPDATE_ENTRY_PATCH + 4 : UPDATE_ENTRY_PATCH + 6] = asm("nop", UPDATE_ENTRY_PATCH + 4)

    OUT_LIB.write_bytes(blob)
    digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"sha256={digest}")
    for title, base, size in [
        ("post-floor patch", POST_FLOOR_PATCH, 8),
        ("update-entry patch", UPDATE_ENTRY_PATCH, 8),
        ("cave", CAVE_BASE, 0xC0),
    ]:
        print(f"\n-- {title} --")
        print(disasm(bytes(blob[base : base + size]), base))


if __name__ == "__main__":
    main()
