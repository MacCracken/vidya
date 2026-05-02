// Vidya — Write-Ahead Logging in AArch64 Assembly
//
// In-memory WAL: append a 24-byte log record (op, key, val) BEFORE
// mutating the data store, then replay the durable prefix on recovery.
// AArch64's `adrp + :lo12:` pattern gives us page-relative addressing
// for the flat log_buf; `str x, [base, off]` writes an i64 at any
// 8-aligned offset that fits the immediate. Constants larger than the
// 12-bit immediate limit (REC_SZ=24 fits, but LOG_CAP_BYTES=6144 does
// NOT — we keep it in a register or use `cmp` against a literal-pool
// load). Functions calling `bl` must save x29 (FP) and x30 (LR).

.global _start

.equ REC_SZ,        24
.equ LOG_CAP_BYTES, 6144
.equ OP_INVALID,    0
.equ OP_SET,        1
.equ OP_DEL,        2
.equ STORE_KEYS,    16

.section .data
.align 3
log_offset:    .quad 0
log_committed: .quad 0

.section .bss
.align 3
log_buf:       .skip LOG_CAP_BYTES
data_vals:     .skip STORE_KEYS * 8
data_present:  .skip STORE_KEYS

.section .rodata
msg_pass:    .ascii "All write_ahead_logging examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

// log_reset: zero the offsets (buffer wiped by reset_all).
log_reset:
    adrp    x9, log_offset
    add     x9, x9, :lo12:log_offset
    str     xzr, [x9]
    adrp    x9, log_committed
    add     x9, x9, :lo12:log_committed
    str     xzr, [x9]
    ret

// store_clear: zero data_vals (16*8) and data_present (16).
store_clear:
    adrp    x9, data_vals
    add     x9, x9, :lo12:data_vals
    mov     x10, #0
