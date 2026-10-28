// Vidya — DNS in AArch64 Assembly
//
// Asm port focuses on zone_lookup with CNAME chain + cache_lookup/insert
// + resolve. 6 tests: A hit, CNAME chain, loop bounded,
// cache miss → hit, miss again after TTL expiry, and a CNAME-reached
// answer that expires with the shortest TTL on its chain.
//
// Simplification: zone_lookup returns -1 for EVERY failure. It does not
// tell NXDOMAIN (no such name) from NODATA (name exists, type does not;
// RFC 2308 §2.2) or SERVFAIL (a CNAME loop or over-deep chain; RFC 1034
// §3.6.2), and resolve caches all of them alike. A real resolver must
// keep them apart: answering NXDOMAIN for a name that exists tells an
// RFC 8020 resolver the whole name is gone.

.global _start

.equ RR_A, 1
.equ RR_CNAME, 3
.equ ZONE_CAP, 64
.equ CACHE_CAP, 32
.equ CNAME_MAX_DEPTH, 16
.equ NEGATIVE_TTL, 300

.bss
.align 8
z_name:       .skip 8 * ZONE_CAP
z_type:       .skip 8 * ZONE_CAP
z_ttl:        .skip 8 * ZONE_CAP
z_value:      .skip 8 * ZONE_CAP
c_name:       .skip 8 * CACHE_CAP
c_type:       .skip 8 * CACHE_CAP
c_value:      .skip 8 * CACHE_CAP
c_expires:    .skip 8 * CACHE_CAP

.data
.align 8
z_count:      .quad 0
c_count:      .quad 0
now_clock:    .quad 0
last_status:  .quad 0
last_ttl:     .quad 0             // min TTL over the chain zone_lookup walked

