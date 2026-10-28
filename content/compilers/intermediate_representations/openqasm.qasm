// Vidya — Intermediate Representations in OpenQASM (Gate IR Levels)
//
// Analogy: custom gates are the "source", standard-library gates
// are the "IR", and the primitive U gate (plus the ctrl @ modifier)
// is the "machine code". Compilation lowers through these levels,
// like source -> IR -> assembly.

OPENQASM 3.1;
include "stdgates.inc";

// ── Level 1 (Source): high-level intent ──────────────────────────
gate teleport_prep a, b { h a; cx a, b; }

// ── Level 2 (IR): decomposed into standard gates ────────────────
// teleport_prep lowers to: h, cx (standard gate level)

// ── Level 3 (Machine): language primitives ──────────────────────
// OpenQASM 3's only built-in gates are U and gphase; stdgates.inc
// defines everything else on top of them. (OpenQASM 2.0 also built
// in CX; 3.x keeps CX in stdgates.inc for compatibility.)
// h lowers to: U(pi/2, 0, pi), up to a global phase
// cx lowers to: ctrl @ x, i.e. a controlled U(pi, 0, pi)
// Real hardware has its own native set (often rz, sx and CZ or ECR),
// so a backend lowers once more.

qubit[2] q;
bit[2] c;

// Source level (high-level gate call):
teleport_prep q[0], q[1];
// Parser lowers to IR: h q[0]; cx q[0], q[1];
// Backend lowers to machine: U(pi/2,0,pi) q[0]; CX q[0],q[1];

c = measure q;
// A Bell pair: c reads 00 or 11, each half the time
// @expect c in {0, 3}
