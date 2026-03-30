// Vidya — Testing in OpenQASM (Circuit Verification)
//
// Quantum circuit testing: verify gate identities (H·H = I),
// check entanglement properties, confirm state preparation.
// Each section is a self-contained test circuit.

OPENQASM 2.0;
include "qelib1.inc";

// ── Test: H·H = Identity ─────────────────────────────────────────
// Applying Hadamard twice returns to original state
qreg hh[1];
creg hh_c[1];

h hh[0];          // |0> → |+>
h hh[0];          // |+> → |0>
measure hh -> hh_c;
// Expected: always 0

// ── Test: X flips |0> to |1> ──────────────────────────────────────
qreg xtest[1];
creg xtest_c[1];

x xtest[0];
measure xtest -> xtest_c;
// Expected: always 1

// ── Test: X·X = Identity ──────────────────────────────────────────
qreg xx[1];
creg xx_c[1];

x xx[0];
x xx[0];
measure xx -> xx_c;
// Expected: always 0

// ── Test: Bell state produces correlated outcomes ─────────────────
qreg bell_test[2];
creg bell_c[2];

h bell_test[0];
cx bell_test[0], bell_test[1];
measure bell_test -> bell_c;
// Expected: only 00 or 11 (never 01 or 10)

// ── Test: CNOT with control=0 does nothing ────────────────────────
qreg cnot_test[2];
creg cnot_c[2];

// control = |0>, target = |0>
cx cnot_test[0], cnot_test[1];
measure cnot_test -> cnot_c;
// Expected: always 00

// ── Test: CNOT with control=1 flips target ────────────────────────
qreg cnot2[2];
creg cnot2_c[2];

x cnot2[0];                    // control = |1>
cx cnot2[0], cnot2[1];        // flips target
measure cnot2 -> cnot2_c;
// Expected: always 11

// ── Test: Z gate has no effect on |0> ─────────────────────────────
qreg ztest[1];
creg ztest_c[1];

z ztest[0];        // Z|0> = |0> (global phase only)
measure ztest -> ztest_c;
// Expected: always 0

// ── Test: circuit inverse = identity ──────────────────────────────
qreg inv[2];
creg inv_c[2];

// Forward
h inv[0];
cx inv[0], inv[1];
rz(pi/4) inv[1];

// Reverse (inverse)
rz(-pi/4) inv[1];
cx inv[0], inv[1];
h inv[0];

measure inv -> inv_c;
// Expected: always 00 (forward + inverse = identity)

// ── Test: Toffoli only flips when both controls are 1 ─────────────
qreg toff[3];
creg toff_c[3];

x toff[0];        // control 1 = |1>
x toff[1];        // control 2 = |1>
ccx toff[0], toff[1], toff[2];  // target flips
measure toff -> toff_c;
// Expected: always 111
