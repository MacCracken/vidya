// Vidya — Boot and Startup in OpenQASM (Circuit Initialization)
//
// Analogy: quantum circuit initialization parallels system boot.
// All qubits start in |0⟩ (reset state), then initialization gates
// bring the system to a known working state — like firmware boot.

OPENQASM 2.0;
include "qelib1.inc";

// ── Boot: all qubits begin in ground state |0⟩ ──────────────────
qreg sys[4];
creg sys_c[4];

// Stage 1: hardware reset (implicit — qubits are |0000⟩)
// Stage 2: initialize working state
h sys[0];
h sys[1];
x sys[2];
h sys[3];
// System is now "booted" — ready for computation

measure sys -> sys_c;
