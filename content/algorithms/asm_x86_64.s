# Vidya — Algorithms in x86_64 Assembly
#
# Fundamental algorithms at the instruction level: binary search,
# insertion sort, GCD, and Fibonacci. At this level you see the
# actual comparisons, branches, and memory accesses — no abstraction.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:   .ascii "All algorithms examples passed.\n"
msg_len = . - msg_pass

# Sorted test data for binary search
.align 8
search_data:
    .long 1, 3, 5, 7, 9, 11, 13, 15, 17, 19
search_len = 10

# Unsorted data for sorting
sort_data_init:
    .long 5, 2, 8, 1, 9, 3
sort_len = 6

sort_expected:
    .long 1, 2, 3, 5, 8, 9

.section .bss
sort_buf:   .skip 24      # 6 * 4 bytes for sort workspace

.section .text

_start:
    # ── Test 1: binary search — find 7 at index 3 ─────────────────────
    lea     rsi, [search_data]
    mov     ecx, search_len
    mov     edx, 7
    call    binary_search
    cmp     eax, 3
    jne     fail

    # ── Test 2: binary search — find 1 at index 0 ─────────────────────
    lea     rsi, [search_data]
    mov     ecx, search_len
    mov     edx, 1
    call    binary_search
    cmp     eax, 0
    jne     fail

    # ── Test 3: binary search — find 19 at index 9 ────────────────────
    lea     rsi, [search_data]
    mov     ecx, search_len
    mov     edx, 19
    call    binary_search
    cmp     eax, 9
    jne     fail

    # ── Test 4: binary search — miss (4 not in array) ─────────────────
    lea     rsi, [search_data]
    mov     ecx, search_len
    mov     edx, 4
    call    binary_search
    cmp     eax, -1
    jne     fail

    # ── Test 5: insertion sort ─────────────────────────────────────────
    # Copy unsorted data to writable buffer
    lea     rsi, [sort_data_init]
    lea     rdi, [sort_buf]
    mov     ecx, sort_len
    call    copy_array

    lea     rdi, [sort_buf]
    mov     ecx, sort_len
    call    insertion_sort

    # Verify sorted
    lea     rsi, [sort_buf]
    lea     rdi, [sort_expected]
    mov     ecx, sort_len
    call    arrays_equal
    test    eax, eax
    jz      fail

    # ── Test 6: GCD(48, 18) = 6 ───────────────────────────────────────
    mov     edi, 48
    mov     esi, 18
    call    gcd
    cmp     eax, 6
    jne     fail

    # ── Test 7: GCD(17, 13) = 1 (coprime) ─────────────────────────────
    mov     edi, 17
    mov     esi, 13
    call    gcd
    cmp     eax, 1
    jne     fail

    # ── Test 8: GCD(100, 75) = 25 ─────────────────────────────────────
    mov     edi, 100
    mov     esi, 75
    call    gcd
    cmp     eax, 25
    jne     fail

    # ── Test 9: Fibonacci(10) = 55 ────────────────────────────────────
    mov     edi, 10
    call    fibonacci
    cmp     rax, 55
    jne     fail

    # ── Test 10: Fibonacci(20) = 6765 ─────────────────────────────────
    mov     edi, 20
    call    fibonacci
    cmp     rax, 6765
    jne     fail

    # ── Test 11: Fibonacci(0) = 0 ─────────────────────────────────────
    mov     edi, 0
    call    fibonacci
    cmp     rax, 0
    jne     fail

    # ── All passed ─────────────────────────────────────────────────────
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

# ── binary_search(rsi=arr, ecx=len, edx=target) → eax (index or -1) ─
binary_search:
    xor     r8d, r8d            # lo = 0
    mov     r9d, ecx            # hi = len
.bs_loop:
    cmp     r8d, r9d
    jge     .bs_notfound
    # mid = lo + (hi - lo) / 2
    mov     eax, r9d
    sub     eax, r8d
    shr     eax, 1
    add     eax, r8d            # eax = mid
    mov     r10d, [rsi + rax*4] # arr[mid]
    cmp     r10d, edx
    je      .bs_found
    jl      .bs_go_right
    # arr[mid] > target: hi = mid
    mov     r9d, eax
    jmp     .bs_loop
.bs_go_right:
    # arr[mid] < target: lo = mid + 1
    lea     r8d, [rax + 1]
    jmp     .bs_loop
.bs_found:
    ret                         # eax already = mid
.bs_notfound:
    mov     eax, -1
    ret

# ── insertion_sort(rdi=arr, ecx=len) ──────────────────────────────────
insertion_sort:
    cmp     ecx, 1
    jle     .isort_done
    mov     r8d, 1              # i = 1
.isort_outer:
    cmp     r8d, ecx
    jge     .isort_done
    mov     eax, [rdi + r8*4]   # key = arr[i]
    mov     r9d, r8d
    dec     r9d                  # j = i - 1
.isort_inner:
    cmp     r9d, 0
    jl      .isort_place
    mov     r10d, [rdi + r9*4]  # arr[j]
    cmp     r10d, eax
    jle     .isort_place
    # arr[j+1] = arr[j]
    lea     r11d, [r9d + 1]
    mov     [rdi + r11*4], r10d
    dec     r9d
    jmp     .isort_inner
.isort_place:
    lea     r11d, [r9d + 1]
    mov     [rdi + r11*4], eax  # arr[j+1] = key
    inc     r8d
    jmp     .isort_outer
.isort_done:
    ret

# ── gcd(edi=a, esi=b) → eax ──────────────────────────────────────────
# Euclidean algorithm: while b != 0: a, b = b, a % b
gcd:
    mov     eax, edi
    mov     ecx, esi
.gcd_loop:
    test    ecx, ecx
    jz      .gcd_done
    xor     edx, edx
    div     ecx             # eax = a / b, edx = a % b
    mov     eax, ecx        # a = b
    mov     ecx, edx        # b = a % b
    jmp     .gcd_loop
.gcd_done:
    ret

# ── fibonacci(edi=n) → rax ────────────────────────────────────────────
fibonacci:
    cmp     edi, 1
    jle     .fib_base
    xor     rax, rax        # a = 0
    mov     rcx, 1          # b = 1
    mov     r8d, 2          # i = 2
.fib_loop:
    cmp     r8d, edi
    jg      .fib_done
    mov     rdx, rcx        # next = b
    add     rdx, rax        # next = a + b
    mov     rax, rcx        # a = b
    mov     rcx, rdx        # b = next
    inc     r8d
    jmp     .fib_loop
.fib_done:
    mov     rax, rcx
    ret
.fib_base:
    mov     eax, edi        # fib(0)=0, fib(1)=1 — mov to eax zero-extends to rax
    ret

# ── copy_array(rsi=src, rdi=dst, ecx=count) ──────────────────────────
copy_array:
    xor     edx, edx
.ca_loop:
    cmp     edx, ecx
    jge     .ca_done
    mov     eax, [rsi + rdx*4]
    mov     [rdi + rdx*4], eax
    inc     edx
    jmp     .ca_loop
.ca_done:
    ret

# ── arrays_equal(rsi=a, rdi=b, ecx=count) → eax (1=equal, 0=not) ────
arrays_equal:
    xor     edx, edx
.ae_loop:
    cmp     edx, ecx
    jge     .ae_equal
    mov     eax, [rsi + rdx*4]
    cmp     eax, [rdi + rdx*4]
    jne     .ae_notequal
    inc     edx
    jmp     .ae_loop
.ae_equal:
    mov     eax, 1
    ret
.ae_notequal:
    xor     eax, eax
    ret
