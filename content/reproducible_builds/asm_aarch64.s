// Vidya — Reproducible Builds in AArch64 Assembly
//
// A reproducible build is a pure function of its inputs: the same
// sources produce a byte-identical artifact, on any machine, at any
// time. Three classic sources of non-determinism, and their fixes:
//
//   1. Embedded wall-clock timestamps  -> clamp every timestamp to
//      SOURCE_DATE_EPOCH (a fixed build time taken from the sources)
//      so "now" never leaks in.
//   2. Filesystem iteration order      -> readdir() order varies; SORT
//      filenames before processing so output doesn't depend on layout.
//   3. Non-deterministic artifact names -> name artifacts by the HASH
//      of their content (content-addressing) -> identical inputs map to
//      identical paths, and the build becomes idempotent.
//
// Verification: build twice and compare digests. This models that
// pipeline over an in-memory file set (name key + content signature)
// and shows a deterministic build staying identical across runs that
// differ in input order AND wall-clock time, while a naive build drifts.
// Mirrors content/reproducible_builds/cyrius.cyr exactly.
//
// Static parallel arrays in .bss, 8 bytes per i64 slot. Every function
// that calls `bl` saves x29/x30 in its prologue. The fold modulo is
// done with udiv+msub (all values are non-negative).

.global _start

.equ HB,    131            // hash polynomial base
.equ HM,    1000003        // hash modulus (prime; < 2^53)
.equ HSEED, 7              // digest seed

.section .bss
.align 3
f_name:     .skip 8 * 128    // file name sort-keys
f_content:  .skip 8 * 128    // file content signatures
f_n:        .skip 8          // number of active files

.section .rodata
msg_pass:    .ascii "All reproducible_builds examples passed.\n"
msg_pass_len = . - msg_pass

.section .text

// fold(x0 = h, x1 = v) -> x0 = (h*HB + v) % HM
// All values non-negative -> modulo via udiv + msub.
fold:
    mov     x9, #HB
    mul     x10, x0, x9              // h * HB
    add     x10, x10, x1             // + v
    ldr     x11, =HM
    udiv    x12, x10, x11
    msub    x0, x12, x11, x10        // h - (h/HM)*HM
    ret

// normalize_ts(x0 = now, x1 = sde) -> x0 = (now > sde) ? sde : now
normalize_ts:
    cmp     x0, x1
    csel    x0, x1, x0, gt           // gt -> sde, else now
    ret

// cas_path(x0 = content) -> x0 = (content*HB + 7) % HM
cas_path:
    mov     x9, #HB
    mul     x10, x0, x9
    add     x10, x10, #7
    ldr     x11, =HM
    udiv    x12, x10, x11
    msub    x0, x12, x11, x10
    ret

// files_reset(x0 = n): f_n = n
files_reset:
    adrp    x9, f_n
    add     x9, x9, :lo12:f_n
    str     x0, [x9]
    ret

