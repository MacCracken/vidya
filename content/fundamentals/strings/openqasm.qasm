// Vidya — Strings in OpenQASM (Quantum Data Encoding)
//
// Quantum "strings" are qubit states: bit strings encoded as
// computational basis states. |101> encodes the classical
// bit string "101". This is how data enters quantum circuits.

OPENQASM 3.1;
include "stdgates.inc";

// ── Basis encoding: "101" as a 3-qubit state ──────────────────────
// X gate flips |0> to |1>. Leave qubit alone for |0>.
qubit[3] data;
bit[3] result;

x data[0];        // bit 0 = 1
                   // bit 1 = 0 (default)
x data[2];        // bit 2 = 1
// State is now |101>

// ── Read back: measurement collapses to classical bits ────────────
result = measure data;
// result will always be 101 (deterministic state)
// @expect result == 5

// ── Superposition: qubit encodes two values simultaneously ────────
qubit[1] sup;
bit[1] sup_c;

h sup[0];         // |0> → (|0> + |1>)/√2
// Now sup[0] is "both 0 and 1" — measured probabilistically
sup_c = measure sup;
// @expect sup_c in {0, 1}

// ── Multi-qubit superposition: all strings at once ────────────────
qubit[3] multi;
bit[3] multi_c;

h multi[0];       // each qubit in superposition
h multi[1];
h multi[2];
// State: equal superposition of all 8 bit strings 000..111

multi_c = measure multi;
// Measurement reads ONE of the 8 strings, uniformly — not all of them
// @expect multi_c in {0, 1, 2, 3, 4, 5, 6, 7}
