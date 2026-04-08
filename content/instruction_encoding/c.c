#define _GNU_SOURCE
// Vidya — Instruction Encoding in C
//
// Encode x86_64 instructions to machine code bytes in a buffer.
// REX prefixes, ModR/M bytes, SIB bytes, immediate encoding.
// Each encoder function emits to a uint8_t buffer and returns
// the number of bytes written. Verified with assert.

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// ── Register codes ───────────────────────────────────────────────────
enum Reg64 {
    RAX = 0, RCX = 1, RDX = 2, RBX = 3,
    RSP = 4, RBP = 5, RSI = 6, RDI = 7,
    R8  = 8, R9  = 9, R10 = 10, R11 = 11,
    R12 = 12, R13 = 13, R14 = 14, R15 = 15,
};

static uint8_t low3(enum Reg64 r)       { return (uint8_t)(r & 0x7); }
static int     needs_ext(enum Reg64 r)  { return r >= 8; }

// ── REX prefix: 0100WRXB ─────────────────────────────────────────────
static uint8_t rex_byte(int w, int r, int x, int b) {
    return (uint8_t)(0x40
        | (w ? 0x08 : 0)
        | (r ? 0x04 : 0)
        | (x ? 0x02 : 0)
        | (b ? 0x01 : 0));
}

// ── ModR/M: [mod(2)][reg(3)][r/m(3)] ─────────────────────────────────
static uint8_t modrm(uint8_t mod, uint8_t reg, uint8_t rm) {
    return (uint8_t)(((mod & 0x3) << 6) | ((reg & 0x7) << 3) | (rm & 0x7));
}

// ── SIB: [scale(2)][index(3)][base(3)] ───────────────────────────────
static uint8_t sib(uint8_t scale, uint8_t index, uint8_t base) {
    return (uint8_t)(((scale & 0x3) << 6) | ((index & 0x7) << 3) | (base & 0x7));
}

// ── Emit helpers ─────────────────────────────────────────────────────
static int emit8(uint8_t *buf, int pos, uint8_t val) {
    buf[pos] = val;
    return pos + 1;
}

static int emit32(uint8_t *buf, int pos, int32_t val) {
    memcpy(&buf[pos], &val, 4);
    return pos + 4;
}

static int emit64(uint8_t *buf, int pos, int64_t val) {
    memcpy(&buf[pos], &val, 8);
    return pos + 8;
}

// ── MOV r64, imm64 ──────────────────────────────────────────────────
// REX.W + (0xB8 + rd) + imm64 = 10 bytes
static int encode_mov_reg_imm64(uint8_t *buf, enum Reg64 dst, int64_t imm) {
    int p = 0;
    p = emit8(buf, p, rex_byte(1, 0, 0, needs_ext(dst)));
    p = emit8(buf, p, (uint8_t)(0xB8 + low3(dst)));
    p = emit64(buf, p, imm);
    return p;
}

// ── MOV r64, r64 ────────────────────────────────────────────────────
// REX.W + 0x89 + ModR/M(11, src, dst) = 3 bytes
static int encode_mov_reg_reg(uint8_t *buf, enum Reg64 dst, enum Reg64 src) {
    int p = 0;
    p = emit8(buf, p, rex_byte(1, needs_ext(src), 0, needs_ext(dst)));
    p = emit8(buf, p, 0x89);
    p = emit8(buf, p, modrm(0x3, low3(src), low3(dst)));
    return p;
}

// ── ADD r64, r64 ────────────────────────────────────────────────────
// REX.W + 0x01 + ModR/M(11, src, dst) = 3 bytes
static int encode_add_reg_reg(uint8_t *buf, enum Reg64 dst, enum Reg64 src) {
    int p = 0;
    p = emit8(buf, p, rex_byte(1, needs_ext(src), 0, needs_ext(dst)));
    p = emit8(buf, p, 0x01);
    p = emit8(buf, p, modrm(0x3, low3(src), low3(dst)));
    return p;
}

