// Vidya — Build Systems in AArch64 Assembly
//
// A minimal build-system core: a DAG of targets, topological build
// order (Kahn ready-scan), content-signature dirty-tracking, and
// ninja-style incremental rebuild (only dirty targets run), plus cycle
// detection. Mirrors content/build_systems/cyrius.cyr exactly.
//
// No real files: each target carries a source "content signature" (an
// integer). A target's INPUT signature mixes its own source with the
// OUTPUT signatures of its dependencies; if that differs from what it
// was last built against, the target is dirty and rebuilds. Editing a
// source re-dirties everything downstream — like mtime/hash tools
// (make, ninja, bazel) decide what to redo.
//
// Static parallel arrays in .bss, 8 bytes per i64 slot. Every function
// that calls `bl` saves x29/x30 in its prologue. The signature modulo
// is done with udiv+msub (all values are non-negative).

.global _start

.equ MAXD, 8                // max deps per target
.equ HB,   131              // signature polynomial base
.equ HM,   1000003          // signature modulus (prime; < 2^53)

.section .bss
.align 3
t_src:      .skip 8 * 16     // source content signature (16 targets)
t_depcnt:   .skip 8 * 16     // number of dependencies
t_deps:     .skip 8 * 128    // flat deps: t_deps[t*MAXD + k]
t_built:    .skip 8 * 16     // signature last built against (-1 = never)
t_out:      .skip 8 * 16     // current output signature
t_order:    .skip 8 * 16     // topological order (target ids)
t_placed:   .skip 8 * 16     // topo scratch: placed flag
n_targets:  .skip 8          // number of active targets

.section .rodata
msg_pass:    .ascii "All build_systems examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

// bs_reset(x0 = n): set n_targets, zero src/depcnt/out, t_built = -1.
bs_reset:
    adrp    x9, n_targets
    add     x9, x9, :lo12:n_targets
    str     x0, [x9]                 // n_targets = n

    adrp    x10, t_src
    add     x10, x10, :lo12:t_src
    adrp    x11, t_depcnt
    add     x11, x11, :lo12:t_depcnt
    adrp    x12, t_built
    add     x12, x12, :lo12:t_built
    adrp    x13, t_out
    add     x13, x13, :lo12:t_out

    mov     x14, #0                  // i
