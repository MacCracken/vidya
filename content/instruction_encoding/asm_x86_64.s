# Vidya — Instruction Encoding in x86_64 Assembly
#
# x86_64 instructions are variable-length (1-15 bytes). Each instruction
# may have: legacy prefixes, REX prefix, opcode (1-3 bytes), ModR/M byte,
# SIB byte, displacement (1/2/4 bytes), immediate (1/2/4/8 bytes).
#
# REX prefix (0x40-0x4F): extends registers to r8-r15, enables 64-bit
# operand size. Bits: 0100 W R X B
#   W = 64-bit operand size
#   R = extends ModR/M reg field (accesses r8-r15)
#   X = extends SIB index field
#   B = extends ModR/M r/m or SIB base field
#
# ModR/M byte: mod(2) | reg(3) | r/m(3)
#   mod=11: register direct
#   mod=00: [r/m] memory, no displacement
#   mod=01: [r/m + disp8]
#   mod=10: [r/m + disp32]
#   r/m=100: SIB byte follows
#   r/m=101 with mod=00: RIP-relative addressing

.intel_syntax noprefix
.global _start

.section .data
.align 8
value:      .quad 42
array:      .quad 10, 20, 30, 40, 50

.section .rodata
msg_pass:   .ascii "All instruction encoding examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    # ════════════════════════════════════════════════════════════════
    # 1. Simple register-register encodings (no REX needed for 32-bit)
    # ════════════════════════════════════════════════════════════════

    # xor eax, eax              → 31 C0
    # Opcode 31 = XOR r/m32, r32
    # ModR/M: C0 = 11 000 000 (mod=11 reg=eax r/m=eax)
    xor     eax, eax
    cmp     eax, 0
    jne     fail

    # mov ebx, 1                → BB 01 00 00 00
    # Opcode B8+rd = MOV r32, imm32 (BB = B8 + 3 for ebx)
    mov     ebx, 1
    cmp     ebx, 1
    jne     fail

    # ════════════════════════════════════════════════════════════════
    # 2. REX prefix — 64-bit operand size (REX.W)
    # ════════════════════════════════════════════════════════════════

    # mov rax, rbx              → 48 89 D8
    # REX: 48 = 0100 1000 (W=1, R=0, X=0, B=0) → 64-bit operand
    # Opcode 89 = MOV r/m64, r64
    # ModR/M: D8 = 11 011 000 (mod=11 reg=rbx r/m=rax)
    mov     rax, rbx
    cmp     rax, 1
    jne     fail

    # mov rax, 0x100            → 48 C7 C0 00 01 00 00
    # REX.W + opcode C7 /0 = MOV r/m64, imm32 (sign-extended)
    mov     rax, 0x100
    cmp     rax, 256
    jne     fail

    # ════════════════════════════════════════════════════════════════
    # 3. REX prefix — extended registers (REX.R, REX.B)
    # ════════════════════════════════════════════════════════════════

    # mov r8, rax               → 49 89 C0
    # REX: 49 = 0100 1001 (W=1, R=0, X=0, B=1) → r/m is r8
    # ModR/M: C0 = 11 000 000 (reg=rax, r/m=r8 via REX.B)
    mov     r8, rax
    cmp     r8, 256
    jne     fail

    # mov r12, r8               → 4D 89 C4
    # REX: 4D = 0100 1101 (W=1, R=1, X=0, B=1)
    # R=1 extends reg to r8+, B=1 extends r/m to r12
    mov     r12, r8
    cmp     r12, 256
    jne     fail

    # ════════════════════════════════════════════════════════════════
    # 4. ModR/M addressing modes
    # ════════════════════════════════════════════════════════════════

    # Register direct (mod=11):
    # add rax, rcx              → 48 01 C8
    # ModR/M: C8 = 11 001 000 (mod=11 reg=rcx r/m=rax)
    xor     rcx, rcx
    mov     rax, 42
    add     rax, rcx
    cmp     rax, 42
    jne     fail

    # Memory indirect (mod=00, RIP-relative):
    # mov rax, [rip+disp32]     → 48 8B 05 xx xx xx xx
    # ModR/M: 05 = 00 000 101 (mod=00, reg=rax, r/m=101 → RIP+disp32)
    mov     rax, [value]
    cmp     rax, 42
    jne     fail

    # Memory + disp8 (mod=01):
    # mov rax, [rbx + 8]        → 48 8B 43 08
    # ModR/M: 43 = 01 000 011 (mod=01, reg=rax, r/m=rbx, +disp8)
    lea     rbx, [array]
    mov     rax, [rbx + 8]      # array[1] = 20
    cmp     rax, 20
    jne     fail

    # Memory + disp32 (mod=10):
    # mov rax, [rbx + 256]    → 48 8B 83 00 01 00 00
    # ModR/M: 83 = 10 000 011 (mod=10, reg=rax, r/m=rbx, +disp32)
    # (displacement > 127 requires disp32)
    # We'll use a smaller disp32 that fits our array:
    mov     rax, [rbx + 32]     # array[4] = 50
    cmp     rax, 50
    jne     fail

    # ════════════════════════════════════════════════════════════════
    # 5. SIB byte — scaled index addressing
    # ════════════════════════════════════════════════════════════════
    # SIB byte: scale(2) | index(3) | base(3)
    # scale: 00=1, 01=2, 10=4, 11=8
    #
    # mov rax, [rbx + rcx*8]    → 48 8B 04 CB
    # ModR/M: 04 = 00 000 100 (mod=00, reg=rax, r/m=100 → SIB follows)
    # SIB: CB = 11 001 011 (scale=8, index=rcx, base=rbx)
    lea     rbx, [array]
    mov     rcx, 2              # index 2
    mov     rax, [rbx + rcx * 8]    # array[2] = 30
    cmp     rax, 30
    jne     fail

    # LEA with SIB for multiply-add:
    # lea rax, [rcx + rcx*4]    → 48 8D 04 89
    # Computes rcx * 5 without multiplication
    mov     rcx, 7
    lea     rax, [rcx + rcx * 4]    # 7 * 5 = 35
    cmp     rax, 35
    jne     fail

    # ════════════════════════════════════════════════════════════════
    # 6. Immediate sizes
    # ════════════════════════════════════════════════════════════════

    # imm8 (sign-extended):
    # add rax, 1                → 48 83 C0 01
    # Opcode 83 /0 = ADD r/m64, imm8 (sign-extended to 64 bits)
    mov     rax, 10
    add     rax, 1              # uses imm8 encoding
    cmp     rax, 11
    jne     fail

    # imm32 (sign-extended to 64):
    # add rax, 0x10000          → 48 05 00 00 01 00
    # Opcode 05 = ADD rax, imm32
    mov     rax, 0
    add     rax, 0x10000
    cmp     rax, 0x10000
    jne     fail

    # movabs — 64-bit immediate (only MOV can take imm64):
    # mov rax, 0x123456789ABCDEF0 → 48 B8 F0 DE BC 9A 78 56 34 12
    # Opcode: REX.W + B8+rd = MOV r64, imm64
    mov     rax, 0x123456789ABCDEF0
    mov     rdx, 0x123456789ABCDEF0
    cmp     rax, rdx
    jne     fail

    # ════════════════════════════════════════════════════════════════
    # 7. Two-byte opcode (0F escape)
    # ════════════════════════════════════════════════════════════════

    # cmovz — conditional move
    # cmovz rax, rcx            → 48 0F 44 C1
    # 0F 44 = two-byte opcode for CMOVZ
    mov     rax, 10
    mov     rcx, 20
    cmp     rax, 10             # sets ZF
    cmovz   rax, rcx            # rax = rcx if ZF=1
    cmp     rax, 20
    jne     fail

    # bsr — bit scan reverse
    # bsr rax, rcx              → 48 0F BD C1
    # Finds highest set bit
    mov     rcx, 0x80           # bit 7 is highest
    bsr     rax, rcx
    cmp     rax, 7
    jne     fail

    # ── Print success ───────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall
