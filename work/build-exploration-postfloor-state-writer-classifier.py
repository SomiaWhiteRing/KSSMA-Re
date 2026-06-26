from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks

ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
OUT_LIB = ROOT / "librooneyj-exploration-postfloor-state-writer-classifier.so"

STATE_ADDR = 0x004493AC

POST_SET2_PATCH = 0x00342108
POST_SET2_RESUME = 0x00341FAE
CAVE_POST = 0x003E7720

WRITES_R4 = [
    ("update-area-select-state3", 0x003413A6, 0x003413AA, bytes.fromhex("0323e363"), 3, 0x80),
    ("update-area4-selected-zero", 0x0034149A, 0x0034149E, bytes.fromhex("0023e363"), 0, 0x82),
    ("update-state2-reset-zero", 0x00341538, 0x0034153C, bytes.fromhex("0023e363"), 0, 0x84),
    ("update-focus-end-zero", 0x003415E2, 0x003415E6, bytes.fromhex("0023e363"), 0, 0x86),
    ("preupdate-state1-to-state4", 0x00342036, 0x0034203A, bytes.fromhex("0423e363"), 4, 0x88),
    ("preupdate-error-zero", 0x00342050, 0x00342054, bytes.fromhex("0023e363"), 0, 0x8A),
]

INIT_WRITE = (
    "initmodel-state1",
    0x00340E8C,
    0x00340E90,
    bytes.fromhex("f2637354"),
    0x8C,
)

WRITER_CAVES = [
    0x003E7760,
    0x003E77A0,
    0x003E7E60,
    0x003E7EA0,
    0x003E7EE0,
    0x003E7F20,
]
INIT_CAVE = 0x003E7F60


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


def find_udf_pc(blob: bytes, addr: int) -> int:
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB + CS_MODE_LITTLE_ENDIAN)
    for ins in md.disasm(blob, addr):
        if ins.mnemonic == "udf":
            return ins.address
    raise SystemExit(f"no udf found in block at {addr:#x}")


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


def post_set2_block(base: int) -> bytes:
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


def writer_r4_block(base: int, value: int, trap_imm: int) -> bytes:
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
        movs r3, #{value}
        str r3, [r4, #0x3c]
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def init_writer_block(base: int, trap_imm: int) -> bytes:
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
        str r2, [r6, #0x3c]
        strb r3, [r6, r1]
        """,
        base + len(block),
    )
    block += b"\x00\x00\x00\x00"
    return bytes(block)


def main() -> None:
    blob = bytearray(STOCK_LIB.read_bytes())
    require(blob, POST_SET2_PATCH, bytes.fromhex("0223e3634fe7"))
    require(blob, CAVE_POST, b"\x00" * 0xC0)
    require(blob, 0x003E7E60, b"\x00" * 0x1A0)
    for _, patch, _, expected, _, _ in WRITES_R4:
        require(blob, patch, expected)
    _, init_patch, _, init_expected, _ = INIT_WRITE
    require(blob, init_patch, init_expected)

    post = post_set2_block(CAVE_POST)
    blob[CAVE_POST : CAVE_POST + len(post)] = post
    branch(blob, CAVE_POST + len(post) - 4, POST_SET2_RESUME)
    branch(blob, POST_SET2_PATCH, CAVE_POST)
    blob[POST_SET2_PATCH + 4 : POST_SET2_PATCH + 6] = bytes.fromhex("c046")

    for (name, patch, resume, _, value, trap), cave in zip(WRITES_R4, WRITER_CAVES):
        block = writer_r4_block(cave, value, trap)
        if any(blob[cave : cave + len(block)]):
            raise SystemExit(f"{name} cave at {cave:#x} overlaps nonzero bytes")
        blob[cave : cave + len(block)] = block
        branch(blob, cave + len(block) - 4, resume)
        branch(blob, patch, cave)

    init_name, init_patch, init_resume, _, init_trap = INIT_WRITE
    init = init_writer_block(INIT_CAVE, init_trap)
    if any(blob[INIT_CAVE : INIT_CAVE + len(init)]):
        raise SystemExit(f"{init_name} cave at {INIT_CAVE:#x} overlaps nonzero bytes")
    blob[INIT_CAVE : INIT_CAVE + len(init)] = init
    branch(blob, INIT_CAVE + len(init) - 4, init_resume)
    branch(blob, init_patch, INIT_CAVE)

    OUT_LIB.write_bytes(blob)
    digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"sha256={digest}")
    print("pc map:")
    for (name, patch, _, _, value, trap), cave in zip(WRITES_R4, WRITER_CAVES):
        block = bytes(blob[cave : cave + 0x40])
        print(
            f"  {name}: trap_pc=0x{find_udf_pc(block, cave):08x} "
            f"udf=0x{trap:02x} writer=0x{patch:08x} writes_state={value}"
        )
    init_block = bytes(blob[INIT_CAVE : INIT_CAVE + 0x40])
    print(
        f"  {init_name}: trap_pc=0x{find_udf_pc(init_block, INIT_CAVE):08x} "
        f"udf=0x{init_trap:02x} writer=0x{init_patch:08x} writes_state=1"
    )
    for title, base, size in [
        ("post-set2", POST_SET2_PATCH, 8),
        ("init-write", init_patch, 8),
        *[(name, patch, 8) for name, patch, _, _, _, _ in WRITES_R4],
        ("cave-low", CAVE_POST, 0xC0),
        ("cave-high", 0x003E7E60, 0x1A0),
    ]:
        print(f"\n-- {title} --")
        print(disasm(bytes(blob[base : base + size]), base))


if __name__ == "__main__":
    main()