.Lbr_loop:
    cmp     x14, x0
    b.ge    .Lbr_done
    str     xzr, [x10, x14, lsl #3]  // t_src[i] = 0
    str     xzr, [x11, x14, lsl #3]  // t_depcnt[i] = 0
    mov     x15, #-1
    str     x15, [x12, x14, lsl #3]  // t_built[i] = -1
    str     xzr, [x13, x14, lsl #3]  // t_out[i] = 0
    add     x14, x14, #1
    b       .Lbr_loop
.Lbr_done:
    ret

// bs_set_src(x0 = t, x1 = sig): t_src[t] = sig
bs_set_src:
    adrp    x9, t_src
    add     x9, x9, :lo12:t_src
    str     x1, [x9, x0, lsl #3]
    ret

// bs_add_dep(x0 = t, x1 = d):
//   c = t_depcnt[t]; t_deps[t*MAXD + c] = d; t_depcnt[t] = c + 1
bs_add_dep:
    adrp    x9, t_depcnt
    add     x9, x9, :lo12:t_depcnt
    ldr     x10, [x9, x0, lsl #3]    // c
    // off = t*MAXD + c
    lsl     x11, x0, #3              // t * MAXD (MAXD=8)
    add     x11, x11, x10            // + c
    adrp    x12, t_deps
    add     x12, x12, :lo12:t_deps
    str     x1, [x12, x11, lsl #3]   // t_deps[off] = d
    add     x10, x10, #1
    str     x10, [x9, x0, lsl #3]    // t_depcnt[t] = c + 1
    ret

// bs_topo() -> x0 = number of targets ordered (< n_targets ⇒ cycle).
// Kahn ready-scan: place any unplaced target whose deps are all placed.
// Callee-saved: x19=n, x20=placed, x21=t (outer), x19 reused as scratch
// only after final read. No `bl` made → no x30 spill needed, but we keep
// x19/x20/x21 saved per the convention.
bs_topo:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]

    adrp    x9, n_targets
    add     x9, x9, :lo12:n_targets
    ldr     x19, [x9]                // n = n_targets

    // clear t_placed[0..n)
    adrp    x10, t_placed
    add     x10, x10, :lo12:t_placed
    mov     x11, #0
.Ltopo_clr:
    cmp     x11, x19
    b.ge    .Ltopo_clr_done
    str     xzr, [x10, x11, lsl #3]
    add     x11, x11, #1
    b       .Ltopo_clr
.Ltopo_clr_done:

    mov     x20, #0                  // placed = 0
.Ltopo_outer:
    cmp     x20, x19
    b.ge    .Ltopo_ret               // placed >= n ⇒ done
    mov     x12, #0                  // progress = 0
    mov     x21, #0                  // t = 0
.Ltopo_scan:
    cmp     x21, x19
    b.ge    .Ltopo_scan_done

    // if t_placed[t] != 0 → skip
    adrp    x9, t_placed
    add     x9, x9, :lo12:t_placed
    ldr     x10, [x9, x21, lsl #3]
    cbnz    x10, .Ltopo_next

    // ready = 1; for k in 0..depcnt: if !placed[dep] ready = 0
    mov     x13, #1                  // ready
    adrp    x9, t_depcnt
    add     x9, x9, :lo12:t_depcnt
    ldr     x14, [x9, x21, lsl #3]   // dc
    mov     x15, #0                  // k
    // base of t_deps row = t*MAXD
    lsl     x16, x21, #3             // t * MAXD
    adrp    x17, t_deps
    add     x17, x17, :lo12:t_deps
    adrp    x6, t_placed
    add     x6, x6, :lo12:t_placed
.Ltopo_dep:
    cmp     x15, x14
    b.ge    .Ltopo_dep_done
    add     x7, x16, x15             // t*MAXD + k
    ldr     x8, [x17, x7, lsl #3]    // d = t_deps[...]
    ldr     x3, [x6, x8, lsl #3]     // t_placed[d]
    cbnz    x3, .Ltopo_dep_ok
    mov     x13, #0                  // ready = 0
.Ltopo_dep_ok:
    add     x15, x15, #1
    b       .Ltopo_dep
.Ltopo_dep_done:
    cbz     x13, .Ltopo_next         // not ready

    // place t: t_order[placed] = t; t_placed[t] = 1; placed++; progress=1
    adrp    x9, t_order
    add     x9, x9, :lo12:t_order
    str     x21, [x9, x20, lsl #3]
    adrp    x9, t_placed
    add     x9, x9, :lo12:t_placed
    mov     x10, #1
    str     x10, [x9, x21, lsl #3]
    add     x20, x20, #1
    mov     x12, #1                  // progress = 1

.Ltopo_next:
    add     x21, x21, #1
    b       .Ltopo_scan
.Ltopo_scan_done:
    cbz     x12, .Ltopo_ret          // no progress ⇒ stuck (cycle)
    b       .Ltopo_outer

.Ltopo_ret:
    mov     x0, x20                  // return placed
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// bs_sig(x0 = t) -> x0 = input signature.
//   sig = t_src[t] % HM
//   for k in 0..depcnt: sig = (sig*HB + t_out[dep]) % HM
// All values non-negative ⇒ modulo via udiv + msub.
bs_sig:
    // sig = t_src[t] % HM
    adrp    x9, t_src
    add     x9, x9, :lo12:t_src
    ldr     x10, [x9, x0, lsl #3]    // src
    ldr     x11, =HM
    udiv    x12, x10, x11
    msub    x10, x12, x11, x10       // sig = src - (src/HM)*HM

    adrp    x9, t_depcnt
    add     x9, x9, :lo12:t_depcnt
    ldr     x13, [x9, x0, lsl #3]    // dc
    mov     x14, #0                  // k
    lsl     x15, x0, #3              // t * MAXD
    adrp    x16, t_deps
    add     x16, x16, :lo12:t_deps
    adrp    x17, t_out
    add     x17, x17, :lo12:t_out
    mov     x6, #HB
.Lsig_loop:
    cmp     x14, x13
    b.ge    .Lsig_done
    add     x7, x15, x14             // t*MAXD + k
    ldr     x8, [x16, x7, lsl #3]    // d
    ldr     x3, [x17, x8, lsl #3]    // t_out[d]
    // sig = (sig*HB + t_out[d]) % HM
    mul     x10, x10, x6
    add     x10, x10, x3
    udiv    x12, x10, x11
    msub    x10, x12, x11, x10
    add     x14, x14, #1
    b       .Lsig_loop
.Lsig_done:
    mov     x0, x10
    ret

// bs_build() -> x0 = number of targets rebuilt.
// ordered = bs_topo(); walk order; if sig != t_built[t] rebuild.
// Callee-saved: x19=ordered, x20=i, x21=rebuilt.
bs_build:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]

    bl      bs_topo
    mov     x19, x0                  // ordered
    mov     x20, #0                  // i
    mov     x21, #0                  // rebuilt
.Lbld_loop:
    cmp     x20, x19
    b.ge    .Lbld_done
    // t = t_order[i]
    adrp    x9, t_order
    add     x9, x9, :lo12:t_order
    ldr     x0, [x9, x20, lsl #3]
    mov     x22, x0                  // keep t (x22 is scratch here, save it)
    str     x22, [sp, #-16]!         // protect t across bs_sig
    bl      bs_sig                   // x0 = sig
    ldr     x22, [sp], #16           // restore t
    // if sig != t_built[t]
    adrp    x9, t_built
    add     x9, x9, :lo12:t_built
    ldr     x10, [x9, x22, lsl #3]
    cmp     x0, x10
    b.eq    .Lbld_next
    // t_out[t] = sig; t_built[t] = sig; rebuilt++
    adrp    x10, t_out
    add     x10, x10, :lo12:t_out
    str     x0, [x10, x22, lsl #3]
    str     x0, [x9, x22, lsl #3]
    add     x21, x21, #1
.Lbld_next:
    add     x20, x20, #1
    b       .Lbld_loop
.Lbld_done:
    mov     x0, x21
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// build_graph(): app(2) <- util.o(0), main.o(1)
build_graph:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x0, #3
    bl      bs_reset
    mov     x0, #0
    mov     x1, #1001
    bl      bs_set_src
    mov     x0, #1
    mov     x1, #2002
    bl      bs_set_src
    mov     x0, #2
    mov     x1, #3003
    bl      bs_set_src
    mov     x0, #2
    mov     x1, #0
    bl      bs_add_dep
    mov     x0, #2
    mov     x1, #1
    bl      bs_add_dep
    ldp     x29, x30, [sp], #16
    ret

// order_pos(x0 = target) -> x0 = index in t_order, or -1.
order_pos:
    adrp    x9, n_targets
    add     x9, x9, :lo12:n_targets
    ldr     x10, [x9]                // n
    adrp    x11, t_order
    add     x11, x11, :lo12:t_order
    mov     x12, #0                  // i
.Lop_loop:
    cmp     x12, x10
    b.ge    .Lop_notfound
    ldr     x13, [x11, x12, lsl #3]
    cmp     x13, x0
    b.eq    .Lop_found
    add     x12, x12, #1
    b       .Lop_loop
.Lop_found:
    mov     x0, x12
    ret
.Lop_notfound:
    mov     x0, #-1
    ret

// _start: run all tests; sp is 16-byte aligned at entry.
_start:
    // ---- Test 1: topo orders all 3; app after util.o and main.o ----
    bl      build_graph
    bl      bs_topo
    cmp     x0, #3
    b.ne    fail

    // pos(2) > pos(0)
    mov     x0, #2
    bl      order_pos
    mov     x19, x0                  // pos2
    mov     x0, #0
    bl      order_pos
    cmp     x19, x0                  // pos2 > pos0 ?
    b.le    fail
    // pos(2) > pos(1)
    mov     x0, #1
    bl      order_pos
    cmp     x19, x0
    b.le    fail

    // ---- Test 2: cold build rebuilds all 3 ----
    bl      build_graph
    bl      bs_build
    cmp     x0, #3
    b.ne    fail

    // ---- Test 3: second build (no edits) rebuilds 0 ----
    bl      build_graph
    bl      bs_build                 // cold
    bl      bs_build                 // noop
    cbnz    x0, fail

    // ---- Test 4: edit main.c (t_src[1]=2999) → rebuilds 2 ----
    bl      build_graph
    bl      bs_build                 // cold
    mov     x0, #1
    mov     x1, #2999
    bl      bs_set_src
    bl      bs_build
    cmp     x0, #2
    b.ne    fail

    // ---- Test 5: edit util.c (t_src[0]=1999) → rebuilds 2,
    //              t_built[1] unchanged ----
    bl      build_graph
    bl      bs_build                 // cold
    // capture t_built[1]
    adrp    x9, t_built
    add     x9, x9, :lo12:t_built
    ldr     x19, [x9, #8]            // t_built[1]
    mov     x0, #0
    mov     x1, #1999
    bl      bs_set_src
    bl      bs_build
    cmp     x0, #2
    b.ne    fail
    adrp    x9, t_built
    add     x9, x9, :lo12:t_built
    ldr     x10, [x9, #8]            // t_built[1] after
    cmp     x10, x19
    b.ne    fail

    // ---- Test 6: 2-node cycle 0→1, 1→0 → topo places < 2 ----
    mov     x0, #2
    bl      bs_reset
    mov     x0, #0
    mov     x1, #1
    bl      bs_add_dep
    mov     x0, #1
    mov     x1, #0
    bl      bs_add_dep
    bl      bs_topo
    cmp     x0, #2
    b.ge    fail

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
    mov     x0, #2
    adr     x1, msg_fail
    mov     x2, msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0
