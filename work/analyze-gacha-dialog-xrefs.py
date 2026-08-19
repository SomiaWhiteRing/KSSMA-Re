#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path

from capstone import CS_ARCH_ARM, CS_MODE_THUMB, Cs
from capstone.arm import ARM_OP_IMM
from elftools.elf.elffile import ELFFile


ACCEPTED_SHA256 = "36A4826BD42BCF203B51D0344AF5A1B479B961BD26DDB4685DD01A8B325B69A2"
TARGETS = {
    "DialogModel_initDialog": 0x001D4F7C,
    "LayoutScene_showDialog": 0x001F3D94,
    "SceneControl_push": 0x001F6950,
}


def main():
    parser = argparse.ArgumentParser(description="List direct Thumb call sites for the gacha dialog producer path.")
    parser.add_argument("library", type=Path)
    parser.add_argument("--start", type=lambda value: int(value, 0))
    parser.add_argument("--end", type=lambda value: int(value, 0))
    args = parser.parse_args()

    blob = args.library.read_bytes()
    digest = hashlib.sha256(blob).hexdigest().upper()
    if digest != ACCEPTED_SHA256:
        raise SystemExit(f"unexpected library SHA-256: {digest}")

    with args.library.open("rb") as stream:
        elf = ELFFile(stream)
        text = elf.get_section_by_name(".text")
        if text is None:
            raise SystemExit("ELF has no .text section")
        text_address = int(text["sh_addr"])
        text_data = text.data()

    disassembler = Cs(CS_ARCH_ARM, CS_MODE_THUMB)
    disassembler.detail = True
    disassembler.skipdata = True
    xrefs = {name: [] for name in TARGETS}
    calls = []
    for instruction in disassembler.disasm(text_data, text_address):
        if not instruction.mnemonic.startswith("bl") or not instruction.operands:
            continue
        operand = instruction.operands[0]
        if operand.type != ARM_OP_IMM:
            continue
        target = int(operand.imm) & ~1
        calls.append((instruction.address, target, instruction.mnemonic, instruction.op_str))
        for name, wanted in TARGETS.items():
            if target == wanted:
                xrefs[name].append({
                    "address": f"0x{instruction.address:08x}",
                    "mnemonic": instruction.mnemonic,
                    "operands": instruction.op_str,
                })

    literal = (90100).to_bytes(4, "little")
    literal_offsets = []
    cursor = 0
    while True:
        cursor = blob.find(literal, cursor)
        if cursor < 0:
            break
        literal_offsets.append(f"0x{cursor:08x}")
        cursor += 1

    print(json.dumps({
        "library": str(args.library),
        "sha256": digest,
        "textAddress": f"0x{text_address:08x}",
        "textSize": len(text_data),
        "decodedDirectCalls": len(calls),
        "xrefs": xrefs,
        "scene90100LiteralFileOffsets": literal_offsets,
    }, indent=2))

    if args.start is not None or args.end is not None:
        if args.start is None or args.end is None or args.start >= args.end:
            raise SystemExit("--start and --end must define a non-empty range")
        range_start = args.start & ~1
        range_end = args.end & ~1
        if range_start < text_address or range_end > text_address + len(text_data):
            raise SystemExit("requested range is outside .text")
        code = text_data[range_start - text_address:range_end - text_address]
        print("\nDISASSEMBLY")
        for instruction in disassembler.disasm(code, range_start):
            raw = instruction.bytes.hex()
            print(f"0x{instruction.address:08x}  {raw:<8}  {instruction.mnemonic:<8} {instruction.op_str}")


if __name__ == "__main__":
    main()
