// Vidya — Trait and Typeclass Systems in OpenQASM (Gate Interfaces)
//
// Analogy: custom gate definitions are trait implementations.
// The gate signature is the trait, and the body is the impl.
// Different gates can satisfy the same interface pattern.

OPENQASM 3.1;
include "stdgates.inc";

// ── "Trait": entangler — any gate that creates entanglement ──────
// Impl 1: Bell-style entangler
gate entangle_bell a, b { h a; cx a, b; }

// Impl 2: GHZ-style entangler (different implementation, same trait)
gate entangle_ghz a, b, c { h a; cx a, b; cx b, c; }

qubit[2] q2;
qubit[3] q3;
bit[2] c2;
bit[3] c3;

entangle_bell q2[0], q2[1];     // dispatch to impl 1
entangle_ghz q3[0], q3[1], q3[2]; // dispatch to impl 2

c2 = measure q2;
c3 = measure q3;
// Both impls satisfy the "entangler" contract: all-equal outcomes only
// @expect c2 in {0, 3}
// @expect c3 in {0, 7}
