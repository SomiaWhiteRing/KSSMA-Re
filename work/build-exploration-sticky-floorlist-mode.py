from __future__ import annotations

import hashlib
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_LITTLE_ENDIAN, CS_MODE_THUMB, Cs
from keystone import KS_ARCH_ARM, KS_MODE_LITTLE_ENDIAN, KS_MODE_THUMB, Ks


ROOT = Path(__file__).resolve().parent
STOCK_LIB = ROOT / "million_cn" / "apktool" / "lib" / "armeabi" / "librooneyj.so"
OUT_LIB = ROOT / "librooneyj-exploration-sticky-floorlist-mode.so"

STOCK_SHA256 = "CC922CCCC226047B1BF6F19A7A4C06733CDD7434916085477F500E349C836C27"

FLOOR_RESPONSE_GATE_PATCH = 0x003420B6
FLOOR_LIST_ACTIVE2_PATH = 0x00342142

SET_RECORDS_POST_PATCH = 0x002D2ED8
SET_RECORDS_POST_RESUME = 0x002D2EDC
ACTION_84_PATCH = 0x002D332C
ACTION_84_RESUME = 0x002D3332

GATE_CAVE = 0x003E7720
SAVE_PICKLIST_CAVE = 0x003E77A0
ACTION_84_CAVE = 0x003E7E60

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


def gate_block(base: int) -> bytes:
    block = bytearray()
    block += load_addr("r2", base + len(block), STATE_ADDR)
    block += asm(
        """
        movs r3, #1
        str r3, [r2]
        movs r3, #0
        strb r3, [r4, r5]
        b.w 0x342142
        """,
        base + len(block),
    )
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
        movs r3, #0
        str r3, [r2]
        str r3, [r8, #0x84]
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


def write_block(blob: bytearray, name: str, base: int, block: bytes, limit: int) -> None:
    if len(block) > limit:
        raise SystemExit(f"{name} cave too large: {len(block)} > {limit}")
    if any(blob[base : base + len(block)]):
        raise SystemExit(f"{name} cave at {base:#x} overlaps nonzero bytes")
    blob[base : base + len(block)] = block


def assert_branch_target(blob: bytes, offset: int, target: int) -> None:
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB + CS_MODE_LITTLE_ENDIAN)
    ins = next(md.disasm(bytes(blob[offset : offset + 4]), offset), None)
    if ins is None:
        raise SystemExit(f"no instruction at {offset:#x}")
    if not ins.mnemonic.startswith("b"):
        raise SystemExit(f"expected branch at {offset:#x}, got {ins.mnemonic} {ins.op_str}")
    actual = int(ins.op_str.removeprefix("#"), 16)
    if actual != target:
        raise SystemExit(
            f"bad branch at {offset:#x}: got {actual:#x}, expected {target:#x}"
        )


def main() -> None:
    blob = bytearray(STOCK_LIB.read_bytes())
    digest = hashlib.sha256(blob).hexdigest().upper()
    if digest != STOCK_SHA256:
        raise SystemExit(f"unexpected stock sha256: got {digest}, expected {STOCK_SHA256}")

    require(blob, FLOOR_RESPONSE_GATE_PATCH, bytes.fromhex("3d482368"))
    require(blob, SET_RECORDS_POST_PATCH, bytes.fromhex("49464a68"))
    require(blob, ACTION_84_PATCH, bytes.fromhex("fa2284235200"))
    require(blob, GATE_CAVE, b"\x00" * 0xC0)
    require(blob, ACTION_84_CAVE, b"\x00" * 0x80)

    gate = gate_block(GATE_CAVE)
    save_picklist = save_picklist_block(SAVE_PICKLIST_CAVE)
    action84 = action84_block(ACTION_84_CAVE)

    write_block(blob, "gate", GATE_CAVE, gate, SAVE_PICKLIST_CAVE - GATE_CAVE)
    write_block(blob, "save_picklist", SAVE_PICKLIST_CAVE, save_picklist, (GATE_CAVE + 0xC0) - SAVE_PICKLIST_CAVE)
    write_block(blob, "action84", ACTION_84_CAVE, action84, 0x80)

    branch(blob, SAVE_PICKLIST_CAVE + len(save_picklist) - 4, SET_RECORDS_POST_RESUME)
    branch(blob, ACTION_84_CAVE + len(action84) - 4, ACTION_84_RESUME)

    branch(blob, FLOOR_RESPONSE_GATE_PATCH, GATE_CAVE)
    branch(blob, SET_RECORDS_POST_PATCH, SAVE_PICKLIST_CAVE)
    branch(blob, ACTION_84_PATCH, ACTION_84_CAVE)
    blob[ACTION_84_PATCH + 4 : ACTION_84_PATCH + 6] = asm("nop", ACTION_84_PATCH + 4)

    assert_branch_target(blob, FLOOR_RESPONSE_GATE_PATCH, GATE_CAVE)
    assert_branch_target(blob, SET_RECORDS_POST_PATCH, SAVE_PICKLIST_CAVE)
    assert_branch_target(blob, ACTION_84_PATCH, ACTION_84_CAVE)
    assert_branch_target(blob, GATE_CAVE + len(gate) - 4, FLOOR_LIST_ACTIVE2_PATH)
    assert_branch_target(blob, SAVE_PICKLIST_CAVE + len(save_picklist) - 4, SET_RECORDS_POST_RESUME)
    assert_branch_target(blob, ACTION_84_CAVE + len(action84) - 4, ACTION_84_RESUME)

    OUT_LIB.write_bytes(blob)
    patched_digest = hashlib.sha256(blob).hexdigest().upper()
    print(f"wrote {OUT_LIB}")
    print(f"stock_sha256={digest}")
    print(f"sha256={patched_digest}")
    print("branch map:")
    print(f"  floor response gate: 0x{FLOOR_RESPONSE_GATE_PATCH:08x} -> 0x{GATE_CAVE:08x}; stock +0x56 fresh floor path -> 0x{FLOOR_LIST_ACTIVE2_PATH:08x}")
    print(f"  save floor_list PickList: 0x{SET_RECORDS_POST_PATCH:08x} -> 0x{SAVE_PICKLIST_CAVE:08x}; resume -> 0x{SET_RECORDS_POST_RESUME:08x}")
    print(f"  floor_list +0x84 action guard: 0x{ACTION_84_PATCH:08x} -> 0x{ACTION_84_CAVE:08x}; resume -> 0x{ACTION_84_RESUME:08x}")
    print("trap map: none; this patch uses branch gates only")
    for title, base, size in [
        ("floor response gate patch", FLOOR_RESPONSE_GATE_PATCH, 8),
        ("setRecords-save patch", SET_RECORDS_POST_PATCH, 8),
        ("action84 patch", ACTION_84_PATCH, 10),
        ("gate cave", GATE_CAVE, SAVE_PICKLIST_CAVE - GATE_CAVE),
        ("save cave", SAVE_PICKLIST_CAVE, 0x40),
        ("action84 cave", ACTION_84_CAVE, 0x80),
    ]:
        print(f"\n-- {title} --")
        print(disasm(bytes(blob[base : base + size]), base))


if __name__ == "__main__":
    main()
