// Vidya — Trait and Typeclass Systems in OpenQASM (Gate Interfaces)
//
// Analogy: custom gate definitions are trait implementations.
// The gate signature is the trait, and the body is the impl.
// Different gates can satisfy the same interface pattern.

OPENQASM 2.0;
include "qelib1.inc";

// ── "Trait": entangler — any gate that creates entanglement ──────
// Impl 1: Bell-style entangler
gate entangle_bell a, b { h a; cx a, b; }

// Impl 2: GHZ-style entangler (different implementation, same trait)
gate entangle_ghz a, b, c { h a; cx a, b; cx b, c; }

qreg q2[2];
qreg q3[3];
creg c2[2];
creg c3[3];

entangle_bell q2[0], q2[1];     // dispatch to impl 1
entangle_ghz q3[0], q3[1], q3[2]; // dispatch to impl 2

measure q2 -> c2;
measure q3 -> c3;
