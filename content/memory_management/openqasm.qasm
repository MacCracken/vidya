// Vidya — Memory Management in OpenQASM (Qubit Resources)
//
// Qubits are the scarcest resource. Circuit width (qubit count)
// and depth (gate count) are the two dimensions of cost.
// Uncomputation returns ancilla qubits to |0> for reuse.

OPENQASM 2.0;
include "qelib1.inc";

// ── Qubit allocation: declared upfront ────────────────────────────
qreg data[2];     // 2 data qubits
qreg ancilla[1];  // 1 ancilla (temporary workspace)
creg out[2];

// ─�� Ancilla usage: compute, use, uncompute ────────────────────────
// Compute: entangle ancilla with data
h data[0];
cx data[0], ancilla[0];

// Use the ancilla for some operation
cx ancilla[0], data[1];

// Uncompute: reverse to free the ancilla back to |0>
cx data[0], ancilla[0];
// ancilla[0] is now back to |0> — available for reuse

// ── Width vs depth tradeoff ───────────────────────────────────────
// Wide circuit: 4 parallel H gates (depth 1, width 4)
qreg wide[4];
creg wide_c[4];

h wide[0];
h wide[1];
h wide[2];
h wide[3];
// depth = 1, uses 4 qubits

measure wide -> wide_c;

// ── Uncomputation: reverse Bell pair ──────────────────────────────
qreg bell[2];
creg bell_c[2];

// Create entanglement
h bell[0];
cx bell[0], bell[1];

// Uncompute: reverse to disentangle
cx bell[0], bell[1];
h bell[0];
// Both qubits back to |0> — "memory freed"

measure bell -> bell_c;
// Should always be 00

// ── Measure data qubits ───────────────────────────────────────────
measure data -> out;
