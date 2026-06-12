// Vidya — Package Resolution in AArch64 Assembly
//
// The core of a dependency resolver (npm, cargo, cyrius.cyml's own):
// semantic versioning, caret constraint matching, range intersection
// for diamond dependencies, highest-version selection, bounded
// backtracking, and dependency-cycle detection. Mirrors
// content/package_resolution/cyrius.cyr exactly.
//
// A semver major.minor.patch is encoded as one integer
//   enc = major*1_000_000 + minor*1_000 + patch
// so version comparison IS integer comparison. A constraint is a
// half-open range [lo, hi). A caret ^X.Y.Z = [X.Y.Z, (X+1).0.0).
// Resolving a shared ("diamond") dependency intersects the ranges every
// requirer imposes and picks the highest version that survives —
// backtracking on an earlier choice when the highest pick paints a
// later dependency into an impossible corner.
//
// Static parallel arrays in .bss, 8 bytes per i64 slot. Every function
// that calls `bl` saves x29/x30 in its prologue. sv_major divides via
// udiv (all version values are non-negative). -1 sentinels mark "no
// match"; comparisons against them are signed.

.global _start

.equ VMAJ, 1000000          // major weight
.equ VMIN, 1000             // minor weight
.equ MAXD, 8                // max deps per package

.section .bss
.align 3
c_vers:     .skip 8 * 128    // available versions of shared dep C
c_n:        .skip 8          // count of C versions
g_chosen_c: .skip 8          // resolve_backtrack's chosen C output
p_depcnt:   .skip 8 * 128    // per-package dependency count
p_deps:     .skip 8 * 1024   // flat deps: p_deps[p*MAXD + k]
p_placed:   .skip 8 * 128    // Kahn scratch: placed flag
p_n:        .skip 8          // number of active packages

.section .rodata
msg_pass:    .ascii "All package_resolution examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

// ---------------------------------------------------------------------
// Semver encode / inspect
// ---------------------------------------------------------------------

// sv(x0 = maj, x1 = min, x2 = pat) -> x0 = maj*VMAJ + min*VMIN + pat
sv:
    ldr     x9, =VMAJ
    mul     x0, x0, x9               // maj*VMAJ
    ldr     x9, =VMIN
    madd    x0, x1, x9, x0           // + min*VMIN
    add     x0, x0, x2               // + pat
    ret

// sv_major(x0 = v) -> x0 = v / VMAJ
sv_major:
    ldr     x9, =VMAJ
    udiv    x0, x0, x9
    ret

// ---------------------------------------------------------------------
// Caret range [lo, hi): ^X.Y.Z = [X.Y.Z, (X+1).0.0)
// ---------------------------------------------------------------------

// caret_lo(x0 = v) -> x0 = v
caret_lo:
    ret

// caret_hi(x0 = v) -> x0 = (sv_major(v) + 1) * VMAJ
caret_hi:
    ldr     x9, =VMAJ
    udiv    x10, x0, x9              // sv_major(v)
    add     x10, x10, #1
    mul     x0, x10, x9
    ret

// ---------------------------------------------------------------------
// Constraint satisfaction over a half-open range
// ---------------------------------------------------------------------

// satisfies(x0 = v, x1 = lo, x2 = hi) -> x0 = 1 if lo<=v<hi else 0
satisfies:
    cmp     x0, x1
    b.lt    .Lsat_no                 // v < lo
    cmp     x0, x2
    b.ge    .Lsat_no                 // v >= hi
    mov     x0, #1
    ret
.Lsat_no:
    mov     x0, #0
    ret

// ---------------------------------------------------------------------
// Range intersection: [max(lo), min(hi)); empty iff lo >= hi
// ---------------------------------------------------------------------

// range_lo_max(x0 = a, x1 = b) -> x0 = max(a, b)
range_lo_max:
    cmp     x0, x1
    csel    x0, x0, x1, gt
    ret

// range_hi_min(x0 = a, x1 = b) -> x0 = min(a, b)
range_hi_min:
    cmp     x0, x1
    csel    x0, x0, x1, lt
    ret

// range_empty(x0 = lo, x1 = hi) -> x0 = 1 if lo >= hi else 0
range_empty:
    cmp     x0, x1
    cset    x0, ge
    ret