// file_set(x0 = i, x1 = name, x2 = content):
//   f_name[i] = name; f_content[i] = content
file_set:
    adrp    x9, f_name
    add     x9, x9, :lo12:f_name
    str     x1, [x9, x0, lsl #3]
    adrp    x9, f_content
    add     x9, x9, :lo12:f_content
    str     x2, [x9, x0, lsl #3]
    ret

// files_sort(): insertion sort by f_name ascending, f_content moved
// alongside so the (name, content) pairing is preserved.
files_sort:
    adrp    x16, f_name
    add     x16, x16, :lo12:f_name
    adrp    x17, f_content
    add     x17, x17, :lo12:f_content
    adrp    x9, f_n
    add     x9, x9, :lo12:f_n
    ldr     x9, [x9]                 // n
    mov     x1, #1                   // i = 1
.Lsort_outer:
    cmp     x1, x9
    b.ge    .Lsort_done
    ldr     x2, [x16, x1, lsl #3]    // kn = f_name[i]
    ldr     x3, [x17, x1, lsl #3]    // kc = f_content[i]
    sub     x4, x1, #1               // j = i - 1
.Lsort_inner:
    cmp     x4, #0
    b.lt    .Lsort_place             // j < 0 -> done
    ldr     x5, [x16, x4, lsl #3]    // f_name[j]
    cmp     x5, x2
    b.le    .Lsort_place             // f_name[j] <= kn -> done
    // shift: f_name[j+1] = f_name[j]; f_content[j+1] = f_content[j]
    add     x6, x4, #1
    str     x5, [x16, x6, lsl #3]
    ldr     x7, [x17, x4, lsl #3]
    str     x7, [x17, x6, lsl #3]
    sub     x4, x4, #1               // j = j - 1
    b       .Lsort_inner
.Lsort_place:
    add     x6, x4, #1               // j + 1
    str     x2, [x16, x6, lsl #3]    // f_name[j+1] = kn
    str     x3, [x17, x6, lsl #3]    // f_content[j+1] = kc
    add     x1, x1, #1               // i++
    b       .Lsort_outer
.Lsort_done:
    ret

// build_digest(x0 = do_sort, x1 = do_norm, x2 = now, x3 = sde) -> x0 = h
// Callee-saved: x19=i, x20=n, x21=h. x22/x23 hold array bases.
build_digest:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    str     x23, [sp, #48]

    // if do_sort: files_sort()
    cbz     x0, .Lbd_nosort
    // preserve args across bl (do_norm, now, sde)
    mov     x24, x1
    mov     x25, x2
    mov     x26, x3
    bl      files_sort
    mov     x1, x24
    mov     x2, x25
    mov     x3, x26
.Lbd_nosort:
    // ts = do_norm ? normalize_ts(now, sde) : now
    mov     x10, x2                  // ts = now
    cbz     x1, .Lbd_nonorm
    mov     x0, x2
    mov     x1, x3
    bl      normalize_ts
    mov     x10, x0                  // ts = normalize_ts(now, sde)
.Lbd_nonorm:
    // h = fold(HSEED, ts)
    mov     x0, #HSEED
    mov     x1, x10
    bl      fold
    mov     x21, x0                  // h

    mov     x19, #0                  // i = 0
    adrp    x20, f_n
    add     x20, x20, :lo12:f_n
    ldr     x20, [x20]               // n
    adrp    x22, f_name
    add     x22, x22, :lo12:f_name
    adrp    x23, f_content
    add     x23, x23, :lo12:f_content
.Lbd_loop:
    cmp     x19, x20
    b.ge    .Lbd_ret
    // h = fold(h, f_name[i])
    mov     x0, x21
    ldr     x1, [x22, x19, lsl #3]
    bl      fold
    mov     x21, x0
    // h = fold(h, f_content[i])
    mov     x0, x21
    ldr     x1, [x23, x19, lsl #3]
    bl      fold
    mov     x21, x0
    add     x19, x19, #1
    b       .Lbd_loop
.Lbd_ret:
    mov     x0, x21
    ldr     x23, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// setup_order_a(): files = (30,111),(10,222),(20,333); f_n = 3
setup_order_a:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x0, #3
    bl      files_reset
    mov     x0, #0
    mov     x1, #30
    mov     x2, #111
    bl      file_set
    mov     x0, #1
    mov     x1, #10
    mov     x2, #222
    bl      file_set
    mov     x0, #2
    mov     x1, #20
    mov     x2, #333
    bl      file_set
    ldp     x29, x30, [sp], #16
    ret

// setup_order_b(): files = (20,333),(30,111),(10,222); f_n = 3
setup_order_b:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x0, #3
    bl      files_reset
    mov     x0, #0
    mov     x1, #20
    mov     x2, #333
    bl      file_set
    mov     x0, #1
    mov     x1, #30
    mov     x2, #111
    bl      file_set
    mov     x0, #2
    mov     x1, #10
    mov     x2, #222
    bl      file_set
    ldp     x29, x30, [sp], #16
    ret

// _start: run all tests; sp is 16-byte aligned at entry.
// Callee-saved x19/x20 hold digests across calls.
_start:
    // ---- Test 1: normalize_ts clamps future, keeps past ----
    mov     x0, #9999
    mov     x1, #5000
    bl      normalize_ts
    mov     x9, #5000
    cmp     x0, x9
    b.ne    fail
    mov     x0, #3000
    mov     x1, #5000
    bl      normalize_ts
    mov     x9, #3000
    cmp     x0, x9
    b.ne    fail

    // ---- Test 2: after setup_a + sort, names ascending; content paired ----
    bl      setup_order_a
    bl      files_sort
    adrp    x9, f_name
    add     x9, x9, :lo12:f_name
    ldr     x10, [x9, #0]
    cmp     x10, #10
    b.ne    fail
    ldr     x10, [x9, #8]
    cmp     x10, #20
    b.ne    fail
    ldr     x10, [x9, #16]
    cmp     x10, #30
    b.ne    fail
    adrp    x9, f_content
    add     x9, x9, :lo12:f_content
    ldr     x10, [x9, #0]            // content followed name 10
    cmp     x10, #222
    b.ne    fail

    // ---- Test 3: content-addressing is a pure function of content ----
    mov     x0, #111
    bl      cas_path
    mov     x19, x0                  // cas(111)
    mov     x0, #111
    bl      cas_path
    cmp     x0, x19                  // same content -> same path
    b.ne    fail
    mov     x0, #222
    bl      cas_path
    cmp     x0, x19                  // different content -> different path
    b.eq    fail

    // ---- Test 4: deterministic build identical across order + clock ----
    bl      setup_order_a
    mov     x0, #1
    mov     x1, #1
    mov     x2, #9999
    mov     x3, #5000
    bl      build_digest
    mov     x19, x0                  // d1
    bl      setup_order_b
    mov     x0, #1
    mov     x1, #1
    mov     x2, #8888
    mov     x3, #5000
    bl      build_digest
    cmp     x0, x19
    b.ne    fail

    // ---- Test 5: naive build (no sort, raw now) drifts ----
    bl      setup_order_a
    mov     x0, #0
    mov     x1, #0
    mov     x2, #9999
    mov     x3, #5000
    bl      build_digest
    mov     x19, x0                  // d1
    bl      setup_order_b
    mov     x0, #0
    mov     x1, #0
    mov     x2, #8888
    mov     x3, #5000
    bl      build_digest
    cmp     x0, x19
    b.eq    fail                     // must differ

    // ---- Test 6: normalization alone kills clock drift ----
    bl      setup_order_a
    mov     x0, #1
    mov     x1, #1
    mov     x2, #9999
    mov     x3, #5000
    bl      build_digest
    mov     x19, x0                  // norm1 (clamps 9999 -> 5000)
    bl      setup_order_a
    mov     x0, #1
    mov     x1, #1
    mov     x2, #7777
    mov     x3, #5000
    bl      build_digest
    cmp     x0, x19                  // norm2 (clamps 7777 -> 5000)
    b.ne    fail

    // ---- All passed ----
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0

fail:
    mov     x0, #1
    mov     x8, #93
    svc     #0
