# Vidya — Performance in x86_64 Assembly
#
# At the assembly level, performance is about instruction selection,
# pipeline utilization, cache behavior, and avoiding stalls. Key
# techniques: branchless code (cmov), SIMD, alignment, and minimizing
# memory access latency. All backed by Intel/AMD optimization manuals.

.intel_syntax noprefix
.global _start

.section .data
.align 16
array:      .long 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16
arr_count = (. - array) / 4

.section .rodata
msg_pass:   .ascii "All performance examples passed.\n"
msg_len = . - msg_pass

.section .bss
.align 64
buffer:     .skip 256

.section .text

_start:
    # ── Branchless min/max with CMOV ────────────────────────────────
    # Branches cause pipeline stalls on misprediction (~15 cycles)
    # CMOV is always ~1 cycle, no prediction needed

    # Branchless min(42, 99)
    mov     eax, 42
    mov     ecx, 99
    cmp     eax, ecx
    cmovg   eax, ecx            # eax = min(eax, ecx)
    cmp     eax, 42
    jne     fail

    # Branchless max(42, 99)
    mov     eax, 42
    mov     ecx, 99
    cmp     eax, ecx
    cmovl   eax, ecx            # eax = max(eax, ecx)
    cmp     eax, 99
    jne     fail

    # ── Branchless absolute value ───────────────────────────────────
    # cdq + xor + sub: no branch, constant time
    mov     eax, -42
    cdq                         # edx = all 1s if negative, all 0s if positive
    xor     eax, edx
    sub     eax, edx
    cmp     eax, 42
    jne     fail

    # ── LEA for fast arithmetic ─────────────────────────────────────
    # LEA can compute a*b+c in one instruction (1 cycle)
    # Multiply by 5: x*4 + x
    mov     eax, 10
    lea     eax, [eax + eax * 4]    # eax = 10*5 = 50
    cmp     eax, 50
    jne     fail

    # Multiply by 3
    mov     eax, 7
    lea     eax, [eax + eax * 2]    # eax = 7*3 = 21
    cmp     eax, 21
    jne     fail

    # ── Loop unrolling: reduce branch overhead ──────────────────────
    # Sum array of 16 ints, 4 at a time
    xor     eax, eax
    xor     ecx, ecx
.unrolled_loop:
    cmp     ecx, arr_count
    jge     .unrolled_done
    add     eax, [array + ecx * 4]
    add     eax, [array + ecx * 4 + 4]
    add     eax, [array + ecx * 4 + 8]
    add     eax, [array + ecx * 4 + 12]
    add     ecx, 4
    jmp     .unrolled_loop
.unrolled_done:
    cmp     eax, 136            # 1+2+...+16 = 136
    jne     fail

    # ── XOR vs MOV for zeroing ──────────────────────────────────────
    # xor reg, reg is preferred over mov reg, 0
    # It's shorter (2 bytes vs 5) and breaks dependency chains
    xor     eax, eax            # preferred: 2 bytes, breaks deps
    cmp     eax, 0
    jne     fail

    # ── Strength reduction: shift vs multiply ───────────────────────
    # Multiply by power of 2: use shift (1 cycle vs 3 for imul)
    mov     eax, 7
    shl     eax, 3              # eax * 8
    cmp     eax, 56
    jne     fail

    # Divide by power of 2: use shift
    mov     eax, 64
    shr     eax, 2              # eax / 4
    cmp     eax, 16
    jne     fail

    # ── PREFETCH: hint to load cache line ───────────────────────────
    # Prefetch data into L1 cache before we need it
    prefetcht0 [buffer]         # temporal: expect reuse
    # prefetchnta [buffer]      # non-temporal: expect no reuse

    # ── Alignment: 16-byte for SSE, 64-byte for cache lines ────────
    # Our array is .align 16, buffer is .align 64
    # Misaligned access can cross cache lines (penalty ~10 cycles)

    # ── REP STOSD: fast memory fill ─────────────────────────────────
    # Optimized by CPU microcode for large fills
    lea     rdi, [buffer]
    mov     ecx, 64             # 64 dwords = 256 bytes
    mov     eax, 0xDEADBEEF
    rep     stosd

    # Verify
    cmp     dword ptr [buffer], 0xDEADBEEF
    jne     fail
    cmp     dword ptr [buffer + 252], 0xDEADBEEF
    jne     fail

    # ── POPCNT: population count (hardware bit counting) ────────────
    # Count set bits — used in bitmap operations, hash tables
    mov     rax, 0xFF00FF00FF00FF00
    popcnt  rcx, rax            # count of set bits
    cmp     rcx, 32             # 8 bytes * 4 bits each = 32
    jne     fail

    # ── LZCNT/TZCNT: leading/trailing zero count ───────────────────
    # Find highest/lowest set bit — used for log2, priority queues
    mov     rax, 0x0000000000001000
    tzcnt   rcx, rax            # trailing zeros
    cmp     rcx, 12             # bit 12 is the lowest set bit
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
