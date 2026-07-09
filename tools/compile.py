#!/usr/bin/env python3
"""Two-pass assembler for this project's CPU instruction set.

Each mnemonic is encoded by its own documented operand order rather than
one generic parser, since `load` lists (dest, addr, imm) while `store`
lists (addr, data, imm).

Source syntax:
  - Comments: `--` to end of line.
  - Blank lines: ignored.
  - Labels: a line consisting of `#name` marks the *next* instruction's
    address as `name`, for use as a branch/jump target. Labels do not
    consume an instruction slot.
  - Everything else is one instruction per line: a mnemonic followed by
    space-separated operands. Registers are written `r0`..`r15`.
    beq/bne/jump accept either a `#label` or a raw signed integer for their
    branch-offset/address operand.

Produces two plain machine-code output files (never VHDL or other HDL):
  1. A human-readable binary listing: each instruction's fields
     space-separated and grouped, annotated with the original source line.
  2. A plain machine-code file: one instruction per line, each line exactly
     32 characters of '0'/'1', nothing else -- the actual compiled binary.
"""

import argparse
import re
import sys

INSTRUCTION_MEMORY_SIZE = 1024

R_TYPE_FUNCT = {
    "add": 0b000,
    "sub": 0b001,
    "and": 0b010,
    "or": 0b011,
    "xor": 0b100,
    "not": 0b101,
    "lbs": 0b110,
    "inc": 0b111,
}

NOP_OPCODE = 0x3F


class AssemblyError(Exception):
    def __init__(self, line_number, message):
        super().__init__(f"line {line_number}: {message}")


def parse_register(token, line_number):
    match = re.fullmatch(r"r(\d+)", token)
    if not match:
        raise AssemblyError(line_number, f"expected a register (r0-r15), got '{token}'")
    register = int(match.group(1))
    if not 0 <= register <= 15:
        raise AssemblyError(line_number, f"register out of range (0-15): '{token}'")
    return register


def parse_integer(token, line_number):
    try:
        return int(token, 0)
    except ValueError:
        raise AssemblyError(line_number, f"expected an integer, got '{token}'") from None


def encode_r_type(rs, rt, rd, funct):
    return (0 << 26) | (rs << 22) | (rt << 18) | (rd << 14) | (funct << 11)


def encode_i_type(opcode, rs, rt, immediate, line_number):
    if not -32768 <= immediate <= 65535:
        raise AssemblyError(line_number, f"immediate {immediate} does not fit in 16 bits")
    if immediate < 0:
        immediate += 1 << 16
    return (opcode << 26) | (rs << 22) | (rt << 18) | ((immediate & 0xFFFF) << 2)


def encode_j_type(opcode, address, line_number):
    if not 0 <= address < INSTRUCTION_MEMORY_SIZE:
        raise AssemblyError(
            line_number,
            f"address {address} is out of range (0-{INSTRUCTION_MEMORY_SIZE - 1})",
        )
    return (opcode << 26) | (address << 16)


class ParsedInstruction:
    """One instruction, its address, and enough context to encode it once
    all labels are known (pass 1) and to render both output formats
    (pass 2)."""

    def __init__(self, address, line_number, source_line, mnemonic, operands):
        self.address = address
        self.line_number = line_number
        self.source_line = source_line
        self.mnemonic = mnemonic
        self.operands = operands


def tokenize_source(source_lines):
    """Pass 1: strip comments/blank lines, assign addresses, and record
    label -> address. Returns (instructions, labels)."""

    instructions = []
    labels = {}
    address = 0

    for line_number, raw_line in enumerate(source_lines, start=1):
        line = raw_line.split("--", 1)[0].strip()
        if not line:
            continue

        if line.startswith("#"):
            label_name = line[1:].strip()
            if not label_name:
                raise AssemblyError(line_number, "empty label name")
            if label_name in labels:
                raise AssemblyError(line_number, f"label '{label_name}' already defined")
            labels[label_name] = address
            continue

        tokens = line.split()
        mnemonic_tokens = 2 if tokens[0] == "load" and tokens[1:2] == ["immediate"] else 1
        mnemonic = " ".join(tokens[:mnemonic_tokens])
        operands = tokens[mnemonic_tokens:]

        if address >= INSTRUCTION_MEMORY_SIZE:
            raise AssemblyError(
                line_number,
                f"program exceeds instruction memory size ({INSTRUCTION_MEMORY_SIZE} words)",
            )

        instructions.append(
            ParsedInstruction(address, line_number, line, mnemonic, operands)
        )
        address += 1

    return instructions, labels


