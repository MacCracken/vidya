# Vidya — Compiler Bootstrapping in Python
#
# Demonstrates a minimal two-pass assembler.
# This is the pattern used to bootstrap a compiler from nothing:
#   Pass 1: collect labels and compute byte offsets
#   Pass 2: emit machine code with resolved label addresses
#
# The key insight: a compiler is just a function from text to bytes.
# Self-hosting means that function can process its own source code.

import struct


# Instruction types
LOAD_IMM = 0  # load immediate into register
ADD      = 1  # add two registers
JUMP     = 2  # jump to label
LABEL    = 3  # label definition (no code emitted)
HALT     = 4  # stop execution


def make_load_imm(reg, value):
    return {"op": LOAD_IMM, "reg": reg, "value": value}


def make_add(dst, src):
    return {"op": ADD, "dst": dst, "src": src}


def make_jump(label):
    return {"op": JUMP, "label": label}


def make_label(name):
    return {"op": LABEL, "name": name}


def make_halt():
    return {"op": HALT}


def collect_labels(instructions):
    """Pass 1: Scan instructions, record label positions."""
    labels = {}
    offset = 0
    for inst in instructions:
        op = inst["op"]
        if op == LABEL:
            labels[inst["name"]] = offset
            # Labels emit no bytes
        elif op == LOAD_IMM:
            offset += 10  # REX.W + opcode + imm64
        elif op == ADD:
            offset += 3   # REX.W + opcode + ModR/M
        elif op == JUMP:
            offset += 5   # opcode + rel32
        elif op == HALT:
            offset += 1   # single byte
    return labels


def emit_code(instructions, labels):
    """Pass 2: Emit bytes with resolved label addresses."""
    code = bytearray()
    offset = 0
    for inst in instructions:
        op = inst["op"]
        if op == LOAD_IMM:
            code.append(0x48)                          # REX.W
            code.append(0xB8 + inst["reg"])             # opcode + reg
            code.extend(struct.pack("<q", inst["value"]))  # imm64 LE
            offset += 10
        elif op == ADD:
            code.append(0x48)                           # REX.W
            code.append(0x01)                           # ADD opcode
            code.append(0xC0 | (inst["src"] << 3) | inst["dst"])  # ModR/M
            offset += 3
        elif op == JUMP:
            target = labels[inst["label"]]
            rel = target - (offset + 5)
            code.append(0xE9)                           # JMP rel32
            code.extend(struct.pack("<i", rel))         # rel32 LE
            offset += 5
        elif op == LABEL:
            pass  # no bytes
        elif op == HALT:
            code.append(0xF4)                           # HLT
            offset += 1
    return code


def main():
    # A tiny program: load 10 into r0, load 32 into r1, add them, loop
    program = [
        make_label("start"),
        make_load_imm(0, 10),
        make_load_imm(1, 32),
        make_add(0, 1),
        make_jump("start"),
        make_halt(),
    ]

    labels = collect_labels(program)
    code = emit_code(program, labels)

    # Print results
    label_str = ", ".join(f"{k}={v}" for k, v in sorted(labels.items()))
    print(f"Labels: {{{label_str}}}")
    hex_str = " ".join(f"{b:02X}" for b in code)
    print(f"Code ({len(code)} bytes): [{hex_str}]")
    print("Bootstrap chain: source -> labels -> machine code")

    # Verify output: check known byte values
    # Layout: LOAD(10) + LOAD(10) + ADD(3) + JMP(5) + HLT(1) = 29 bytes
    assert len(code) == 29, f"expected 29 bytes, got {len(code)}"
    assert code[0] == 0x48, "first byte should be REX.W"
    assert code[1] == 0xB8, "second byte should be MOV r0 opcode"
    assert code[23] == 0xE9, "jump opcode at offset 23"
    assert code[28] == 0xF4, "halt at offset 28"
    assert labels["start"] == 0, "start label at offset 0"
    print("All verifications passed.")


if __name__ == "__main__":
    main()
