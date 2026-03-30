// Vidya — Strings in OpenQASM (Quantum Data Encoding)
//
// Quantum "strings" are qubit states: bit strings encoded as
// computational basis states. |101> encodes the classical
// bit string "101". This is how data enters quantum circuits.

OPENQASM 2.0;
include "qelib1.inc";

// ── Basis encoding: "101" as a 3-qubit state ──────────────────────
// X gate flips |0> to |1>. Leave qubit alone for |0>.
qreg data[3];
creg result[3];

x data[0];        // bit 0 = 1
                   // bit 1 = 0 (default)
x data[2];        // bit 2 = 1
// State is now |101>

// ── Read back: measurement collapses to classical bits ────────────
measure data -> result;
// result will always be 101 (deterministic state)

// ── Superposition: qubit encodes two values simultaneously ────────
qreg sup[1];
creg sup_c[1];

h sup[0];         // |0> → (|0> + |1>)/√2
// Now sup[0] is "both 0 and 1" — measured probabilistically
measure sup -> sup_c;

// ── Multi-qubit superposition: all strings at once ────────────────
qreg multi[3];
creg multi_c[3];

h multi[0];       // each qubit in superposition
h multi[1];
h multi[2];
// State: equal superposition of all 8 bit strings 000..111

measure multi -> multi_c;