.section .rodata
msg_pass:     .ascii "dns: 6/6 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// zone_add(x0=name, x1=rtype, x2=ttl, x3=value)
zone_add:
    adrp    x4, z_count
    add     x4, x4, :lo12:z_count
    ldr     x5, [x4]
    cmp     x5, #ZONE_CAP
    b.ge    .za_done
    adrp    x6, z_name
    add     x6, x6, :lo12:z_name
    str     x0, [x6, x5, lsl #3]
    adrp    x6, z_type
    add     x6, x6, :lo12:z_type
    str     x1, [x6, x5, lsl #3]
    adrp    x6, z_ttl
    add     x6, x6, :lo12:z_ttl
    str     x2, [x6, x5, lsl #3]
    adrp    x6, z_value
    add     x6, x6, :lo12:z_value
    str     x3, [x6, x5, lsl #3]
    add     x5, x5, #1
    str     x5, [x4]
.za_done:
    ret

// zone_lookup(x0=name, x1=rtype) -> x0; on a hit, last_ttl = the
// minimum TTL over every record on the chain (each CNAME and the final
// record): the answer must not be cached longer than any link lives.
zone_lookup:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    mov     x19, x0               // cur
    mov     x20, x1               // rtype
    mov     x21, #0               // depth
    mov     x7, #0x7FFFFFFFFFFFFFFF   // min_ttl (no call below: x7 is safe)
.zl_outer:
    cmp     x21, #CNAME_MAX_DEPTH
    b.gt    .zl_neg
    // Direct match scan
    adrp    x2, z_count
    add     x2, x2, :lo12:z_count
    ldr     x22, [x2]             // count
    mov     x3, #0                // i
.zl_search:
    cmp     x3, x22
    b.ge    .zl_search_done
    adrp    x4, z_name
    add     x4, x4, :lo12:z_name
    ldr     x5, [x4, x3, lsl #3]
    cmp     x5, x19
    b.ne    .zl_search_next
    adrp    x4, z_type
    add     x4, x4, :lo12:z_type
    ldr     x5, [x4, x3, lsl #3]
    cmp     x5, x20
    b.ne    .zl_search_next
    adrp    x4, z_ttl
    add     x4, x4, :lo12:z_ttl
    ldr     x8, [x4, x3, lsl #3]
    cmp     x8, x7
    csel    x7, x8, x7, lt        // min_ttl = min(min_ttl, ttl)
    adrp    x4, last_ttl
    add     x4, x4, :lo12:last_ttl
    str     x7, [x4]
    adrp    x4, z_value
    add     x4, x4, :lo12:z_value
    ldr     x0, [x4, x3, lsl #3]
    b       .zl_done
.zl_search_next:
    add     x3, x3, #1
    b       .zl_search
.zl_search_done:
    cmp     x20, #RR_A
    b.ne    .zl_neg
    mov     x3, #0
    mov     x6, #0                // cn
.zl_cname:
    cmp     x3, x22
    b.ge    .zl_cname_done
    adrp    x4, z_name
    add     x4, x4, :lo12:z_name
    ldr     x5, [x4, x3, lsl #3]
    cmp     x5, x19
    b.ne    .zl_cname_next
    adrp    x4, z_type
    add     x4, x4, :lo12:z_type
    ldr     x5, [x4, x3, lsl #3]
    cmp     x5, #RR_CNAME
    b.ne    .zl_cname_next
    adrp    x4, z_ttl
    add     x4, x4, :lo12:z_ttl
    ldr     x8, [x4, x3, lsl #3]
    cmp     x8, x7
    csel    x7, x8, x7, lt        // the CNAME's own TTL bounds the answer
    adrp    x4, z_value
    add     x4, x4, :lo12:z_value
    ldr     x6, [x4, x3, lsl #3]
    b       .zl_cname_done
.zl_cname_next:
    add     x3, x3, #1
    b       .zl_cname
.zl_cname_done:
    cbz     x6, .zl_neg
    mov     x19, x6
    add     x21, x21, #1
    b       .zl_outer
.zl_neg:
    mov     x0, #-1
.zl_done:
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

// cache_lookup(x0=name, x1=rtype) -> x0
cache_lookup:
    adrp    x2, c_count
    add     x2, x2, :lo12:c_count
    ldr     x2, [x2]
    mov     x3, #0
.cl_loop:
    cmp     x3, x2
    b.ge    .cl_miss
    adrp    x4, c_name
    add     x4, x4, :lo12:c_name
    ldr     x5, [x4, x3, lsl #3]
    cmp     x5, x0
    b.ne    .cl_next
    adrp    x4, c_type
    add     x4, x4, :lo12:c_type
    ldr     x5, [x4, x3, lsl #3]
    cmp     x5, x1
    b.ne    .cl_next
    adrp    x4, c_expires
    add     x4, x4, :lo12:c_expires
    ldr     x5, [x4, x3, lsl #3]
    adrp    x6, now_clock
    add     x6, x6, :lo12:now_clock
    ldr     x6, [x6]
    cmp     x5, x6
    b.le    .cl_next
    adrp    x4, last_status
    add     x4, x4, :lo12:last_status
    mov     x5, #1
    str     x5, [x4]
    adrp    x4, c_value
    add     x4, x4, :lo12:c_value
    ldr     x0, [x4, x3, lsl #3]
    ret
.cl_next:
    add     x3, x3, #1
    b       .cl_loop
.cl_miss:
    adrp    x4, last_status
    add     x4, x4, :lo12:last_status
    mov     x5, #0
    str     x5, [x4]
    mov     x0, #-1
    ret

// cache_insert(x0=name, x1=rtype, x2=value, x3=ttl)
cache_insert:
    adrp    x4, now_clock
    add     x4, x4, :lo12:now_clock
    ldr     x5, [x4]
    add     x5, x5, x3            // exp
    adrp    x6, c_count
    add     x6, x6, :lo12:c_count
    ldr     x7, [x6]
    mov     x8, #0
.ci_loop:
    cmp     x8, x7
    b.ge    .ci_append
    adrp    x9, c_name
    add     x9, x9, :lo12:c_name
    ldr     x10, [x9, x8, lsl #3]
    cmp     x10, x0
    b.ne    .ci_next
    adrp    x9, c_type
    add     x9, x9, :lo12:c_type
    ldr     x10, [x9, x8, lsl #3]
    cmp     x10, x1
    b.ne    .ci_next
    adrp    x9, c_value
    add     x9, x9, :lo12:c_value
    str     x2, [x9, x8, lsl #3]
    adrp    x9, c_expires
    add     x9, x9, :lo12:c_expires
    str     x5, [x9, x8, lsl #3]
    ret
.ci_next:
    add     x8, x8, #1
    b       .ci_loop
.ci_append:
    cmp     x7, #CACHE_CAP
    b.ge    .ci_done
    adrp    x9, c_name
    add     x9, x9, :lo12:c_name
    str     x0, [x9, x7, lsl #3]
    adrp    x9, c_type
    add     x9, x9, :lo12:c_type
    str     x1, [x9, x7, lsl #3]
    adrp    x9, c_value
    add     x9, x9, :lo12:c_value
    str     x2, [x9, x7, lsl #3]
    adrp    x9, c_expires
    add     x9, x9, :lo12:c_expires
    str     x5, [x9, x7, lsl #3]
    add     x7, x7, #1
    str     x7, [x6]
.ci_done:
    ret

// advance_time(x0=s)
advance_time:
    adrp    x1, now_clock
    add     x1, x1, :lo12:now_clock
    ldr     x2, [x1]
    add     x2, x2, x0
    str     x2, [x1]
    ret

// resolve(x0=name, x1=rtype) -> x0
resolve:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    mov     x19, x0
    mov     x20, x1
    bl      cache_lookup
    adrp    x2, last_status
    add     x2, x2, :lo12:last_status
    ldr     x2, [x2]
    cbnz    x2, .rs_done
    mov     x0, x19
    mov     x1, x20
    bl      zone_lookup
    cmn     x0, #1
    b.ne    .rs_pos
    mov     x0, x19
    mov     x1, x20
    mov     x2, #-1
    mov     x3, #NEGATIVE_TTL
    bl      cache_insert
    mov     x0, #-1
    b       .rs_done
.rs_pos:
    // Only x19/x20 were saved in the prologue, so x21-x28 are off limits
    // (callee-saved: our caller expects them back). Spill the value instead.
    str     x0, [sp, #-16]!
    // TTL = min over the chain, from zone_lookup. (Looking up a record
    // named `name` of type `rtype` finds nothing for a CNAME-reached
    // answer and would fall back to NEGATIVE_TTL, outliving the A record.)
    adrp    x6, last_ttl
    add     x6, x6, :lo12:last_ttl
    ldr     x5, [x6]
    ldr     x2, [sp], #16         // value
    mov     x0, x19
    mov     x1, x20
    mov     x3, x5
    bl      cache_insert
    // Re-load value to return — was popped already; recompute via zone_lookup again
    // (cheap; alternative is to push twice). Keep it simple.
    mov     x0, x19
    mov     x1, x20
    bl      zone_lookup
.rs_done:
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

assert_eq:
    cmp     x0, x1
    b.ne    fail_exit
    ret

fail_exit:
    mov     x0, #1
    adrp    x1, msg_fail
    add     x1, x1, :lo12:msg_fail
    mov     x2, #msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0

_start:
    // Build zone subset
    mov     x0, #1
    mov     x1, #RR_A
    mov     x2, #300
    ldr     x3, =0x7F000001
    bl      zone_add
    mov     x0, #2
    mov     x1, #RR_CNAME
    mov     x2, #600
    mov     x3, #1
    bl      zone_add
    mov     x0, #10
    mov     x1, #RR_CNAME
    mov     x2, #600
    mov     x3, #11
    bl      zone_add
    mov     x0, #11
    mov     x1, #RR_CNAME
    mov     x2, #600
    mov     x3, #10
    bl      zone_add

    // 1. A direct
    mov     x0, #1
    mov     x1, #RR_A
    bl      zone_lookup
    ldr     x1, =0x7F000001
    bl      assert_eq

    // 2. CNAME chain
    mov     x0, #2
    mov     x1, #RR_A
    bl      zone_lookup
    ldr     x1, =0x7F000001
    bl      assert_eq

    // 3. CNAME loop bounded
    mov     x0, #10
    mov     x1, #RR_A
    bl      zone_lookup
    mov     x1, #-1
    bl      assert_eq

    // 4. Cache miss → hit (status AND the answer: a cache that stored the
    //    wrong value would still report a hit)
    mov     x0, #1
    mov     x1, #RR_A
    bl      resolve
    mov     x19, x0               // answer (x19: callee-saved, survives bl)
    adrp    x0, last_status
    add     x0, x0, :lo12:last_status
    ldr     x0, [x0]
    mov     x1, #0
    bl      assert_eq
    mov     x0, x19
    ldr     x1, =0x7F000001
    bl      assert_eq
    mov     x0, #1
    mov     x1, #RR_A
    bl      resolve
    mov     x19, x0
    adrp    x0, last_status
    add     x0, x0, :lo12:last_status
    ldr     x0, [x0]
    mov     x1, #1
    bl      assert_eq
    mov     x0, x19
    ldr     x1, =0x7F000001
    bl      assert_eq

    // 5. TTL expiry
    mov     x0, #301
    bl      advance_time
    mov     x0, #1
    mov     x1, #RR_A
    bl      resolve
    mov     x19, x0
    adrp    x0, last_status
    add     x0, x0, :lo12:last_status
    ldr     x0, [x0]
    mov     x1, #0
    bl      assert_eq
    mov     x0, x19
    ldr     x1, =0x7F000001
    bl      assert_eq

    // 6. A CNAME-reached answer expires with the SHORTEST TTL on its
    //    chain: 3 -> CNAME (600 s) -> 4 (A, 60 s). Caching it for longer
    //    would keep serving the A record after it expired.
    mov     x0, #3
    mov     x1, #RR_CNAME
    mov     x2, #600
    mov     x3, #4
    bl      zone_add
    mov     x0, #4
    mov     x1, #RR_A
    mov     x2, #60
    ldr     x3, =0x7F000004
    bl      zone_add
    mov     x0, #3
    mov     x1, #RR_A
    bl      resolve               // miss: fills the cache
    mov     x0, #61
    bl      advance_time
    mov     x0, #3
    mov     x1, #RR_A
    bl      resolve
    adrp    x0, last_status
    add     x0, x0, :lo12:last_status
    ldr     x0, [x0]
    mov     x1, #0                // must be a miss: the A record expired
    bl      assert_eq

    mov     x0, #1
    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0
