// Vidya — Type Systems in OpenQASM (Quantum & Classical Types)
//
// OpenQASM has two fundamental types: qreg (quantum register)
// and creg (classical register). Gates act on qregs, measurement
// converts qreg to creg. This is the quantum type boundary.

OPENQASM 2.0;
include "qelib1.inc";

// ── Quantum type: qreg ────────────────────────────────────────────
// Qubits exist in superposition — fundamentally different from bits
qreg q[3];

// ── Classical type: creg ──────────────────────────────────────────
// Classical bits hold measurement results — standard 0 or 1
creg c[3];

// ── Gate types: single-qubit ──────────────────────────────────────
h q[0];            // Hadamard: creates superposition
x q[1];            // Pauli-X: NOT gate
z q[2];            // Pauli-Z: phase flip

// ── Gate types: two-qubit (entangling) ────────────────────────────
cx q[0], q[1];     // CNOT: controlled-X
cz q[1], q[2];     // controlled-Z

// ── Gate types: parameterized rotations ───────────────────────────
// Continuous parameters (angles in radians)
rx(pi/4) q[0];    // rotation around X axis
ry(pi/2) q[1];    // rotation around Y axis
rz(pi) q[2];      // rotation around Z axis

// ── Type conversion: measurement (quantum → classical) ────────────
// The only way to get classical data from quantum state
measure q -> c;
// After measurement, q is collapsed — no longer in superposition

// ── Barrier: type-level circuit separator ──────────────────────────
// Prevents gate reordering across the barrier
qreg typed[2];
creg typed_c[2];

h typed[0];
barrier typed;     // no optimization across this boundary
cx typed[0], typed[1];

measure typed -> typed_c;

// ─�� Custom gate definition: user-defined type ─────────────────────
// Define a new gate as a composition of primitives
gate bell a, b {
    h a;
    cx a, b;
}

qreg custom[2];
creg custom_c[2];
bell custom[0], custom[1];    // use the custom gate
measure custom -> custom_c;
