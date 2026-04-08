// Vidya — Macro Systems in OpenQASM (Gate Definition as Macro)
//
// Analogy: custom gate definitions expand inline at each call site,
// like macro expansion. The gate body is a template that gets
// instantiated with specific qubit arguments.

OPENQASM 2.0;
include "qelib1.inc";

// ── "Macro" definition: reusable gate template ───────────────────
gate bell_pair a, b { h a; cx a, b; }
gate ghz3 a, b, c { h a; cx a, b; cx b, c; }

// ── "Macro expansion": each call inlines the gate body ───────────
qreg m1[2];
qreg m2[2];
qreg m3[3];
creg c1[2];
creg c2[2];
creg c3[3];

bell_pair m1[0], m1[1];   // expands to: h m1[0]; cx m1[0], m1[1]
bell_pair m2[0], m2[1];   // same template, different arguments
ghz3 m3[0], m3[1], m3[2]; // larger macro expansion

measure m1 -> c1;
measure m2 -> c2;
measure m3 -> c3;