def resolve_branch_target(operand, current_address, labels, line_number):
    """beq/bne operands are a relative offset: either a raw integer, or a
    label resolved to (label_address - current_address)."""

    if operand.startswith("#"):
        label_name = operand[1:]
        if label_name not in labels:
            raise AssemblyError(line_number, f"undefined label '{operand}'")
        offset = labels[label_name] - current_address
    else:
        offset = parse_integer(operand, line_number)

    if not -512 <= offset <= 511:
        raise AssemblyError(
            line_number,
            f"branch offset {offset} does not fit in the 10-bit signed field (-512 to 511)",
        )
    return offset


def resolve_jump_target(operand, labels, line_number):
    """jump's operand is an absolute address: either a raw integer, or a
    label resolved directly to its own address."""

    if operand.startswith("#"):
        label_name = operand[1:]
        if label_name not in labels:
            raise AssemblyError(line_number, f"undefined label '{operand}'")
        return labels[label_name]
    return parse_integer(operand, line_number)


def encode_instruction(instruction, labels):
    mnemonic = instruction.mnemonic
    operands = instruction.operands
    line_number = instruction.line_number
    address = instruction.address

    if mnemonic in R_TYPE_FUNCT:
        # Always three register operands (rs, rt, rd), even for funct
        # codes like `not`/`lbs`/`inc` that only use one or two of them
        # (e.g. "inc r2 r2 r2").
        if len(operands) != 3:
            raise AssemblyError(line_number, f"'{mnemonic}' expects 3 register operands (rs rt rd)")
        rs = parse_register(operands[0], line_number)
        rt = parse_register(operands[1], line_number)
        rd = parse_register(operands[2], line_number)
        return encode_r_type(rs, rt, rd, R_TYPE_FUNCT[mnemonic])

    if mnemonic == "load immediate":
        if len(operands) != 2:
            raise AssemblyError(line_number, "'load immediate' expects (rt, immediate)")
        rt = parse_register(operands[0], line_number)
        immediate = parse_integer(operands[1], line_number)
        return encode_i_type(0x22, 0, rt, immediate, line_number)

    if mnemonic == "load":
        # Text order is (dest, addr, imm) -- opposite of `store` below.
        if len(operands) != 3:
            raise AssemblyError(line_number, "'load' expects (rt, rs, immediate)")
        rt = parse_register(operands[0], line_number)
        rs = parse_register(operands[1], line_number)
        immediate = parse_integer(operands[2], line_number)
        return encode_i_type(0x23, rs, rt, immediate, line_number)

    if mnemonic == "store":
        # Text order is (addr, data, imm) -- opposite of `load` above.
        if len(operands) != 3:
            raise AssemblyError(line_number, "'store' expects (rs, rt, immediate)")
        rs = parse_register(operands[0], line_number)
        rt = parse_register(operands[1], line_number)
        immediate = parse_integer(operands[2], line_number)
        return encode_i_type(0x21, rs, rt, immediate, line_number)

    if mnemonic in ("beq", "bne"):
        if len(operands) != 3:
            raise AssemblyError(line_number, f"'{mnemonic}' expects (rs, rt, label-or-offset)")
        rs = parse_register(operands[0], line_number)
        rt = parse_register(operands[1], line_number)
        offset = resolve_branch_target(operands[2], address, labels, line_number)
        opcode = 0x05 if mnemonic == "beq" else 0x04
        return encode_i_type(opcode, rs, rt, offset, line_number)

    if mnemonic == "jump":
        if len(operands) != 1:
            raise AssemblyError(line_number, "'jump' expects (label-or-address)")
        target = resolve_jump_target(operands[0], labels, line_number)
        return encode_j_type(0x02, target, line_number)

    if mnemonic == "nop":
        if operands:
            raise AssemblyError(line_number, "'nop' takes no operands")
        return encode_j_type(NOP_OPCODE, 0, line_number)

    raise AssemblyError(line_number, f"unknown mnemonic '{mnemonic}'")


