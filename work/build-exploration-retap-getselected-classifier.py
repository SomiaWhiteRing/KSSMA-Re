from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks

ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
OUT_LIB = ROOT / "librooneyj-exploration-retap-getselected-classifier.so"

POST_FLOOR_PATCH = 0x00342108
POST_FLOOR_RESUME = 0x00341FAE
AREA0_AFTER_CALL_PATCH = 0x0034137A
AREA0_AFTER_CALL_RESUME = 0x0034137E
FLOOR2_AFTER_CALL_PATCH = 0x003413CA
FLOOR2_AFTER_CALL_RESUME = 0x003413CE
AREA4_AFTER_CALL_PATCH = 0x00341488
AREA4_AFTER_CALL_RESUME = 0x0034148C

CAVE_BASE = 0x003E7720
AREA0_CAVE = 0x003E7760
FLOOR2_CAVE = 0x003E77A0
AREA4_CAVE = 0x003E7E60
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


def post_floor_block() -> bytes:
    block = bytearray()
    block += asm("push {r4,r5,lr}", CAVE_BASE + len(block))
    block += load_addr("r2", CAVE_BASE + len(block), STATE_ADDR)
    block += asm(
        """
        movs r3, #1
        str r3, [r2]
        movs r3, #2
        str r3, [r4, #0x3c]
        pop {r4,r5,r6}
        """,
        CAVE_BASE + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def classifier_block(base: int, replay: str, trap_imm: int) -> bytes:
    block = bytearray()
    block += asm("push {r1,r2}", base + len(block))
    block += load_addr("r1", base + len(block), STATE_ADDR)
    block += asm(
        f"""
        ldr r2, [r1]
        cmp r2, #1
        bne replay_label
        cmp r0, #0
        blt replay_label
        udf #{trap_imm}
    replay_label:
        pop {{r1,r2}}
        {replay}
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def main() -> None:
    blob = bytearray(STOCK_LIB.read_bytes())
    require(blob, POST_FLOOR_PATCH, bytes.fromhex("0223e3634fe7"))
    require(blob, AREA0_AFTER_CALL_PATCH, bytes.fromhex("002815db"))
    require(blob, FLOOR2_AFTER_CALL_PATCH, bytes.fromhex("061eeddb"))
    require(blob, AREA4_AFTER_CALL_PATCH, bytes.fromhex("72680023"))
    require(blob, CAVE_BASE, b"\x00" * 0xC0)
    require(blob, AREA4_CAVE, b"\x00" * 0x80)

    post = post_floor_block()
    area0 = classifier_block(
        AREA0_CAVE,
        """
        cmp r0, #0
        bge continue_original
        b.w 0x3413aa
    continue_original:
        """,
        0x60,
    )
    floor2 = classifier_block(
        FLOOR2_CAVE,
        """
        subs r6, r0, #0
        bge continue_original
        b.w 0x3413aa
    continue_original:
        """,
        0x62,
    )
    area4 = classifier_block(AREA4_CAVE, "ldr r2, [r6, #4]\nmovs r3, #0", 0x64)

    blocks = [(CAVE_BASE, post), (AREA0_CAVE, area0), (FLOOR2_CAVE, floor2), (AREA4_CAVE, area4)]
    for base, block in blocks:
        if any(blob[base : base + len(block)]):
            raise SystemExit(f"cave at {base:#x} overlaps nonzero bytes")
        blob[base : base + len(block)] = block

    branch(blob, CAVE_BASE + len(post) - 4, POST_FLOOR_RESUME)
    branch(blob, AREA0_CAVE + len(area0) - 4, AREA0_AFTER_CALL_RESUME)
    branch(blob, FLOOR2_CAVE + len(floor2) - 4, FLOOR2_AFTER_CALL_RESUME)
    branch(blob, AREA4_CAVE + len(area4) - 4, AREA4_AFTER_CALL_RESUME)

    branch(blob, POST_FLOOR_PATCH, CAVE_BASE)
    blob[POST_FLOOR_PATCH + 4 : POST_FLOOR_PATCH + 6] = bytes.fromhex("c046")
    branch(blob, AREA0_AFTER_CALL_PATCH, AREA0_CAVE)
    branch(blob, FLOOR2_AFTER_CALL_PATCH, FLOOR2_CAVE)
    branch(blob, AREA4_AFTER_CALL_PATCH, AREA4_CAVE)

    OUT_LIB.write_bytes(blob)
    digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"sha256={digest}")
    for title, base, size in [
        ("post-floor patch", POST_FLOOR_PATCH, 8),
        ("area0 after getSelected patch", AREA0_AFTER_CALL_PATCH, 8),
        ("floor2 after getSelected patch", FLOOR2_AFTER_CALL_PATCH, 8),
        ("area4 after getSelected patch", AREA4_AFTER_CALL_PATCH, 8),
        ("first cave", CAVE_BASE, 0xC0),
        ("area4 cave", AREA4_CAVE, 0x80),
    ]:
        print(f"\n-- {title} --")
        print(disasm(bytes(blob[base : base + size]), base))


if __name__ == "__main__":
    main()