.Lsc_v:
    cmp     x10, #STORE_KEYS
    b.ge    .Lsc_v_done
    str     xzr, [x9, x10, lsl #3]
    add     x10, x10, #1
    b       .Lsc_v
.Lsc_v_done:
    adrp    x9, data_present
    add     x9, x9, :lo12:data_present
    mov     x10, #0
.Lsc_p:
    cmp     x10, #STORE_KEYS
    b.ge    .Lsc_p_done
    strb    wzr, [x9, x10]
    add     x10, x10, #1
    b       .Lsc_p
.Lsc_p_done:
    ret

// reset_all: log_reset + store_clear + wipe log_buf.
reset_all:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    bl      log_reset
    bl      store_clear
    adrp    x9, log_buf
    add     x9, x9, :lo12:log_buf
    mov     x10, #0
    ldr     x11, =LOG_CAP_BYTES
.Lra_loop:
    cmp     x10, x11
    b.ge    .Lra_done
    strb    wzr, [x9, x10]
    add     x10, x10, #1
    b       .Lra_loop
.Lra_done:
    ldp     x29, x30, [sp], #16
    ret

// log_append(x0=op, x1=key, x2=val) -> x0 = 1 ok / 0 full
log_append:
    adrp    x9, log_offset
    add     x9, x9, :lo12:log_offset
    ldr     x10, [x9]                   // current offset
    add     x11, x10, #REC_SZ
    ldr     x12, =LOG_CAP_BYTES
    cmp     x11, x12
    b.gt    .Lla_full
    adrp    x13, log_buf
    add     x13, x13, :lo12:log_buf
    str     x0, [x13, x10]              // op
    add     x14, x10, #8
    str     x1, [x13, x14]              // key
    add     x14, x10, #16
    str     x2, [x13, x14]              // val
    str     x11, [x9]                   // log_offset = old + REC_SZ
    mov     x0, #1
    ret
.Lla_full:
    mov     x0, #0
    ret

// log_commit: snapshot offset as durable prefix.
log_commit:
    adrp    x9, log_offset
    add     x9, x9, :lo12:log_offset
    ldr     x10, [x9]
    adrp    x9, log_committed
    add     x9, x9, :lo12:log_committed
    str     x10, [x9]
    mov     x0, x10
    ret

// store_set(x0=key, x1=val) -> x0 = 1 ok / 0 fail
store_set:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    cmp     x0, #0
    b.lt    .Lss_fail
    cmp     x0, #STORE_KEYS
    b.ge    .Lss_fail
    mov     x19, x0                     // key
    mov     x20, x1                     // val
    mov     x0, #OP_SET
    mov     x1, x19
    mov     x2, x20
    bl      log_append
    cbz     x0, .Lss_done               // x0 already 0
    adrp    x9, data_vals
    add     x9, x9, :lo12:data_vals
    str     x20, [x9, x19, lsl #3]
    adrp    x9, data_present
    add     x9, x9, :lo12:data_present
    mov     w10, #1
    strb    w10, [x9, x19]
    mov     x0, #1
.Lss_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.Lss_fail:
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// store_del(x0=key) -> x0 = 1 ok / 0 fail
store_del:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    cmp     x0, #0
    b.lt    .Lsd_fail
    cmp     x0, #STORE_KEYS
    b.ge    .Lsd_fail
    mov     x19, x0
    mov     x0, #OP_DEL
    mov     x1, x19
    mov     x2, #0
    bl      log_append
    cbz     x0, .Lsd_done
    adrp    x9, data_vals
    add     x9, x9, :lo12:data_vals
    str     xzr, [x9, x19, lsl #3]
    adrp    x9, data_present
    add     x9, x9, :lo12:data_present
    strb    wzr, [x9, x19]
    mov     x0, #1
.Lsd_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.Lsd_fail:
    mov     x0, #0
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// store_get(x0=key) -> x0 = value or -1
store_get:
    cmp     x0, #0
    b.lt    .Lsg_absent
    cmp     x0, #STORE_KEYS
    b.ge    .Lsg_absent
    adrp    x9, data_present
    add     x9, x9, :lo12:data_present
    ldrb    w10, [x9, x0]
    cbz     w10, .Lsg_absent
    adrp    x9, data_vals
    add     x9, x9, :lo12:data_vals
    ldr     x0, [x9, x0, lsl #3]
    ret
.Lsg_absent:
    mov     x0, #-1
    ret

// replay -> x0 = applied count
replay:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    bl      store_clear
    mov     x19, #0                     // pos
    mov     x20, #0                     // applied
    adrp    x9, log_buf
    add     x9, x9, :lo12:log_buf
    adrp    x10, log_committed
    add     x10, x10, :lo12:log_committed
    ldr     x10, [x10]                  // committed snapshot
    adrp    x11, data_vals
    add     x11, x11, :lo12:data_vals
    adrp    x12, data_present
    add     x12, x12, :lo12:data_present
.Lrp_loop:
    cmp     x19, x10
    b.ge    .Lrp_done
    ldr     x13, [x9, x19]              // op
    add     x14, x19, #8
    ldr     x15, [x9, x14]              // key
    add     x14, x19, #16
    ldr     x16, [x9, x14]              // val
    cmp     x13, #OP_SET
    b.eq    .Lrp_set
    cmp     x13, #OP_DEL
    b.eq    .Lrp_del
    b       .Lrp_next
.Lrp_set:
    str     x16, [x11, x15, lsl #3]
    mov     w17, #1
    strb    w17, [x12, x15]
    add     x20, x20, #1
    b       .Lrp_next
.Lrp_del:
    str     xzr, [x11, x15, lsl #3]
    strb    wzr, [x12, x15]
    add     x20, x20, #1
.Lrp_next:
    add     x19, x19, #REC_SZ
    b       .Lrp_loop
.Lrp_done:
    mov     x0, x20
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// expect_eq(x0=actual, x1=expected): branches to fail on mismatch.
expect_eq:
    cmp     x0, x1
    b.ne    fail
    ret

// load64_buf(x0=byte_offset) -> x0 = log_buf[off..]
load64_buf:
    adrp    x9, log_buf
    add     x9, x9, :lo12:log_buf
    ldr     x0, [x9, x0]
    ret

_start:
    // --- test_append_and_replay ---
    bl      reset_all
    mov     x0, #0
    mov     x1, #100
    bl      store_set
    mov     x0, #1
    mov     x1, #200
    bl      store_set
    mov     x0, #2
    mov     x1, #300
    bl      store_set
    bl      log_commit
    bl      store_clear
    bl      replay
    mov     x1, #3
    bl      expect_eq
    mov     x0, #0
    bl      store_get
    mov     x1, #100
    bl      expect_eq
    mov     x0, #1
    bl      store_get
    mov     x1, #200
    bl      expect_eq
    mov     x0, #2
    bl      store_get
    mov     x1, #300
    bl      expect_eq

    // --- test_log_before_data_invariant ---
    bl      reset_all
    mov     x0, #5
    mov     x1, #42
    bl      store_set
    mov     x1, #1
    bl      expect_eq
    mov     x0, #0
    bl      load64_buf
    mov     x1, #OP_SET
    bl      expect_eq
    mov     x0, #8
    bl      load64_buf
    mov     x1, #5
    bl      expect_eq
    mov     x0, #16
    bl      load64_buf
    mov     x1, #42
    bl      expect_eq
    mov     x0, #5
    bl      store_get
    mov     x1, #42
    bl      expect_eq

    // --- test_uncommitted_writes_lost_on_crash ---
    bl      reset_all
    mov     x0, #0
    mov     x1, #1
    bl      store_set
    mov     x0, #1
    mov     x1, #2
    bl      store_set
    bl      log_commit
    mov     x0, #2
    mov     x1, #3
    bl      store_set
    mov     x0, #3
    mov     x1, #4
    bl      store_set
    bl      store_clear
    bl      replay
    mov     x1, #2
    bl      expect_eq
    mov     x0, #0
    bl      store_get
    mov     x1, #1
    bl      expect_eq
    mov     x0, #1
    bl      store_get
    mov     x1, #2
    bl      expect_eq
    mov     x0, #2
    bl      store_get
    mov     x1, #-1
    bl      expect_eq
    mov     x0, #3
    bl      store_get
    mov     x1, #-1
    bl      expect_eq

    // --- test_delete_replays_correctly ---
    bl      reset_all
    mov     x0, #0
    mov     x1, #100
    bl      store_set
    mov     x0, #1
    mov     x1, #200
    bl      store_set
    mov     x0, #0
    bl      store_del
    bl      log_commit
    bl      store_clear
    bl      replay
    mov     x0, #0
    bl      store_get
    mov     x1, #-1
    bl      expect_eq
    mov     x0, #1
    bl      store_get
    mov     x1, #200
    bl      expect_eq

    // --- test_overwrite_uses_last_record ---
    bl      reset_all
    mov     x0, #7
    mov     x1, #100
    bl      store_set
    mov     x0, #7
    mov     x1, #200
    bl      store_set
    mov     x0, #7
    mov     x1, #300
    bl      store_set
    bl      log_commit
    bl      store_clear
    bl      replay
    mov     x0, #7
    bl      store_get
    mov     x1, #300
    bl      expect_eq

    // --- test_sequential_offsets_monotonic ---
    bl      reset_all
    adrp    x19, log_offset
    add     x19, x19, :lo12:log_offset
    ldr     x20, [x19]                  // prev
    mov     x21, #0                     // i
.Lmono_loop:
    cmp     x21, #5
    b.ge    .Lmono_done
    mov     x0, x21
    mov     x9, #10
    mul     x1, x21, x9                 // val = i * 10
    bl      store_set
    ldr     x9, [x19]
    cmp     x9, x20
    b.le    fail
    mov     x20, x9
    add     x21, x21, #1
    b       .Lmono_loop
.Lmono_done:

    // --- test_log_capacity_limit ---
    bl      reset_all
    mov     x21, #0                     // i
    mov     x22, #0                     // failures
.Lcap_loop:
    cmp     x21, #300
    b.ge    .Lcap_done
    mov     x0, #0
    mov     x1, x21
    bl      store_set
    cbnz    x0, .Lcap_skip
    add     x22, x22, #1
.Lcap_skip:
    add     x21, x21, #1
    b       .Lcap_loop
.Lcap_done:
    cbz     x22, fail

    // --- Done — write success and exit 0 ---
    mov     x0, #1
    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0

fail:
    mov     x0, #2
    adrp    x1, msg_fail
    add     x1, x1, :lo12:msg_fail
    mov     x2, #msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0