def format_binary_listing_line(address, word, mnemonic, source_line):
    """Splits `word` into its format's fields (space-separated) for the
    human-readable output. Format is inferred from the mnemonic, matching
    exactly how encode_instruction dispatched it."""

    opcode_bits = f"{(word >> 26) & 0x3F:06b}"

    if mnemonic in R_TYPE_FUNCT:
        rs_bits = f"{(word >> 22) & 0xF:04b}"
        rt_bits = f"{(word >> 18) & 0xF:04b}"
        rd_bits = f"{(word >> 14) & 0xF:04b}"
        funct_bits = f"{(word >> 11) & 0x7:03b}"
        unused_bits = f"{word & 0x7FF:011b}"
        fields = f"{opcode_bits} {rs_bits} {rt_bits} {rd_bits} {funct_bits} {unused_bits}"
    elif mnemonic == "jump" or mnemonic == "nop":
        address_bits = f"{(word >> 16) & 0x3FF:010b}"
        unused_bits = f"{word & 0xFFFF:016b}"
        fields = f"{opcode_bits} {address_bits} {unused_bits}"
    else:
        rs_bits = f"{(word >> 22) & 0xF:04b}"
        rt_bits = f"{(word >> 18) & 0xF:04b}"
        immediate_bits = f"{(word >> 2) & 0xFFFF:016b}"
        unused_bits = f"{word & 0x3:02b}"
        fields = f"{opcode_bits} {rs_bits} {rt_bits} {immediate_bits} {unused_bits}"

    return f"{address:4d}: {fields}  -- {source_line}"


def write_binary_listing(path, encoded_instructions):
    with open(path, "w") as output_file:
        for instruction, word in encoded_instructions:
            output_file.write(
                format_binary_listing_line(
                    instruction.address, word, instruction.mnemonic, instruction.source_line
                )
                + "\n"
            )


def write_machine_code(path, encoded_instructions):
    """Emits the actual compiled binary: one line per instruction, each
    line exactly 32 characters of '0'/'1', in address order, nothing else
    -- no comments, no VHDL, no field separators (that's what the
    human-readable listing is for). This is the file
    program_loader_pkg.vhd's LoadProgramFromFile reads."""

    with open(path, "w") as output_file:
        for _, word in encoded_instructions:
            output_file.write(f"{word:032b}\n")


def assemble(source_lines):
    instructions, labels = tokenize_source(source_lines)
    encoded_instructions = [
        (instruction, encode_instruction(instruction, labels))
        for instruction in instructions
    ]
    return encoded_instructions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", help="assembly source file (.asm)")
    parser.add_argument(
        "--binary-out", required=True, help="output path for the human-readable binary listing"
    )
    parser.add_argument(
        "--bits-out", required=True, help="output path for the plain machine-code file"
    )
    arguments = parser.parse_args()

    with open(arguments.source) as source_file:
        source_lines = source_file.readlines()

    try:
        encoded_instructions = assemble(source_lines)
    except AssemblyError as error:
        print(f"error: {arguments.source}: {error}", file=sys.stderr)
        sys.exit(1)

    write_binary_listing(arguments.binary_out, encoded_instructions)
    write_machine_code(arguments.bits_out, encoded_instructions)

    print(
        f"assembled {len(encoded_instructions)} instructions from {arguments.source}\n"
        f"  binary listing -> {arguments.binary_out}\n"
        f"  machine code   -> {arguments.bits_out}"
    )


if __name__ == "__main__":
    main()
