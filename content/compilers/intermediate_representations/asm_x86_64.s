# Vidya — Intermediate Representations in x86_64 Assembly
#
# What IR "lowers to": the actual machine instructions a compiler backend
# emits from three-address code (TAC). Each block shows the IR operation
# as a comment alongside the x86_64 instruction it becomes. This is the
# final stage of compilation — IR → machine code.
#
# The examples cover: arithmetic, comparisons, branches, function calls,
# memory loads/stores, and phi-node resolution (register moves at block
# boundaries).
#
# Build: as --64 asm_x86_64.s -o out.o && ld out.o -o out && ./out

.section .text
.globl _start

_start:
    # ══════════════════════════════════════════════════════════════════
    # Test 1: Arithmetic TAC → x86_64
    # ══════════════════════════════════════════════════════════════════
    # Source:   result = (a + b) * c - d
    # IR:
    #   t1 = a + b
    #   t2 = t1 * c
    #   t3 = t2 - d
    #   result = t3

    # IR: t1 = a + b          →  mov + add
    mov     $10, %rax              # a = 10
    mov     $20, %rbx              # b = 20
    add     %rbx, %rax             # t1 = a + b = 30

    # IR: t2 = t1 * c         →  imul
    mov     $3, %rcx               # c = 3
    imul    %rcx, %rax             # t2 = t1 * c = 90

    # IR: t3 = t2 - d         →  sub
    mov     $5, %rdx               # d = 5
    sub     %rdx, %rax             # t3 = t2 - d = 85

    # IR: result = t3          →  (already in %rax)
    cmp     $85, %rax
    jne     fail

    # ══════════════════════════════════════════════════════════════════
    # Test 2: Conditional branch TAC → x86_64
    # ══════════════════════════════════════════════════════════════════
    # Source:   if (x > 0) y = 1 else y = -1
    # IR:
    #   t1 = x > 0
    #   if t1 goto L_then
    #   goto L_else
    # L_then:
    #   y = 1
    #   goto L_join
    # L_else:
    #   y = -1
    # L_join:
    #   (use y)

    mov     $42, %rax              # x = 42

    # IR: t1 = x > 0          →  cmp
    # IR: if t1 goto L_then   →  jg
    cmp     $0, %rax
    jg      t2_then

    # IR: goto L_else          →  jmp
    jmp     t2_else

t2_then:
    # IR: y = 1                →  mov
    mov     $1, %rbx
    jmp     t2_join                # IR: goto L_join → jmp

t2_else:
    # IR: y = -1               →  mov
    mov     $-1, %rbx

t2_join:
    # y should be 1 (since x=42 > 0)
    cmp     $1, %rbx
    jne     fail

    # ══════════════════════════════════════════════════════════════════
    # Test 3: Loop TAC → x86_64
    # ══════════════════════════════════════════════════════════════════
    # Source:   sum = 0; for (i = 1; i <= 5; i++) sum += i;
    # IR:
    #   sum = 0
    #   i = 1
    # L_loop:
    #   t1 = i <= 5
    #   if_not t1 goto L_exit
    #   sum = sum + i
    #   i = i + 1
    #   goto L_loop
    # L_exit:

    # IR: sum = 0              →  xor (zero idiom)
    xor     %rax, %rax             # sum = 0

    # IR: i = 1                →  mov
    mov     $1, %rcx               # i = 1

t3_loop:
    # IR: t1 = i <= 5          →  cmp
    # IR: if_not t1 goto exit  →  jg
    cmp     $5, %rcx
    jg      t3_exit

    # IR: sum = sum + i        →  add
    add     %rcx, %rax

    # IR: i = i + 1            →  inc (or add $1)
    inc     %rcx

    # IR: goto L_loop          →  jmp
    jmp     t3_loop

t3_exit:
    # sum should be 1+2+3+4+5 = 15
    cmp     $15, %rax
    jne     fail

    # ══════════════════════════════════════════════════════════════════
    # Test 4: Memory load/store TAC → x86_64
    # ══════════════════════════════════════════════════════════════════
    # IR:
    #   store 42 → [addr]
    #   t1 = load [addr]
    #   t2 = t1 + 8
    #   store t2 → [addr]

    lea     scratch(%rip), %rdi

    # IR: store 42 → [addr]   →  movq
    movq    $42, (%rdi)

    # IR: t1 = load [addr]    →  movq
    movq    (%rdi), %rax

    # IR: t2 = t1 + 8         →  add
    add     $8, %rax

    # IR: store t2 → [addr]   →  movq
    movq    %rax, (%rdi)

    # Verify
    cmpq    $50, (%rdi)
    jne     fail

    # ══════════════════════════════════════════════════════════════════
    # Test 5: Function call TAC → x86_64
    # ══════════════════════════════════════════════════════════════════
    # IR:
    #   param 7
    #   param 3
    #   t1 = call multiply
    #   result = t1

    # IR: param 7              →  mov to %rdi (System V ABI arg1)
    mov     $7, %rdi

    # IR: param 3              →  mov to %rsi (System V ABI arg2)
    mov     $3, %rsi

    # IR: t1 = call multiply   →  call
    call    ir_multiply

    # IR: result = t1           →  (already in %rax per ABI)
    cmp     $21, %rax
    jne     fail

    # ══════════════════════════════════════════════════════════════════
    # Test 6: Phi node resolution → register moves at block boundary
    # ══════════════════════════════════════════════════════════════════
    # SSA IR:
    #   entry:
    #     x0 = 10
    #     goto L1
    #   L1:
    #     x1 = phi(x0 from entry, x2 from L2)
    #     if x1 < 100 goto L2 else goto exit
    #   L2:
    #     x2 = x1 * 2
    #     goto L1
    #   exit:
    #     result = x1
    #
    # After phi elimination, the phi becomes mov at the end of
    # each predecessor block.

    # entry: x0 = 10
    mov     $10, %rax              # x = 10
    # phi resolution: x1 = x0 (move at end of entry block)
    # (x is already in %rax, phi is trivially resolved)
    jmp     phi_L1

phi_L1:
    # x1 is in %rax (from entry or from L2)
    cmp     $100, %rax
    jge     phi_exit

    # L2: x2 = x1 * 2
    shl     $1, %rax               # x2 = x1 * 2
    # phi resolution: mov x2 → x1 (already in %rax)
    jmp     phi_L1

phi_exit:
    # x should be 10 * 2^n >= 100 → 10,20,40,80,160
    cmp     $160, %rax
    jne     fail

    # ── All passed ───────────────────────────────────────────────────
    mov     $1, %rax
    mov     $1, %rdi
    lea     msg_pass(%rip), %rsi
    mov     $msg_len, %rdx
    syscall

    mov     $60, %rax
    xor     %rdi, %rdi
    syscall

fail:
    mov     $60, %rax
    mov     $1, %rdi
    syscall

# ── ir_multiply(rdi=a, rsi=b) → rax ─────────────────────────────────
# IR: t1 = a * b → imul
ir_multiply:
    mov     %rdi, %rax
    imul    %rsi, %rax
    ret

# ── Data ─────────────────────────────────────────────────────────────
.section .bss
scratch:
    .skip   8

.section .rodata
msg_pass:
    .ascii  "All intermediate representations examples passed.\n"
    msg_len = . - msg_pass
