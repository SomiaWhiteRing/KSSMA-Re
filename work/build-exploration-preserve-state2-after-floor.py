from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks

ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
OUT_LIB = ROOT / "librooneyj-exploration-preserve-state2-after-floor.so"

POST_FLOOR_PATCH = 0x00342108
POST_FLOOR_RESUME = 0x00341FAE
FOCUS_ZERO_PATCH = 0x003415E2
FOCUS_ZERO_RESUME = 0x003415E6
CAVE_BASE = 0x003E7720
FOCUS_CAVE = 0x003E7760
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
        raise SystemExit(f"unexpected bytes at {offset:#x}: got {actual.hex()}, expected {expected.hex()}")


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
    require(blob, FOCUS_ZERO_PATCH, bytes.fromhex("0023e363"))
    require(blob, CAVE_BASE, b"\x00" * 0xC0)

    post = bytearray()
    post += asm("push {r4,r5,lr}", CAVE_BASE + len(post))
    post += load_addr("r2", CAVE_BASE + len(post), STATE_ADDR)
    post += asm(
        """
        movs r3, #1
        str r3, [r2]
        movs r3, #2
        str r3, [r4, #0x3c]
        pop {r4,r5,r6}
        """,
        CAVE_BASE + len(post),
    )
    post += b"\x00\x00\x00\x00"

    focus = bytearray()
    focus += asm("push {r2,r3}", FOCUS_CAVE + len(focus))
    focus += load_addr("r2", FOCUS_CAVE + len(focus), STATE_ADDR)
    focus += asm(
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
        FOCUS_CAVE + len(focus),
    )
    focus += b"\x00\x00\x00\x00"

    for name, base, block in [("post", CAVE_BASE, post), ("focus", FOCUS_CAVE, focus)]:
        if any(blob[base:base+len(block)]):
            raise SystemExit(f"{name} cave overlaps nonzero bytes")
        blob[base:base+len(block)] = block

    branch(blob, CAVE_BASE + len(post) - 4, POST_FLOOR_RESUME)
    branch(blob, FOCUS_CAVE + len(focus) - 4, FOCUS_ZERO_RESUME)
    branch(blob, POST_FLOOR_PATCH, CAVE_BASE)
    blob[POST_FLOOR_PATCH + 4 : POST_FLOOR_PATCH + 6] = bytes.fromhex("c046")
    branch(blob, FOCUS_ZERO_PATCH, FOCUS_CAVE)

    OUT_LIB.write_bytes(blob)
    digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"sha256={digest}")
    for title, base, size in [("post", POST_FLOOR_PATCH, 8), ("focus-zero", FOCUS_ZERO_PATCH, 8), ("cave", CAVE_BASE, 0xC0)]:
        print(f"\n-- {title} --")
        print(disasm(bytes(blob[base:base+size]), base))

if __name__ == "__main__":
    main()
