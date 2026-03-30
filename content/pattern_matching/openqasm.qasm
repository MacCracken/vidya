// Vidya — Pattern Matching in OpenQASM (Measurement & Discrimination)
//
// Quantum measurement projects a state onto a basis. Different
// measurement bases reveal different information. The Deutsch-Jozsa
// algorithm "matches" whether a function is constant or balanced
// with a single quantum query.

OPENQASM 2.0;
include "qelib1.inc";

// ── Computational basis measurement ───────────────────────────────
qreg z_basis[1];
creg z_out[1];

x z_basis[0];          // prepare |1>
measure z_basis -> z_out;
// Always "1" — deterministic

// ── Hadamard basis measurement ────────────────────────────────────
// Measure |+> in X basis: H then measure
qreg x_basis[1];
creg x_out[1];

h x_basis[0];          // prepare |+> = (|0>+|1>)/√2
h x_basis[0];          // rotate to X basis
measure x_basis -> x_out;
// Always "0" — |+> is eigenstate of X

// ── Bell state discrimination ─────────────────────────────────────
// Create |Φ+> then measure in Bell basis
qreg bell[2];
creg bell_out[2];

h bell[0];
cx bell[0], bell[1];   // |Φ+> = (|00>+|11>)/√2

// Bell measurement: reverse preparation
cx bell[0], bell[1];
h bell[0];
measure bell -> bell_out;
// Deterministic outcome identifies which Bell state

// ── Deutsch-Jozsa: single-query function classification ───────────
// Determines if f(x) is constant (f(0)=f(1)) or balanced (f(0)≠f(1))
// Classical: needs 2 queries. Quantum: needs 1.
qreg dj[2];           // qubit 0 = input, qubit 1 = ancilla
creg dj_out[1];

// Prepare
x dj[1];              // ancilla to |1>
h dj[0];              // input superposition
h dj[1];              // ancilla in |->

// Oracle: balanced function f(x) = x (implemented as CNOT)
cx dj[0], dj[1];

// Extract result
h dj[0];
measure dj[0] -> dj_out[0];
// dj_out = 1 → balanced, dj_out = 0 → constant

// ── Multi-outcome: uniform superposition ──────────────────────────
qreg uniform[2];
creg uniform_out[2];

h uniform[0];
h uniform[1];
// All 4 outcomes equally likely: 00, 01, 10, 11
measure uniform -> uniform_out;