// ── ADD r64, imm8 (sign-extended) ────────────────────────────────────
// REX.W + 0x83 + ModR/M(11, /0, dst) + imm8 = 4 bytes
static int encode_add_reg_imm8(uint8_t *buf, enum Reg64 dst, int8_t imm) {
    int p = 0;
    p = emit8(buf, p, rex_byte(1, 0, 0, needs_ext(dst)));
    p = emit8(buf, p, 0x83);
    p = emit8(buf, p, modrm(0x3, 0, low3(dst)));  // /0 = ADD
    p = emit8(buf, p, (uint8_t)imm);
    return p;
}

// ── JMP rel32 ────────────────────────────────────────────────────────
// 0xE9 + rel32 = 5 bytes
// Displacement is relative to next instruction: rel32 = target - (jmp_addr + 5)
static int encode_jmp_rel32(uint8_t *buf, int32_t rel) {
    int p = 0;
    p = emit8(buf, p, 0xE9);
    p = emit32(buf, p, rel);
    return p;
}

// ── CALL rel32 ───────────────────────────────────────────────────────
// 0xE8 + rel32 = 5 bytes
static int encode_call_rel32(uint8_t *buf, int32_t rel) {
    int p = 0;
    p = emit8(buf, p, 0xE8);
    p = emit32(buf, p, rel);
    return p;
}

// ── RET ──────────────────────────────────────────────────────────────
// 0xC3 = 1 byte
static int encode_ret(uint8_t *buf) {
    buf[0] = 0xC3;
    return 1;
}

// ── SYSCALL ──────────────────────────────────────────────────────────
// 0x0F 0x05 = 2 bytes
static int encode_syscall(uint8_t *buf) {
    buf[0] = 0x0F;
    buf[1] = 0x05;
    return 2;
}

// ── Tests ────────────────────────────────────────────────────────────

static void test_rex_prefix(void) {
    assert(rex_byte(1, 0, 0, 0) == 0x48);  // REX.W
    assert(rex_byte(1, 0, 0, 1) == 0x49);  // REX.WB
    assert(rex_byte(1, 1, 0, 0) == 0x4C);  // REX.WR
    assert(rex_byte(1, 1, 1, 1) == 0x4F);  // REX.WRXB
    assert(rex_byte(0, 0, 0, 0) == 0x40);  // bare REX
}

static void test_modrm_byte(void) {
    // mod=11, reg=rbx(3), rm=rax(0)
    assert(modrm(0x3, 3, 0) == 0xD8);
    // mod=11, reg=rdx(2), rm=rcx(1)
    assert(modrm(0x3, 2, 1) == 0xD1);
    // mod=00, reg=rax(0), rm=100(SIB follows)
    assert(modrm(0x0, 0, 4) == 0x04);
    // Opcode extension: /5 for SUB, mod=11, rm=rax(0)
    assert(modrm(0x3, 5, 0) == 0xE8);
}

static void test_sib_byte(void) {
    // [rsp] encoding: scale=0, index=rsp(none=4), base=rsp(4)
    assert(sib(0, 4, 4) == 0x24);
    // [rbx + rcx*8]: scale=3, index=rcx(1), base=rbx(3)
    assert(sib(3, 1, 3) == 0xCB);
}

static void test_mov_imm64(void) {
    uint8_t buf[16];

    // mov rax, 0x400078 → 48 B8 78 00 40 00 00 00 00 00
    int n = encode_mov_reg_imm64(buf, RAX, 0x400078);
    assert(n == 10);
    uint8_t expect1[] = {0x48, 0xB8, 0x78, 0x00, 0x40, 0x00,
                         0x00, 0x00, 0x00, 0x00};
    assert(memcmp(buf, expect1, 10) == 0);

    // mov rcx, 0xDEADBEEFCAFEBABE
    n = encode_mov_reg_imm64(buf, RCX, (int64_t)0xDEADBEEFCAFEBABEULL);
    assert(n == 10);
    uint8_t expect2[] = {0x48, 0xB9, 0xBE, 0xBA, 0xFE, 0xCA,
                         0xEF, 0xBE, 0xAD, 0xDE};
    assert(memcmp(buf, expect2, 10) == 0);

    // mov r8, 1 → REX.WB (0x49)
    n = encode_mov_reg_imm64(buf, R8, 1);
    assert(n == 10);
    assert(buf[0] == 0x49);
    assert(buf[1] == 0xB8);  // 0xB8 + low3(R8) = 0xB8 + 0 = 0xB8
    assert(buf[2] == 0x01);
}

