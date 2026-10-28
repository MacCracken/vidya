// Vidya — Boot and Startup in OpenQASM (Circuit Initialization)
//
// Analogy: quantum circuit initialization parallels system boot.
// All qubits start in |0⟩ (reset state), then initialization gates
// bring the system to a known working state — like firmware boot.
//
// Gotcha: OpenQASM 3 does not promise that starting state. A freshly
// declared qubit is in an undefined state (2.0 guaranteed |0⟩); qiskit
// and IBM hardware happen to start every qubit in |0⟩. A portable
// program resets explicitly, just as firmware never trusts RAM to
// power up zeroed.

OPENQASM 3.1;
include "stdgates.inc";

// ── Boot: all qubits begin in ground state |0⟩ ──────────────────
qubit[4] sys;
bit[4] sys_c;

// Stage 1: hardware reset — explicit, so the program does not depend on
// what the executor happened to leave in the qubits
reset sys;
// Stage 2: initialize working state
h sys[0];
h sys[1];
x sys[2];
h sys[3];
// System is now "booted" — ready for computation

sys_c = measure sys;
// sys[2] reads 1 on every shot; sys[0], sys[1], sys[3] are each 0 or 1
// with equal probability — 8 equally likely boot states, all with bit 2 set.
// @expect sys_c in {4, 5, 6, 7, 12, 13, 14, 15}
