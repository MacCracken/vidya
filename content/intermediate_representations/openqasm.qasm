// Vidya — Intermediate Representations in OpenQASM (Gate IR Levels)
//
// Analogy: QASM text is the "source", custom gates are the "IR",
// and primitive U/CX gates are the "machine code". Compilation
// lowers through these levels, like source -> IR -> assembly.

OPENQASM 2.0;
include "qelib1.inc";

// ── Level 1 (Source): high-level intent ──────────────────────────
gate teleport_prep a, b { h a; cx a, b; }

// ── Level 2 (IR): decomposed into standard gates ────────────────
// teleport_prep lowers to: h, cx (standard gate level)

// ── Level 3 (Machine): hardware primitives U and CX ─────────────
// h lowers to: u2(0, pi) which is U(pi/2, 0, pi)
// cx is already a hardware primitive: CX

qreg q[2];
creg c[2];

// Source level (high-level gate call):
teleport_prep q[0], q[1];
// Parser lowers to IR: h q[0]; cx q[0], q[1];
// Backend lowers to machine: U(pi/2,0,pi) q[0]; CX q[0],q[1];

measure q -> c;
