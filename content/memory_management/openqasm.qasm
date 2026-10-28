// Vidya — Memory Management in OpenQASM (Qubit Resources)
//
// Qubits are the scarcest resource. Circuit width (qubit count)
// and depth (number of gate layers — the critical path, not the gate
// count) are the two dimensions of cost.
// Uncomputation returns ancilla qubits to |0> for reuse.

OPENQASM 3.1;
include "stdgates.inc";

// ── Qubit allocation: declared upfront ────────────────────────────
qubit[2] data;     // 2 data qubits
qubit[1] ancilla;  // 1 ancilla (temporary workspace)
bit[2] out;

// ── Ancilla usage: compute, use, uncompute ────────────────────────
// Compute: entangle ancilla with data
h data[0];
cx data[0], ancilla[0];

// Use the ancilla for some operation
cx ancilla[0], data[1];

// Uncompute: reverse to free the ancilla back to |0>
cx data[0], ancilla[0];
// ancilla[0] is now back to |0> — available for reuse
bit[1] anc_c;
anc_c[0] = measure ancilla[0];
// @expect anc_c == 0

// ── Width vs depth tradeoff ───────────────────────────────────────
// Wide circuit: 4 parallel H gates (depth 1, width 4)
qubit[4] wide;
bit[4] wide_c;

h wide[0];
h wide[1];
h wide[2];
h wide[3];
// depth = 1, uses 4 qubits

wide_c = measure wide;
// Four independent coin flips: all 16 outcomes equally likely
// @expect wide_c in {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}

// ── Uncomputation: reverse Bell pair ──────────────────────────────
qubit[2] bell;
bit[2] bell_c;

// Create entanglement
h bell[0];
cx bell[0], bell[1];

// Uncompute: reverse to disentangle
cx bell[0], bell[1];
h bell[0];
// Both qubits back to |0> — "memory freed"

bell_c = measure bell;
// Should always be 00
// @expect bell_c == 0

// ── Measure data qubits ───────────────────────────────────────────
out = measure data;
// data[1] received a copy of data[0] through the ancilla: 00 or 11
// @expect out in {0, 3}
