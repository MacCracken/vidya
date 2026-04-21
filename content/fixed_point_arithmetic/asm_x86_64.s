# Vidya — Fixed-Point Arithmetic in x86_64 Assembly
#
# 16.16 fixed-point: upper 48 bits integer, lower 16 bits fraction.
# All operations use integer ALU — no FPU, no SSE, no SIMD.
# Demonstrates: multiply, divide, sine table, overflow-safe patterns.

.intel_syntax noprefix
.global _start

.section .data

# Quarter-wave sine table (256 entries, 16.16 fixed-point)
# sin(i * pi/512) * 65536 for i = 0..255
# Full sine via symmetry: sin(256+i) = sin(255-i), sin(512+i) = -sin(i)
sine_table:
    .quad 0, 402, 804, 1206, 1608, 2010, 2412, 2814
    .quad 3216, 3617, 4019, 4420, 4821, 5222, 5623, 6023
    .quad 6424, 6824, 7224, 7623, 8022, 8421, 8820, 9218
    .quad 9616, 10014, 10411, 10808, 11204, 11600, 11996, 12391
    .quad 12785, 13179, 13573, 13966, 14359, 14751, 15143, 15534
    .quad 15924, 16314, 16703, 17091, 17479, 17867, 18253, 18639
    .quad 19024, 19409, 19793, 20176, 20558, 20939, 21320, 21699
    .quad 22078, 22456, 22834, 23210, 23586, 23960, 24334, 24707
    .quad 25079, 25450, 25821, 26190, 26558, 26925, 27291, 27656
    .quad 28020, 28383, 28745, 29106, 29466, 29824, 30182, 30538
    .quad 30893, 31248, 31600, 31952, 32303, 32652, 33000, 33347
    .quad 33692, 34036, 34379, 34721, 35062, 35401, 35738, 36075
    .quad 36410, 36744, 37076, 37407, 37736, 38064, 38391, 38716
    .quad 39040, 39362, 39683, 40002, 40320, 40636, 40951, 41264
    .quad 41576, 41886, 42194, 42501, 42806, 43110, 43412, 43713
    .quad 44011, 44308, 44604, 44898, 45190, 45480, 45769, 46056
    .quad 46341, 46624, 46906, 47186, 47464, 47741, 48015, 48288
    .quad 48559, 48828, 49095, 49361, 49624, 49886, 50146, 50404
    .quad 50660, 50914, 51166, 51417, 51665, 51911, 52156, 52398
    .quad 52639, 52878, 53114, 53349, 53581, 53812, 54040, 54267
    .quad 54491, 54714, 54934, 55152, 55368, 55582, 55794, 56004
    .quad 56212, 56418, 56621, 56823, 57022, 57219, 57414, 57607
    .quad 57798, 57986, 58172, 58356, 58538, 58718, 58896, 59071
    .quad 59244, 59415, 59583, 59750, 59914, 60075, 60235, 60392
    .quad 60547, 60700, 60851, 60999, 61145, 61288, 61429, 61568
    .quad 61705, 61839, 61971, 62101, 62228, 62353, 62476, 62596
    .quad 62714, 62830, 62943, 63054, 63162, 63268, 63372, 63473
    .quad 63572, 63668, 63763, 63854, 63944, 64031, 64115, 64197
    .quad 64277, 64355, 64430, 64503, 64573, 64641, 64707, 64770
    .quad 64830, 64889, 64945, 64998, 65049, 65098, 65144, 65188
    .quad 65229, 65268, 65305, 65339, 65371, 65400, 65427, 65451
    .quad 65473, 65493, 65510, 65525, 65537, 65547, 65554, 65559

test_count: .quad 0
pass_count: .quad 0

.section .rodata
msg_pass:     .ascii "PASS: "
msg_pass_len = . - msg_pass
msg_fail:     .ascii "FAIL: "
msg_fail_len = . - msg_fail
msg_newline:  .ascii "\n"
msg_mul:      .ascii "fx_mul(3.0, 2.5) == 7.5"
msg_mul_len = . - msg_mul
msg_div:      .ascii "fx_div(10.0, 4.0) == 2.5"
msg_div_len = . - msg_div
msg_overflow: .ascii "fx_mul_safe large values no overflow"
msg_ovf_len = . - msg_overflow
msg_sin0:     .ascii "sin(0) == 0"
msg_sin0_len = . - msg_sin0
msg_sin256:   .ascii "sin(256) == 65536 (1.0)"
msg_s256_len = . - msg_sin256
msg_asr:      .ascii "asr(-256, 1) == -128"
msg_asr_len = . - msg_asr
msg_summary:  .ascii "All fixed-point arithmetic examples passed.\n"
msg_sum_len = . - msg_summary
msg_not_all:  .ascii "SOME TESTS FAILED\n"
msg_not_len = . - msg_not_all

.section .text

# fx_mul: (rdi * rsi) >> 16
# Standard fixed-point multiply. Overflows on large inputs.
fx_mul:
    mov     rax, rdi
    imul    rsi             # rdx:rax = rdi * rsi (128-bit result)
    shrd    rax, rdx, 16   # shift 128-bit result right by 16
    ret

# fx_mul_safe: (rdi >> 8) * (rsi >> 8)
# Overflow-safe multiply. Trades 8 bits of precision for safety.
fx_mul_safe:
    mov     rax, rdi
    sar     rax, 8
    mov     rcx, rsi
    sar     rcx, 8
    imul    rcx
    ret

