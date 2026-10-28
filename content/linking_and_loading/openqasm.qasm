// Vidya — Linking and Loading in OpenQASM (Include Resolution)
//
// Analogy: `include "stdgates.inc"` is link-time symbol resolution.
// The standard library gates (h, cx, t, s) are "linked in" from
// the include file, like a library linked in at build time.

OPENQASM 3.1;
include "stdgates.inc";  // "linking" the standard gate library

// ── Using "linked" symbols from the standard library ─────────────
qubit[2] q;
bit[2] c;

// These gates are defined in stdgates.inc, not built-in (OpenQASM 3's
// only built-in gates are U and gphase)
h q[0];            // resolved from include: U(pi/2, 0, pi)
t q[0];            // resolved from include: pow(0.5) @ s = phase pi/4
cx q[0], q[1];     // resolved from include: ctrl @ x
// swap q[0], q[1] expanded — stdgates.inc defines `swap` as exactly
// these three CNOTs; spelled out so the "linked" body is visible.
cx q[0], q[1];
cx q[1], q[0];
cx q[0], q[1];

c = measure q;
// h + cx make a Bell pair (t only adds a phase) and the swap exchanges
// two equal bits: c reads 00 or 11
// @expect c in {0, 3}
