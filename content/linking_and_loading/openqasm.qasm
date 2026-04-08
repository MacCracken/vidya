// Vidya — Linking and Loading in OpenQASM (Include Resolution)
//
// Analogy: `include "qelib1.inc"` is link-time symbol resolution.
// The standard library gates (h, cx, t, s) are "linked in" from
// the include file, like a shared library loaded at program start.

OPENQASM 2.0;
include "qelib1.inc";  // "linking" the standard gate library

// ── Using "linked" symbols from the standard library ─────────────
qreg q[2];
creg c[2];

// These gates are defined in qelib1.inc, not built-in
h q[0];            // resolved from include: u2(0, pi)
t q[0];            // resolved from include: u1(pi/4)
cx q[0], q[1];     // resolved from include: CX primitive
swap q[0], q[1];   // resolved from include: 3x cx

measure q -> c;