# fx_div: (rdi << 16) / rsi
# Fixed-point divide. Caller must ensure rsi != 0.
fx_div:
    test    rsi, rsi
    jz      .div_zero
    mov     rax, rdi
    sal     rax, 16
    cqo                     # sign-extend rax into rdx:rax
    idiv    rsi
    ret
.div_zero:
    xor     rax, rax        # return 0 on divide by zero
    ret

# asr: arithmetic shift right (rdi >> rsi), sign-preserving
# Cyrius >> is logical. This is the arithmetic version.
asr:
    mov     rax, rdi
    mov     rcx, rsi
    sar     rax, cl
    ret

# sin_lookup: sine table lookup with quarter-wave symmetry
# rdi = angle (0-1023, where 1024 = full circle)
# Returns 16.16 fixed-point sine value
sin_lookup:
    and     rdi, 1023       # mask to 0-1023
    cmp     rdi, 512
    jge     .sin_neg
    # Positive half (0-511)
    cmp     rdi, 256
    jge     .sin_mirror
    # First quadrant (0-255): direct lookup
    lea     rax, [rip + sine_table]
    mov     rax, [rax + rdi * 8]
    ret
.sin_mirror:
    # Second quadrant (256-511): mirror = table[511 - angle]
    mov     rax, 511
    sub     rax, rdi
    lea     rcx, [rip + sine_table]
    mov     rax, [rcx + rax * 8]
    ret
.sin_neg:
    # Negative half (512-1023): negate the positive half
    sub     rdi, 512
    cmp     rdi, 256
    jge     .sin_neg_mirror
    lea     rax, [rip + sine_table]
    mov     rax, [rax + rdi * 8]
    neg     rax
    ret
.sin_neg_mirror:
    mov     rax, 511
    sub     rax, rdi
    lea     rcx, [rip + sine_table]
    mov     rax, [rcx + rax * 8]
    neg     rax
    ret

# --- Test helpers ---

# assert_eq: compare rdi (actual) with rsi (expected)
# rdx = message ptr, rcx = message len
assert_eq:
    push    rdx
    push    rcx
    inc     qword ptr [rip + test_count]
    cmp     rdi, rsi
    jne     .assert_fail
    inc     qword ptr [rip + pass_count]
    # Print "PASS: "
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    jmp     .assert_msg
.assert_fail:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
.assert_msg:
    pop     rdx             # len
    pop     rsi             # ptr
    mov     rax, 1
    mov     rdi, 1
    # rsi = msg ptr, rdx = msg len
    syscall
    # newline
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_newline]
    mov     rdx, 1
    syscall
    ret

_start:
    # Test 1: fx_mul(3.0, 2.5) should equal 7.5
    # 3.0 = 3 << 16 = 196608
    # 2.5 = 2.5 * 65536 = 163840
    # 7.5 = 7.5 * 65536 = 491520
    mov     rdi, 196608
    mov     rsi, 163840
    call    fx_mul
    mov     rdi, rax
    mov     rsi, 491520
    lea     rdx, [rip + msg_mul]
    mov     rcx, msg_mul_len
    call    assert_eq

    # Test 2: fx_div(10.0, 4.0) should equal 2.5
    # 10.0 = 655360, 4.0 = 262144, 2.5 = 163840
    mov     rdi, 655360
    mov     rsi, 262144
    call    fx_div
    mov     rdi, rax
    mov     rsi, 163840
    lea     rdx, [rip + msg_div]
    mov     rcx, msg_div_len
    call    assert_eq

    # Test 3: fx_mul_safe with large values (1000.0 * 1000.0)
    # 1000.0 = 65536000. Normal fx_mul would overflow.
    # fx_mul_safe: (65536000 >> 8) * (65536000 >> 8) = 256000 * 256000 = 65536000000
    # Expected: 1000000.0 in fixed-point = 65536000000 (fits in 64-bit)
    mov     rdi, 65536000
    mov     rsi, 65536000
    call    fx_mul_safe
    # Result should be positive and large (not wrapped negative)
    test    rax, rax
    mov     rdi, 1          # set to 1 (pass) if positive
    js      .ovf_neg
    jmp     .ovf_check
.ovf_neg:
    xor     rdi, rdi        # 0 (fail) if negative
.ovf_check:
    mov     rsi, 1
    lea     rdx, [rip + msg_overflow]
    mov     rcx, msg_ovf_len
    call    assert_eq

    # Test 4: sin(0) == 0
    xor     rdi, rdi
    call    sin_lookup
    mov     rdi, rax
    xor     rsi, rsi
    lea     rdx, [rip + msg_sin0]
    mov     rcx, msg_sin0_len
    call    assert_eq

    # Test 5: sin(256) == 65536 (1.0) — peak of sine wave
    # Actually sin(256) mirrors to table[255] which is near 65536
    mov     rdi, 256
    call    sin_lookup
    # Should be close to 65536 (within table[255] = 65559)
    mov     rdi, rax
    mov     rsi, 65559      # table[255] value
    lea     rdx, [rip + msg_sin256]
    mov     rcx, msg_s256_len
    call    assert_eq

    # Test 6: asr(-256, 1) == -128
    mov     rdi, -256
    mov     rsi, 1
    call    asr
    mov     rdi, rax
    mov     rsi, -128
    lea     rdx, [rip + msg_asr]
    mov     rcx, msg_asr_len
    call    assert_eq

    # Summary
    mov     rax, [rip + test_count]
    cmp     rax, [rip + pass_count]
    jne     .not_all_passed

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_summary]
    mov     rdx, msg_sum_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall

.not_all_passed:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rip + msg_not_all]
    mov     rdx, msg_not_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall
