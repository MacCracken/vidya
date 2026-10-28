// Vidya — Type Systems in OpenQASM (Quantum & Classical Types)
//
// OpenQASM 3 has two types on either side of the quantum boundary:
// qubit (quantum) and bit (classical), each declarable as a register
// (qubit[n], bit[n]). Around them sits a full classical type system —
// int[n], uint[n], float[n], angle[n], bool, complex, duration and
// arrays. Gates act on qubits; measurement converts qubit to bit.
// This is the quantum type boundary.

OPENQASM 3.1;
include "stdgates.inc";

// ── Quantum type: qubit ───────────────────────────────────────────
// Qubits exist in superposition — fundamentally different from bits
qubit[3] q;

// ── Classical type: bit ───────────────────────────────────────────
// Classical bits hold measurement results — standard 0 or 1
bit[3] c;

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
c = measure q;
// After measurement, q is collapsed — no longer in superposition
// q[2] only ever received phase gates (z, cz, rz), so c[2] = 0; q[0]
// and q[1] take all four combinations.
// @expect c in {0, 1, 2, 3}

// ── Barrier: type-level circuit separator ──────────────────────────
// Prevents gate reordering across the barrier
qubit[2] typed;
bit[2] typed_c;

h typed[0];
barrier typed;     // no optimization across this boundary
cx typed[0], typed[1];

typed_c = measure typed;
// @expect typed_c in {0, 3}

// ── Custom gate definition: user-defined type ─────────────────────
// Define a new gate as a composition of primitives
gate bell a, b {
    h a;
    cx a, b;
}

qubit[2] custom;
bit[2] custom_c;
bell custom[0], custom[1];    // use the custom gate
custom_c = measure custom;
// @expect custom_c in {0, 3}
