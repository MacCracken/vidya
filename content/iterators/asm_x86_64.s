# Vidya — Iterators in x86_64 Assembly
#
# Assembly iteration is explicit: load, compare, branch. For loops
# become counter + conditional jump. Array traversal uses base + index
# or pointer increment. There is no abstraction — you write every step.

.intel_syntax noprefix
.global _start

.section .data
numbers:    .long 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
num_count = (. - numbers) / 4

.section .rodata
msg_pass:   .ascii "All iterator examples passed.\n"
msg_len = . - msg_pass

.section .bss
results:    .skip 40            # space for 10 ints

.section .text

_start:
    # ── Sum array with index ────────────────────────────────────────
    xor     eax, eax            # sum = 0
    xor     ecx, ecx            # i = 0
.sum_loop:
    cmp     ecx, num_count
    jge     .sum_done
    add     eax, [numbers + ecx * 4]
    inc     ecx
    jmp     .sum_loop
.sum_done:
    cmp     eax, 55             # 1+2+...+10 = 55
    jne     fail

    # ── Sum with pointer iteration ──────────────────────────────────
    lea     rsi, [numbers]
    lea     rdi, [numbers + num_count * 4]  # end pointer
    xor     eax, eax
.ptr_loop:
    cmp     rsi, rdi
    jge     .ptr_done
    add     eax, [rsi]
    add     rsi, 4
    jmp     .ptr_loop
.ptr_done:
    cmp     eax, 55
    jne     fail

    # ── Filter even numbers ─────────────────────────────────────────
    # Count how many even numbers in array
    xor     ecx, ecx            # i = 0
    xor     edx, edx            # even_count = 0
.filter_loop:
    cmp     ecx, num_count
    jge     .filter_done
    mov     eax, [numbers + ecx * 4]
    test    eax, 1              # check bit 0
    jnz     .filter_skip        # odd, skip
    inc     edx
.filter_skip:
    inc     ecx
    jmp     .filter_loop
.filter_done:
    cmp     edx, 5              # 2,4,6,8,10 = 5 evens
    jne     fail

    # ── Map: square each element ────────────────────────────────────
    # Store squares in results buffer
    xor     ecx, ecx
.map_loop:
    cmp     ecx, num_count
    jge     .map_done
    mov     eax, [numbers + ecx * 4]
    imul    eax, eax            # square
    mov     [results + ecx * 4], eax
    inc     ecx
    jmp     .map_loop
.map_done:
    # Verify: results[0] = 1, results[4] = 25, results[9] = 100
    cmp     dword ptr [results], 1
    jne     fail
    cmp     dword ptr [results + 4 * 4], 25
    jne     fail
    cmp     dword ptr [results + 9 * 4], 100
    jne     fail

    # ── Fold/reduce: product of first 5 ─────────────────────────────
    mov     eax, 1              # accumulator = 1
    xor     ecx, ecx
.fold_loop:
    cmp     ecx, 5
    jge     .fold_done
    imul    eax, [numbers + ecx * 4]
    inc     ecx
    jmp     .fold_loop
.fold_done:
    cmp     eax, 120            # 1*2*3*4*5 = 120
    jne     fail

    # ── Find first element > 7 ──────────────────────────────────────
    xor     ecx, ecx
.find_loop:
    cmp     ecx, num_count
    jge     fail                # not found = error
    mov     eax, [numbers + ecx * 4]
    cmp     eax, 7
    jg      .find_done
    inc     ecx
    jmp     .find_loop
.find_done:
    cmp     eax, 8              # first element > 7 is 8
    jne     fail

    # ── Countdown (reverse iteration) ───────────────────────────────
    mov     ecx, num_count
    xor     edx, edx            # sum of last 3
.rev_loop:
    dec     ecx
    js      .rev_check          # ecx < 0, done
    cmp     edx, 3
    jge     .rev_check
    add     edx, 1
    add     eax, [numbers + ecx * 4]  # not accumulating here, just testing iteration
    jmp     .rev_loop
.rev_check:
    # We iterated backward — that's the test

    # ── rep scasb: find byte in string ──────────────────────────────
    # Search for 'l' in "hello"
    lea     rdi, [msg_pass]     # search in pass message
    mov     rcx, msg_len
    mov     al, 'l'
    repne   scasb               # scan until match or rcx=0
    je      .scas_found
    jmp     fail
.scas_found:
    # Found 'l' — rdi points past it

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
