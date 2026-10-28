# Vidya — Instruction Encoding in Python
#
# Manually encode x86_64 instructions to machine code bytes.
# REX prefixes, ModR/M bytes, SIB bytes, immediate encoding.
# struct.pack handles little-endian byte emission.
# Every encoding is verified against known-good byte sequences.

import struct


def main():
    test_rex_prefix()
    test_modrm_byte()
    test_sib_byte()
    test_mov_reg_imm64()
    test_add_reg_reg()
    test_jmp_rel32()
    test_ret()
    test_mov_reg_reg()
    test_special_cases()

    print("All instruction encoding examples passed.")


# ── Register encoding ────────────────────────────────────────────────
# x86_64 register codes (low 3 bits used in ModR/M and opcode)
RAX, RCX, RDX, RBX = 0, 1, 2, 3
RSP, RBP, RSI, RDI = 4, 5, 6, 7
R8, R9, R10, R11 = 8, 9, 10, 11
R12, R13, R14, R15 = 12, 13, 14, 15


def low3(reg: int) -> int:
    """Low 3 bits of register code (for ModR/M/SIB encoding)."""
    return reg & 0x7


def needs_rex_ext(reg: int) -> bool:
    """Whether register needs REX extension (R8-R15)."""
    return reg >= 8


# ── REX prefix ────────────────────────────────────────────────────────
def rex(w: bool = False, r: bool = False,
        x: bool = False, b: bool = False) -> int:
    """Build REX prefix: 0100WRXB.

    W = 64-bit operand size
    R = extends ModR/M.reg
    X = extends SIB.index
    B = extends ModR/M.r/m or SIB.base
    """
    return (0x40
            | (0x08 if w else 0)
            | (0x04 if r else 0)
            | (0x02 if x else 0)
            | (0x01 if b else 0))


def test_rex_prefix():
    # REX.W only (64-bit operand, no extended registers)
    assert rex(w=True) == 0x48
    # REX.WB (64-bit + extended r/m, e.g. R8 as destination)
    assert rex(w=True, b=True) == 0x49
    # REX.WR (64-bit + extended reg field)
    assert rex(w=True, r=True) == 0x4C
    # REX.WRXB (all bits set)
    assert rex(w=True, r=True, x=True, b=True) == 0x4F
    # Bare REX (no bits set — used to access spl/bpl/sil/dil)
    assert rex() == 0x40


# ── ModR/M byte ───────────────────────────────────────────────────────
def modrm(mod: int, reg: int, rm: int) -> int:
    """Build ModR/M byte: [mod(2)][reg(3)][r/m(3)].

    mod=11: register-register
    mod=00: [r/m] (memory, no displacement)
    mod=01: [r/m + disp8]
    mod=10: [r/m + disp32]
    reg: register operand or opcode extension (/0../7)
    r/m: register or memory operand
    """
    return ((mod & 0x3) << 6) | ((reg & 0x7) << 3) | (rm & 0x7)


def test_modrm_byte():
    # mod=11, reg=rbx(3), r/m=rax(0) → register-to-register
    assert modrm(0b11, RBX, RAX) == 0xD8
    # mod=11, reg=rdx(2), r/m=rcx(1)
    assert modrm(0b11, RDX, RCX) == 0xD1
    # mod=00, reg=rax(0), r/m=100(SIB follows)
    assert modrm(0b00, RAX, 0b100) == 0x04
    # mod=01, reg=rax(0), r/m=rbp(5) → [rbp + disp8]
    assert modrm(0b01, RAX, RBP) == 0x45


# ── SIB byte ──────────────────────────────────────────────────────────
def sib(scale: int, index: int, base: int) -> int:
    """Build SIB byte: [scale(2)][index(3)][base(3)].

    scale: 0=1, 1=2, 2=4, 3=8
    index: register for scaled index (4=none)
    base: base register
    """
    return ((scale & 0x3) << 6) | ((index & 0x7) << 3) | (base & 0x7)


def test_sib_byte():
    # [rsp] needs SIB(0x24): scale=0, index=rsp(none), base=rsp
    assert sib(0, RSP, RSP) == 0x24
    # [rbx + rcx*8]: scale=3(8), index=rcx(1), base=rbx(3)
    assert sib(3, RCX, RBX) == 0xCB


# ── MOV r64, imm64 ───────────────────────────────────────────────────
def encode_mov_reg_imm64(dst: int, imm: int) -> bytes:
    """Encode MOV r64, imm64: REX.W + (0xB8 + rd) + imm64.

    This is the 10-byte absolute move — loads a full 64-bit immediate.
    The register is encoded directly in the opcode byte (0xB8+rd).
    """
    prefix = rex(w=True, b=needs_rex_ext(dst))
    opcode = 0xB8 + low3(dst)
    # imm64 as unsigned little-endian 8 bytes
    return bytes([prefix, opcode]) + struct.pack("<Q", imm & 0xFFFFFFFFFFFFFFFF)


