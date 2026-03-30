// Vidya — Algorithms in AArch64 Assembly
//
// Fundamental algorithms at the instruction level: binary search,
// insertion sort, GCD, and Fibonacci. AArch64's conditional
// instructions and barrel shifter make some operations cleaner
// than x86_64.

.global _start

.section .rodata
msg_pass:   .ascii "All algorithms examples passed.\n"
msg_len = . - msg_pass

.align 4
search_data:
    .word 1, 3, 5, 7, 9, 11, 13, 15, 17, 19
search_len = 10

sort_data_init:
    .word 5, 2, 8, 1, 9, 3
sort_len = 6

sort_expected:
    .word 1, 2, 3, 5, 8, 9

.section .bss
sort_buf:   .skip 24      // 6 * 4 bytes

.section .text

_start:
    // ── Test 1: binary search — find 7 at index 3 ────────────────────
    adr     x0, search_data
    mov     w1, search_len
    mov     w2, #7
    bl      binary_search
    cmp     w0, #3
    b.ne    fail

    // ── Test 2: binary search — find 1 at index 0 ────────────────────
    adr     x0, search_data
    mov     w1, search_len
    mov     w2, #1
    bl      binary_search
    cmp     w0, #0
    b.ne    fail

    // ── Test 3: binary search — find 19 at index 9 ───────────────────
    adr     x0, search_data
    mov     w1, search_len
    mov     w2, #19
    bl      binary_search
    cmp     w0, #9
    b.ne    fail

    // ── Test 4: binary search — miss ──────────────────────────────────
    adr     x0, search_data
    mov     w1, search_len
    mov     w2, #4
    bl      binary_search
    cmn     w0, #1              // compare with -1
    b.ne    fail

    // ── Test 5: insertion sort ────────────────────────────────────────
    adr     x0, sort_data_init
    adr     x1, sort_buf
    mov     w2, sort_len
    bl      copy_array

    adr     x0, sort_buf
    mov     w1, sort_len
    bl      insertion_sort

    adr     x0, sort_buf
    adr     x1, sort_expected
    mov     w2, sort_len
    bl      arrays_equal
    cbz     w0, fail

    // ── Test 6: GCD(48, 18) = 6 ──────────────────────────────────────
    mov     w0, #48
    mov     w1, #18
    bl      gcd
    cmp     w0, #6
    b.ne    fail

    // ── Test 7: GCD(17, 13) = 1 ──────────────────────────────────────
    mov     w0, #17
    mov     w1, #13
    bl      gcd
    cmp     w0, #1
    b.ne    fail

    // ── Test 8: GCD(100, 75) = 25 ────────────────────────────────────
    mov     w0, #100
    mov     w1, #75
    bl      gcd
    cmp     w0, #25
    b.ne    fail

    // ── Test 9: Fibonacci(10) = 55 ───────────────────────────────────
    mov     w0, #10
    bl      fibonacci
    cmp     x0, #55
    b.ne    fail

    // ── Test 10: Fibonacci(20) = 6765 ────────────────────────────────
    mov     w0, #20
    bl      fibonacci
    mov     x9, #6765
    cmp     x0, x9
    b.ne    fail

    // ── Test 11: Fibonacci(0) = 0 ────────────────────────────────────
    mov     w0, #0
    bl      fibonacci
    cmp     x0, #0
    b.ne    fail

    // ── All passed ───────────────────────────────────────────────────
    mov     x8, #64             // sys_write
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, #93             // sys_exit
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// ── binary_search(x0=arr, w1=len, w2=target) → w0 (index or -1) ────
binary_search:
    mov     w3, #0              // lo = 0
    mov     w4, w1              // hi = len
.bs_loop:
    cmp     w3, w4
    b.ge    .bs_notfound
    sub     w5, w4, w3          // hi - lo
    lsr     w5, w5, #1          // (hi - lo) / 2
    add     w5, w5, w3          // mid = lo + (hi - lo) / 2
    ldr     w6, [x0, w5, uxtw #2]  // arr[mid]
    cmp     w6, w2
    b.eq    .bs_found
    b.lt    .bs_go_right
    // arr[mid] > target: hi = mid
    mov     w4, w5
    b       .bs_loop
.bs_go_right:
    add     w3, w5, #1          // lo = mid + 1
    b       .bs_loop
.bs_found:
    mov     w0, w5
    ret
.bs_notfound:
    mov     w0, #-1
    ret

// ── insertion_sort(x0=arr, w1=len) ───────────────────────────────────
insertion_sort:
    cmp     w1, #1
    b.le    .isort_done
    mov     w8, #1              // i = 1
.isort_outer:
    cmp     w8, w1
    b.ge    .isort_done
    ldr     w9, [x0, w8, uxtw #2]  // key = arr[i]
    sub     w10, w8, #1         // j = i - 1
.isort_inner:
    tbnz    w10, #31, .isort_place  // if j < 0 (sign bit set)
    ldr     w11, [x0, w10, uxtw #2]  // arr[j]
    cmp     w11, w9
    b.le    .isort_place
    add     w12, w10, #1
    str     w11, [x0, w12, uxtw #2]  // arr[j+1] = arr[j]
    sub     w10, w10, #1
    b       .isort_inner
.isort_place:
    add     w12, w10, #1
    str     w9, [x0, w12, uxtw #2]   // arr[j+1] = key
    add     w8, w8, #1
    b       .isort_outer
.isort_done:
    ret

// ── gcd(w0=a, w1=b) → w0 ────────────────────────────────────────────
gcd:
    cbz     w1, .gcd_done
.gcd_loop:
    udiv    w2, w0, w1          // q = a / b
    msub    w2, w2, w1, w0      // r = a - q * b (= a % b)
    mov     w0, w1
    mov     w1, w2
    cbnz    w1, .gcd_loop
.gcd_done:
    ret

// ── fibonacci(w0=n) → x0 ────────────────────────────────────────────
fibonacci:
    cmp     w0, #1
    b.le    .fib_base
    mov     x1, #0              // a = 0
    mov     x2, #1              // b = 1
    mov     w3, #2              // i = 2
.fib_loop:
    cmp     w3, w0
    b.gt    .fib_done
    add     x4, x1, x2         // next = a + b
    mov     x1, x2             // a = b
    mov     x2, x4             // b = next
    add     w3, w3, #1
    b       .fib_loop
.fib_done:
    mov     x0, x2
    ret
.fib_base:
    uxtw    x0, w0             // fib(0)=0, fib(1)=1
    ret

// ── copy_array(x0=src, x1=dst, w2=count) ────────────────────────────
copy_array:
    mov     w3, #0
.ca_loop:
    cmp     w3, w2
    b.ge    .ca_done
    ldr     w4, [x0, w3, uxtw #2]
    str     w4, [x1, w3, uxtw #2]
    add     w3, w3, #1
    b       .ca_loop
.ca_done:
    ret

// ── arrays_equal(x0=a, x1=b, w2=count) → w0 (1=equal, 0=not) ──────
arrays_equal:
    mov     w3, #0
.ae_loop:
    cmp     w3, w2
    b.ge    .ae_equal
    ldr     w4, [x0, w3, uxtw #2]
    ldr     w5, [x1, w3, uxtw #2]
    cmp     w4, w5
    b.ne    .ae_notequal
    add     w3, w3, #1
    b       .ae_loop
.ae_equal:
    mov     w0, #1
    ret
.ae_notequal:
    mov     w0, #0
    ret