static void test_mov_reg(void) {
    uint8_t buf[16];

    // mov rax, rbx → 48 89 D8
    int n = encode_mov_reg_reg(buf, RAX, RBX);
    assert(n == 3);
    assert(buf[0] == 0x48 && buf[1] == 0x89 && buf[2] == 0xD8);

    // mov r8, r15 → 4D 89 F8
    n = encode_mov_reg_reg(buf, R8, R15);
    assert(n == 3);
    assert(buf[0] == 0x4D && buf[1] == 0x89 && buf[2] == 0xF8);
}

static void test_add_reg(void) {
    uint8_t buf[16];

    // add rcx, rdx → 48 01 D1
    int n = encode_add_reg_reg(buf, RCX, RDX);
    assert(n == 3);
    assert(buf[0] == 0x48 && buf[1] == 0x01 && buf[2] == 0xD1);

    // add rax, rbx → 48 01 D8
    n = encode_add_reg_reg(buf, RAX, RBX);
    assert(n == 3);
    assert(buf[0] == 0x48 && buf[1] == 0x01 && buf[2] == 0xD8);

    // add r8, r15 → 4D 01 F8
    n = encode_add_reg_reg(buf, R8, R15);
    assert(n == 3);
    assert(buf[0] == 0x4D && buf[1] == 0x01 && buf[2] == 0xF8);
}

static void test_add_imm8(void) {
    uint8_t buf[16];

    // add rsp, -8 → 48 83 C4 F8 (ModR/M: mod=11, /0=ADD, rm=rsp)
    int n = encode_add_reg_imm8(buf, RSP, -8);
    assert(n == 4);
    uint8_t expect[] = {0x48, 0x83, 0xC4, 0xF8};
    assert(memcmp(buf, expect, 4) == 0);

    // add r12, 16 → 49 83 C4 10 (REX.WB for R12)
    n = encode_add_reg_imm8(buf, R12, 16);
    assert(n == 4);
    assert(buf[0] == 0x49 && buf[1] == 0x83 && buf[2] == 0xC4 && buf[3] == 0x10);
}

static void test_jmp(void) {
    uint8_t buf[16];

    // jmp +0x100 → E9 00 01 00 00
    int n = encode_jmp_rel32(buf, 0x100);
    assert(n == 5);
    uint8_t expect1[] = {0xE9, 0x00, 0x01, 0x00, 0x00};
    assert(memcmp(buf, expect1, 5) == 0);

    // jmp -0x50 (backward) → E9 B0 FF FF FF
    n = encode_jmp_rel32(buf, -0x50);
    assert(n == 5);
    uint8_t expect2[] = {0xE9, 0xB0, 0xFF, 0xFF, 0xFF};
    assert(memcmp(buf, expect2, 5) == 0);
}

static void test_call(void) {
    uint8_t buf[16];

    // call +0x100 → E8 00 01 00 00
    int n = encode_call_rel32(buf, 0x100);
    assert(n == 5);
    assert(buf[0] == 0xE8);
    assert(buf[1] == 0x00 && buf[2] == 0x01 && buf[3] == 0x00 && buf[4] == 0x00);
}

static void test_ret_and_syscall(void) {
    uint8_t buf[16];

    assert(encode_ret(buf) == 1);
    assert(buf[0] == 0xC3);

    assert(encode_syscall(buf) == 2);
    assert(buf[0] == 0x0F && buf[1] == 0x05);
}

int main(void) {
    test_rex_prefix();
    test_modrm_byte();
    test_sib_byte();
    test_mov_imm64();
    test_mov_reg();
    test_add_reg();
    test_add_imm8();
    test_jmp();
    test_call();
    test_ret_and_syscall();

    printf("All instruction encoding examples passed.\n");
    return 0;
}
