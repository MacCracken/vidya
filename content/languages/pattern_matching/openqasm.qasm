// Vidya — Pattern Matching in OpenQASM (Measurement & Discrimination)
//
// Quantum measurement projects a state onto a basis. Different
// measurement bases reveal different information. The Deutsch-Jozsa
// algorithm "matches" whether a function is constant or balanced
// with a single quantum query.

OPENQASM 3.1;
include "stdgates.inc";

// ── Computational basis measurement ───────────────────────────────
qubit[1] z_basis;
bit[1] z_out;

x z_basis[0];          // prepare |1>
z_out = measure z_basis;
// Always "1" — deterministic
// @expect z_out == 1

// ── Hadamard basis measurement ────────────────────────────────────
// Measure |+> in X basis: H then measure
qubit[1] x_basis;
bit[1] x_out;

h x_basis[0];          // prepare |+> = (|0>+|1>)/√2
h x_basis[0];          // rotate to X basis
x_out = measure x_basis;
// Always "0" — |+> is eigenstate of X
// @expect x_out == 0

// ── Bell state discrimination ─────────────────────────────────────
// Create |Φ+> then measure in Bell basis
qubit[2] bell;
bit[2] bell_out;

h bell[0];
cx bell[0], bell[1];   // |Φ+> = (|00>+|11>)/√2

// Bell measurement: reverse preparation
cx bell[0], bell[1];
h bell[0];
bell_out = measure bell;
// Deterministic outcome identifies which Bell state: 00 = |Φ+>
// @expect bell_out == 0

// ── Deutsch-Jozsa: single-query function classification ───────────
// Determines if f(x) is constant (f(0)=f(1)) or balanced (f(0)≠f(1))
// Classical: needs 2 queries. Quantum: needs 1.
qubit[2] dj;           // qubit 0 = input, qubit 1 = ancilla
bit[1] dj_out;

// Prepare
x dj[1];              // ancilla to |1>
h dj[0];              // input superposition
h dj[1];              // ancilla in |->

// Oracle: balanced function f(x) = x (implemented as CNOT)
cx dj[0], dj[1];

// Extract result
h dj[0];
dj_out[0] = measure dj[0];
// dj_out = 1 → balanced, dj_out = 0 → constant. f(x) = x is balanced,
// so dj_out reads 1 on every shot.
// @expect dj_out == 1

// ── Multi-outcome: uniform superposition ──────────────────────────
qubit[2] uniform;
bit[2] uniform_out;

h uniform[0];
h uniform[1];
// All 4 outcomes equally likely: 00, 01, 10, 11
uniform_out = measure uniform;
// @expect uniform_out in {0, 1, 2, 3}
