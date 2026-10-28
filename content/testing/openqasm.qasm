// Vidya — Testing in OpenQASM (Circuit Verification)
//
// Quantum circuit testing: verify gate identities (H·H = I),
// check entanglement properties, confirm state preparation.
// Each section is a self-contained test circuit.

OPENQASM 3.1;
include "stdgates.inc";

// ── Test: H·H = Identity ─────────────────────────────────────────
// Applying Hadamard twice returns to original state
qubit[1] hh;
bit[1] hh_c;

h hh[0];          // |0> → |+>
h hh[0];          // |+> → |0>
hh_c = measure hh;
// Expected: always 0
// @expect hh_c == 0

// ── Test: X flips |0> to |1> ──────────────────────────────────────
qubit[1] xtest;
bit[1] xtest_c;

x xtest[0];
xtest_c = measure xtest;
// Expected: always 1
// @expect xtest_c == 1

// ── Test: X·X = Identity ──────────────────────────────────────────
qubit[1] xx;
bit[1] xx_c;

x xx[0];
x xx[0];
xx_c = measure xx;
// Expected: always 0
// @expect xx_c == 0

// ── Test: Bell state produces correlated outcomes ─────────────────
qubit[2] bell_test;
bit[2] bell_c;

h bell_test[0];
cx bell_test[0], bell_test[1];
bell_c = measure bell_test;
// Expected: only 00 or 11 (never 01 or 10)
// @expect bell_c in {0, 3}

// ── Test: CNOT with control=0 does nothing ────────────────────────
qubit[2] cnot_test;
bit[2] cnot_c;

// control = |0>, target = |0>
cx cnot_test[0], cnot_test[1];
cnot_c = measure cnot_test;
// Expected: always 00
// @expect cnot_c == 0

// ── Test: CNOT with control=1 flips target ────────────────────────
qubit[2] cnot2;
bit[2] cnot2_c;

x cnot2[0];                    // control = |1>
cx cnot2[0], cnot2[1];        // flips target
cnot2_c = measure cnot2;
// Expected: always 11
// @expect cnot2_c == 3

// ── Test: Z gate has no effect on |0> ─────────────────────────────
qubit[1] ztest;
bit[1] ztest_c;

z ztest[0];        // Z|0> = |0> (global phase only)
ztest_c = measure ztest;
// Expected: always 0
// @expect ztest_c == 0

// ── Test: circuit inverse = identity ──────────────────────────────
qubit[2] inverse;
bit[2] inv_c;

// Forward
h inverse[0];
cx inverse[0], inverse[1];
rz(pi/4) inverse[1];

// Reverse (inverse): the gates in reverse order, each inverted. OpenQASM 3
// can also generate this: define the forward circuit as a gate `fwd`
// and apply `inv @ fwd`.
rz(-pi/4) inverse[1];
cx inverse[0], inverse[1];
h inverse[0];

inv_c = measure inverse;
// Expected: always 00 (forward + inverse = identity)
// @expect inv_c == 0

// ── Test: Toffoli only flips when both controls are 1 ─────────────
qubit[3] toff;
bit[3] toff_c;

x toff[0];        // control 1 = |1>
x toff[1];        // control 2 = |1>
ccx toff[0], toff[1], toff[2];  // target flips
toff_c = measure toff;
// Expected: always 111
// @expect toff_c == 7
