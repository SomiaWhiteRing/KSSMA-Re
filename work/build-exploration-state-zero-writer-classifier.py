from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks

ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
OUT_LIB = ROOT / "librooneyj-exploration-state-zero-writer-classifier.so"

POST_FLOOR_PATCH = 0x00342108
POST_FLOOR_RESUME = 0x00341FAE
WRITES = [
    ("update-area4-selected-zero", 0x0034149A, 0x0034149E, bytes.fromhex("0023e363"), 0x70),
    ("update-state2-reset-zero", 0x00341538, 0x0034153C, bytes.fromhex("0023e363"), 0x72),
    ("update-focus-end-zero", 0x003415E2, 0x003415E6, bytes.fromhex("0023e363"), 0x74),
    ("preupdate-error-zero", 0x00342050, 0x00342054, bytes.fromhex("0023e363"), 0x76),
]
CAVE_BASE = 0x003E7720
WRITER_CAVES = [0x003E7760, 0x003E77A0, 0x003E7E60, 0x003E7EA0]
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


def writer_block(base: int, trap_imm: int) -> bytes:
    block = bytearray()
    block += asm("push {r2,r3}", base + len(block))
    block += load_addr("r2", base + len(block), STATE_ADDR)
    block += asm(
        f"""
        ldr r3, [r2]
        cmp r3, #1
        bne replay
        udf #{trap_imm}
    replay:
        pop {{r2,r3}}
        movs r3, #0
        str r3, [r4, #0x3c]
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def main() -> None:
    blob = bytearray(STOCK_LIB.read_bytes())
    require(blob, POST_FLOOR_PATCH, bytes.fromhex("0223e3634fe7"))
    require(blob, CAVE_BASE, b"\x00" * 0xC0)
    require(blob, 0x003E7E60, b"\x00" * 0x100)
    for _, patch, _, expected, _ in WRITES:
        require(blob, patch, expected)

    post = post_floor_block()
    blob[CAVE_BASE : CAVE_BASE + len(post)] = post
    branch(blob, CAVE_BASE + len(post) - 4, POST_FLOOR_RESUME)
    branch(blob, POST_FLOOR_PATCH, CAVE_BASE)
    blob[POST_FLOOR_PATCH + 4 : POST_FLOOR_PATCH + 6] = bytes.fromhex("c046")

    for (name, patch, resume, _, trap), cave in zip(WRITES, WRITER_CAVES):
        block = writer_block(cave, trap)
        if any(blob[cave : cave + len(block)]):
            raise SystemExit(f"{name} cave at {cave:#x} overlaps nonzero bytes")
        blob[cave : cave + len(block)] = block
        branch(blob, cave + len(block) - 4, resume)
        branch(blob, patch, cave)

    OUT_LIB.write_bytes(blob)
    digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"sha256={digest}")
    for title, base, size in [("post", POST_FLOOR_PATCH, 8)] + [(n, p, 8) for n,p,_,_,_ in WRITES] + [("cave1", CAVE_BASE, 0xC0), ("cave2", 0x003E7E60, 0x100)]:
        print(f"\n-- {title} --")
        print(disasm(bytes(blob[base:base+size]), base))

if __name__ == "__main__":
    main()
