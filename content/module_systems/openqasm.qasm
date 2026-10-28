// Vidya — Module Systems in OpenQASM (Include as Module Import)
//
// Analogy: `include` imports gate definitions from another file,
// like a module system. The standard library stdgates.inc plays the
// "prelude" — except that it is not implicit: a program that omits
// the include sees only the built-in U and gphase.

OPENQASM 3.1;
include "stdgates.inc";  // module import: brings h, cx, t, s, etc.

// ── Using symbols from the imported module ───────────────────────
// All standard gates are "exported" by stdgates.inc
qubit[2] q;
bit[2] c;

// Gates from the standard module
h q[0];
s q[0];
cx q[0], q[1];

// Custom "local module" definition
gate local_op a { t a; h a; t a; }
local_op q[1];

c = measure q;
// local_op's h on q[1] mixes it out of the Z basis, so the Bell pair's
// 00/11 correlation no longer shows: all four outcomes are equally likely
// @expect c in {0, 1, 2, 3}
