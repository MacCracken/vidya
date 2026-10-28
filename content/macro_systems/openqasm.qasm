// Vidya — Macro Systems in OpenQASM (Gate Definition as Macro)
//
// Analogy: custom gate definitions expand inline at each call site,
// like macro expansion. The gate body is a template that gets
// instantiated with specific qubit arguments.

OPENQASM 3.1;
include "stdgates.inc";

// ── "Macro" definition: reusable gate template ───────────────────
gate bell_pair a, b { h a; cx a, b; }
gate ghz3 a, b, c { h a; cx a, b; cx b, c; }

// ── "Macro expansion": each call inlines the gate body ───────────
qubit[2] m1;
qubit[2] m2;
qubit[3] m3;
bit[2] c1;
bit[2] c2;
bit[3] c3;

bell_pair m1[0], m1[1];   // expands to: h m1[0]; cx m1[0], m1[1]
bell_pair m2[0], m2[1];   // same template, different arguments
ghz3 m3[0], m3[1], m3[2]; // larger macro expansion

c1 = measure m1;
c2 = measure m2;
c3 = measure m3;
// Each expansion is independent: c1 and c2 each read 00 or 11, c3
// reads 000 or 111.
// @expect c1 in {0, 3}
// @expect c2 in {0, 3}
// @expect c3 in {0, 7}