// ---------------------------------------------------------------------
// best_match(x0 = vers, x1 = n, x2 = lo, x3 = hi)
//   highest vers[0..n) in [lo, hi); -1 if none.
// ---------------------------------------------------------------------
// x9=vers, x10=n, x11=lo, x12=hi, x13=best, x14=i, x15=v
best_match:
    mov     x9, x0
    mov     x10, x1
    mov     x11, x2
    mov     x12, x3
    mov     x13, #-1                 // best = -1
    mov     x14, #0                  // i = 0
.Lbm_loop:
    cmp     x14, x10
    b.ge    .Lbm_done
    ldr     x15, [x9, x14, lsl #3]   // v = vers[i]
    // satisfies(v, lo, hi)?  lo <= v < hi
    cmp     x15, x11
    b.lt    .Lbm_next                // v < lo
    cmp     x15, x12
    b.ge    .Lbm_next                // v >= hi
    // v in range: best = max(best, v)
    cmp     x15, x13
    b.le    .Lbm_next                // v <= best
    mov     x13, x15                 // best = v
.Lbm_next:
    add     x14, x14, #1
    b       .Lbm_loop
.Lbm_done:
    mov     x0, x13
    ret

// ---------------------------------------------------------------------
// setup_c(): c_n = 3; c_vers = {1.0.0, 1.5.0, 2.0.0}
// ---------------------------------------------------------------------
setup_c:
    adrp    x9, c_vers
    add     x9, x9, :lo12:c_vers
    ldr     x10, =1000000            // sv(1,0,0)
    str     x10, [x9, #0]
    ldr     x10, =1005000            // sv(1,5,0)
    str     x10, [x9, #8]
    ldr     x10, =2000000            // sv(2,0,0)
    str     x10, [x9, #16]
    adrp    x9, c_n
    add     x9, x9, :lo12:c_n
    mov     x10, #3
    str     x10, [x9]
    ret

// ---------------------------------------------------------------------
// resolve_shared(x0 = a_base, x1 = b_base) -> x0 = chosen C, or -1.
//   lo = max(caret_lo a, caret_lo b); hi = min(caret_hi a, caret_hi b)
//   empty? -1 : best_match(c_vers, c_n, lo, hi)
// ---------------------------------------------------------------------
// Callee-saved: x19=lo, x20=hi.
resolve_shared:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // lo = max(a_base, b_base)  (caret_lo is identity)
    cmp     x0, x1
    csel    x19, x0, x1, gt          // lo

    // hi = min(caret_hi(a_base), caret_hi(b_base))
    stp     x0, x1, [sp, #-16]!      // protect a_base, b_base
    bl      caret_hi                 // x0 was a_base -> hi_a
    mov     x20, x0                  // hold hi_a
    ldp     x0, x1, [sp], #16        // restore a_base, b_base
    mov     x0, x1                   // b_base
    bl      caret_hi                 // hi_b
    cmp     x20, x0
    csel    x20, x20, x0, lt         // hi = min(hi_a, hi_b)

    // empty iff lo >= hi
    cmp     x19, x20
    b.ge    .Lrs_none

    // best_match(&c_vers, c_n, lo, hi)
    adrp    x0, c_vers
    add     x0, x0, :lo12:c_vers
    adrp    x9, c_n
    add     x9, x9, :lo12:c_n
    ldr     x1, [x9]
    mov     x2, x19
    mov     x3, x20
    bl      best_match
    b       .Lrs_done
.Lrs_none:
    mov     x0, #-1
.Lrs_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ---------------------------------------------------------------------
// resolve_backtrack(x0 = a_vers, x1 = a_creq, x2 = an, x3 = b_base)
//   -> x0 = chosen A (highest A for which some C satisfies both), or -1.
//   Writes chosen C into g_chosen_c.
// ---------------------------------------------------------------------
// Callee-saved: x19=a_vers, x20=a_creq, x21=an, x22=b_base,
//               x23=bestA, x24=bestC, x25=i.
resolve_backtrack:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    str     x25, [sp, #64]

    mov     x19, x0                  // a_vers
    mov     x20, x1                  // a_creq
    mov     x21, x2                  // an
    mov     x22, x3                  // b_base
    mov     x23, #-1                 // bestA
    mov     x24, #-1                 // bestC
    mov     x25, #0                  // i
.Lrb_loop:
    cmp     x25, x21
    b.ge    .Lrb_done
    ldr     x26, [x19, x25, lsl #3]  // aver
    ldr     x27, [x20, x25, lsl #3]  // creq

    // lo = max(caret_lo(creq), caret_lo(b_base)) = max(creq, b_base)
    cmp     x27, x22
    csel    x9, x27, x22, gt
    mov     x28, x9                  // lo (hold across calls)

    // hi = min(caret_hi(creq), caret_hi(b_base))
    mov     x0, x27
    bl      caret_hi
    mov     x9, x0                   // hi_creq
    str     x9, [sp, #-16]!          // protect hi_creq
    mov     x0, x22
    bl      caret_hi                 // hi_b
    ldr     x9, [sp], #16            // hi_creq
    cmp     x9, x0
    csel    x9, x9, x0, lt           // hi = min

    // empty? lo >= hi → skip
    cmp     x28, x9
    b.ge    .Lrb_next

    // c = best_match(&c_vers, c_n, lo, hi)
    adrp    x0, c_vers
    add     x0, x0, :lo12:c_vers
    adrp    x10, c_n
    add     x10, x10, :lo12:c_n
    ldr     x1, [x10]
    mov     x2, x28                  // lo
    mov     x3, x9                   // hi
    bl      best_match               // x0 = c
    // if c == -1 → skip
    cmn     x0, #1
    b.eq    .Lrb_next
    // if aver > bestA: bestA = aver; bestC = c
    cmp     x26, x23
    b.le    .Lrb_next
    mov     x23, x26                 // bestA = aver
    mov     x24, x0                  // bestC = c
.Lrb_next:
    add     x25, x25, #1
    b       .Lrb_loop
.Lrb_done:
    // g_chosen_c = bestC
    adrp    x9, g_chosen_c
    add     x9, x9, :lo12:g_chosen_c
    str     x24, [x9]
    mov     x0, x23                  // return bestA

    ldr     x25, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// ---------------------------------------------------------------------
// Dependency-graph cycle detection (Kahn ready-scan).
// ---------------------------------------------------------------------

// pkg_reset(x0 = n): p_n = n; p_depcnt[0..n) = 0
pkg_reset:
    adrp    x9, p_n
    add     x9, x9, :lo12:p_n
    str     x0, [x9]
    adrp    x10, p_depcnt
    add     x10, x10, :lo12:p_depcnt
    mov     x11, #0
.Lpr_loop:
    cmp     x11, x0
    b.ge    .Lpr_done
    str     xzr, [x10, x11, lsl #3]
    add     x11, x11, #1
    b       .Lpr_loop
.Lpr_done:
    ret

// pkg_add_dep(x0 = p, x1 = d):
//   c = p_depcnt[p]; p_deps[p*MAXD + c] = d; p_depcnt[p] = c + 1
pkg_add_dep:
    adrp    x9, p_depcnt
    add     x9, x9, :lo12:p_depcnt
    ldr     x10, [x9, x0, lsl #3]    // c
    lsl     x11, x0, #3              // p * MAXD  (MAXD = 8)
    add     x11, x11, x10            // + c
    adrp    x12, p_deps
    add     x12, x12, :lo12:p_deps
    str     x1, [x12, x11, lsl #3]   // p_deps[off] = d
    add     x10, x10, #1
    str     x10, [x9, x0, lsl #3]    // p_depcnt[p] = c + 1
    ret

// pkg_has_cycle() -> x0 = 1 if a cycle exists else 0.
// Kahn: place any unplaced package whose deps are all placed; if a full
// scan makes no progress while some remain, that's a cycle.
// Callee-saved: x19=n, x20=placed, x21=p (outer scan cursor).
pkg_has_cycle:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]

    adrp    x9, p_n
    add     x9, x9, :lo12:p_n
    ldr     x19, [x9]                // n = p_n

    // clear p_placed[0..n)
    adrp    x10, p_placed
    add     x10, x10, :lo12:p_placed
    mov     x11, #0
.Lhc_clr:
    cmp     x11, x19
    b.ge    .Lhc_clr_done
    str     xzr, [x10, x11, lsl #3]
    add     x11, x11, #1
    b       .Lhc_clr
.Lhc_clr_done:

    mov     x20, #0                  // placed = 0
.Lhc_outer:
    cmp     x20, x19
    b.ge    .Lhc_ok                  // placed >= n ⇒ acyclic
    mov     x12, #0                  // progress = 0
    mov     x21, #0                  // p = 0
.Lhc_scan:
    cmp     x21, x19
    b.ge    .Lhc_scan_done

    // if p_placed[p] != 0 → skip
    adrp    x9, p_placed
    add     x9, x9, :lo12:p_placed
    ldr     x10, [x9, x21, lsl #3]
    cbnz    x10, .Lhc_next

    // ready = 1; for k in 0..depcnt: if !placed[dep] ready = 0
    mov     x13, #1                  // ready
    adrp    x9, p_depcnt
    add     x9, x9, :lo12:p_depcnt
    ldr     x14, [x9, x21, lsl #3]   // dc
    mov     x15, #0                  // k
    lsl     x16, x21, #3             // p * MAXD
    adrp    x17, p_deps
    add     x17, x17, :lo12:p_deps
    adrp    x6, p_placed
    add     x6, x6, :lo12:p_placed
.Lhc_dep:
    cmp     x15, x14
    b.ge    .Lhc_dep_done
    add     x7, x16, x15             // p*MAXD + k
    ldr     x8, [x17, x7, lsl #3]    // d = p_deps[...]
    ldr     x3, [x6, x8, lsl #3]     // p_placed[d]
    cbnz    x3, .Lhc_dep_ok
    mov     x13, #0                  // ready = 0
.Lhc_dep_ok:
    add     x15, x15, #1
    b       .Lhc_dep
.Lhc_dep_done:
    cbz     x13, .Lhc_next           // not ready

    // place p: p_placed[p] = 1; placed++; progress = 1
    adrp    x9, p_placed
    add     x9, x9, :lo12:p_placed
    mov     x10, #1
    str     x10, [x9, x21, lsl #3]
    add     x20, x20, #1
    mov     x12, #1                  // progress = 1
.Lhc_next:
    add     x21, x21, #1
    b       .Lhc_scan
.Lhc_scan_done:
    cbz     x12, .Lhc_cycle          // no progress ⇒ stuck (cycle)
    b       .Lhc_outer

.Lhc_cycle:
    mov     x0, #1
    b       .Lhc_ret
.Lhc_ok:
    mov     x0, #0
.Lhc_ret:
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ---------------------------------------------------------------------
// _start: run the hardcoded contract checks; any mismatch -> fail.
// sp is 16-byte aligned at entry.
// ---------------------------------------------------------------------
_start:
    // ---- semver ordering ----
    // sv(1,2,3) > sv(1,2,0)
    mov     x0, #1
    mov     x1, #2
    mov     x2, #3
    bl      sv
    mov     x19, x0                  // sv(1,2,3)
    mov     x0, #1
    mov     x1, #2
    mov     x2, #0
    bl      sv
    cmp     x19, x0
    b.le    fail

    // sv(2,0,0) > sv(1,9,9)
    mov     x0, #2
    mov     x1, #0
    mov     x2, #0
    bl      sv
    mov     x19, x0
    mov     x0, #1
    mov     x1, #9
    mov     x2, #9
    bl      sv
    cmp     x19, x0
    b.le    fail

    // sv_major(sv(1,5,2)) == 1
    mov     x0, #1
    mov     x1, #5
    mov     x2, #2
    bl      sv
    bl      sv_major
    cmp     x0, #1
    b.ne    fail

    // ---- caret ----
    // caret_hi(sv(1,2,0)) == 2000000
    mov     x0, #1
    mov     x1, #2
    mov     x2, #0
    bl      sv
    bl      caret_hi
    ldr     x9, =2000000
    cmp     x0, x9
    b.ne    fail

    // satisfies(sv(1,4,0), caret_lo(sv(1,2,0)), caret_hi(sv(1,2,0))) == 1
    // lo = sv(1,2,0) = 1002000 ; hi = 2000000
    mov     x0, #1
    mov     x1, #4
    mov     x2, #0
    bl      sv                       // x0 = sv(1,4,0)
    ldr     x1, =1002000             // lo
    ldr     x2, =2000000             // hi
    bl      satisfies
    cmp     x0, #1
    b.ne    fail

    // satisfies(sv(2,0,0), 1002000, 2000000) == 0
    mov     x0, #2
    mov     x1, #0
    mov     x2, #0
    bl      sv
    ldr     x1, =1002000
    ldr     x2, =2000000
    bl      satisfies
    cbnz    x0, fail

    // satisfies(sv(1,1,0), 1002000, 2000000) == 0
    mov     x0, #1
    mov     x1, #1
    mov     x2, #0
    bl      sv
    ldr     x1, =1002000
    ldr     x2, =2000000
    bl      satisfies
    cbnz    x0, fail

    // ---- intersect ----
    // range_lo_max(sv(1,0,0), sv(1,3,0)) == sv(1,3,0) = 1003000
    ldr     x0, =1000000
    ldr     x1, =1003000
    bl      range_lo_max
    ldr     x9, =1003000
    cmp     x0, x9
    b.ne    fail

    // range_hi_min(sv(2,0,0), sv(3,0,0)) == sv(2,0,0) = 2000000
    ldr     x0, =2000000
    ldr     x1, =3000000
    bl      range_hi_min
    ldr     x9, =2000000
    cmp     x0, x9
    b.ne    fail

    // ^1.0.0 ∩ ^2.0.0 empty:
    // lo = max(1000000, 2000000) = 2000000 ; hi = min(2000000, 3000000) = 2000000
    ldr     x0, =2000000             // lo
    ldr     x1, =2000000             // hi
    bl      range_empty
    cmp     x0, #1
    b.ne    fail

    // ---- best_match ----
    bl      setup_c
    // best_match(C, ^1.0.0) == 1005000
    // lo = 1000000, hi = caret_hi(1000000) = 2000000
    adrp    x0, c_vers
    add     x0, x0, :lo12:c_vers
    adrp    x9, c_n
    add     x9, x9, :lo12:c_n
    ldr     x1, [x9]
    ldr     x2, =1000000
    ldr     x3, =2000000
    bl      best_match
    ldr     x9, =1005000
    cmp     x0, x9
    b.ne    fail

    // best_match(C, ^3.0.0) == -1
    // lo = 3000000, hi = 4000000
    adrp    x0, c_vers
    add     x0, x0, :lo12:c_vers
    adrp    x9, c_n
    add     x9, x9, :lo12:c_n
    ldr     x1, [x9]
    ldr     x2, =3000000
    ldr     x3, =4000000
    bl      best_match
    cmn     x0, #1                   // x0 == -1 ?
    b.ne    fail

    // ---- diamond resolution ----
    bl      setup_c
    // resolve_shared(^1.0.0, ^1.0.0) == 1005000
    ldr     x0, =1000000
    ldr     x1, =1000000
    bl      resolve_shared
    ldr     x9, =1005000
    cmp     x0, x9
    b.ne    fail

    // resolve_shared(^1.0.0, ^2.0.0) == -1
    ldr     x0, =1000000
    ldr     x1, =2000000
    bl      resolve_shared
    cmn     x0, #1
    b.ne    fail

    // ---- bounded backtracking ----
    bl      setup_c
    // A 1.1.0 -> C ^2.0.0 ; A 1.0.0 -> C ^1.0.0 ; B -> C ^1.0.0
    // Build a_vers / a_creq on the stack (two slots each, 16-aligned 32B).
    sub     sp, sp, #32
    ldr     x9, =1001000             // sv(1,1,0)
    str     x9, [sp, #0]             // a_vers[0]
    ldr     x9, =1000000             // sv(1,0,0)
    str     x9, [sp, #8]             // a_vers[1]
    ldr     x9, =2000000             // sv(2,0,0)
    str     x9, [sp, #16]            // a_creq[0]
    ldr     x9, =1000000             // sv(1,0,0)
    str     x9, [sp, #24]            // a_creq[1]

    mov     x0, sp                   // a_vers ptr
    add     x1, sp, #16              // a_creq ptr
    mov     x2, #2                   // an
    ldr     x3, =1000000             // b_base = ^1.0.0
    bl      resolve_backtrack
    // chosen A == sv(1,0,0) = 1000000
    ldr     x9, =1000000
    cmp     x0, x9
    add     sp, sp, #32              // free stack args (does not touch flags)
    b.ne    fail
    // chosen C == sv(1,5,0) = 1005000
    adrp    x9, g_chosen_c
    add     x9, x9, :lo12:g_chosen_c
    ldr     x10, [x9]
    ldr     x9, =1005000
    cmp     x10, x9
    b.ne    fail

    // ---- cycle detection ----
    // A↔B is a cycle
    mov     x0, #2
    bl      pkg_reset
    mov     x0, #0
    mov     x1, #1
    bl      pkg_add_dep
    mov     x0, #1
    mov     x1, #0
    bl      pkg_add_dep
    bl      pkg_has_cycle
    cmp     x0, #1
    b.ne    fail

    // app -> A, app -> B (diamond) is acyclic
    mov     x0, #3
    bl      pkg_reset
    mov     x0, #2
    mov     x1, #0
    bl      pkg_add_dep
    mov     x0, #2
    mov     x1, #1
    bl      pkg_add_dep
    bl      pkg_has_cycle
    cbnz    x0, fail

    // ---- all passed ----
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