def test_mov_reg_imm64():
    # mov rax, 0x400078
    result = encode_mov_reg_imm64(RAX, 0x400078)
    assert result == bytes([0x48, 0xB8,
                            0x78, 0x00, 0x40, 0x00,
                            0x00, 0x00, 0x00, 0x00])
    assert len(result) == 10  # always 10 bytes

    # mov rcx, 0xDEADBEEFCAFEBABE
    result = encode_mov_reg_imm64(RCX, 0xDEADBEEFCAFEBABE)
    assert result == bytes([0x48, 0xB9,
                            0xBE, 0xBA, 0xFE, 0xCA,
                            0xEF, 0xBE, 0xAD, 0xDE])

    # mov r8, 1 (extended register needs REX.B)
    result = encode_mov_reg_imm64(R8, 1)
    assert result == bytes([0x49, 0xB8,
                            0x01, 0x00, 0x00, 0x00,
                            0x00, 0x00, 0x00, 0x00])


# ── ADD r64, r64 ──────────────────────────────────────────────────────
def encode_add_reg_reg(dst: int, src: int) -> bytes:
    """Encode ADD r/m64, r64: REX.W + 0x01 + ModR/M(11, src, dst).

    ModR/M mod=11 means register-to-register.
    reg field = source, r/m field = destination.
    """
    prefix = rex(w=True, r=needs_rex_ext(src), b=needs_rex_ext(dst))
    return bytes([prefix, 0x01, modrm(0b11, low3(src), low3(dst))])


def test_add_reg_reg():
    # add rcx, rdx → 48 01 D1 (REX.W + ADD + ModR/M(11, rdx, rcx))
    result = encode_add_reg_reg(RCX, RDX)
    assert result == bytes([0x48, 0x01, 0xD1])

    # add rax, rbx → 48 01 D8
    result = encode_add_reg_reg(RAX, RBX)
    assert result == bytes([0x48, 0x01, 0xD8])

    # add r8, r15 → 4D 01 F8 (REX.WRB)
    result = encode_add_reg_reg(R8, R15)
    assert result == bytes([0x4D, 0x01, 0xF8])

    # add rax, r9 → 4C 01 C8 (REX.WR for extended src)
    result = encode_add_reg_reg(RAX, R9)
    assert result == bytes([0x4C, 0x01, 0xC8])


# ── JMP rel32 ─────────────────────────────────────────────────────────
def encode_jmp_rel32(rel: int) -> bytes:
    """Encode JMP rel32: 0xE9 + rel32 (signed, little-endian).

    Displacement is relative to the NEXT instruction (after the 5-byte JMP).
    To jump to address T from JMP at address A: rel32 = T - (A + 5).
    """
    return bytes([0xE9]) + struct.pack("<i", rel)


def test_jmp_rel32():
    # jmp +0x100
    result = encode_jmp_rel32(0x100)
    assert result == bytes([0xE9, 0x00, 0x01, 0x00, 0x00])
    assert len(result) == 5

    # jmp -0x50 (backward jump, negative displacement)
    result = encode_jmp_rel32(-0x50)
    assert result == bytes([0xE9, 0xB0, 0xFF, 0xFF, 0xFF])

    # jmp +0 (jump to next instruction — effectively a NOP)
    result = encode_jmp_rel32(0)
    assert result == bytes([0xE9, 0x00, 0x00, 0x00, 0x00])


# ── RET ───────────────────────────────────────────────────────────────
def encode_ret() -> bytes:
    """Encode RET: single byte 0xC3."""
    return bytes([0xC3])


def test_ret():
    assert encode_ret() == bytes([0xC3])
    assert len(encode_ret()) == 1


# ── MOV r64, r64 ──────────────────────────────────────────────────────
def encode_mov_reg_reg(dst: int, src: int) -> bytes:
    """Encode MOV r/m64, r64: REX.W + 0x89 + ModR/M(11, src, dst)."""
    prefix = rex(w=True, r=needs_rex_ext(src), b=needs_rex_ext(dst))
    return bytes([prefix, 0x89, modrm(0b11, low3(src), low3(dst))])


def test_mov_reg_reg():
    # mov rax, rbx → 48 89 D8
    result = encode_mov_reg_reg(RAX, RBX)
    assert result == bytes([0x48, 0x89, 0xD8])

    # mov r8, r15 → 4D 89 F8
    result = encode_mov_reg_reg(R8, R15)
    assert result == bytes([0x4D, 0x89, 0xF8])


# ── Special cases ─────────────────────────────────────────────────────
def test_special_cases():
    # Verify ModR/M field layout matches Intel manual:
    #   mod=11, reg=rdx(010), rm=rcx(001) → 11_010_001 = 0xD1
    assert modrm(0b11, 0b010, 0b001) == 0b11010001
    assert modrm(0b11, 0b010, 0b001) == 0xD1

    # ModR/M for opcode extension: ADD r/m64, imm8 uses /0
    #   mod=11, /0(000), r/m=rsp(100) → 11_000_100 = 0xC4
    assert modrm(0b11, 0, RSP) == 0xC4

    # SUB uses /5: mod=11, /5(101), r/m=rax(000) → 11_101_000 = 0xE8
    assert modrm(0b11, 5, RAX) == 0xE8

    # Full encoding: add rsp, -8 → 48 83 C4 F8
    #   REX.W=0x48, opcode=0x83 (imm8), ModR/M(11, /0, rsp), imm8=-8
    prefix = rex(w=True)
    enc = bytes([prefix, 0x83, modrm(0b11, 0, RSP),
                 struct.pack("<b", -8)[0]])
    assert enc == bytes([0x48, 0x83, 0xC4, 0xF8])

    # SYSCALL is a fixed 2-byte instruction
    syscall = bytes([0x0F, 0x05])
    assert len(syscall) == 2


if __name__ == "__main__":
    main()
